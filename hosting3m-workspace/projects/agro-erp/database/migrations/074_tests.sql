-- 074_tests.sql — functional checks for migration 074 (LOCAL only). Everything is rolled back at the end.
-- Uses the 38 animals registered by alta_38_bendicion_20261015.sql (company 5: 33, company 8: 5)
-- and fjpimienta@gmail.com (member of company 5, NOT of company 8).
BEGIN;

DO $$
DECLARE
    v_user  text := 'fjpimienta@gmail.com';
    v_8     jsonb := '[
      {"identificador":"0724019910","guia_transito":"7139697"},{"identificador":"0724019803","guia_transito":"7139697"},
      {"identificador":"0724019869","guia_transito":"7139697"},{"identificador":"0724388322","guia_transito":"7139697"},
      {"identificador":"0724388335","guia_transito":"7139697"},
      {"identificador":"0724019854","guia_transito":"7139698"},{"identificador":"0724019858","guia_transito":"7139698"},
      {"identificador":"0724388300","guia_transito":"7139698"}]';
    v_res   jsonb;
    v_n     int;
    v_req   uuid;
BEGIN
    IF (SELECT count(*) FROM cattle_livestock WHERE metadata->>'source' = 'REGULARIZACION_PADRON'
          AND metadata->>'guia_transito' IN ('7139696','7139697','7139698') AND current_status = 'ACTIVO') <> 38 THEN
        RAISE EXCEPTION 'precondition: the 38 animals must be registered and ACTIVO';
    END IF;

    -- T1: preview by a user that is NOT a member of company 8 -> 3 valid, 5 errors, nothing written
    v_res := sp_solicitar_venta_orden(v_8, v_user, DATE '2026-10-09', true, 'TEST');
    RAISE NOTICE 'T1 %: validos=% errores=% (%)',
        CASE WHEN (v_res->>'validos')::int = 3 AND jsonb_array_length(v_res->'errores') = 5
              AND v_res->'errores'->0->>'error' = 'No existe en tus empresas' THEN 'OK' ELSE 'FAIL' END,
        v_res->>'validos', jsonb_array_length(v_res->'errores'), v_res->'errores'->0->>'error';

    -- T2: create the same order -> rejected as a whole (all-or-nothing)
    BEGIN
        PERFORM sp_solicitar_venta_orden(v_8, v_user, DATE '2026-10-09', false, 'TEST');
        RAISE NOTICE 'T2 FAIL: order with foreign animals was created';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T2 % (%): %', CASE WHEN SQLSTATE = 'P0034' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, left(SQLERRM, 90);
    END;
    SELECT count(*) INTO v_n FROM sale_orders WHERE channel = 'TEST';
    RAISE NOTICE 'T2b %: sale_orders created = %', CASE WHEN v_n = 0 THEN 'OK' ELSE 'FAIL' END, v_n;

    -- Make the user a plain member (EDITOR) of company 8 for the rest of the test (rolled back)
    INSERT INTO user_companies (email, id_company, role, is_active) VALUES (v_user, 8, 'EDITOR', true);

    -- T3: preview of the full 38 -> 38 valid in 3 groups (Maceo/7139696, Santa Lucía/7139697, San José/7139698)
    v_res := sp_solicitar_venta_orden(
        (SELECT jsonb_agg(jsonb_build_object('identificador', rfid_siniiga, 'guia_transito', metadata->>'guia_transito'))
           FROM cattle_livestock WHERE metadata->>'source' = 'REGULARIZACION_PADRON'
            AND metadata->>'guia_transito' IN ('7139696','7139697','7139698')),
        v_user, DATE '2026-10-09', true, 'TEST');
    RAISE NOTICE 'T3 %: validos=% grupos=%',
        CASE WHEN (v_res->>'validos')::int = 38 AND jsonb_array_length(v_res->'grupos') = 3 THEN 'OK' ELSE 'FAIL' END,
        v_res->>'validos', (SELECT string_agg((g->>'empresa') || ' / ' || (g->>'guia_transito') || ': ' || (g->>'cantidad'), ' | ')
                              FROM jsonb_array_elements(v_res->'grupos') g);

    -- T4: create the 8-animal order (2 companies) -> 8 requests, same order, guide per group
    v_res := sp_solicitar_venta_orden(v_8, v_user, DATE '2026-10-09', false, 'TEST');
    SELECT count(*) INTO v_n FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid;
    RAISE NOTICE 'T4 %: % solicitudes, orden %, empresas %, guías %',
        CASE WHEN v_n = 8
              AND (SELECT count(DISTINCT id_company) FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid) = 2
              AND (SELECT count(*) FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid
                     AND id_company = 8 AND payload->>'guia_transito' = '7139697') = 5
              AND (SELECT count(*) FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid
                     AND id_company = 5 AND payload->>'guia_transito' = '7139698') = 3
             THEN 'OK' ELSE 'FAIL' END,
        v_n, v_res->>'orden_venta',
        (SELECT string_agg(DISTINCT id_company::text, ',') FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid),
        (SELECT string_agg(DISTINCT payload->>'guia_transito', ',') FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid);

    -- T4b: every request carries the order-level counts (8 animals, 2 companies)
    RAISE NOTICE 'T4b %: payload counts',
        CASE WHEN NOT EXISTS (SELECT 1 FROM pending_authorizations WHERE sale_order_id = (v_res->>'order_id')::uuid
                                AND (payload->>'orden_total_animales' IS DISTINCT FROM '8'
                                     OR payload->>'orden_total_empresas' IS DISTINCT FROM '2'))
             THEN 'OK' ELSE 'FAIL' END;

    -- T5: the same animals again -> rejected (already pending)
    BEGIN
        PERFORM sp_solicitar_venta_orden(v_8, v_user, DATE '2026-10-09', false, 'TEST');
        RAISE NOTICE 'T5 FAIL: duplicated order created';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T5 % (%): %', CASE WHEN SQLERRM LIKE '%pendiente%' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, left(SQLERRM, 90);
    END;

    -- T6: missing guide and repeated identifier are reported in preview
    v_res := sp_solicitar_venta_orden('[{"identificador":"0724756966"},
                                        {"identificador":"0724756963","guia_transito":"7139696"},
                                        {"identificador":"0724756963","guia_transito":"7139696"}]', v_user, NULL, true, 'TEST');
    RAISE NOTICE 'T6 %: %',
        CASE WHEN (v_res->>'validos')::int = 0
              AND v_res->'errores' @> '[{"error":"Falta la guía de tránsito"}]'
              AND v_res->'errores' @> '[{"error":"Identificador repetido en la orden"}]' THEN 'OK' ELSE 'FAIL' END,
        v_res->'errores';

    -- T7: a future sale date is rejected
    BEGIN
        PERFORM sp_solicitar_venta_orden('[{"identificador":"0724756966","guia_transito":"7139696"}]', v_user,
                                         (now() AT TIME ZONE 'America/Mexico_City')::date + 1, true, 'TEST');
        RAISE NOTICE 'T7 FAIL: future date accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T7 % (%): %', CASE WHEN SQLSTATE = 'P0033' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, left(SQLERRM, 80);
    END;

    -- T8: a requester who is only EDITOR of company 8 cannot approve company 8's part (approval stays ADMIN-only)
    SELECT pa.id INTO v_req FROM pending_authorizations pa
     WHERE pa.id_company = 8 AND pa.estado = 'PENDIENTE' AND pa.sale_order_id IS NOT NULL LIMIT 1;
    BEGIN
        PERFORM sp_resolver_autorizacion(v_req, 'RECHAZADO', v_user, 'Prueba 074');
        RAISE NOTICE 'T8 FAIL: a non-ADMIN resolved a request of company 8';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T8 OK (%): %', SQLSTATE, left(SQLERRM, 80);
    END;

    -- T10: a read-only membership cannot request sales (role allowlist ADMIN/EDITOR)
    UPDATE user_companies SET role = 'CUSTOMER' WHERE email = v_user AND id_company = 8;
    v_res := sp_solicitar_venta_orden('[{"identificador":"0724019910","guia_transito":"7139697"}]', v_user, NULL, true, 'TEST');
    RAISE NOTICE 'T10 %: %',
        CASE WHEN v_res->'errores'->0->>'error' = 'Tu acceso a la empresa de este animal es de solo lectura' THEN 'OK' ELSE 'FAIL' END,
        v_res->'errores'->0->>'error';
    UPDATE user_companies SET role = 'EDITOR' WHERE email = v_user AND id_company = 8;

    -- T11: a second PENDIENTE for the same animal (any event type) is rejected with a friendly message (P0036)
    BEGIN
        INSERT INTO pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        SELECT id_company, livestock_id, 'BAJA_MORTANDAD', '{"causa_mortandad":"NATURAL"}', solicitado_por_email
          FROM pending_authorizations WHERE sale_order_id IS NOT NULL AND estado = 'PENDIENTE' LIMIT 1;
        RAISE NOTICE 'T11 FAIL: second PENDIENTE for the same animal accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T11 % (%): %', CASE WHEN SQLSTATE = 'P0036' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, left(SQLERRM, 110);
    END;
    RAISE NOTICE 'T11b %: unique index present',
        CASE WHEN to_regclass('public.uq_pending_auth_one_pending_per_animal') IS NOT NULL THEN 'OK' ELSE 'WARN (not created)' END;

    -- T9: unknown requester
    BEGIN
        PERFORM sp_solicitar_venta_orden(v_8, 'nadie@ejemplo.com', NULL, true, 'TEST');
        RAISE NOTICE 'T9 FAIL: unknown user accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T9 % (%): %', CASE WHEN SQLSTATE = 'P0031' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;
END $$;

ROLLBACK;
