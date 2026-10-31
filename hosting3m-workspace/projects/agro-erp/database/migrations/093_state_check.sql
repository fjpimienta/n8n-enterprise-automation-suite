-- 093_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 093_state_check.sql
-- FINGERPRINT lines must be identical at every step except register_def, which must equal the 091 version in 'before' and 'rolled_back'.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t093.expect', :'expect', false) AS expect;
\echo === FINGERPRINTS
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, is_active::text, metadata::text), '#' ORDER BY id_company)) FROM companys
UNION ALL SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company)) FROM user_companies
UNION ALL SELECT 'company_tax_ids_data', coalesce(md5(string_agg(concat_ws('|', id_company::text, rfc, is_active::text, qa_skip_sat::text), '#' ORDER BY id_company, rfc)), 'empty') FROM company_tax_ids
UNION ALL SELECT 'cattle_expenses_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_expenses'
UNION ALL SELECT 'cattle_expenses_triggers', count(*)::text FROM pg_trigger WHERE tgrelid = 'public.cattle_expenses'::regclass AND NOT tgisinternal
UNION ALL SELECT 'expense_invoices_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'expense_invoices'
UNION ALL SELECT 'drafts_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'expense_invoice_drafts'
UNION ALL SELECT 'sp_company_tax_id_set_def', md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure))
UNION ALL SELECT 'sp_expense_invoice_preview_def', md5(pg_get_functiondef('public.sp_expense_invoice_preview(text,text,text,text,text,text)'::regprocedure))
UNION ALL SELECT 'sp_expense_invoice_confirm_def', md5(pg_get_functiondef('public.sp_expense_invoice_confirm(text,text,text,text,text,text)'::regprocedure));
\echo === REGISTER FUNCTION (differs by design: 091 text before/rolled_back, 093 text applied)
SELECT 'register_def' AS fingerprint, md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure)) AS md5,
       pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure) LIKE '%v_rfc_new%' AS has_093_logic;
DO $$
DECLARE
    e      text := current_setting('t093.expect');
    v_093  boolean := pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure) LIKE '%v_rfc_new%';
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF e IN ('before', 'rolled_back') AND v_093 THEN RAISE EXCEPTION 'STATE FAIL: 093 logic is present'; END IF;
    IF e = 'applied' AND NOT v_093 THEN RAISE EXCEPTION 'STATE FAIL: 093 logic is missing'; END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
