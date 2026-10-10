-- 071_sale_income.sql  (v2 — replaces the first local draft of 071; safe to re-run)
-- Business rules (set by the project owner, 2026-10-10):
--  * The foreman REQUESTS the sale: which animals leave (identifier, category comes from the herd record),
--    sale date and transit guide. The foreman never sets prices.
--  * The PRICE is set exclusively by the UPP owners / administrators (ADMIN), WHEN APPROVING the sale.
--    Amounts printed on guides or invoices are never used (they are often symbolic, e.g. $1.00 per head).
--  * Three sale modes:
--      POR_PIEZA    -> "al bulto": an amount per animal.
--      POR_KG       -> the ADMIN gives the animal's weight and the amount; $/kg is derived.
--      POR_GENETICA -> a fixed amount per animal for genetic quality.
--  * Buyer, payment method (EFECTIVO / TRANSFERENCIA) and whether it was invoiced are mandatory.
--    "Bancarizado" is derived: TRANSFERENCIA = true, EFECTIVO = false.
--  * Reference prices per category can be configured to pre-fill the approval form. The recorded amount
--    is always the one the ADMIN confirms.
--  * Income is recorded ONLY on approval. Rejected, cancelled or expired requests never produce income.
--    A sale cannot be approved without its sale data (fail-closed).
--  * Income and reference prices are financial data: ADMIN only.

BEGIN;

-- 0) Undo the first local draft (request-time validation trigger). No-op on a fresh database.
DROP TRIGGER  IF EXISTS trg_pending_auth_validate_sale ON public.pending_authorizations;
DROP FUNCTION IF EXISTS public.fn_pending_auth_validate_sale();

-- 1) Backup of the resolver being replaced (only the first time this migration runs)
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

-- 3) Reference prices per category (pre-fill only; never imposed)
CREATE TABLE IF NOT EXISTS public.cattle_sale_reference_prices (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id              integer       NOT NULL REFERENCES public.companys(id_company),
    category               varchar(50)   NOT NULL,
    sale_mode              varchar(20)   NOT NULL CHECK (sale_mode IN ('POR_PIEZA', 'POR_KG', 'POR_GENETICA')),
    reference_amount       numeric(12,2) CHECK (reference_amount > 0),
    reference_price_per_kg numeric(10,2) CHECK (reference_price_per_kg > 0),
    valid_from             date          NOT NULL DEFAULT CURRENT_DATE,
    valid_to               date,
    is_active              boolean       NOT NULL DEFAULT true,
    notes                  text,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT sale_reference_value_check
        CHECK (reference_amount IS NOT NULL OR reference_price_per_kg IS NOT NULL),
    CONSTRAINT sale_reference_range_check
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
CREATE INDEX IF NOT EXISTS idx_sale_reference_tenant_cat ON public.cattle_sale_reference_prices (tenant_id, category);

-- 4) Single place that validates and normalizes the sale data entered by the ADMIN
CREATE OR REPLACE FUNCTION public.fn_normalize_sale_data(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
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
    IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' THEN
        RAISE EXCEPTION 'La aprobación de una venta requiere los datos de venta (modo, importe, comprador y forma de pago)'
            USING ERRCODE = 'P0021';
    END IF;

    v_mode := upper(btrim(COALESCE(p_data->>'modo_venta', '')));
    IF v_mode NOT IN ('POR_PIEZA', 'POR_KG', 'POR_GENETICA') THEN
        RAISE EXCEPTION 'modo_venta debe ser POR_PIEZA, POR_KG o POR_GENETICA' USING ERRCODE = 'P0022';
    END IF;

    IF COALESCE(p_data->>'precio_venta', '') !~ '^\d+(\.\d{1,2})?$' OR (p_data->>'precio_venta')::numeric <= 0 THEN
        RAISE EXCEPTION 'precio_venta debe ser el importe real del animal, mayor a cero' USING ERRCODE = 'P0023';
    END IF;
    v_amount := (p_data->>'precio_venta')::numeric;

    IF NULLIF(btrim(COALESCE(p_data->>'peso_kg', '')), '') IS NOT NULL THEN
        IF p_data->>'peso_kg' !~ '^\d+(\.\d{1,2})?$' OR (p_data->>'peso_kg')::numeric <= 0 THEN
            RAISE EXCEPTION 'peso_kg debe ser un número mayor a cero' USING ERRCODE = 'P0026';
        END IF;
        v_weight := (p_data->>'peso_kg')::numeric;
    END IF;

    IF v_mode = 'POR_KG' THEN
        IF v_weight IS NULL THEN
            RAISE EXCEPTION 'La venta POR_KG requiere el peso del animal' USING ERRCODE = 'P0026';
        END IF;
        v_ppk := round(v_amount / v_weight, 2);
    END IF;

    v_buyer := btrim(COALESCE(p_data->>'comprador', ''));
    IF v_buyer = '' THEN
        RAISE EXCEPTION 'La venta requiere el nombre del comprador' USING ERRCODE = 'P0024';
    END IF;

    v_pay := upper(btrim(COALESCE(p_data->>'forma_pago', '')));
    IF v_pay NOT IN ('EFECTIVO', 'TRANSFERENCIA') THEN
        RAISE EXCEPTION 'forma_pago debe ser EFECTIVO o TRANSFERENCIA' USING ERRCODE = 'P0025';
    END IF;

    IF lower(COALESCE(p_data->>'facturado', 'false')) NOT IN ('true', 'false') THEN
        RAISE EXCEPTION 'facturado debe ser true o false' USING ERRCODE = 'P0025';
    END IF;
    v_inv := lower(COALESCE(p_data->>'facturado', 'false')) = 'true';

    RETURN jsonb_build_object(
        'modo_venta',    v_mode,
        'precio_venta',  v_amount,
        'peso_kg',       v_weight,
        'precio_kg',     v_ppk,
        'comprador',     v_buyer,
        'forma_pago',    v_pay,
        'facturado',     v_inv,
        'folio_factura', NULLIF(btrim(COALESCE(p_data->>'folio_factura', '')), ''),
        'bancarizado',   (v_pay = 'TRANSFERENCIA')
    );
END;
$function$;

-- 5) Resolver: 069 rules + sale data entered by the ADMIN at approval time.
--    The 4-argument version is dropped so calls with 4 arguments (sp_review_pending_request, gateway)
--    resolve unambiguously to the new one through the DEFAULT of p_datos_venta.
DROP FUNCTION IF EXISTS public.sp_resolver_autorizacion(uuid, character varying, character varying, text);

CREATE OR REPLACE FUNCTION public.sp_resolver_autorizacion(
    p_request_id         uuid,
    p_decision           character varying,
    p_resuelto_por_email character varying,
    p_notas              text  DEFAULT NULL::text,
    p_datos_venta        jsonb DEFAULT NULL::jsonb
)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_request        pending_authorizations%ROWTYPE;
    v_resultado_sp   jsonb;
    v_excepcion      boolean := false;
    v_sale           jsonb;
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

    -- 071: a sale is approved only with the sale data set by the ADMIN (validated BEFORE touching the animal).
    IF v_request.tipo_evento = 'VENTA' THEN
        v_sale := public.fn_normalize_sale_data(p_datos_venta);
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

    -- 071: record the income of the approved sale (same transaction: all or nothing).
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
             v_sale->>'modo_venta',
             (v_sale->>'precio_venta')::numeric,
             (v_sale->>'peso_kg')::numeric,
             (v_sale->>'precio_kg')::numeric,
             v_sale->>'comprador',
             v_sale->>'forma_pago',
             (v_sale->>'facturado')::boolean,
             v_sale->>'folio_factura',
             (v_sale->>'bancarizado')::boolean,
             NULLIF(v_request.payload->>'guia_transito', ''),
             v_request.solicitado_por_email,
             p_resuelto_por_email);

        -- The sale weight is the animal's last real weighing.
        IF v_sale->>'peso_kg' IS NOT NULL THEN
            INSERT INTO public.cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
            VALUES (v_request.livestock_id, (v_sale->>'peso_kg')::numeric, v_sale_date::timestamp, 'VENTA');
        END IF;
    END IF;

    v_excepcion := COALESCE((v_resultado_sp->>'excepcion_sanitaria')::boolean, false);

    UPDATE pending_authorizations
       SET estado = 'APROBADO',
           resuelto_por_email = p_resuelto_por_email,
           fecha_resolucion = now(),
           notas_resolucion = CASE WHEN v_excepcion THEN '[EXCEPCION SANITARIA] ' || p_notas ELSE p_notas END,
           payload = CASE WHEN v_sale IS NOT NULL THEN payload || jsonb_build_object('venta', v_sale) ELSE payload END
     WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'success', true, 'estado', 'APROBADO', 'request_id', p_request_id,
        'excepcion_sanitaria', v_excepcion,
        'venta', v_sale,
        'resultado_sp', v_resultado_sp
    );
END;
$function$;

-- 6) Gateway models (ADMIN only)
UPDATE crud_models
   SET allowed_fields = '["request_id", "decision", "resuelto_por_email", "notas", "datos_venta"]'
 WHERE model_name = 'resolver_autorizacion';

DELETE FROM crud_models WHERE model_name = 'cattle_sale_income';  -- re-created below (first draft had no ops change)
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops, hooks,
                         allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
                         joins, is_global, sp_requires_tenant)
VALUES ('cattle_sale_income', 'cattle_sale_income', 'id',
        '["id","tenant_id","livestock_id","pending_authorization_id","sale_date","sale_mode","amount","weight_kg","price_per_kg","buyer_name","payment_method","invoiced","invoice_folio","banked","guia_transito","requested_by_email","approved_by_email","notes","created_at"]',
        '{}', '{SELECT}', '{"pre": [], "post": []}',
        'ADMIN', 'ADMIN', 'ADMIN', 'ADMIN', '[]', false, false);

INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops, hooks,
                         allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
                         joins, is_global, sp_requires_tenant)
SELECT 'cattle_sale_reference_prices', 'cattle_sale_reference_prices', 'id',
       '["id","tenant_id","category","sale_mode","reference_amount","reference_price_per_kg","valid_from","valid_to","is_active","notes","created_at"]',
       '{"category": {"type": "text", "required": true}, "sale_mode": {"type": "text", "required": true}}',
       '{SELECT,INSERT,UPDATE,DELETE}', '{"pre": [], "post": []}',
       'ADMIN', 'ADMIN', 'ADMIN', 'ADMIN', '[]', false, false
WHERE NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'cattle_sale_reference_prices');

-- 7) Verification
SELECT p.oid::regprocedure FROM pg_proc p WHERE proname IN ('sp_resolver_autorizacion', 'fn_normalize_sale_data');
SELECT count(*) AS old_trigger_left FROM pg_trigger WHERE tgname = 'trg_pending_auth_validate_sale';
SELECT model_name, allowed_ops, allowed_roles_select FROM crud_models
 WHERE model_name IN ('resolver_autorizacion', 'cattle_sale_income', 'cattle_sale_reference_prices');

COMMIT;