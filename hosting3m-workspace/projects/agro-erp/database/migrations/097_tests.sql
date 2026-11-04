-- 097_tests.sql: LOCAL / rehearsal database only. All synthetic rows and the function replacement are rolled back.
-- Creates two synthetic companies and synthetic users inside this transaction; it does not use a real company or account.
\set ON_ERROR_STOP on
BEGIN;
\set embedded true
\ir 097_fifo_sale_unidentified.sql

DO $$
DECLARE
    v_company_a integer;
    v_company_b integer;
    v_admin text := 't097-admin@example.test';
    v_reader text := 't097-reader@example.test';
    v_unit_a uuid;
    v_unit_b uuid;
    v_upp_a text;
    v_upp_b text;
    v_upp_sequence integer;
    v_fifo_lot uuid;
    v_legacy_lot uuid;
    v_foreign_lot uuid;
    v_oldest uuid := '00000097-0000-4000-8000-000000000003';
    v_tie_low uuid := '00000097-0000-4000-8000-000000000001';
    v_tie_high uuid := '00000097-0000-4000-8000-000000000002';
    v_pending uuid := '00000097-0000-4000-8000-000000000004';
    v_tagged uuid := '00000097-0000-4000-8000-000000000005';
    v_bovine uuid := '00000097-0000-4000-8000-000000000006';
    v_unknown uuid := '00000097-0000-4000-8000-000000000007';
    v_legacy_sheep uuid;
    v_legacy_bovine uuid;
    v_unknown_tagged uuid;
    v_unknown_species_supported boolean := true;
    v_legacy_total integer;
    v_result jsonb;
    v_request uuid;
    v_selected uuid;
    v_failed boolean;
    v_before_orders bigint;
    v_after_orders bigint;
    v_before_requests bigint;
    v_after_requests bigint;
    v_before_history bigint;
    v_after_history bigint;
    v_before_income bigint;
    v_after_income bigint;
    v_sale jsonb := jsonb_build_object(
        'modo_venta', 'POR_PIEZA',
        'precio_venta', '100',
        'comprador', 'T097 Buyer',
        'forma_pago', 'EFECTIVO');
BEGIN
    SELECT coalesce(max(id_company), 0) + 1001 INTO v_company_a FROM public.companys;
    v_company_b := v_company_a + 1;
    INSERT INTO public.companys (id_company, company_name, is_active)
    VALUES (v_company_a, 'T097 Synthetic A', true), (v_company_b, 'T097 Synthetic B', true);

    INSERT INTO public.users (email, tenant_id, names, lastname, phone, password, role, is_active)
    VALUES
        (v_admin, v_company_a, 'Test', 'Admin', NULL, encode(sha256(convert_to('t097-only', 'UTF8')), 'hex'), 'ADMIN', true),
        (v_reader, v_company_a, 'Test', 'Reader', NULL, encode(sha256(convert_to('t097-only', 'UTF8')), 'hex'), 'CUSTOMER', true);
    INSERT INTO public.user_companies (email, id_company, role, is_active)
    VALUES (v_admin, v_company_a, 'ADMIN', true), (v_reader, v_company_a, 'CUSTOMER', true);

    v_upp_sequence := v_company_a % 10000;
    LOOP
        v_upp_a := '99-097-' || lpad(v_upp_sequence::text, 4, '0') || '-001';
        v_upp_b := '99-097-' || lpad(((v_upp_sequence + 1) % 10000)::text, 4, '0') || '-001';
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.production_units
             WHERE is_active AND upp_code IN (v_upp_a, v_upp_b));
        v_upp_sequence := (v_upp_sequence + 2) % 10000;
    END LOOP;
    INSERT INTO public.production_units (id_company, upp_code, ranch_name)
    VALUES (v_company_a, v_upp_a, 'T097 Synthetic UPP A')
    RETURNING id INTO v_unit_a;
    INSERT INTO public.production_units (id_company, upp_code, ranch_name)
    VALUES (v_company_b, v_upp_b, 'T097 Synthetic UPP B')
    RETURNING id INTO v_unit_b;
    INSERT INTO public.production_unit_lots (id_company, production_unit_id, lot_name, tenure_type)
    VALUES (v_company_a, v_unit_a, 'T097 FIFO', 'PROPIO') RETURNING id INTO v_fifo_lot;
    INSERT INTO public.production_unit_lots (id_company, production_unit_id, lot_name, tenure_type)
    VALUES (v_company_a, v_unit_a, 'T097 Legacy', 'PROPIO') RETURNING id INTO v_legacy_lot;
    INSERT INTO public.production_unit_lots (id_company, production_unit_id, lot_name, tenure_type)
    VALUES (v_company_b, v_unit_b, 'T097 Foreign', 'PROPIO') RETURNING id INTO v_foreign_lot;

    INSERT INTO public.cattle_livestock
        (id, tenant_id, business_model, category, current_status, species, production_unit_id, lot_id, created_at, metadata)
    VALUES
        (v_tie_low, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_fifo_lot, timestamp '2026-01-02 08:00:00', '{"test_key":"T097-tie-low"}'),
        (v_tie_high, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_fifo_lot, timestamp '2026-01-02 08:00:00', '{"test_key":"T097-tie-high"}'),
        (v_oldest, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_fifo_lot, timestamp '2026-01-01 08:00:00', '{"test_key":"T097-oldest"}'),
        (v_pending, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_fifo_lot, timestamp '2026-01-03 08:00:00', '{"test_key":"T097-pending"}'),
        (v_tagged, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_fifo_lot, timestamp '2026-01-04 08:00:00', '{"test_key":"T097-tagged"}'),
        (v_bovine, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', 'BOVINO', v_unit_a, v_fifo_lot, timestamp '2026-01-05 08:00:00', '{"test_key":"T097-bovine"}'),
        ('00000097-0000-4000-8000-000000000008', v_company_b, 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_b, v_foreign_lot, timestamp '2026-01-01 08:00:00', '{"test_key":"T097-foreign"}');
    UPDATE public.cattle_livestock SET rfid_siniiga = 'T097-TAG' WHERE id = v_tagged;

    BEGIN
        INSERT INTO public.cattle_livestock
            (id, tenant_id, business_model, category, current_status, species, production_unit_id, lot_id, created_at, metadata)
        VALUES (v_unknown, v_company_a, 'CRIA', 'BORREGA', 'ACTIVO', NULL, v_unit_a, v_fifo_lot,
                timestamp '2026-01-06 08:00:00', '{"test_key":"T097-null-species"}');
    EXCEPTION WHEN not_null_violation OR check_violation THEN
        v_unknown_species_supported := false;
        RAISE NOTICE 'SKIP: the current schema does not accept a NULL species fixture';
    END;

    INSERT INTO public.cattle_livestock
        (tenant_id, rfid_siniiga, business_model, category, current_status, species, production_unit_id, lot_id, metadata)
    VALUES (v_company_a, 'T097-LEGACY-SHEEP', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO', v_unit_a, v_legacy_lot, '{"test_key":"T097-legacy-sheep"}')
    RETURNING id INTO v_legacy_sheep;
    INSERT INTO public.cattle_livestock
        (tenant_id, rfid_siniiga, business_model, category, current_status, species, production_unit_id, lot_id, metadata)
    VALUES (v_company_a, 'T097-LEGACY-BOVINE', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', v_unit_a, v_legacy_lot, '{"test_key":"T097-legacy-bovine"}')
    RETURNING id INTO v_legacy_bovine;

    BEGIN
        INSERT INTO public.cattle_livestock
            (tenant_id, numero_fuego, business_model, category, current_status, species, production_unit_id, lot_id, metadata)
        VALUES (v_company_a, 'T097-UNKNOWN-TAG', 'CRIA', 'VACA', 'ACTIVO', NULL, v_unit_a, v_legacy_lot, '{"test_key":"T097-null-tag"}')
        RETURNING id INTO v_unknown_tagged;
    EXCEPTION WHEN not_null_violation OR check_violation THEN
        v_unknown_tagged := NULL;
    END;
    v_legacy_total := 2 + CASE WHEN v_unknown_tagged IS NOT NULL THEN 1 ELSE 0 END;

    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
    VALUES (v_company_a, v_pending, 'VENTA', '{"fecha_evento":"2026-11-04"}', v_admin);

    IF NOT public.fn_species_requires_bovine_compliance('BOVINO'::varchar)
       OR NOT public.fn_species_requires_bovine_compliance(NULL::varchar)
       OR public.fn_species_requires_bovine_compliance('BORREGO'::varchar) THEN
        RAISE EXCEPTION 'FAIL: the 096 guide rule helper changed';
    END IF;

    SELECT count(*) INTO v_before_orders FROM public.sale_orders;
    SELECT count(*) INTO v_before_requests FROM public.pending_authorizations;
    SELECT count(*) INTO v_before_history FROM public.historico_movimientos;
    SELECT count(*) INTO v_before_income FROM public.cattle_sale_income;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'borrega', 'cantidad', 3, 'seleccion', ' fifo ')),
        v_admin, NULL, true, 'TEST');

    IF (v_result->>'success')::boolean IS DISTINCT FROM true
       OR (v_result->>'validos')::int IS DISTINCT FROM 3
       OR jsonb_array_length(v_result->'seleccionados') <> 3
       OR v_result->'seleccionados'->0->>'livestock_id' IS DISTINCT FROM v_oldest::text
       OR v_result->'seleccionados'->1->>'livestock_id' IS DISTINCT FROM v_tie_low::text
       OR v_result->'seleccionados'->2->>'livestock_id' IS DISTINCT FROM v_tie_high::text
       OR v_result->'seleccionados'->0->>'categoria' IS DISTINCT FROM 'BORREGA'
       OR v_result->'seleccionados'->0->>'lote' IS DISTINCT FROM 'T097 FIFO'
       OR v_result->'seleccionados'->0->>'capturado' IS NULL
       OR v_result->'grupos'->0->>'seleccion' IS DISTINCT FROM 'FIFO'
       OR jsonb_array_length(v_result->'grupos'->0->'aretes') <> 0 THEN
        RAISE EXCEPTION 'FAIL: FIFO order, tie-break, preview fields, or tag omission: %', v_result;
    END IF;
    SELECT count(*) INTO v_after_orders FROM public.sale_orders;
    SELECT count(*) INTO v_after_requests FROM public.pending_authorizations;
    SELECT count(*) INTO v_after_history FROM public.historico_movimientos;
    SELECT count(*) INTO v_after_income FROM public.cattle_sale_income;
    IF v_after_orders <> v_before_orders OR v_after_requests <> v_before_requests
       OR v_after_history <> v_before_history OR v_after_income <> v_before_income
       OR EXISTS (SELECT 1 FROM public.cattle_livestock
                   WHERE id IN (v_oldest, v_tie_low, v_tie_high, v_pending, v_tagged, v_bovine)
                     AND current_status <> 'ACTIVO') THEN
        RAISE EXCEPTION 'FAIL: preview wrote to persistent records';
    END IF;
    RAISE NOTICE 'OK: FIFO oldest-first, id tie-break, eligible preview fields, and preview is read-only';

    IF v_result->'seleccionados' @> jsonb_build_array(jsonb_build_object('livestock_id', v_tagged))
       OR v_result->'seleccionados' @> jsonb_build_array(jsonb_build_object('livestock_id', v_bovine)) THEN
        RAISE EXCEPTION 'FAIL: tagged or bovine animal entered FIFO selection';
    END IF;
    IF v_unknown_species_supported
       AND v_result->'seleccionados' @> jsonb_build_array(jsonb_build_object('livestock_id', v_unknown)) THEN
        RAISE EXCEPTION 'FAIL: NULL-species animal entered FIFO selection';
    END IF;
    RAISE NOTICE 'OK: tagged, bovine, and NULL-species animals are excluded from FIFO selection';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 4, 'seleccion', 'FIFO')),
        v_admin, NULL, true, 'TEST');
    IF (v_result->>'success')::boolean IS DISTINCT FROM false
       OR v_result->'errores'->0->>'error' NOT LIKE '%tiene 3 animal(es) elegible(s)%'
       OR v_result->'errores'->0->>'error' NOT LIKE '%bovinos y los animales identificados nunca se seleccionan automáticamente%' THEN
        RAISE EXCEPTION 'FAIL: insufficient FIFO pool message: %', v_result;
    END IF;
    SELECT count(*) INTO v_before_orders FROM public.sale_orders;
    v_failed := false;
    BEGIN
        PERFORM public.sp_solicitar_venta_orden(
            jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 4, 'seleccion', 'FIFO')),
            v_admin, NULL, false, 'TEST');
    EXCEPTION WHEN SQLSTATE 'P0034' THEN
        v_failed := true;
    END;
    SELECT count(*) INTO v_after_orders FROM public.sale_orders;
    IF NOT v_failed OR v_after_orders <> v_before_orders THEN
        RAISE EXCEPTION 'FAIL: an undersized FIFO request created an order';
    END IF;
    RAISE NOTICE 'OK: insufficient FIFO pool reports its size and creates no order';

    FOREACH v_result IN ARRAY ARRAY[
        public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'cantidad', 1, 'seleccion', 'FIFO')), v_admin, NULL, true, 'TEST'),
        public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'seleccion', 'FIFO')), v_admin, NULL, true, 'TEST'),
        public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 0, 'seleccion', 'FIFO')), v_admin, NULL, true, 'TEST')
    ] LOOP
        IF (v_result->>'success')::boolean IS DISTINCT FROM false
           OR v_result->'errores'->0->>'error' NOT LIKE '%requiere lote, categoría y una cantidad entera positiva%' THEN
            RAISE EXCEPTION 'FAIL: FIFO required fields were not validated: %', v_result;
        END IF;
    END LOOP;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'random')),
        v_admin, NULL, true, 'TEST');
    IF v_result->'errores'->0->>'error' IS DISTINCT FROM 'Selección no válida' THEN
        RAISE EXCEPTION 'FAIL: unsupported selection value was accepted: %', v_result;
    END IF;
    RAISE NOTICE 'OK: FIFO required fields and unsupported selection values';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 Foreign', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
        v_admin, NULL, true, 'TEST');
    IF (v_result->>'validos')::int <> 0
       OR v_result->'errores'->0->>'error' IS DISTINCT FROM 'No existe ese lote en tus empresas' THEN
        RAISE EXCEPTION 'FAIL: a lot outside writer memberships was visible: %', v_result;
    END IF;
    v_failed := false;
    BEGIN
        PERFORM public.sp_solicitar_venta_orden(
            jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
            v_reader, NULL, true, 'TEST');
    EXCEPTION WHEN SQLSTATE 'P0035' THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'FAIL: a read-only membership was allowed to preview a sale';
    END IF;
    RAISE NOTICE 'OK: writer membership scope and read-only rejection';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
        v_admin, NULL, false, 'TEST');
    IF (v_result->>'success')::boolean IS DISTINCT FROM true OR (v_result->>'solicitudes')::int <> 1 THEN
        RAISE EXCEPTION 'FAIL: first FIFO order was not created: %', v_result;
    END IF;
    SELECT pa.livestock_id INTO v_selected
      FROM public.pending_authorizations pa
     WHERE pa.sale_order_id = (v_result->>'order_id')::uuid AND pa.estado = 'PENDIENTE';
    IF v_selected IS DISTINCT FROM v_oldest
       OR NOT EXISTS (SELECT 1 FROM public.pending_authorizations pa
                       WHERE pa.sale_order_id = (v_result->>'order_id')::uuid
                         AND pa.payload->>'seleccion_metodo' = 'FIFO_SIN_IDENTIFICADOR'
                         AND pa.payload->>'rfid_siniiga' IS NULL
                         AND pa.payload->>'numero_fuego' IS NULL
                         AND pa.payload->>'electronic_rfid' IS NULL) THEN
        RAISE EXCEPTION 'FAIL: FIFO pending payload or first selection is incorrect';
    END IF;
    RAISE NOTICE 'OK: FIFO payload records its selection method without identifiers';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
        v_admin, NULL, false, 'TEST');
    SELECT pa.livestock_id INTO v_selected
      FROM public.pending_authorizations pa
     WHERE pa.sale_order_id = (v_result->>'order_id')::uuid AND pa.estado = 'PENDIENTE';
    IF v_selected IS DISTINCT FROM v_tie_low OR v_selected = v_oldest THEN
        RAISE EXCEPTION 'FAIL: consecutive FIFO orders selected the same animal or ignored the id tie-break';
    END IF;
    RAISE NOTICE 'OK: consecutive FIFO orders never select the same animal';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
        v_admin, NULL, true, 'TEST');
    IF v_result->'seleccionados'->0->>'livestock_id' IS DISTINCT FROM v_tie_high::text THEN
        RAISE EXCEPTION 'FAIL: a pending-request animal was not skipped: %', v_result;
    END IF;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 FIFO', 'categoria', 'BORREGA', 'cantidad', 1, 'seleccion', 'FIFO')),
        v_admin, NULL, false, 'TEST');
    IF (v_result->>'success')::boolean IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'FAIL: FIFO request for the remaining animal was not created: %', v_result;
    END IF;
    SELECT pa.id INTO v_request
      FROM public.pending_authorizations pa
     WHERE pa.sale_order_id = (v_result->>'order_id')::uuid AND pa.livestock_id = v_tie_high;
    v_result := public.sp_resolver_autorizacion(v_request, 'APROBADO', v_admin, NULL, v_sale);
    IF (v_result->>'success')::boolean IS DISTINCT FROM true
       OR v_result->>'estado' IS DISTINCT FROM 'APROBADO'
       OR NOT EXISTS (SELECT 1 FROM public.cattle_sale_income si
                       WHERE si.tenant_id = v_company_a AND si.livestock_id = v_tie_high
                         AND si.pending_authorization_id = v_request) THEN
        RAISE EXCEPTION 'FAIL: FIFO approval did not register sale income: %', v_result;
    END IF;
    RAISE NOTICE 'OK: pending-request exclusion and end-to-end FIFO approval with income';

    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 Legacy', 'cantidad', v_legacy_total)),
        v_admin, NULL, true, 'TEST');
    IF (v_result->>'success')::boolean IS DISTINCT FROM true
       OR (v_result->>'validos')::int <> v_legacy_total
       OR v_result->'grupos'->0 ? 'seleccion'
       OR NOT (v_result->'grupos'->0 ?& ARRAY['empresa', 'upp', 'guia_transito', 'cantidad', 'por_categoria', 'aretes'])
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_result->'grupos'->0) AS keys(k))
          IS DISTINCT FROM ARRAY['aretes', 'cantidad', 'empresa', 'guia_transito', 'por_categoria', 'upp']
       OR v_result->'grupos'->0->'guia_transito' IS DISTINCT FROM 'null'::jsonb
       OR jsonb_array_length(v_result->'grupos'->0->'aretes') <> v_legacy_total
       OR v_result ? 'seleccionados' THEN
        RAISE EXCEPTION 'FAIL: non-FIFO preview group keys or lot behavior differ from 096: %', v_result;
    END IF;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('lote', 'T097 Legacy', 'cantidad', v_legacy_total - 1)),
        v_admin, NULL, true, 'TEST');
    IF v_result->'errores'->0->>'error' NOT LIKE ('%tiene ' || v_legacy_total::text || ' animal(es)%') THEN
        RAISE EXCEPTION 'FAIL: legacy lot quantity mismatch behavior changed: %', v_result;
    END IF;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('identificador', 'T097-LEGACY-SHEEP')),
        v_admin, NULL, true, 'TEST');
    IF (v_result->>'validos')::int <> 1 THEN
        RAISE EXCEPTION 'FAIL: single-animal non-bovine behavior changed: %', v_result;
    END IF;
    v_result := public.sp_solicitar_venta_orden(
        jsonb_build_array(jsonb_build_object('identificador', 'T097-LEGACY-BOVINE')),
        v_admin, NULL, true, 'TEST');
    IF v_result->'errores'->0->>'error' IS DISTINCT FROM 'Falta la guía de tránsito' THEN
        RAISE EXCEPTION 'FAIL: bovine guide rule changed: %', v_result;
    END IF;
    IF v_unknown_tagged IS NOT NULL THEN
        v_result := public.sp_solicitar_venta_orden(
            jsonb_build_array(jsonb_build_object('identificador', 'T097-UNKNOWN-TAG')),
            v_admin, NULL, true, 'TEST');
        IF v_result->'errores'->0->>'error' IS DISTINCT FROM 'Falta la guía de tránsito' THEN
            RAISE EXCEPTION 'FAIL: NULL-species guide rule changed: %', v_result;
        END IF;
    END IF;
    RAISE NOTICE 'OK: legacy lot and identifier paths retain the 096 guide behavior';
END $$;

ROLLBACK;
\echo '*** 097 tests finished: synthetic companies, data, and function replacement rolled back ***'
