-- Migration 059: Captura de lot_origen_anterior en venta + lectura del lote histórico.
--
-- CAUSA RAÍZ (confirmado contra LOCAL, 2026-09-17): historico_movimientos.lot_origen_anterior
-- (columna agregada 2026-09-16) existía en el esquema pero NINGÚN procedimiento la escribía
-- (0 de 5 filas poblada, cero funciones en pg_proc la referenciaban). sp_procesar_salida_ganado
-- (overload de 4 parámetros) ya limpiaba cattle_livestock.lot_id en cada venta, pero nunca
-- capturó el nombre del lote antes de hacerlo — por eso la pantalla "Censo Biológico Activo"
-- mostraba "Sin lote" para cualquier animal vendido, sin forma de recuperar de dónde salió.
--
-- ALCANCE: solo se toca el overload de 4 parámetros (p_electronic_rfid, p_tenant_id,
-- p_rfid_siniiga, p_numero_fuego) — el mismo que ya limpia lot_id. El overload legacy de
-- 1 parámetro (p_electronic_rfid) NO se toca (confirmado por el cliente que el Build Query
-- real de v6/crud siempre arma los 4 argumentos posicionales para este modelo — ver
-- CLAUDE.md, sección "Sin bloquear operación hoy", para el detalle del hallazgo de
-- ambigüedad de overload que motivó esa verificación).
--
-- Aplicado y verificado en LOCAL y PRODUCCIÓN el mismo turno (Regla 7). La verificación del
-- INSERT se hizo dentro de una transacción con ROLLBACK contra un animal real (ccc04259-...,
-- tenant 6, lote "El Triunfo"), confirmando lot_origen_anterior = 'El Triunfo' y lot_id NULL
-- tras el UPDATE, sin persistir ningún cambio.
BEGIN;

CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying, p_tenant_id integer DEFAULT NULL::integer, p_rfid_siniiga character varying DEFAULT NULL::character varying, p_numero_fuego character varying DEFAULT NULL::character varying)
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
    v_motivo           text := '';
    v_match_count      integer;
    v_audit_identifier character varying(100);
    v_species          character varying(50);
BEGIN
    IF p_electronic_rfid IS NULL AND p_rfid_siniiga IS NULL AND p_numero_fuego IS NULL THEN
        RAISE EXCEPTION 'Debe proporcionar electronic_rfid, rfid_siniiga o numero_fuego'
            USING ERRCODE = 'P0003';
    END IF;

    SELECT count(*) INTO v_match_count
    FROM public.cattle_livestock
    WHERE (
        (p_electronic_rfid IS NOT NULL AND electronic_rfid = p_electronic_rfid)
        OR (p_rfid_siniiga    IS NOT NULL AND rfid_siniiga    = p_rfid_siniiga)
        OR (p_numero_fuego    IS NOT NULL AND numero_fuego    = p_numero_fuego)
      )
      AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id);

    IF v_match_count = 0 THEN
        RAISE EXCEPTION 'Ningún animal coincide con el identificador proporcionado (tenant %)', p_tenant_id
            USING ERRCODE = 'P0002';
    ELSIF v_match_count > 1 THEN
        RAISE EXCEPTION 'Identificador ambiguo: % animales coinciden. Use electronic_rfid o rfid_siniiga para desambiguar', v_match_count
            USING ERRCODE = 'P0004';
    END IF;

    SELECT id, tenant_id, current_status, upp_origen, production_unit_id, lot_id,
           electronic_rfid, rfid_siniiga, numero_fuego, tb_test_date, br_test_date, species
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_unit_id, v_lot_id,
           v_electronic_rfid, v_rfid_siniiga, v_numero_fuego, v_tb_test_date, v_br_test_date, v_species
      FROM public.cattle_livestock
     WHERE (
        (p_electronic_rfid IS NOT NULL AND electronic_rfid = p_electronic_rfid)
        OR (p_rfid_siniiga    IS NOT NULL AND rfid_siniiga    = p_rfid_siniiga)
        OR (p_numero_fuego    IS NOT NULL AND numero_fuego    = p_numero_fuego)
       )
       AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
       FOR UPDATE;

    IF v_current_status = 'VENDIDO' THEN
        RAISE EXCEPTION 'El animal ya fue procesado como VENDIDO'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_species <> 'EQUIDO' AND NOT public.fn_has_official_ear_tag(v_rfid_siniiga) THEN
        v_motivo := v_motivo || 'Sin arete oficial SINIIGA. ';
    END IF;

    IF v_unit_id IS NOT NULL THEN
        v_tb_free := public.fn_is_herd_free(v_unit_id, 'TB');
        v_br_free := public.fn_is_herd_free(v_unit_id, 'BR');
    END IF;
    v_dias_tb := CASE WHEN v_tb_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_tb_test_date END;
    v_dias_br := CASE WHEN v_br_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_br_test_date END;

    IF v_species <> 'EQUIDO' AND NOT v_tb_free AND (v_tb_test_date IS NULL OR v_dias_tb > 60) THEN
        v_motivo := v_motivo || 'Prueba TB vencida o no registrada y sin dictamen de hato libre. ';
    END IF;
    IF v_species <> 'EQUIDO' AND NOT v_br_free AND (v_br_test_date IS NULL OR v_dias_br > 60) THEN
        v_motivo := v_motivo || 'Prueba Brucelosis vencida o no registrada y sin dictamen de hato libre. ';
    END IF;

    IF v_motivo <> '' THEN
        RETURN jsonb_build_object(
            'success', false, 'livestock_id', v_livestock_id,
            'current_status', v_current_status,
            'tb_herd_free', v_tb_free, 'br_herd_free', v_br_free,
            'motivo', trim(v_motivo)
        );
    END IF;

    v_audit_identifier := COALESCE(v_electronic_rfid, v_rfid_siniiga, v_numero_fuego);

    -- NUEVO (migración 059): captura el nombre del lote ANTES de limpiarlo — snapshot de
    -- texto en historico_movimientos, mismo diseño que upp_origen_anterior (no es una FK viva).
    IF v_lot_id IS NOT NULL THEN
        SELECT lot_name INTO v_lot_anterior
          FROM public.production_unit_lots
         WHERE id = v_lot_id;
    END IF;

    UPDATE public.cattle_livestock
       SET current_status = 'VENDIDO', upp_origen = NULL, production_unit_id = NULL, lot_id = NULL
     WHERE id = v_livestock_id;

    INSERT INTO public.historico_movimientos
        (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, upp_origen_anterior, lot_origen_anterior)
    VALUES
        (v_livestock_id, v_audit_identifier, v_tenant_id, 'VENTA', v_upp_anterior, v_lot_anterior);

    RETURN jsonb_build_object(
        'success', true, 'livestock_id', v_livestock_id,
        'current_status', 'VENDIDO', 'tb_herd_free', v_tb_free, 'br_herd_free', v_br_free
    );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Lectura del lote histórico: vista de solo lectura + registro en crud_models.
-- Mismo patrón que vw_upp_compliance_status/vw_psg_compliance_status (allowed_ops sin
-- INSERT/UPDATE/DELETE, allowed_roles_insert/update/delete = 'NONE').
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_cattle_lot_history AS
SELECT DISTINCT ON (hm.livestock_id)
       hm.livestock_id,
       hm.tenant_id,
       hm.lot_origen_anterior,
       hm.tipo_movimiento,
       hm.fecha_registro,
       hm.fecha_registro AS created_at   -- contrato Meta-CRUD: getall exige created_at
  FROM public.historico_movimientos hm
 WHERE hm.lot_origen_anterior IS NOT NULL
 ORDER BY hm.livestock_id, hm.fecha_registro DESC;

COMMENT ON VIEW public.vw_cattle_lot_history IS
    'Lote más reciente capturado en historico_movimientos.lot_origen_anterior por animal — para mostrar el lote histórico en pantallas cuando lot_id ya fue limpiado por una salida (venta). Solo lectura, sin escritura desde el frontend.';

INSERT INTO public.crud_models
    (model_name, table_name, primary_key, allowed_fields, allowed_ops,
     allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
     joins, is_global, sp_requires_tenant)
VALUES
    ('cattle_lot_history', 'vw_cattle_lot_history', 'livestock_id',
     '["livestock_id","tenant_id","lot_origen_anterior","tipo_movimiento","fecha_registro","created_at"]'::jsonb,
     ARRAY['SELECT','GETALL','GETONE'],
     'ADMIN,EDITOR,CUSTOMER', 'NONE', 'NONE', 'NONE',
     '[]'::jsonb, false, true)
ON CONFLICT (model_name) DO NOTHING;

COMMIT;

-- Verificación esperada tras aplicar:
-- SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc
--  WHERE proname = 'sp_procesar_salida_ganado'; -- debe seguir mostrando los 2 overloads
-- SELECT * FROM vw_cattle_lot_history; -- 0 filas hasta la próxima venta real
