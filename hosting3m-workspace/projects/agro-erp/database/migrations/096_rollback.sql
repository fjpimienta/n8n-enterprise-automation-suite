-- 096 ROLLBACK. No DROP / DELETE / TRUNCATE: restores the exact previous definitions of the four functions (production, 2026-11-03).
-- fn_species_requires_bovine_compliance stays in place (nothing uses it after this rollback).
-- Usage: psql -v ON_ERROR_STOP=1 -f 096_rollback.sql (dry run) | -v apply=true (commit). Then 096_state_check.sql -v expect=rolled_back
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)') IS NULL
       OR to_regprocedure('public.sp_procesar_venta_autorizada(uuid,integer,boolean,character varying,text,date)') IS NULL
       OR to_regprocedure('public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying,uuid)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: the sale functions were not found.';
    END IF;
END $$;

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

    -- Captura el nombre del lote ANTES de limpiarlo — historico_movimientos.lot_origen_anterior
    -- es un snapshot de texto (mismo diseño que upp_origen_anterior), no una FK viva.
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
$function$
;

CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying, p_tenant_id integer DEFAULT NULL::integer, p_rfid_siniiga character varying DEFAULT NULL::character varying, p_numero_fuego character varying DEFAULT NULL::character varying, p_livestock_id uuid DEFAULT NULL::uuid)
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
    IF p_livestock_id IS NULL AND p_electronic_rfid IS NULL AND p_rfid_siniiga IS NULL AND p_numero_fuego IS NULL THEN
        RAISE EXCEPTION 'Debe proporcionar electronic_rfid, rfid_siniiga, numero_fuego o livestock_id'
            USING ERRCODE = 'P0003';
    END IF;

    IF p_livestock_id IS NOT NULL THEN
        SELECT count(*) INTO v_match_count
        FROM public.cattle_livestock
        WHERE id = p_livestock_id
          AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id);
    ELSE
        SELECT count(*) INTO v_match_count
        FROM public.cattle_livestock
        WHERE (
            (p_electronic_rfid IS NOT NULL AND electronic_rfid = p_electronic_rfid)
            OR (p_rfid_siniiga    IS NOT NULL AND rfid_siniiga    = p_rfid_siniiga)
            OR (p_numero_fuego    IS NOT NULL AND numero_fuego    = p_numero_fuego)
          )
          AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id);
    END IF;

    IF v_match_count = 0 THEN
        RAISE EXCEPTION 'Ningún animal coincide con el identificador proporcionado (tenant %)', p_tenant_id
            USING ERRCODE = 'P0002';
    ELSIF v_match_count > 1 THEN
        RAISE EXCEPTION 'Identificador ambiguo: % animales coinciden. Use electronic_rfid o rfid_siniiga para desambiguar', v_match_count
            USING ERRCODE = 'P0004';
    END IF;

    IF p_livestock_id IS NOT NULL THEN
        SELECT id, tenant_id, current_status, upp_origen, production_unit_id, lot_id,
               electronic_rfid, rfid_siniiga, numero_fuego, tb_test_date, br_test_date, species
          INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_unit_id, v_lot_id,
               v_electronic_rfid, v_rfid_siniiga, v_numero_fuego, v_tb_test_date, v_br_test_date, v_species
          FROM public.cattle_livestock
         WHERE id = p_livestock_id
           AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
           FOR UPDATE;
    ELSE
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
    END IF;

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

    v_audit_identifier := COALESCE(v_electronic_rfid, v_rfid_siniiga, v_numero_fuego, v_livestock_id::varchar);

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
$function$
;

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

CREATE OR REPLACE FUNCTION public.sp_solicitar_venta_orden(p_items jsonb, p_solicitado_por_email character varying, p_fecha_evento date DEFAULT NULL::date, p_preview boolean DEFAULT true, p_channel character varying DEFAULT 'AGENTE'::character varying)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_email      text := lower(btrim(coalesce(p_solicitado_por_email, '')));
    v_today_cdmx date := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_fecha      date := coalesce(p_fecha_evento, (now() AT TIME ZONE 'America/Mexico_City')::date);
    v_companies  int[];
    v_errors     int;
    v_order      sale_orders%ROWTYPE;
    v_res        jsonb;
    r            record;
    v_n          int;
    v_animal     cattle_livestock%ROWTYPE;
    v_ro_companies int[];
    e            record;
    v_pos        int := 0;
    v_guia       text;
    v_lote       text;
    v_cat        text;
    v_qty        int;
    v_avail      int;
BEGIN
    -- Requester: active user with at least one active membership
    IF v_email = '' THEN
        RAISE EXCEPTION 'Se requiere el email de quien solicita la venta' USING ERRCODE = 'P0007';
    END IF;
    -- Only ADMIN / EDITOR memberships can request sales (fail-closed: any other role is read-only here)
    SELECT array_agg(DISTINCT uc.id_company) FILTER (WHERE upper(uc.role) IN ('ADMIN', 'EDITOR')),
           array_agg(DISTINCT uc.id_company) FILTER (WHERE upper(coalesce(uc.role, '')) NOT IN ('ADMIN', 'EDITOR'))
      INTO v_companies, v_ro_companies
      FROM user_companies uc JOIN users u ON lower(u.email) = lower(uc.email)
     WHERE lower(uc.email) = v_email AND uc.is_active AND u.is_active;
    IF v_companies IS NULL AND v_ro_companies IS NULL THEN
        RAISE EXCEPTION 'El usuario no pertenece a ninguna empresa activa' USING ERRCODE = 'P0031';
    END IF;
    IF v_companies IS NULL THEN
        RAISE EXCEPTION 'Tu acceso es de solo lectura: no puedes solicitar ventas' USING ERRCODE = 'P0035';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La orden debe incluir al menos un animal' USING ERRCODE = 'P0032';
    END IF;
    IF jsonb_array_length(p_items) > 300 THEN
        RAISE EXCEPTION 'La orden no puede tener más de 300 animales' USING ERRCODE = 'P0032';
    END IF;
    IF v_fecha > v_today_cdmx THEN
        RAISE EXCEPTION 'La fecha de venta (%) no puede ser futura', v_fecha USING ERRCODE = 'P0033';
    END IF;

    -- Validation of every item (no writes)
    IF to_regclass('pg_temp.tmp_sale_order_items') IS NULL THEN
        CREATE TEMP TABLE tmp_sale_order_items (
            pos int, identificador text, guia text, livestock_id uuid, id_company int, empresa text,
            upp text, lote text, arete text, numero_fuego text, categoria text, estatus text, error text
        ) ON COMMIT DROP;
    END IF;
    TRUNCATE tmp_sale_order_items;

    -- Each item is either ONE animal  {"identificador", "guia_transito"}
    --                 or a WHOLE LOT   {"lote", "categoria"?, "cantidad"?, "guia_transito"}.
    -- Lots are expanded here (exact lot name, writer companies only, animals not sold/dead), so the agent never
    -- has to list ear tags. "cantidad", when given, must match the animals available or the item fails.
    FOR e IN SELECT x.val FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(val, ord) ORDER BY x.ord LOOP
        v_guia := left(nullif(btrim(e.val->>'guia_transito'), ''), 40);
        v_lote := nullif(btrim(e.val->>'lote'), '');
        IF v_lote IS NULL THEN
            v_pos := v_pos + 1;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia)
            VALUES (v_pos, nullif(btrim(e.val->>'identificador'), ''), v_guia);
            CONTINUE;
        END IF;

        v_cat := upper(nullif(btrim(e.val->>'categoria'), ''));
        v_qty := CASE WHEN btrim(coalesce(e.val->>'cantidad', '')) ~ '^\d+$' THEN btrim(e.val->>'cantidad')::int END;
        SELECT count(*) INTO v_n FROM production_unit_lots lt
         WHERE lt.id_company = ANY (v_companies) AND lower(btrim(lt.lot_name)) = lower(v_lote);
        IF v_n <> 1 THEN
            v_pos := v_pos + 1;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
            VALUES (v_pos, 'lote ' || v_lote, v_guia,
                    CASE WHEN v_n = 0 AND EXISTS (SELECT 1 FROM production_unit_lots lt
                                                   WHERE lt.id_company = ANY (coalesce(v_ro_companies, '{}'))
                                                     AND lower(btrim(lt.lot_name)) = lower(v_lote))
                              THEN 'Tu acceso a la empresa de ese lote es de solo lectura'
                         WHEN v_n = 0 THEN 'No existe ese lote en tus empresas'
                         ELSE 'Hay ' || v_n || ' lotes con ese nombre; da los aretes' END);
            CONTINUE;
        END IF;

        SELECT count(*) INTO v_avail
          FROM cattle_livestock l JOIN production_unit_lots lt ON lt.id = l.lot_id AND lt.id_company = l.tenant_id
         WHERE l.tenant_id = ANY (v_companies) AND lower(btrim(lt.lot_name)) = lower(v_lote)
           AND (v_cat IS NULL OR l.category = v_cat)
           AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO');
        IF v_avail = 0 OR (v_qty IS NOT NULL AND v_qty <> v_avail) THEN
            v_pos := v_pos + 1;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
            VALUES (v_pos, 'lote ' || v_lote, v_guia,
                    'El lote ' || v_lote || ' tiene ' || v_avail || ' animal(es)' || coalesce(' ' || v_cat, '')
                    || ' disponibles' || CASE WHEN v_qty IS NOT NULL THEN ', no ' || v_qty ELSE '' END);
            CONTINUE;
        END IF;

        INSERT INTO tmp_sale_order_items (pos, identificador, guia, livestock_id, id_company, arete, numero_fuego,
                                          categoria, estatus)
        SELECT v_pos + row_number() OVER (ORDER BY l.rfid_siniiga NULLS LAST, l.numero_fuego NULLS LAST, l.id),
               coalesce(l.rfid_siniiga, l.numero_fuego, l.electronic_rfid, l.id::text), v_guia,
               l.id, l.tenant_id, l.rfid_siniiga, l.numero_fuego, l.category, l.current_status
          FROM cattle_livestock l JOIN production_unit_lots lt ON lt.id = l.lot_id AND lt.id_company = l.tenant_id
         WHERE l.tenant_id = ANY (v_companies) AND lower(btrim(lt.lot_name)) = lower(v_lote)
           AND (v_cat IS NULL OR l.category = v_cat)
           AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO');
        v_pos := v_pos + v_avail;
    END LOOP;

    IF v_pos > 300 THEN
        RAISE EXCEPTION 'La orden no puede tener más de 300 animales (tiene %)', v_pos USING ERRCODE = 'P0032';
    END IF;

    UPDATE tmp_sale_order_items SET error = 'Falta el identificador del animal' WHERE identificador IS NULL;
    UPDATE tmp_sale_order_items SET error = 'Falta la guía de tránsito'          WHERE error IS NULL AND guia IS NULL;
    UPDATE tmp_sale_order_items t SET error = 'Identificador repetido en la orden'
     WHERE error IS NULL AND (SELECT count(*) FROM tmp_sale_order_items x WHERE x.identificador = t.identificador) > 1;

    -- Resolve each identifier ONLY inside the requester's companies
    FOR r IN SELECT * FROM tmp_sale_order_items WHERE error IS NULL AND livestock_id IS NULL ORDER BY pos LOOP
        SELECT count(*) INTO v_n
          FROM cattle_livestock l
         WHERE l.tenant_id = ANY (v_companies)
           AND (l.rfid_siniiga = r.identificador OR l.electronic_rfid = r.identificador
                OR l.numero_fuego = r.identificador);
        IF v_n = 0 THEN
            UPDATE tmp_sale_order_items
               SET error = CASE WHEN EXISTS (SELECT 1 FROM cattle_livestock l
                                              WHERE l.tenant_id = ANY (coalesce(v_ro_companies, '{}'))
                                                AND (l.rfid_siniiga = r.identificador OR l.electronic_rfid = r.identificador
                                                     OR l.numero_fuego = r.identificador))
                                THEN 'Tu acceso a la empresa de este animal es de solo lectura'
                                ELSE 'No existe en tus empresas' END
             WHERE pos = r.pos;
        ELSIF v_n > 1 THEN
            UPDATE tmp_sale_order_items
               SET error = 'Identificador ambiguo (' || v_n || ' animales); usa el arete SINIIGA' WHERE pos = r.pos;
        ELSE
            SELECT * INTO v_animal
              FROM cattle_livestock l
             WHERE l.tenant_id = ANY (v_companies)
               AND (l.rfid_siniiga = r.identificador OR l.electronic_rfid = r.identificador
                    OR l.numero_fuego = r.identificador);
            UPDATE tmp_sale_order_items
               SET livestock_id = v_animal.id, id_company = v_animal.tenant_id, arete = v_animal.rfid_siniiga,
                   numero_fuego = v_animal.numero_fuego, categoria = v_animal.category, estatus = v_animal.current_status
             WHERE pos = r.pos;
        END IF;
    END LOOP;

    UPDATE tmp_sale_order_items t SET error = 'Animal repetido en la orden'
     WHERE error IS NULL AND livestock_id IS NOT NULL
       AND (SELECT count(*) FROM tmp_sale_order_items x WHERE x.livestock_id = t.livestock_id) > 1;
    UPDATE tmp_sale_order_items
       SET error = 'Estatus ' || estatus || ': no se puede vender'
     WHERE error IS NULL AND estatus IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO');
    UPDATE tmp_sale_order_items t
       SET error = 'Ya tiene una solicitud pendiente'
     WHERE error IS NULL AND EXISTS (SELECT 1 FROM pending_authorizations pa
                                      WHERE pa.livestock_id = t.livestock_id AND pa.estado = 'PENDIENTE');
    UPDATE tmp_sale_order_items t
       SET empresa = c.company_name
      FROM companys c WHERE c.id_company = t.id_company;
    UPDATE tmp_sale_order_items t
       SET upp  = (SELECT pu.ranch_name FROM cattle_livestock l JOIN production_units pu ON pu.id = l.production_unit_id
                    WHERE l.id = t.livestock_id),
           lote = (SELECT lt.lot_name FROM cattle_livestock l JOIN production_unit_lots lt ON lt.id = l.lot_id
                    WHERE l.id = t.livestock_id)
     WHERE t.livestock_id IS NOT NULL;

    SELECT count(*) INTO v_errors FROM tmp_sale_order_items WHERE error IS NOT NULL;

    v_res := jsonb_build_object(
        'fecha_evento', v_fecha,
        'total', (SELECT count(*) FROM tmp_sale_order_items),
        'validos', (SELECT count(*) FROM tmp_sale_order_items WHERE error IS NULL),
        'errores', coalesce((SELECT jsonb_agg(jsonb_build_object('identificador', identificador, 'error', error) ORDER BY pos)
                               FROM tmp_sale_order_items WHERE error IS NOT NULL), '[]'::jsonb),
        'grupos', coalesce((SELECT jsonb_agg(g ORDER BY g->>'empresa', g->>'guia_transito')
                              FROM (SELECT jsonb_build_object(
                                             'empresa', empresa, 'upp', upp, 'guia_transito', guia,
                                             'cantidad', count(*),
                                             'por_categoria', (SELECT jsonb_object_agg(categoria, n) FROM (
                                                 SELECT x.categoria, count(*) n FROM tmp_sale_order_items x
                                                  WHERE x.error IS NULL AND x.empresa = i.empresa
                                                    AND x.upp IS NOT DISTINCT FROM i.upp AND x.guia = i.guia
                                                  GROUP BY 1) s),
                                             'aretes', jsonb_agg(coalesce(arete, numero_fuego, identificador) ORDER BY pos)) AS g
                                      FROM tmp_sale_order_items i WHERE error IS NULL
                                     GROUP BY empresa, upp, guia) q), '[]'::jsonb));

    IF p_preview THEN
        RETURN v_res || jsonb_build_object('success', v_errors = 0, 'preview', true);
    END IF;

    IF v_errors > 0 THEN
        RAISE EXCEPTION 'La orden no se registró: % animal(es) con error: %', v_errors,
            (SELECT string_agg(identificador || ' (' || error || ')', '; ' ORDER BY pos)
               FROM tmp_sale_order_items WHERE error IS NOT NULL)
            USING ERRCODE = 'P0034';
    END IF;

    -- Concurrency: lock the animals, then re-check status and pending requests under the lock
    PERFORM 1 FROM cattle_livestock
     WHERE id IN (SELECT livestock_id FROM tmp_sale_order_items) ORDER BY id FOR UPDATE;
    UPDATE tmp_sale_order_items t
       SET error = 'Ya tiene una solicitud pendiente'
     WHERE EXISTS (SELECT 1 FROM pending_authorizations pa
                    WHERE pa.livestock_id = t.livestock_id AND pa.estado = 'PENDIENTE');
    UPDATE tmp_sale_order_items t
       SET error = 'Estatus ' || l.current_status || ': no se puede vender'
      FROM cattle_livestock l
     WHERE l.id = t.livestock_id AND t.error IS NULL
       AND l.current_status IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO');
    IF EXISTS (SELECT 1 FROM tmp_sale_order_items WHERE error IS NOT NULL) THEN
        RAISE EXCEPTION 'La orden no se registró: % animal(es) con error: %',
            (SELECT count(*) FROM tmp_sale_order_items WHERE error IS NOT NULL),
            (SELECT string_agg(identificador || ' (' || error || ')', '; ' ORDER BY pos)
               FROM tmp_sale_order_items WHERE error IS NOT NULL)
            USING ERRCODE = 'P0034';
    END IF;

    -- Create the order and one pending authorization per animal, in the animal's own company
    INSERT INTO sale_orders (requested_by_email, fecha_evento, channel)
    VALUES (v_email, v_fecha, coalesce(nullif(btrim(p_channel), ''), 'AGENTE'))
    RETURNING * INTO v_order;

    INSERT INTO pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email, sale_order_id)
    SELECT t.id_company, t.livestock_id, 'VENTA',
           jsonb_strip_nulls(jsonb_build_object(
               'fecha_evento', to_char(v_fecha, 'YYYY-MM-DD'),
               'guia_transito', t.guia,
               'orden_venta', v_order.order_code,
               'rfid_siniiga', t.arete,
               'numero_fuego', t.numero_fuego,
               'electronic_rfid', (SELECT electronic_rfid FROM cattle_livestock WHERE id = t.livestock_id),
               -- Order-level counts only (no identities from other companies): lets each company's panel
               -- know the order also has animals it cannot see.
               'orden_total_animales', (SELECT count(*) FROM tmp_sale_order_items),
               'orden_total_empresas', (SELECT count(DISTINCT id_company) FROM tmp_sale_order_items))),
           v_email, v_order.id
      FROM tmp_sale_order_items t
     ORDER BY t.pos;

    RETURN v_res || jsonb_build_object(
        'success', true, 'preview', false,
        'order_id', v_order.id, 'orden_venta', v_order.order_code,
        'solicitudes', (SELECT count(*) FROM pending_authorizations WHERE sale_order_id = v_order.id));
END;
$function$
;

COMMENT ON FUNCTION public.sp_solicitar_venta_orden(jsonb, varchar, date, boolean, varchar) IS
  'Sale order across the requester''s companies. p_items = [{"identificador": "...", "guia_transito": "..."}]. '
  'p_preview=true validates and groups without writing; p_preview=false creates the order (all-or-nothing).';

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure) LIKE '%fn_species_requires_bovine_compliance%'
       OR pg_get_functiondef('public.sp_procesar_venta_autorizada(uuid,integer,boolean,character varying,text,date)'::regprocedure) LIKE '%fn_species_requires_bovine_compliance%' THEN
        RAISE EXCEPTION '096 rollback: a function still uses the helper';
    END IF;
    RAISE NOTICE '096 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 096 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 096 rollback rolled back ***'
\endif
