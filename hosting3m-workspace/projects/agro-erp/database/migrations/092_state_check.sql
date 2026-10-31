-- 092_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 092_state_check.sql
-- FINGERPRINT lines must be identical at every step (092 touches nothing existing, 091 objects included).
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t092.expect', :'expect', false) AS expect;
\echo === FINGERPRINTS
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, is_active::text, metadata::text), '#' ORDER BY id_company)) FROM companys
UNION ALL SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company)) FROM user_companies
UNION ALL SELECT 'cattle_expenses_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_expenses'
UNION ALL SELECT 'cattle_expenses_triggers', count(*)::text FROM pg_trigger WHERE tgrelid = 'public.cattle_expenses'::regclass AND NOT tgisinternal
UNION ALL SELECT 'expense_invoices_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'expense_invoices'
UNION ALL SELECT 'sp_expense_invoice_register_def', md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure))
UNION ALL SELECT 'sp_company_tax_id_set_def', md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure));
\echo === NEW OBJECTS
SELECT to_regclass('public.expense_invoice_drafts') AS drafts_table,
       to_regprocedure('public.sp_expense_invoice_draft_create(text,text,text,text,text,text)') AS draft_create,
       to_regprocedure('public.sp_expense_invoice_preview(text,text,text,text,text,text)') AS preview_fn,
       to_regprocedure('public.sp_expense_invoice_confirm(text,text,text,text,text,text)') AS confirm_fn;
DO $$
DECLARE
    e     text := current_setting('t092.expect');
    v_tbl boolean := to_regclass('public.expense_invoice_drafts') IS NOT NULL;
    v_fn  boolean := to_regprocedure('public.sp_expense_invoice_draft_create(text,text,text,text,text,text)') IS NOT NULL
                 AND to_regprocedure('public.sp_expense_invoice_preview(text,text,text,text,text,text)') IS NOT NULL
                 AND to_regprocedure('public.sp_expense_invoice_confirm(text,text,text,text,text,text)') IS NOT NULL;
    v_off boolean := false;
BEGIN
    IF v_fn THEN
        v_off := pg_get_functiondef('public.sp_expense_invoice_confirm(text,text,text,text,text,text)'::regprocedure) LIKE '%''disabled''%';
    END IF;
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF e = 'before' AND (v_tbl OR v_fn) THEN RAISE EXCEPTION 'STATE FAIL: 092 objects already exist'; END IF;
    IF e = 'applied' AND NOT (v_tbl AND v_fn AND NOT v_off) THEN RAISE EXCEPTION 'STATE FAIL: 092 is not fully applied (table %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    IF e = 'rolled_back' AND NOT (v_tbl AND v_fn AND v_off) THEN RAISE EXCEPTION 'STATE FAIL: 092 is not rolled back (table %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
