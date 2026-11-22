-- 111_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK). Prints fingerprints and attributes; never an RFC value and no table content.
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 111_state_check.sql
--   before       : none of the 111 objects exists
--   applied      : table, trigger and the four procedures (real text) exist
--   rolled_back  : the four procedures are the fail-closed stub; table, helpers and trigger stay
-- Save the output of each state in the runbook record. The md5 depends on the PostgreSQL major version that deparses the function.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t111.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version;

\echo === FUNCTION FINGERPRINTS (md5 of pg_get_functiondef; NULL = function absent)
SELECT s.name, md5(pg_get_functiondef(to_regprocedure(s.sig))) AS md5
  FROM (VALUES ('fn_agri_cfdi_category',                'public.fn_agri_cfdi_category(text)'),
               ('fn_agri_cfdi_unit',                    'public.fn_agri_cfdi_unit(text)'),
               ('fn_agri_expense_invoice_params_hash',  'public.fn_agri_expense_invoice_params_hash(text,text,text,text,text)'),
               ('fn_trg_agri_expense_invoices_guard',   'public.fn_trg_agri_expense_invoices_guard()'),
               ('fn_trg_agri_expenses_void_invoice',    'public.fn_trg_agri_expenses_void_invoice()'),
               ('sp_agri_expense_invoice_draft_create', 'public.sp_agri_expense_invoice_draft_create(text,text,text,text,text,text)'),
               ('sp_agri_expense_invoice_preview',      'public.sp_agri_expense_invoice_preview(text,text,text,text,text,text,text,text)'),
               ('sp_agri_expense_invoice_confirm',      'public.sp_agri_expense_invoice_confirm(text,text,text,text,text,text,text,text)'),
               ('sp_agri_expense_invoice_register',     'public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)')) AS s(name, sig)
 ORDER BY s.name;

\echo === ATTRIBUTES (expected: plpgsql / sql, not SECURITY DEFINER; the four procedures VOLATILE)
SELECT p.proname, l.lanname, p.provolatile, p.prosecdef, p.proconfig, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('sp_agri_expense_invoice_draft_create', 'sp_agri_expense_invoice_preview', 'sp_agri_expense_invoice_confirm', 'sp_agri_expense_invoice_register')
 ORDER BY p.proname;

\echo === OBJECTS
SELECT to_regclass('public.agri_expense_invoices') IS NOT NULL AS link_table,
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expenses_void_invoice' AND tgrelid = 'public.agri_expenses'::regclass AND tgenabled <> 'D') AS void_trigger,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_expenses_id_company_key') AS expenses_unique,
       (SELECT count(*) FROM public.crud_models WHERE table_name ~ 'agri_expense_invoice|expense_invoice' OR model_name ~ 'agri_expense_invoice') AS models_in_crud_models;

\echo === VERDICT
DO $$
DECLARE
    v_expect text := current_setting('t111.expect');
    v_n      integer := (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                          AND proname IN ('sp_agri_expense_invoice_draft_create', 'sp_agri_expense_invoice_preview', 'sp_agri_expense_invoice_confirm', 'sp_agri_expense_invoice_register'));
    v_stub   boolean;
    v_state  text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF v_n = 0 AND to_regclass('public.agri_expense_invoices') IS NULL THEN
        v_state := 'before';
    ELSIF v_n <> 4 OR to_regclass('public.agri_expense_invoices') IS NULL THEN
        v_state := 'partial';
    ELSE
        v_stub := (SELECT prosrc LIKE '%(rolled back)%' FROM pg_proc WHERE oid = to_regprocedure('public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)'));
        v_state := CASE WHEN v_stub THEN 'rolled_back' ELSE 'applied' END;
        IF v_state = 'applied' AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expenses_void_invoice' AND tgrelid = 'public.agri_expenses'::regclass AND tgenabled <> 'D') THEN
            RAISE EXCEPTION 'STATE CHECK FAILED: the void trigger is missing or disabled';
        END IF;
    END IF;
    IF v_state IS DISTINCT FROM v_expect THEN
        RAISE EXCEPTION 'STATE CHECK FAILED: expected %, found %', v_expect, v_state;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_state;
END $$;
ROLLBACK;
