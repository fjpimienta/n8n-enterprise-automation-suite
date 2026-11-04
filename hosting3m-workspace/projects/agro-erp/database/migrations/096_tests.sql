-- 096_tests.sql: LOCAL / throwaway database only (needs 074 applied). Everything is rolled back.
-- psql -v ON_ERROR_STOP=1 -v tenant=3 -v admin=ADMIN_OR_EDITOR_EMAIL [-v other=ANOTHER_TEST_COMPANY] -f 096_tests.sql
-- 'admin' must be an active ADMIN or EDITOR of 'tenant' and must NOT belong to 'other'. Animals use the fake ear tag prefix T096- (not a 10-digit SINIIGA tag).
\set ON_ERROR_STOP on
\if :{?tenant}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL [-v other=COMPANY] -f 096_tests.sql'
\quit
\endif
\if :{?admin}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL [-v other=COMPANY] -f 096_tests.sql'
\quit
\endif
\if :{?other}
\else
\set other ''
\endif
BEGIN;
\set embedded true
\ir 096_species_scoped_sale_compliance.sql
SELECT set_config('t096.tenant', :'tenant', true) AS tenant, set_config('t096.admin', :'admin', true) AS admin, set_config('t096.other', :'other', true) AS other;

DO $$
DECLARE
    t        integer := current_setting('t096.tenant')::integer;
    a        text    := current_setting('t096.admin');
    o        text    := current_setting('t096.other');
    v_role   text;
    r        jsonb;
    n        bigint;
    v_raise  boolean;
    id_bor   uuid;  id_bor2 uuid; id_bor3 uuid; id_bor4 uuid; id_bor5 uuid;
    id_buf   uuid;  id_equ  uuid;
    id_bov   uuid;  id_bov2 uuid; id_bov3 uuid; id_bov4 uuid; id_low uuid; id_nul uuid; id_emp uuid;
    v_items  jsonb;
    v_ok     boolean;
BEGIN
    SELECT uc.role INTO v_role FROM public.user_companies uc WHERE uc.id_company = t AND lower(uc.email) = lower(a) AND uc.is_active IS TRUE LIMIT 1;
    IF upper(coalesce(v_role, '')) NOT IN ('ADMIN', 'EDITOR') THEN RAISE EXCEPTION 'SETUP: % is not an active ADMIN/EDITOR of company %', a, t; END IF;
    SELECT count(*) INTO n FROM public.cattle_livestock WHERE rfid_siniiga LIKE 'T096-%';
    IF n <> 0 THEN RAISE EXCEPTION 'SETUP: T096- fixtures already exist'; END IF;
    IF o <> '' THEN
        SELECT count(*) INTO n FROM public.user_companies uc WHERE uc.id_company = o::integer AND lower(uc.email) = lower(a) AND uc.is_active IS TRUE;
        IF n <> 0 THEN RAISE EXCEPTION 'SETUP: % belongs to company % (it must not)', a, o; END IF;
    END IF;

    -- fixtures: none has an official 10-digit ear tag, none has TB/BR dates, none has a production unit (no herd-free certificate)
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOR1', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO') RETURNING id INTO id_bor;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOR2', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO') RETURNING id INTO id_bor2;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOR3', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO') RETURNING id INTO id_bor3;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOR4', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO') RETURNING id INTO id_bor4;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOR5', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO') RETURNING id INTO id_bor5;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BUF1', 'CRIA', 'BUFALA', 'ACTIVO', 'BUFALO') RETURNING id INTO id_buf;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-EQU1', 'CRIA', 'YEGUA', 'ACTIVO', 'EQUIDO') RETURNING id INTO id_equ;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOV1', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO') RETURNING id INTO id_bov;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOV2', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO') RETURNING id INTO id_bov2;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOV3', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO') RETURNING id INTO id_bov3;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-BOV4', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO') RETURNING id INTO id_bov4;
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-LOW1', 'CRIA', 'VACA', 'ACTIVO', 'bovino') RETURNING id INTO id_low;

    -- T1 helper truth table
    IF NOT (public.fn_species_requires_bovine_compliance('BOVINO'::varchar) AND public.fn_species_requires_bovine_compliance(' Bovino '::varchar)
            AND public.fn_species_requires_bovine_compliance(NULL::varchar) AND public.fn_species_requires_bovine_compliance(''::varchar))
       OR public.fn_species_requires_bovine_compliance('BORREGO'::varchar) OR public.fn_species_requires_bovine_compliance('BUFALO'::varchar)
       OR public.fn_species_requires_bovine_compliance('EQUIDO'::varchar) OR public.fn_species_requires_bovine_compliance('OVINO'::varchar) THEN
        RAISE EXCEPTION 'FAIL T1 helper truth table';
    END IF;
    RAISE NOTICE 'OK T1 helper truth table';

    -- T2 approval path (sp_procesar_venta_autorizada): sheep, buffalo and equine sell with no ear tag and no TB/BR
    FOREACH n IN ARRAY ARRAY[1, 2, 3] LOOP
        r := public.sp_procesar_venta_autorizada(CASE n WHEN 1 THEN id_bor WHEN 2 THEN id_buf ELSE id_equ END, t, false, a, NULL, NULL);
        IF (r ->> 'success')::boolean IS NOT TRUE OR r ->> 'current_status' <> 'VENDIDO' THEN RAISE EXCEPTION 'FAIL T2 exempt species case %: %', n, r; END IF;
    END LOOP;
    SELECT count(*) INTO n FROM public.historico_movimientos WHERE livestock_id IN (id_bor, id_buf, id_equ) AND tipo_movimiento = 'VENTA' AND tenant_id = t;
    IF n <> 3 THEN RAISE EXCEPTION 'FAIL T2 history rows: %', n; END IF;
    SELECT count(*) INTO n FROM public.cattle_livestock WHERE id IN (id_bor, id_buf, id_equ) AND current_status = 'VENDIDO' AND tenant_id = t;
    IF n <> 3 THEN RAISE EXCEPTION 'FAIL T2 animals not sold: %', n; END IF;
    RAISE NOTICE 'OK T2 sheep, buffalo and equine sell without ear tag or TB/BR';

    -- T3 the bovine regime is unchanged: a BOVINO without tag or tests is still refused (exception not available for the missing tag), a lower-case species too
    FOREACH n IN ARRAY ARRAY[1, 2] LOOP
        r := public.sp_procesar_venta_autorizada(CASE n WHEN 1 THEN id_bov ELSE id_low END, t, false, a, NULL, NULL);
        IF (r ->> 'success')::boolean IS NOT FALSE OR r ->> 'motivo' NOT LIKE '%Sin arete oficial SINIIGA%' OR r ->> 'motivo' NOT LIKE '%Prueba TB%'
           OR r ->> 'motivo' NOT LIKE '%Prueba Brucelosis%' OR (r ->> 'excepcion_disponible')::boolean IS NOT FALSE THEN
            RAISE EXCEPTION 'FAIL T3 bovine case %: %', n, r;
        END IF;
    END LOOP;
    r := public.sp_procesar_venta_autorizada(id_bov, t, true, a, 'prueba', NULL);   -- the sanitary exception does not waive the missing tag
    IF (r ->> 'success')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'FAIL T3 exception waived the ear tag: %', r; END IF;
    SELECT count(*) INTO n FROM public.cattle_livestock WHERE id IN (id_bov, id_low) AND current_status = 'ACTIVO';
    IF n <> 2 THEN RAISE EXCEPTION 'FAIL T3 bovine animals changed status'; END IF;
    RAISE NOTICE 'OK T3 BOVINO (any case) keeps the full compliance check';

    -- T4 unknown or empty species is fail-closed (skipped when the column does not accept NULL/empty)
    BEGIN
        INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-NUL1', 'CRIA', 'VACA', 'ACTIVO', 'BOVINO') RETURNING id INTO id_nul;
        UPDATE public.cattle_livestock SET species = NULL WHERE id = id_nul;
        r := public.sp_procesar_venta_autorizada(id_nul, t, false, a, NULL, NULL);
        IF (r ->> 'success')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'FAIL T4 NULL species sold: %', r; END IF;
        RAISE NOTICE 'OK T4 NULL species stays strict';
    EXCEPTION WHEN not_null_violation THEN
        RAISE NOTICE 'SKIP T4 NULL species (column is NOT NULL)';
    END;
    BEGIN
        INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (t, 'T096-EMP1', 'CRIA', 'VACA', 'ACTIVO', '') RETURNING id INTO id_emp;
        r := public.sp_procesar_venta_autorizada(id_emp, t, false, a, NULL, NULL);
        IF (r ->> 'success')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'FAIL T4 empty species sold: %', r; END IF;
        RAISE NOTICE 'OK T4 empty species stays strict';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'SKIP T4 empty species (rejected by a constraint)';
    END;

    -- T5 tenant isolation of the approval path is unchanged: the same animal under another company is not found
    v_raise := false;
    BEGIN PERFORM public.sp_procesar_venta_autorizada(id_bov2, t + 100000, false, a, NULL, NULL); EXCEPTION WHEN SQLSTATE 'P0002' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T5 wrong tenant was accepted'; END IF;
    RAISE NOTICE 'OK T5 wrong tenant is refused';

    -- T6 direct sale from the web panel (5-parameter overload, by livestock_id and by ear tag): sheep sells, bovine is refused
    r := public.sp_procesar_salida_ganado(NULL::varchar, t, NULL::varchar, NULL::varchar, id_bor2);
    IF (r ->> 'success')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'FAIL T6 sheep by id: %', r; END IF;
    r := public.sp_procesar_salida_ganado(NULL::varchar, t, 'T096-BOV2'::varchar, NULL::varchar, NULL::uuid);
    IF (r ->> 'success')::boolean IS NOT FALSE OR r ->> 'motivo' NOT LIKE '%Sin arete oficial SINIIGA%' THEN RAISE EXCEPTION 'FAIL T6 bovine by tag: %', r; END IF;
    r := public.sp_procesar_salida_ganado(NULL::varchar, t, 'T096-BOR5'::varchar, NULL::varchar, NULL::uuid);
    IF (r ->> 'success')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'FAIL T6 sheep by tag: %', r; END IF;
    RAISE NOTICE 'OK T6 direct sale (5-parameter overload)';

    -- T7 sale order preview: a sheep needs no guide, a bovine without guide is refused, a bovine with guide passes
    v_items := jsonb_build_array(jsonb_build_object('identificador', 'T096-BOR3'),
                                 jsonb_build_object('identificador', 'T096-BOV3'),
                                 jsonb_build_object('identificador', 'T096-BOV4', 'guia_transito', 'G-096'));
    r := public.sp_solicitar_venta_orden(v_items, a, NULL, true, 'TEST');
    IF (r ->> 'success')::boolean IS NOT FALSE OR jsonb_array_length(r -> 'errores') <> 1
       OR r -> 'errores' -> 0 ->> 'identificador' <> 'T096-BOV3' OR r -> 'errores' -> 0 ->> 'error' <> 'Falta la guía de tránsito'
       OR (r ->> 'validos')::int <> 2 THEN
        RAISE EXCEPTION 'FAIL T7 preview: %', r;
    END IF;
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'grupos') g
                    WHERE g ->> 'guia_transito' IS NULL AND (g -> 'por_categoria' ->> 'BORREGA')::int = 1 AND (g ->> 'cantidad')::int = 1)
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'grupos') g
                    WHERE g ->> 'guia_transito' = 'G-096' AND (g -> 'por_categoria' ->> 'VACA')::int = 1)
      INTO v_ok;
    IF NOT v_ok THEN RAISE EXCEPTION 'FAIL T7 groups (a group without guide must still count its categories): %', r -> 'grupos'; END IF;
    RAISE NOTICE 'OK T7 preview: guide required only for the bovine';

    -- T8 an unknown identifier reports that it does not exist, not a missing guide
    r := public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('identificador', 'T096-NOEXISTE')), a, NULL, true, 'TEST');
    IF r -> 'errores' -> 0 ->> 'error' <> 'No existe en tus empresas' THEN RAISE EXCEPTION 'FAIL T8: %', r; END IF;
    RAISE NOTICE 'OK T8 unknown identifier';

    -- T9 creating an order of sheep without guide: one pending request per animal, in the animal's company, with no guide in the payload
    r := public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('identificador', 'T096-BOR4')), a, NULL, false, 'TEST');
    IF (r ->> 'success')::boolean IS NOT TRUE OR (r ->> 'solicitudes')::int <> 1 THEN RAISE EXCEPTION 'FAIL T9 create: %', r; END IF;
    SELECT count(*) INTO n FROM public.pending_authorizations pa
     WHERE pa.livestock_id = id_bor4 AND pa.id_company = t AND pa.tipo_evento = 'VENTA' AND pa.estado = 'PENDIENTE'
       AND NOT (pa.payload ? 'guia_transito') AND pa.sale_order_id IS NOT NULL;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL T9 pending request'; END IF;
    -- a bovine without guide cannot be created
    v_raise := false;
    BEGIN PERFORM public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('identificador', 'T096-BOV3')), a, NULL, false, 'TEST'); EXCEPTION WHEN SQLSTATE 'P0034' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T9 bovine order without guide was created'; END IF;
    RAISE NOTICE 'OK T9 order of sheep without guide';

    -- T10 (optional) an animal of another company stays invisible, whatever its species
    IF o <> '' THEN
        INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, species) VALUES (o::integer, 'T096-OTH1', 'CRIA', 'BORREGA', 'ACTIVO', 'BORREGO');
        r := public.sp_solicitar_venta_orden(jsonb_build_array(jsonb_build_object('identificador', 'T096-OTH1')), a, NULL, true, 'TEST');
        IF r -> 'errores' -> 0 ->> 'error' <> 'No existe en tus empresas' OR (r ->> 'validos')::int <> 0 THEN RAISE EXCEPTION 'FAIL T10 foreign animal visible: %', r; END IF;
        RAISE NOTICE 'OK T10 other company stays isolated';
    ELSE
        RAISE NOTICE 'SKIP T10 (pass -v other=COMPANY to run it)';
    END IF;

    RAISE NOTICE 'ALL 096 TESTS OK';
END $$;
ROLLBACK;
\echo '*** 096 tests finished: everything rolled back ***'
