-- Migration 001: Trazabilidad de salida de ganado (UPP, TB/BR, historico_movimientos, SP)
-- Fase 1 del MVP de trazabilidad ganadera (Sprint 1 - 300 cabezas / UPP La Bendición, UPP 54)
BEGIN;

-- 1. Extensión de cattle_livestock (no se crea tabla nueva: se reutiliza electronic_rfid como bolo RFID)
ALTER TABLE public.cattle_livestock
    ADD COLUMN upp_origen character varying(100),
    ADD COLUMN tb_test_date date,
    ADD COLUMN br_test_date date;

COMMENT ON COLUMN public.cattle_livestock.upp_origen IS 'Centro de costos/rancho de origen (ej. UPP La Bendición, UPP 54). Se pone en NULL cuando el animal sale (VENDIDO).';
COMMENT ON COLUMN public.cattle_livestock.tb_test_date IS 'Fecha de última prueba de Tuberculosis. Vigencia normativa: 60 días.';
COMMENT ON COLUMN public.cattle_livestock.br_test_date IS 'Fecha de última prueba de Brucelosis. Vigencia normativa: 60 días.';

-- 2. Migración del CHECK de current_status: agrega CUARENTENA sin romper los 9 valores ya usados en producción
ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT cattle_livestock_current_status_check;

ALTER TABLE public.cattle_livestock
ADD CONSTRAINT cattle_livestock_current_status_check
CHECK (
    current_status IN (
        'ACTIVO',
        'EN_TRANSITO',
        'VENDIDO',
        'BAJA_MORTANDAD',
        'PREÑADA',
        'VACÍA',
        'DESARROLLO',
        'RIESGO',
        'FINALIZADO',
        'CUARENTENA'
    )
);

-- 3. Archivo histórico de movimientos (salidas/bajas/traslados)
CREATE TABLE public.historico_movimientos (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    livestock_id uuid NOT NULL REFERENCES public.cattle_livestock(id),
    electronic_rfid character varying(100) NOT NULL,
    tenant_id integer NOT NULL,
    tipo_movimiento character varying(50) NOT NULL,
    upp_origen_anterior character varying(100),
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT historico_movimientos_tipo_check CHECK (
        (tipo_movimiento)::text = ANY (ARRAY['VENTA', 'BAJA_MORTANDAD', 'TRASLADO']::text[])
    )
);

CREATE INDEX idx_historico_movimientos_rfid ON public.historico_movimientos (electronic_rfid);
CREATE INDEX idx_historico_movimientos_livestock ON public.historico_movimientos (livestock_id);

-- 4. Stored Procedure atómico de salida de ganado
-- Nota ACID: al ser una función plpgsql invocada dentro de una transacción implícita,
-- cualquier RAISE EXCEPTION revierte automáticamente el UPDATE + INSERT ya ejecutados
-- en esta misma llamada (no se necesita ROLLBACK explícito ni bloque EXCEPTION que lo capture).
CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_livestock_id   uuid;
    v_tenant_id      integer;
    v_current_status character varying(50);
    v_upp_anterior   character varying(100);
BEGIN
    -- FOR UPDATE bloquea la fila para evitar doble procesamiento por lecturas RFID concurrentes
    SELECT id, tenant_id, current_status, upp_origen
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior
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
