-- 083_state_check.sql — READ-ONLY state assertions for migration 083 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 083_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 083_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 083_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 083 -> applied -> rollback -> rolled_back -> 083 -> applied.
-- The FINGERPRINT lines must be identical at every step: 083 only creates / replaces functions and never touches a
-- table, a view, crud_models, the companies or the memberships.

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t083.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL
SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text, metadata::text), '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company))
  FROM user_companies
UNION ALL
SELECT 'agri_structure_data',
       md5(concat_ws('#',
           (SELECT string_agg(row_to_json(p)::text, '|' ORDER BY p.id) FROM agri_plantations p),
           (SELECT string_agg(row_to_json(l)::text, '|' ORDER BY l.id) FROM agri_lots l),
           (SELECT string_agg(row_to_json(r)::text, '|' ORDER BY r.id) FROM agri_rows r),
           (SELECT string_agg(row_to_json(h)::text, '|' ORDER BY h.id) FROM agri_row_census_history h)))
UNION ALL
SELECT 'agri_expenses_data',
       md5(concat_ws('#',
           (SELECT string_agg(row_to_json(c)::text, '|' ORDER BY c.id) FROM agri_expense_categories c),
           (SELECT string_agg(row_to_json(e)::text, '|' ORDER BY e.id) FROM agri_expenses e)))
UNION ALL
SELECT 'cattle_expenses_data', md5(string_agg(row_to_json(e)::text, '|' ORDER BY e.id)) FROM cattle_expenses e;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect   text := current_setting('t083.expect');
    v_tools    text[] := ARRAY['sp_agri_chat_catalog', 'sp_agri_chat_structure', 'sp_agri_chat_lot_summary', 'sp_agri_chat_record_expense',
                               'sp_agri_chat_void_expense', 'sp_agri_chat_recent_expenses', 'sp_agri_chat_expense_balance',
                               'sp_agri_chat_record_row_census'];
    v_helpers  text[] := ARRAY['fn_agri_chat_txt', 'fn_agri_chat_key', 'fn_agri_chat_num', 'fn_agri_chat_date', 'fn_agri_chat_ctx',
                               'fn_agri_chat_resolve_scope'];
    v_found    integer;
    v_company  integer;
    v_email    text;
    v_status   text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_tools);
    IF v_expect = 'before' THEN
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: % tool function(s) already exist', v_found; END IF;
        RAISE NOTICE '083 state check (before): OK';
        RETURN;
    END IF;

    IF v_found <> 8 THEN RAISE EXCEPTION 'FAIL: expected 8 tool functions, found %', v_found; END IF;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 6 THEN RAISE EXCEPTION 'FAIL: expected 6 helper functions, found %', v_found; END IF;

    -- A palm company with an active ADMIN (the QA tenant 10 when it has one).
    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc
     WHERE upper(uc.role) = 'ADMIN' AND uc.is_active AND fn_company_business_domain(uc.id_company) = 'PALM'
     ORDER BY (uc.id_company = 10) DESC, uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no palm company with an active ADMIN to probe'; END IF;
    RAISE NOTICE 'probe: company % as %', v_company, v_email;

    v_status := sp_agri_chat_structure(v_company::text, v_email)->>'status';
    IF v_expect = 'applied' THEN
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: structure answered % (expected ok)', v_status; END IF;
        IF sp_agri_chat_structure(v_company::text, 'nadie@example.test')->>'status' <> 'forbidden' THEN
            RAISE EXCEPTION 'FAIL: a stranger is not forbidden';
        END IF;
        IF sp_agri_chat_catalog('3', v_email)->>'status' NOT IN ('not_palm', 'forbidden') THEN
            RAISE EXCEPTION 'FAIL: a livestock company is not rejected';
        END IF;
    ELSE
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: structure answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '083 state check (%): OK', v_expect;
END $$;

ROLLBACK;
