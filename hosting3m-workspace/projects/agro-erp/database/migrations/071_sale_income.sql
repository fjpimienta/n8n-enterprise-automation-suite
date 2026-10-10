-- 071_sale_income.sql
-- Business rules (set by the project owner, 2026-10-10):
--  * Every sale request must carry its REAL sale data, dictated by the requester. Amounts printed on
--    transit guides or invoices are never used (they are often symbolic, e.g. $1.00 per head).
--  * Three sale modes:
--      POR_PIEZA    -> "al bulto": a price per animal.
--      POR_KG       -> the requester gives the animal's weight and the amount paid; $/kg is derived.
--      POR_GENETICA -> a fixed price per animal for genetic quality (heifers, bulls).
--  * Buyer, payment method (EFECTIVO / TRANSFERENCIA) and whether it was invoiced are mandatory data.
--    "Bancarizado" is derived: TRANSFERENCIA = true, EFECTIVO = false.
--  * Income is recorded ONLY when the sale is approved. Rejected, cancelled or expired requests never
--    produce income. A sale can no longer be approved without a price (fail-closed).
--  * Income is financial data: visible to ADMIN only.

BEGIN;

-- 1) Backup of the function this migration replaces
CREATE TABLE IF NOT EXISTS function_backup_20261010_071 AS
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS identity_args,
       pg_get_functiondef(p.oid)                 AS definition,
       now()                                     AS backed_up_at
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'sp_resolver_autorizacion';

-- 2) Income ledger (one row per sold animal)
CREATE TABLE IF NOT EXISTS public.cattle_sale_income (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                integer       NOT NULL REFERENCES public.companys(id_company),
    livestock_id             uuid          NOT NULL REFERENCES public.cattle_livestock(id),
    pending_authorization_id uuid          UNIQUE REFERENCES public.pending_authorizations(id),
    sale_date                date          NOT NULL,
    sale_mode                varchar(20)   NOT NULL CHECK (sale_mode IN ('POR_PIEZA', 'POR_KG', 'POR_GENETICA')),
    amount                   numeric(12,2) NOT NULL CHECK (amount > 0),
    weight_kg                numeric(10,2) CHECK (weight_kg > 0),
    price_per_kg             numeric(10,2) CHECK (price_per_kg > 0),
    buyer_name               varchar(200)  NOT NULL CHECK (btrim(buyer_name) <> ''),
    payment_method           varchar(20)   NOT NULL CHECK (payment_method IN ('EFECTIVO', 'TRANSFERENCIA')),
    invoiced                 boolean       NOT NULL DEFAULT false,
    invoice_folio            varchar(100),
    banked                   boolean       NOT NULL,
    guia_transito            varchar(100),
    requested_by_email       varchar(255),
    approved_by_email        varchar(255),
    notes                    text,
    created_at               timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT cattle_sale_income_kg_check
        CHECK (sale_mode <> 'POR_KG' OR (weight_kg IS NOT NULL AND price_per_kg IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_sale_income_tenant_date ON public.cattle_sale_income (tenant_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_sale_income_livestock   ON public.cattle_sale_income (livestock_id);

-- 3) Validate and normalize the sale data of every new VENTA request, whatever path inserts it
--    (both sp_solicitar_autorizacion overloads, the gateway or a manual insert).
CREATE OR REPLACE FUNCTION public.fn_pending_auth_validate_sale()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_mode   text;
    v_amount numeric;
    v_weight numeric;
    v_ppk    numeric;
    v_buyer  text;
    v_pay    text;
    v_inv    boolean;
BEGIN
    IF NEW.tipo_evento <> 'VENTA' THEN
        RETURN NEW;
    END IF;

    v_mode := upper(btrim(COALESCE(NEW.payload->>'modo_venta', '')));
    IF v_mode NOT IN ('POR_PIEZA', 'POR_KG', 'POR_GENETICA') THEN
        RAISE EXCEPTION 'La venta requiere modo_venta: POR_PIEZA, POR_KG o POR_GENETICA'
            USING ERRCODE = 'P0022';
    END IF;

    IF COALESCE(NEW.payload->>'precio_venta', '') !~ '^\d+(\.\d{1,2})?$' THEN
        RAISE EXCEPTION 'La venta requiere precio_venta: el importe real cobrado por el animal, solo el número'
            USING ERRCODE = 'P0023';
    END IF;
    v_amount := (NEW.payload->>'precio_venta')::numeric;
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'precio_venta debe ser mayor a cero' USING ERRCODE = 'P0023';
    END IF;

    IF NULLIF(btrim(COALESCE(NEW.payload->>'peso_kg', '')), '') IS NOT NULL THEN
        IF NEW.payload->>'peso_kg' !~ '^\d+(\.\d{1,2})?$' OR (NEW.payload->>'peso_kg')::numeric <= 0 THEN
            RAISE EXCEPTION 'peso_kg debe ser un número mayor a cero' USING ERRCODE = 'P0026';
        END IF;
        v_weight := (NEW.payload->>'peso_kg')::numeric;
    END IF;

    IF v_mode = 'POR_KG' THEN
        IF v_weight IS NULL THEN
            RAISE EXCEPTION 'La venta POR_KG requiere peso_kg del animal' USING ERRCODE = 'P0026';
        END IF;
        v_ppk := round(v_amount / v_weight, 2);
    END IF;

    v_buyer := btrim(COALESCE(NEW.payload->>'comprador', ''));
    IF v_buyer = '' THEN
        RAISE EXCEPTION 'La venta requiere el nombre del comprador' USING ERRCODE = 'P0024';
    END IF;

    v_pay := upper(btrim(COALESCE(NEW.payload->>'forma_pago', '')));
    IF v_pay NOT IN ('EFECTIVO', 'TRANSFERENCIA') THEN
        RAISE EXCEPTION 'La venta requiere forma_pago: EFECTIVO o TRANSFERENCIA' USING ERRCODE = 'P0025';
    END IF;

    IF lower(COALESCE(NEW.payload->>'facturado', 'false')) NOT IN ('true', 'false') THEN
        RAISE EXCEPTION 'facturado debe ser true o false' USING ERRCODE = 'P0025';
    END IF;
    v_inv := lower(COALESCE(NEW.payload->>'facturado', 'false')) = 'true';

    NEW.payload := NEW.payload || jsonb_build_object(
        'modo_venta',    v_mode,
        'precio_venta',  v_amount,
        'peso_kg',       v_weight,
        'precio_kg',     v_ppk,
        'comprador',     v_buyer,
        'forma_pago',    v_pay,
        'facturado',     v_inv,
        'folio_factura', NULLIF(btrim(COALESCE(NEW.payload->>'folio_factura', '')), ''),
        'bancarizado',   (v_pay = 'TRANSFERENCIA')
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_pending_auth_validate_sale ON public.pending_authorizations;
CREATE TRIGGER trg_pending_auth_validate_sale
    BEFORE INSERT ON public.pending_authorizations
    FOR EACH ROW EXECUTE FUNCTION public.fn_pending_auth_validate_sale();

-- 4) Resolver: same as 069 + a sale cannot be approved without price, and approval records the income
CREATE OR REPLACE FUNCTION public.sp_resolver_autorizacion(p_request_id uuid, p_decision character varying, p_resuelto_por_email character varying, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_request        pending_authorizations%ROWTYPE;
    v_resultado_sp   jsonb;
    v_excepcion      boolean := false;
    v_sale_date      date;
BEGIN
    IF p_decision IS NULL OR p_decision NOT IN ('APROBADO', 'APROBADO_CON_EXCEPCION', 'RECHAZADO') THEN
        RAISE EXCEPTION 'decision debe ser APROBADO, APROBADO_CON_EXCEPCION o RECHAZADO' USING ERRCODE = 'P0010';
    END IF;

    SELECT * INTO v_request
    FROM pending_authorizations
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud de autorización % no encontrada', p_request_id
            USING ERRCODE = 'P0002';
    END IF;

    -- 069: fail-closed role check, before revealing anything else about the request.
    IF NOT public.fn_is_active_company_admin(p_resuelto_por_email, v_request.id_company) THEN
        RAISE EXCEPTION 'Solo un ADMIN activo de la empresa de la solicitud puede aprobarla o rechazarla'
            USING ERRCODE = 'P0016';
    END IF;

    IF v_request.estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'La solicitud ya fue resuelta previamente (estado actual: %)', v_request.estado
            USING ERRCODE = 'P0011';
    END IF;

    IF v_request.fecha_solicitud::date < CURRENT_DATE THEN
        UPDATE pending_authorizations
           SET estado = 'EXPIRADO', fecha_resolucion = now(),
               notas_resolucion = 'Vencido automáticamente: no autorizado dentro del día de la solicitud.'
         WHERE id = p_request_id;
        RAISE EXCEPTION 'La solicitud venció (era del día %); ya no puede autorizarse', v_request.fecha_solicitud::date
            USING ERRCODE = 'P0012';
    END IF;

    IF p_decision = 'RECHAZADO' THEN
        IF p_notas IS NULL OR btrim(p_notas) = '' THEN
            RAISE EXCEPTION 'El rechazo requiere indicar el motivo en notas'
                USING ERRCODE = 'P0018';
        END IF;

        UPDATE pending_authorizations
           SET estado = 'RECHAZADO', resuelto_por_email = p_resuelto_por_email,
               fecha_resolucion = now(), notas_resolucion = btrim(p_notas)
         WHERE id = p_request_id;

        RETURN jsonb_build_object('success', true, 'estado', 'RECHAZADO', 'request_id', p_request_id);
    END IF;

    -- 071: a sale without its real price can no longer be approved (legacy requests included).
    IF v_request.tipo_evento = 'VENTA'
       AND (v_request.payload->>'precio_venta' IS NULL OR v_request.payload->>'modo_venta' IS NULL) THEN
        RAISE EXCEPTION 'La venta no tiene precio registrado; debe cancelarse y solicitarse de nuevo con el precio real'
            USING ERRCODE = 'P0021';
    END IF;

    v_excepcion := (p_decision = 'APROBADO_CON_EXCEPCION');

    IF v_excepcion THEN
        IF v_request.tipo_evento <> 'VENTA' THEN
            RAISE EXCEPTION 'La excepción sanitaria solo aplica a solicitudes de VENTA'
                USING ERRCODE = 'P0014';
        END IF;

        IF p_notas IS NULL OR btrim(p_notas) = '' THEN
            RAISE EXCEPTION 'La excepción sanitaria requiere indicar el motivo en notas'
                USING ERRCODE = 'P0015';
        END IF;
    END IF;

    IF v_request.tipo_evento = 'BAJA_MORTANDAD' THEN
        SELECT sp_procesar_baja_mortandad(
            p_electronic_rfid      := v_request.payload->>'electronic_rfid',
            p_rfid_siniiga         := v_request.payload->>'rfid_siniiga',
            p_numero_fuego         := v_request.payload->>'numero_fuego',
            p_tenant_id            := v_request.id_company,
            p_causa_mortandad      := v_request.payload->>'causa_mortandad',
            p_fecha_evento         := (v_request.payload->>'fecha_evento')::date,
            p_descripcion          := v_request.payload->>'descripcion',
            p_reportado_por_email  := v_request.solicitado_por_email,
            p_autorizado_por_email := p_resuelto_por_email,
            p_livestock_id         := v_request.livestock_id
        ) INTO v_resultado_sp;

    ELSIF v_request.tipo_evento = 'VENTA' THEN
        SELECT public.sp_procesar_venta_autorizada(
            p_livestock_id         := v_request.livestock_id,
            p_tenant_id            := v_request.id_company,
            p_excepcion_sanitaria  := v_excepcion,
            p_autorizado_por_email := p_resuelto_por_email,
            p_notas                := p_notas,
            p_fecha_evento         := CASE WHEN v_request.payload->>'fecha_evento' ~ '^\d{4}-\d{2}-\d{2}$'
                                           THEN (v_request.payload->>'fecha_evento')::date END
        ) INTO v_resultado_sp;

    ELSE
        RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado', v_request.tipo_evento
            USING ERRCODE = 'P0013';
    END IF;

    -- A dispatcher that reports success:false (e.g. sanitary rejection) must NOT close the request.
    IF v_resultado_sp->>'success' = 'false' THEN
        RETURN jsonb_build_object(
            'success', false,
            'estado', 'PENDIENTE',
            'request_id', p_request_id,
            'motivo', v_resultado_sp->>'motivo',
            'resultado_sp', v_resultado_sp
        );
    END IF;

    -- 071: record the income of an approved sale (same transaction: all or nothing).
    IF v_request.tipo_evento = 'VENTA' THEN
        v_sale_date := COALESCE(
            CASE WHEN v_request.payload->>'fecha_evento' ~ '^\d{4}-\d{2}-\d{2}$'
                 THEN (v_request.payload->>'fecha_evento')::date END,
            (v_request.fecha_solicitud AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date);

        INSERT INTO public.cattle_sale_income
            (tenant_id, livestock_id, pending_authorization_id, sale_date, sale_mode, amount,
             weight_kg, price_per_kg, buyer_name, payment_method, invoiced, invoice_folio, banked,
             guia_transito, requested_by_email, approved_by_email)
        VALUES
            (v_request.id_company, v_request.livestock_id, v_request.id, v_sale_date,
             v_request.payload->>'modo_venta',
             (v_request.payload->>'precio_venta')::numeric,
             (v_request.payload->>'peso_kg')::numeric,
             (v_request.payload->>'precio_kg')::numeric,
             v_request.payload->>'comprador',
             v_request.payload->>'forma_pago',
             COALESCE((v_request.payload->>'facturado')::boolean, false),
             v_request.payload->>'folio_factura',
             COALESCE((v_request.payload->>'bancarizado')::boolean, false),
             NULLIF(v_request.payload->>'guia_transito', ''),
             v_request.solicitado_por_email,
             p_resuelto_por_email);

        -- The sale weight is the animal's last real weighing.
        IF v_request.payload->>'peso_kg' IS NOT NULL THEN
            INSERT INTO public.cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
            VALUES (v_request.livestock_id, (v_request.payload->>'peso_kg')::numeric,
                    v_sale_date::timestamp, 'VENTA');
        END IF;
    END IF;

    v_excepcion := COALESCE((v_resultado_sp->>'excepcion_sanitaria')::boolean, false);

    UPDATE pending_authorizations
       SET estado = 'APROBADO',
           resuelto_por_email = p_resuelto_por_email,
           fecha_resolucion = now(),
           notas_resolucion = CASE WHEN v_excepcion THEN '[EXCEPCION SANITARIA] ' || p_notas ELSE p_notas END
     WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'success', true, 'estado', 'APROBADO', 'request_id', p_request_id,
        'excepcion_sanitaria', v_excepcion,
        'resultado_sp', v_resultado_sp
    );
END;
$function$;

-- 5) Read-only gateway model, ADMIN only (financial data)
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops, hooks,
                         allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
                         joins, is_global, sp_requires_tenant)
SELECT 'cattle_sale_income', 'cattle_sale_income', 'id',
       '["id","tenant_id","livestock_id","pending_authorization_id","sale_date","sale_mode","amount","weight_kg","price_per_kg","buyer_name","payment_method","invoiced","invoice_folio","banked","guia_transito","requested_by_email","approved_by_email","notes","created_at"]',
       '{}', '{SELECT}', '{"pre": [], "post": []}',
       'ADMIN', 'ADMIN', 'ADMIN', 'ADMIN',
       '[]', false, false
WHERE NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'cattle_sale_income');

-- 6) Verification
SELECT to_regclass('public.cattle_sale_income') AS income_table;
SELECT tgname FROM pg_trigger WHERE tgname = 'trg_pending_auth_validate_sale';
SELECT model_name, allowed_ops, allowed_roles_select FROM crud_models WHERE model_name = 'cattle_sale_income';

COMMIT;