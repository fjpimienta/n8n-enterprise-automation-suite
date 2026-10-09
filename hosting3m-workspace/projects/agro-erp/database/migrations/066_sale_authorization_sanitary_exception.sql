-- 066_sale_authorization_sanitary_exception.sql
-- ALREADY APPLIED in PRODUCTION on 2026-10-06 (backup: function_backup_20261006_066).
-- Versioned retroactively on 2026-10-08. Do NOT re-run blindly.
-- Adds APROBADO_CON_EXCEPCION (ADMIN-only sanitary exception for sales), routes VENTA to
-- sp_procesar_venta_autorizada, and keeps a request PENDIENTE when the dispatcher returns success:false.
BEGIN;
CREATE OR REPLACE FUNCTION public.sp_procesar_venta_autorizada(p_livestock_id uuid, p_tenant_id integer, p_excepcion_sanitaria boolean DEFAULT false, p_autorizado_por_email character varying DEFAULT NULL::character varying, p_notas text DEFAULT NULL::text, p_fecha_evento date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_livestock_id     uuid;
    v_tenant_id        integer;
    v_current_status   character varying(50);
    v_upp_anterior     character varying(100);
    v_unit_id          uuid;
    v_lot_id           uuid;
    v_lot_anterior     character varying(100);
    v_electronic_rfid  character varying(100);
    v_rfid_siniiga     character varying(100);
    v_numero_fuego     character varying(100);
    v_tb_test_date     date;
    v_br_test_date     date;
    v_dias_tb          integer;
    v_dias_br          integer;
    v_tb_free          boolean := false;
    v_br_free          boolean := false;
    v_species          character varying(50);
    v_motivo_id        text := '';
    v_motivo_san       text := '';
    v_usa_excepcion    boolean := false;
    v_audit_identifier character varying(100);
    v_notes            text;
BEGIN
    IF p_livestock_id IS NULL OR p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'livestock_id y tenant_id son obligatorios'
            USING ERRCODE = 'P0003';
    END IF;

    IF p_fecha_evento IS NOT NULL AND p_fecha_evento > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha del movimiento (%) no puede ser futura', p_fecha_evento
            USING ERRCODE = 'P0017';
    END IF;

    SELECT id, tenant_id, current_status, upp_origen, production_unit_id, lot_id,
           electronic_rfid, rfid_siniiga, numero_fuego, tb_test_date, br_test_date, species
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_unit_id, v_lot_id,
           v_electronic_rfid, v_rfid_siniiga, v_numero_fuego, v_tb_test_date, v_br_test_date, v_species
      FROM public.cattle_livestock
     WHERE id = p_livestock_id
       AND tenant_id = p_tenant_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ningún animal coincide con livestock_id % en el tenant %', p_livestock_id, p_tenant_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_current_status = 'VENDIDO' THEN
        RAISE EXCEPTION 'El animal ya fue procesado como VENDIDO'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_current_status = 'BAJA_MORTANDAD' THEN
        RAISE EXCEPTION 'El animal ya fue registrado como BAJA_MORTANDAD'
            USING ERRCODE = 'P0008';
    END IF;

    -- Identification: official ear tag. NEVER waivable.
    IF COALESCE(v_species, '') <> 'EQUIDO' AND NOT public.fn_has_official_ear_tag(v_rfid_siniiga) THEN
        v_motivo_id := 'Sin arete oficial SINIIGA. ';
    END IF;

    -- Sanitary status: TB / Brucellosis (waivable only through the audited exception).
    IF v_unit_id IS NOT NULL THEN
        v_tb_free := public.fn_is_herd_free(v_unit_id, 'TB');
        v_br_free := public.fn_is_herd_free(v_unit_id, 'BR');
    END IF;
    v_dias_tb := CASE WHEN v_tb_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_tb_test_date END;
    v_dias_br := CASE WHEN v_br_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_br_test_date END;

    IF COALESCE(v_species, '') <> 'EQUIDO' AND NOT v_tb_free AND (v_tb_test_date IS NULL OR v_dias_tb > 60) THEN
        v_motivo_san := v_motivo_san || 'Prueba TB vencida o no registrada y sin dictamen de hato libre. ';
    END IF;
    IF COALESCE(v_species, '') <> 'EQUIDO' AND NOT v_br_free AND (v_br_test_date IS NULL OR v_dias_br > 60) THEN
        v_motivo_san := v_motivo_san || 'Prueba Brucelosis vencida o no registrada y sin dictamen de hato libre. ';
    END IF;

    v_usa_excepcion := COALESCE(p_excepcion_sanitaria, false) AND v_motivo_san <> '';

    IF v_usa_excepcion AND (p_notas IS NULL OR btrim(p_notas) = '' OR p_autorizado_por_email IS NULL) THEN
        RAISE EXCEPTION 'La excepción sanitaria requiere justificación (notas) y el email de quien autoriza'
            USING ERRCODE = 'P0015';
    END IF;

    IF v_motivo_id <> '' OR (v_motivo_san <> '' AND NOT v_usa_excepcion) THEN
        RETURN jsonb_build_object(
            'success', false,
            'livestock_id', v_livestock_id,
            'current_status', v_current_status,
            'tb_herd_free', v_tb_free,
            'br_herd_free', v_br_free,
            'motivo', trim(v_motivo_id || v_motivo_san),
            'excepcion_disponible', (v_motivo_id = '' AND v_motivo_san <> '')
        );
    END IF;

    v_audit_identifier := COALESCE(v_electronic_rfid, v_rfid_siniiga, v_numero_fuego, v_livestock_id::varchar);

    IF v_lot_id IS NOT NULL THEN
        SELECT lot_name INTO v_lot_anterior
          FROM public.production_unit_lots
         WHERE id = v_lot_id;
    END IF;

    IF v_upp_anterior IS NULL AND v_unit_id IS NOT NULL THEN
        SELECT upp_code INTO v_upp_anterior
          FROM public.production_units
         WHERE id = v_unit_id;
    END IF;

    v_notes := concat_ws(' | ',
        CASE WHEN p_fecha_evento IS NOT NULL THEN 'Fecha del movimiento: ' || p_fecha_evento::text END,
        CASE WHEN p_autorizado_por_email IS NOT NULL THEN 'Autorizado por: ' || p_autorizado_por_email END,
        CASE WHEN v_usa_excepcion THEN 'EXCEPCION SANITARIA - motivo omitido: ' || trim(v_motivo_san) END,
        NULLIF(btrim(COALESCE(p_notas, '')), '')
    );

    UPDATE public.cattle_livestock
       SET current_status = 'VENDIDO', upp_origen = NULL, production_unit_id = NULL, lot_id = NULL
     WHERE id = v_livestock_id
       AND tenant_id = v_tenant_id;

    INSERT INTO public.historico_movimientos
        (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, upp_origen_anterior, lot_origen_anterior, notes)
    VALUES
        (v_livestock_id, v_audit_identifier, v_tenant_id, 'VENTA', v_upp_anterior, v_lot_anterior, NULLIF(v_notes, ''));

    RETURN jsonb_build_object(
        'success', true,
        'livestock_id', v_livestock_id,
        'current_status', 'VENDIDO',
        'tb_herd_free', v_tb_free,
        'br_herd_free', v_br_free,
        'excepcion_sanitaria', v_usa_excepcion
    );
END;
$function$

;
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
        UPDATE pending_authorizations
           SET estado = 'RECHAZADO', resuelto_por_email = p_resuelto_por_email,
               fecha_resolucion = now(), notas_resolucion = p_notas
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

        IF p_resuelto_por_email IS NULL OR NOT EXISTS (
               SELECT 1
                 FROM public.user_companies uc
                WHERE lower(uc.email) = lower(p_resuelto_por_email)
                  AND uc.id_company   = v_request.id_company
                  AND upper(uc.role)  = 'ADMIN'
           ) THEN
            RAISE EXCEPTION 'Solo un ADMIN de la empresa de la solicitud puede autorizar una excepción sanitaria'
                USING ERRCODE = 'P0016';
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

    -- FIX: a dispatcher that reports success:false (e.g. sanitary rejection) must NOT close the request.
    -- A dispatcher that returns no 'success' key keeps the previous behavior.
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
$function$

;
COMMIT;
