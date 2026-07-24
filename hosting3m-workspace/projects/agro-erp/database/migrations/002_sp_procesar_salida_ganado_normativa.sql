-- Migration 002: Agrega validación normativa (TB/BR <= 60 días) a sp_procesar_salida_ganado.
-- No cambia firma ni forma de invocación: sigue siendo SELECT sp_procesar_salida_ganado(p_electronic_rfid).
-- Rechazo normativo = respuesta normal con success:false (NO excepción), para que el endpoint
-- pueda distinguir "rechazo de negocio" (dispara alerta WhatsApp en Fase 5) de un error real de datos
-- (RFID no encontrado / ya vendido, que sí siguen usando RAISE EXCEPTION).
BEGIN;

CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_livestock_id   uuid;
    v_tenant_id      integer;
    v_current_status character varying(50);
    v_upp_anterior   character varying(100);
    v_tb_test_date   date;
    v_br_test_date   date;
    v_dias_tb        integer;
    v_dias_br        integer;
    v_motivo         text := '';
BEGIN
    -- FOR UPDATE bloquea la fila para evitar doble procesamiento por lecturas RFID concurrentes
    SELECT id, tenant_id, current_status, upp_origen, tb_test_date, br_test_date
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_tb_test_date, v_br_test_date
      FROM public.cattle_livestock
     WHERE electronic_rfid = p_electronic_rfid
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'RFID % no está registrado en el inventario', p_electronic_rfid
            USING ERRCODE = 'P0002';
    END IF;

    IF v_current_status = 'VENDIDO' THEN
        RAISE EXCEPTION 'El animal con RFID % ya fue procesado como VENDIDO', p_electronic_rfid
            USING ERRCODE = 'P0001';
    END IF;

    -- Validación normativa: rechazo de negocio, no de datos.
    v_dias_tb := CASE WHEN v_tb_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_tb_test_date END;
    v_dias_br := CASE WHEN v_br_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_br_test_date END;

    IF v_tb_test_date IS NULL OR v_dias_tb > 60 THEN
        v_motivo := v_motivo || 'Prueba TB ' ||
            (CASE WHEN v_tb_test_date IS NULL THEN 'no registrada. ' ELSE 'vencida hace ' || v_dias_tb || ' días. ' END);
    END IF;

    IF v_br_test_date IS NULL OR v_dias_br > 60 THEN
        v_motivo := v_motivo || 'Prueba Brucelosis ' ||
            (CASE WHEN v_br_test_date IS NULL THEN 'no registrada. ' ELSE 'vencida hace ' || v_dias_br || ' días. ' END);
    END IF;

    IF v_motivo <> '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'livestock_id', v_livestock_id,
            'electronic_rfid', p_electronic_rfid,
            'current_status', v_current_status,
            'motivo', trim(v_motivo)
        );
    END IF;

    UPDATE public.cattle_livestock
       SET current_status = 'VENDIDO',
           upp_origen = NULL
     WHERE id = v_livestock_id;

    INSERT INTO public.historico_movimientos
        (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, upp_origen_anterior)
    VALUES
        (v_livestock_id, p_electronic_rfid, v_tenant_id, 'VENTA', v_upp_anterior);

    RETURN jsonb_build_object(
        'success', true,
        'livestock_id', v_livestock_id,
        'electronic_rfid', p_electronic_rfid,
        'current_status', 'VENDIDO'
    );
END;
$$;

COMMIT;
