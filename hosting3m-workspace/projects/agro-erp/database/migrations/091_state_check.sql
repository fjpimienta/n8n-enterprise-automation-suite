-- 091_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 091_state_check.sql
-- FINGERPRINT lines must be identical at every step (091 touches no existing table, row or function).
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t091.expect', :'expect', false) AS expect;
\echo === FINGERPRINTS
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, is_active::text, metadata::text), '#' ORDER BY id_company)) FROM companys
UNION ALL SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company)) FROM user_companies
UNION ALL SELECT 'cattle_expenses_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_expenses'
UNION ALL SELECT 'cattle_expenses_triggers', count(*)::text FROM pg_trigger WHERE tgrelid = 'public.cattle_expenses'::regclass AND NOT tgisinternal;
\echo === NEW OBJECTS (row counts are informational; a rollback keeps the rows)
SELECT to_regclass('public.company_tax_ids') AS company_tax_ids, to_regclass('public.expense_invoices') AS expense_invoices,
       to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') AS register_fn,
       to_regprocedure('public.sp_company_tax_id_set(text,text,text,text,text)') AS tax_id_fn;
DO $$
DECLARE
    e     text := current_setting('t091.expect');
    v_tbl boolean := to_regclass('public.company_tax_ids') IS NOT NULL AND to_regclass('public.expense_invoices') IS NOT NULL;
    v_fn  boolean := to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') IS NOT NULL
                 AND to_regprocedure('public.sp_company_tax_id_set(text,text,text,text,text)') IS NOT NULL;
    v_off boolean := false;
BEGIN
    IF v_fn THEN
        v_off := pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure) LIKE '%''disabled''%';
    END IF;
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF e = 'before' AND (v_tbl OR v_fn) THEN RAISE EXCEPTION 'STATE FAIL: 091 objects already exist'; END IF;
    IF e = 'applied' AND NOT (v_tbl AND v_fn AND NOT v_off) THEN RAISE EXCEPTION 'STATE FAIL: 091 is not fully applied (tables %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    IF e = 'rolled_back' AND NOT (v_tbl AND v_fn AND v_off) THEN RAISE EXCEPTION 'STATE FAIL: 091 is not rolled back (tables %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
