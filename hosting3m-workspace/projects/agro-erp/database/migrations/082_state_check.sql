-- 082_state_check.sql — READ-ONLY state assertions for migration 082 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK. Exits non-zero (with ON_ERROR_STOP) when an assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 082_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 082_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 082_state_check.sql
--
-- The FINGERPRINT lines must be identical before, after and after the rollback: 082 only creates / replaces
-- one function and never touches data, crud_models or the companies.

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t082.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL
SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text), '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'cattle_expenses_data', md5(string_agg(row_to_json(e)::text, '|' ORDER BY e.id)) FROM cattle_expenses e
UNION ALL
SELECT 'agri_expenses_data', md5(coalesce(string_agg(row_to_json(e)::text, '|' ORDER BY e.id), '')) FROM agri_expenses e;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect   text := current_setting('t082.expect');
    v_exists   boolean := to_regprocedure('public.fn_reject_palm_company(integer)') IS NOT NULL;
    v_palm     integer;
    v_cattle   integer;
    v_rejects  boolean;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;

    SELECT min(id_company) INTO v_palm FROM companys WHERE fn_company_business_domain(id_company) = 'PALM';
    SELECT min(id_company) INTO v_cattle FROM companys WHERE fn_company_business_domain(id_company) = 'LIVESTOCK';
    RAISE NOTICE 'sample companies: palm=% livestock=%', v_palm, v_cattle;

    IF v_expect = 'before' THEN
        IF v_exists THEN RAISE EXCEPTION 'FAIL: fn_reject_palm_company already exists'; END IF;
        RAISE NOTICE '082 state check (before): OK';
        RETURN;
    END IF;

    IF NOT v_exists THEN RAISE EXCEPTION 'FAIL: fn_reject_palm_company missing'; END IF;
    IF NOT fn_reject_palm_company(v_cattle) OR NOT fn_reject_palm_company(NULL) THEN
        RAISE EXCEPTION 'FAIL: a livestock company or NULL must pass';
    END IF;

    BEGIN
        PERFORM fn_reject_palm_company(v_palm);
        v_rejects := false;
    EXCEPTION WHEN SQLSTATE 'P0094' THEN
        v_rejects := true;
    END;

    IF v_expect = 'applied' AND NOT v_rejects THEN RAISE EXCEPTION 'FAIL: palm company % is not rejected', v_palm; END IF;
    IF v_expect = 'rolled_back' AND v_rejects THEN RAISE EXCEPTION 'FAIL: palm company % is still rejected', v_palm; END IF;
    RAISE NOTICE '082 state check (%): OK', v_expect;
END $$;

ROLLBACK;
