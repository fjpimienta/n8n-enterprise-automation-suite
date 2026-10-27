-- 084_state_check.sql — READ-ONLY state assertions for migration 084 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 084_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 084_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 084_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 084 -> applied -> rollback -> rolled_back -> 084 -> applied.
-- The FINGERPRINT lines must be identical at every step: 084 only creates / replaces functions, one type and one
-- view and never touches a table, a column, a trigger, crud_models, the companies, memberships, animals or events.
-- The pre-existing reproduction procedures are fingerprinted too (phase 1 must not change them).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t084.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL
SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text, metadata::text), '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company))
  FROM user_companies
UNION ALL
SELECT 'cattle_livestock_data', md5(string_agg(row_to_json(l)::text, '|' ORDER BY l.id)) FROM cattle_livestock l
UNION ALL
SELECT 'birth_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM birth_events b
UNION ALL
SELECT 'breeding_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM cattle_breeding_events b
UNION ALL
SELECT 'health_logs_data', md5(string_agg(row_to_json(h)::text, '|' ORDER BY h.id)) FROM cattle_health_logs h
UNION ALL
SELECT 'weight_logs_data', md5(string_agg(row_to_json(w)::text, '|' ORDER BY w.id)) FROM cattle_weight_logs w
UNION ALL
SELECT 'event_voids_data', md5(string_agg(row_to_json(v)::text, '|' ORDER BY v.id)) FROM event_voids v
UNION ALL
SELECT 'preexisting_repro_procedures',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('sp_register_birth_event', 'sp_log_breeding_event', 'sp_log_palpation_event', 'sp_void_event');

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t084.expect');
    v_tools   text[] := ARRAY['sp_repro_list_births', 'sp_repro_dam_birth_history', 'sp_repro_births_summary',
                              'sp_repro_list_unregistered_historical_births', 'sp_repro_identifier_quality_report'];
    v_helpers text[] := ARRAY['fn_repro_txt', 'fn_repro_int', 'fn_repro_date', 'fn_repro_ctx', 'fn_is_placeholder_birth_date',
                              'fn_fire_number_shape', 'fn_estimate_birth_from_fire_number'];
    v_found   integer;
    v_company integer;
    v_email   text;
    v_status  text;
    v_blocked boolean := false;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_tools);

    IF v_expect = 'before' THEN
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: % tool function(s) already exist', v_found; END IF;
        IF to_regclass('public.vw_animal_effective_birth') IS NOT NULL THEN RAISE EXCEPTION 'FAIL: the view already exists'; END IF;
        RAISE NOTICE '084 state check (before): OK';
        RETURN;
    END IF;

    IF v_found <> 5 THEN RAISE EXCEPTION 'FAIL: expected 5 tool functions, found %', v_found; END IF;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 7 THEN RAISE EXCEPTION 'FAIL: expected 7 helper / parser functions, found %', v_found; END IF;
    IF to_regclass('public.vw_animal_effective_birth') IS NULL THEN RAISE EXCEPTION 'FAIL: the view is missing'; END IF;

    -- Shape of the tools: text parameters, never executable through the gateway.
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_tools)
                  AND (p.proargtypes[0] <> 'text'::regtype OR p.proargtypes[1] <> 'text'::regtype)) THEN
        RAISE EXCEPTION 'FAIL: a tool does not take (text, text, ...) as first parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_tools)
                  AND p.provolatile <> 's') THEN
        RAISE EXCEPTION 'FAIL: every reproduction tool must be STABLE (read-only)';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models WHERE table_name = 'vw_animal_effective_birth' OR model_name = 'vw_animal_effective_birth') THEN
        RAISE EXCEPTION 'FAIL: the internal view is exposed through crud_models';
    END IF;

    -- Parser, independent of the data.
    IF public.fn_fire_number_shape('26-45-4') <> 'CURRENT' OR public.fn_fire_number_shape('2097') <> 'LEGACY'
       OR public.fn_fire_number_shape('2534') <> 'UNCONFIRMED_SHAPE' OR public.fn_fire_number_shape('08-4 P') <> 'OTHER'
       OR (public.fn_estimate_birth_from_fire_number('2097')).birth_year IS DISTINCT FROM 2020
       OR (public.fn_estimate_birth_from_fire_number('26-45-4')).birth_month IS DISTINCT FROM 4 THEN
        RAISE EXCEPTION 'FAIL: parser answers are wrong';
    END IF;

    -- A real member of a non-palm company to probe the tool (read-only call).
    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
     WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
     ORDER BY uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
    RAISE NOTICE 'probe: company % (user not shown)', v_company;

    IF v_expect = 'applied' THEN
        v_status := sp_repro_list_births(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_births answered % (expected ok)', v_status; END IF;
        BEGIN
            PERFORM sp_repro_list_births(v_company::text, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;  -- expected: fail-closed
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer'; END IF;
    ELSE
        v_status := sp_repro_list_births(v_company::text, v_email)->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: list_births answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '084 state check (%): OK', v_expect;
END $$;

ROLLBACK;
