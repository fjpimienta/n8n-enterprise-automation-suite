-- 097_fifo_sale_unidentified.sql
-- Adds deterministic FIFO selection for unidentified non-bovine animals in a named lot.
-- Replaces only sp_solicitar_venta_orden; no table, animal, identifier, or company data is changed.
-- Rollback: 097_rollback.sql. Verification: 097_state_check.sql. Tests: 097_tests.sql.
-- Usage: psql -v ON_ERROR_STOP=1 -f 097_fifo_sale_unidentified.sql (dry run) | -v apply=true (commit)
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
DECLARE
    v_def text;
BEGIN
    IF to_regprocedure('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_solicitar_venta_orden not found.';
    END IF;
    v_def := pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure);
    IF md5(v_def) <> 'd3c1fadef0b7d5e9c188acda08df85fb' THEN
        RAISE EXCEPTION 'ABORT: the live definition differs from the 096 definition (md5 %). Rebuild this migration from the live definition.', md5(v_def);
    END IF;
    IF to_regprocedure('public.fn_species_requires_bovine_compliance(character varying)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: 096 species helper not found.';
    END IF;
END $$;

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
    v_seleccion  text;
    v_lote_id    uuid;
    v_lote_company int;
    v_fifo_start int;
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
            upp text, lote text, arete text, numero_fuego text, categoria text, estatus text, seleccion text, error text
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
        v_seleccion := upper(nullif(btrim(e.val->>'seleccion'), ''));
        IF v_seleccion IS NOT NULL AND v_seleccion <> 'FIFO' THEN
            v_pos := v_pos + 1;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
            VALUES (v_pos, coalesce('lote ' || v_lote, 'elemento de la orden'), v_guia, 'Selección no válida');
            CONTINUE;
        END IF;
        IF v_seleccion = 'FIFO' THEN
            v_cat := upper(nullif(btrim(e.val->>'categoria'), ''));
            v_qty := NULL;
            IF btrim(coalesce(e.val->>'cantidad', '')) ~ '^\d+$' THEN
                BEGIN
                    v_qty := btrim(e.val->>'cantidad')::int;
                EXCEPTION WHEN numeric_value_out_of_range THEN
                    v_qty := NULL;
                END;
            END IF;
            IF v_lote IS NULL OR v_cat IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
                v_pos := v_pos + 1;
                INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
                VALUES (v_pos, coalesce('lote ' || v_lote, 'elemento de la orden'), v_guia,
                        'La selección FIFO requiere lote, categoría y una cantidad entera positiva');
                CONTINUE;
            END IF;
        END IF;
        IF v_lote IS NULL THEN
            v_pos := v_pos + 1;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia)
            VALUES (v_pos, nullif(btrim(e.val->>'identificador'), ''), v_guia);
            CONTINUE;
        END IF;

        IF v_seleccion IS NULL THEN
            v_cat := upper(nullif(btrim(e.val->>'categoria'), ''));
            v_qty := CASE WHEN btrim(coalesce(e.val->>'cantidad', '')) ~ '^\d+$' THEN btrim(e.val->>'cantidad')::int END;
        END IF;
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

        IF v_seleccion = 'FIFO' THEN
            SELECT lt.id, lt.id_company INTO v_lote_id, v_lote_company
              FROM production_unit_lots lt
             WHERE lt.id_company = ANY (v_companies) AND lower(btrim(lt.lot_name)) = lower(v_lote);

            SELECT count(*) INTO v_avail
              FROM cattle_livestock l
             WHERE l.lot_id = v_lote_id AND l.tenant_id = v_lote_company
               AND l.category = v_cat
               AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO')
               AND nullif(btrim(l.rfid_siniiga), '') IS NULL
               AND nullif(btrim(l.numero_fuego), '') IS NULL
               AND nullif(btrim(l.electronic_rfid), '') IS NULL
               AND NOT public.fn_species_requires_bovine_compliance(l.species)
               AND NOT EXISTS (SELECT 1 FROM pending_authorizations pa
                                WHERE pa.livestock_id = l.id AND pa.estado = 'PENDIENTE');

            IF v_avail < v_qty THEN
                v_pos := v_pos + 1;
                INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
                VALUES (v_pos, 'lote ' || v_lote, v_guia,
                        'El lote ' || v_lote || ' tiene ' || v_avail || ' animal(es) elegible(s) para selección FIFO; se solicitaron ' || v_qty
                        || '. Los animales bovinos y los animales identificados nunca se seleccionan automáticamente');
                CONTINUE;
            END IF;

            v_fifo_start := v_pos;
            INSERT INTO tmp_sale_order_items (pos, identificador, guia, livestock_id, id_company, arete, numero_fuego,
                                              categoria, estatus, seleccion)
            SELECT v_pos + row_number() OVER (ORDER BY l.created_at ASC, l.id ASC), l.id::text, v_guia,
                   l.id, l.tenant_id, NULL, NULL, l.category, l.current_status, 'FIFO'
              FROM cattle_livestock l
             WHERE l.lot_id = v_lote_id AND l.tenant_id = v_lote_company
               AND l.category = v_cat
               AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO')
               AND nullif(btrim(l.rfid_siniiga), '') IS NULL
               AND nullif(btrim(l.numero_fuego), '') IS NULL
               AND nullif(btrim(l.electronic_rfid), '') IS NULL
               AND NOT public.fn_species_requires_bovine_compliance(l.species)
               AND NOT EXISTS (SELECT 1 FROM pending_authorizations pa
                                WHERE pa.livestock_id = l.id AND pa.estado = 'PENDIENTE')
             ORDER BY l.created_at ASC, l.id ASC
             LIMIT v_qty;
            GET DIAGNOSTICS v_n = ROW_COUNT;
            IF v_n <> v_qty THEN
                UPDATE tmp_sale_order_items
                   SET error = 'El animal seleccionado FIFO ya no cumple los requisitos; vuelve a generar la vista previa'
                 WHERE pos > v_fifo_start;
                v_pos := v_pos + v_n;
                v_pos := v_pos + 1;
                INSERT INTO tmp_sale_order_items (pos, identificador, guia, error)
                VALUES (v_pos, 'lote ' || v_lote, v_guia,
                        'El lote ' || v_lote || ' tiene ' || v_n || ' animal(es) elegible(s) para selección FIFO; se solicitaron ' || v_qty
                        || '. Los animales bovinos y los animales identificados nunca se seleccionan automáticamente');
                CONTINUE;
            END IF;
            v_pos := v_pos + v_qty;
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

    -- 096: the transit guide is required only for animals under the bovine regime (BOVINO or unknown species).
    -- It is checked after the animal is resolved, inside the requester's companies, because the species is only known then.
    UPDATE tmp_sale_order_items t SET error = 'Falta la guía de tránsito'
     WHERE t.error IS NULL AND t.guia IS NULL AND t.livestock_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM cattle_livestock l
                    WHERE l.id = t.livestock_id AND l.tenant_id = t.id_company
                      AND public.fn_species_requires_bovine_compliance(l.species));
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
                              FROM (SELECT jsonb_strip_nulls(jsonb_build_object(
                                             'empresa', empresa, 'upp', upp, 'guia_transito', guia,
                                             'cantidad', count(*),
                                             'seleccion', i.seleccion,
                                             'por_categoria', (SELECT jsonb_object_agg(categoria, n) FROM (
                                                 SELECT x.categoria, count(*) n FROM tmp_sale_order_items x
                                                  WHERE x.error IS NULL AND x.empresa = i.empresa
                                                    AND x.upp IS NOT DISTINCT FROM i.upp AND x.guia IS NOT DISTINCT FROM i.guia
                                                    AND x.seleccion IS NOT DISTINCT FROM i.seleccion
                                                  GROUP BY 1) s),
                                             'aretes', coalesce(jsonb_agg(coalesce(arete, numero_fuego, identificador) ORDER BY pos)
                                                                  FILTER (WHERE i.seleccion IS NULL), '[]'::jsonb))) AS g
                                      FROM tmp_sale_order_items i WHERE error IS NULL
                                     GROUP BY empresa, upp, guia, seleccion) q), '[]'::jsonb));

    IF EXISTS (SELECT 1 FROM tmp_sale_order_items WHERE seleccion = 'FIFO') THEN
        v_res := v_res || jsonb_build_object('seleccionados',
            (SELECT coalesce(jsonb_agg(jsonb_build_object(
                        'livestock_id', t.livestock_id,
                        'categoria', t.categoria,
                        'lote', t.lote,
                        'capturado', l.created_at) ORDER BY t.pos), '[]'::jsonb)
               FROM tmp_sale_order_items t JOIN cattle_livestock l ON l.id = t.livestock_id AND l.tenant_id = t.id_company
              WHERE t.error IS NULL AND t.seleccion = 'FIFO'));
    END IF;

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
    UPDATE tmp_sale_order_items t
       SET error = 'El animal seleccionado FIFO ya no cumple los requisitos; vuelve a generar la vista previa'
     WHERE t.error IS NULL AND t.seleccion = 'FIFO'
       AND NOT EXISTS (
           SELECT 1 FROM cattle_livestock l
            WHERE l.id = t.livestock_id AND l.tenant_id = t.id_company
              AND nullif(btrim(l.rfid_siniiga), '') IS NULL
              AND nullif(btrim(l.numero_fuego), '') IS NULL
              AND nullif(btrim(l.electronic_rfid), '') IS NULL
              AND NOT public.fn_species_requires_bovine_compliance(l.species)
              AND NOT EXISTS (SELECT 1 FROM pending_authorizations pa
                               WHERE pa.livestock_id = l.id AND pa.estado = 'PENDIENTE'));
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
               'seleccion_metodo', CASE WHEN t.seleccion = 'FIFO' THEN 'FIFO_SIN_IDENTIFICADOR' END,
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
  'The transit guide is required only for animals under the bovine regime (fn_species_requires_bovine_compliance). '
  'p_preview=true validates and groups without writing; p_preview=false creates the order (all-or-nothing).';

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure) NOT LIKE '%FIFO_SIN_IDENTIFICADOR%'
       OR pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure) NOT LIKE '%seleccionados%'
       OR pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure) NOT LIKE '%l.created_at ASC, l.id ASC%' THEN
        RAISE EXCEPTION '097: FIFO selection definition is incomplete';
    END IF;
    RAISE NOTICE '097: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 097 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 097 rolled back ***'
\endif
\endif
