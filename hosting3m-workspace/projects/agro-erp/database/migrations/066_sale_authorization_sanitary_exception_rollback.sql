-- 066 ROLLBACK: restores sp_resolver_autorizacion as it was before 066.
-- Does NOT drop sp_procesar_venta_autorizada (harmless if left in place).
CREATE OR REPLACE FUNCTION public.sp_resolver_autorizacion(p_request_id uuid, p_decision character varying, p_resuelto_por_email character varying, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_request        pending_authorizations%ROWTYPE;
    v_resultado_sp   jsonb;
BEGIN
    IF p_decision NOT IN ('APROBADO', 'RECHAZADO') THEN
        RAISE EXCEPTION 'decision debe ser APROBADO o RECHAZADO' USING ERRCODE = 'P0010';
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
        SELECT sp_procesar_salida_ganado(
            p_electronic_rfid := v_request.payload->>'electronic_rfid',
            p_tenant_id       := v_request.id_company,
            p_rfid_siniiga    := v_request.payload->>'rfid_siniiga',
            p_numero_fuego    := v_request.payload->>'numero_fuego',
            p_livestock_id    := v_request.livestock_id
        ) INTO v_resultado_sp;

    ELSE
        RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado', v_request.tipo_evento
            USING ERRCODE = 'P0013';
    END IF;

    UPDATE pending_authorizations
       SET estado = 'APROBADO', resuelto_por_email = p_resuelto_por_email,
           fecha_resolucion = now(), notas_resolucion = p_notas
     WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'success', true, 'estado', 'APROBADO', 'request_id', p_request_id,
        'resultado_sp', v_resultado_sp
    );
END;
$function$

;
