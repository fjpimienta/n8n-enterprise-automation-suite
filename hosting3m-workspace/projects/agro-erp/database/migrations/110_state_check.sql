-- 110_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK). Prints fingerprints and attributes; never an RFC value and no table content.
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 110_state_check.sql
--   before / rolled_back : both functions equal the repository 091 / 093 text   (md5 below, computed by applying 091..093 on a throwaway database)
--   applied              : both functions equal the 110 text
-- Save the output of each state in the runbook record. The md5 depends on the PostgreSQL major version that deparses the function: compare on the same major version.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t110.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version;

\echo === FUNCTION FINGERPRINTS (md5 of pg_get_functiondef; NULL = function absent)
SELECT s.name, md5(pg_get_functiondef(to_regprocedure(s.sig))) AS md5
  FROM (VALUES ('sp_expense_invoice_register', 'public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'),
               ('sp_company_tax_id_set',       'public.sp_company_tax_id_set(text,text,text,text,text)')) AS s(name, sig)
 ORDER BY s.name;

\echo === ATTRIBUTES (expected in every state: plpgsql, volatile, not SECURITY DEFINER, no proconfig)
SELECT p.proname, l.lanname, p.provolatile, p.prosecdef, p.proconfig,
       has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
 WHERE p.oid IN (to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'),
                 to_regprocedure('public.sp_company_tax_id_set(text,text,text,text,text)'))
 ORDER BY p.proname;

\echo === CLASSIFIER (109 must be applied and not the stub for the gate to accept anything)
SELECT to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)') IS NOT NULL AS classifier_present,
       coalesce((SELECT prosrc LIKE '%''DISABLED''%' FROM pg_proc WHERE oid = to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)')), false) AS classifier_is_stub;

\echo === VERDICT
DO $$
DECLARE
    v_expect text := current_setting('t110.expect');
    v_reg    text := md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure));
    v_tax    text := md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure));
    v_state  text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF v_reg = '0612086a244911ac15c47a5405f7ac0b' AND v_tax = 'e89f615ed99bae63adb6d53554819789' THEN
        v_state := 'repo_093';          -- the state of "before" and of "rolled_back"
    ELSIF v_reg = 'acbeeb49f222d36de95f8db2be3cd4be' AND v_tax = 'f7cec648615c6741f166d9356f0530c9' THEN
        v_state := 'applied';
    ELSE
        RAISE EXCEPTION 'STATE CHECK FAILED: the functions are neither the repository 093 / 091 text nor the 110 text (register %, tax_id_set %)', v_reg, v_tax;
    END IF;
    IF v_expect = 'applied' AND v_state <> 'applied' THEN RAISE EXCEPTION 'STATE CHECK FAILED: expected applied, found %', v_state; END IF;
    IF v_expect IN ('before', 'rolled_back') AND v_state <> 'repo_093' THEN RAISE EXCEPTION 'STATE CHECK FAILED: expected %, found %', v_expect, v_state; END IF;
    RAISE NOTICE 'STATE OK: %', v_expect;
END $$;
ROLLBACK;
