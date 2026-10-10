-- 069_authorization_admin_only_and_requester_cancel.sql
-- Business rules (set by the project owner, 2026-10-08):
--  * Only an active ADMIN of the request's company may APPROVE, APPROVE_WITH_EXCEPTION or REJECT.
--  * Rejecting requires a reason.
--  * Only the user who created a request may CANCEL it (sale or mortality), with a mandatory
--    reason, while it is still PENDIENTE and not expired. ADMINs reject; they do not cancel.

BEGIN;

-- 1) Backups (function definition + estado constraint)
CREATE TABLE IF NOT EXISTS function_backup_20261008_069 AS
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS identity_args,
       pg_get_functiondef(p.oid)                 AS definition,
       now()                                     AS backed_up_at
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'sp_resolver_autorizacion';

CREATE TABLE IF NOT EXISTS constraint_backup_20261008_069 AS
SELECT conname, pg_get_constraintdef(oid) AS definition, now() AS backed_up_at
FROM pg_constraint
WHERE conrelid = 'public.pending_authorizations'::regclass
  AND conname  = 'pending_authorizations_estado_check';

-- 2) New terminal state CANCELADO (constraint is replaced in the same transaction)
ALTER TABLE public.pending_authorizations
  DROP CONSTRAINT pending_authorizations_estado_check;
ALTER TABLE public.pending_authorizations
  ADD CONSTRAINT pending_authorizations_estado_check
  CHECK (estado IN ('PENDIENTE', 'APROBADO', 'RECHAZADO', 'EXPIRADO', 'CANCELADO'));

-- 3) Single source of truth for "active ADMIN of this company"
CREATE OR REPLACE FUNCTION public.fn_is_active_company_admin(p_email character varying, p_id_company integer)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT p_email IS NOT NULL AND EXISTS (
    SELECT 1
      FROM public.user_companies uc
     WHERE lower(uc.email)  = lower(p_email)
       AND uc.id_company    = p_id_company
       AND uc.is_active     = true
       AND upper(uc.role)   = 'ADMIN'
  );
$$;

-- 4) Resolver: ADMIN required for every decision; reject requires a reason
CREATE OR REPLACE FUNCTION public.sp_resolver_autorizacion(p_request_id uuid, p_decision character varying, p_resuelto_por_email character varying, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_request        pending_authorizations%ROWTYPE;
    v_resultado_sp   jsonb;
    v_excepcion      boolean := false;
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
        -- 069: a rejection must state its reason.
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
        -- ADMIN requirement is now enforced above for every decision.
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

    -- The exception label is stored only when the exception was actually needed and used.
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

-- 5) Requester-only cancellation (sale or mortality). The animal is untouched:
--    its status only ever changes on approval.
CREATE OR REPLACE FUNCTION public.sp_cancelar_autorizacion(
    p_request_id          uuid,
    p_tenant_id           integer,
    p_cancelado_por_email character varying,
    p_motivo              text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_request pending_authorizations%ROWTYPE;
BEGIN
    IF p_request_id IS NULL OR p_tenant_id IS NULL OR p_cancelado_por_email IS NULL THEN
        RAISE EXCEPTION 'request_id, tenant_id y email de quien cancela son obligatorios'
            USING ERRCODE = 'P0003';
    END IF;

    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'La cancelación requiere indicar el motivo'
            USING ERRCODE = 'P0020';
    END IF;

    -- Tenant-scoped lookup: a request from another company is simply "not found".
    SELECT * INTO v_request
      FROM pending_authorizations
     WHERE id = p_request_id
       AND id_company = p_tenant_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud % no encontrada en esta empresa', p_request_id
            USING ERRCODE = 'P0002';
    END IF;

    -- Only the original requester, still active in the company, may cancel.
    IF lower(v_request.solicitado_por_email) <> lower(p_cancelado_por_email)
       OR NOT EXISTS (
            SELECT 1 FROM public.user_companies uc
             WHERE lower(uc.email) = lower(p_cancelado_por_email)
               AND uc.id_company   = p_tenant_id
               AND uc.is_active    = true
       ) THEN
        RAISE EXCEPTION 'Solo quien creó la solicitud puede cancelarla'
            USING ERRCODE = 'P0019';
    END IF;

    IF v_request.estado <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'La solicitud ya no está pendiente (estado actual: %)', v_request.estado
            USING ERRCODE = 'P0011';
    END IF;

    IF v_request.fecha_solicitud::date < CURRENT_DATE THEN
        RAISE EXCEPTION 'La solicitud ya venció (era del día %); no puede cancelarse', v_request.fecha_solicitud::date
            USING ERRCODE = 'P0012';
    END IF;

    UPDATE pending_authorizations
       SET estado             = 'CANCELADO',
           resuelto_por_email = p_cancelado_por_email,
           fecha_resolucion   = now(),
           notas_resolucion   = '[CANCELADO POR SOLICITANTE] ' || btrim(p_motivo)
     WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'success', true,
        'estado', 'CANCELADO',
        'request_id', p_request_id,
        'tipo_evento', v_request.tipo_evento
    );
END;
$function$;

-- 6) Gateway model for the web panel (roles checked by the gateway; actor rules by the SP)
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops, hooks,
                         allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
                         joins, is_global, sp_requires_tenant)
SELECT 'cancelar_autorizacion', 'sp_cancelar_autorizacion', 'request_id',
       '["request_id", "cancelado_por_email", "motivo"]',
       '{"request_id": {"type": "text", "required": true}, "motivo": {"type": "text", "required": true}}',
       '{INSERT}', '{"pre": [], "post": []}',
       'ADMIN', 'ADMIN,EDITOR', 'ADMIN', 'ADMIN',
       '[]', false, true
WHERE NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'cancelar_autorizacion');

-- 7) Verification
SELECT pg_get_constraintdef(oid) FROM pg_constraint
 WHERE conname = 'pending_authorizations_estado_check';
SELECT proname FROM pg_proc
 WHERE proname IN ('fn_is_active_company_admin', 'sp_resolver_autorizacion', 'sp_cancelar_autorizacion');
SELECT model_name, allowed_roles_insert, sp_requires_tenant FROM crud_models
 WHERE model_name IN ('resolver_autorizacion', 'cancelar_autorizacion');

COMMIT;
