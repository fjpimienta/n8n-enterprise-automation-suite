-- 104_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 104_state_check.sql
-- FINGERPRINT lines must be identical at every step (104 touches no existing table, row or function).
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t104.expect', :'expect', false) AS expect;
\echo === FINGERPRINTS
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, is_active::text, metadata::text), '#' ORDER BY id_company)) FROM companys
UNION ALL SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company)) FROM user_companies
UNION ALL SELECT 'agri_expenses_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_expenses'
UNION ALL SELECT 'expense_invoices_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position)) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'expense_invoices'
UNION ALL SELECT 'fn_repro_ctx', md5(pg_get_functiondef(to_regprocedure('public.fn_repro_ctx(text,text)')))
UNION ALL SELECT 'fn_reject_palm_company', md5(pg_get_functiondef(to_regprocedure('public.fn_reject_palm_company(integer)')))
UNION ALL SELECT 'sp_expense_invoice_register', md5(pg_get_functiondef(to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)')))
UNION ALL SELECT 'sp_agri_expense_balance', md5(pg_get_functiondef(to_regprocedure('public.sp_agri_expense_balance(integer,date,date,character varying,uuid,uuid,uuid,character varying)')));
\echo === NEW OBJECTS (row counts are informational; a rollback keeps the rows)
SELECT to_regclass('public.company_flags') AS company_flags, to_regclass('public.company_issuer_rfcs') AS issuer_rfcs,
       to_regclass('public.agri_sale_invoices') AS sale_invoices, to_regclass('public.agri_sale_audit') AS sale_audit,
       to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') AS register_fn,
       to_regprocedure('public.sp_agri_void_sale(integer,text,uuid,text)') AS void_fn,
       to_regprocedure('public.sp_agri_sales_balance(integer,date,date,character varying,uuid,uuid,character varying)') AS balance_fn;
DO $$
DECLARE
    e     text := current_setting('t104.expect');
    v_tbl boolean := to_regclass('public.company_flags') IS NOT NULL AND to_regclass('public.company_issuer_rfcs') IS NOT NULL
                 AND to_regclass('public.agri_sale_invoices') IS NOT NULL AND to_regclass('public.agri_sale_audit') IS NOT NULL;
    v_fn  boolean := to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NOT NULL
                 AND to_regprocedure('public.sp_agri_void_sale(integer,text,uuid,text)') IS NOT NULL
                 AND to_regprocedure('public.sp_agri_sales_balance(integer,date,date,character varying,uuid,uuid,character varying)') IS NOT NULL;
    v_off boolean := false;
BEGIN
    IF v_fn THEN
        v_off := pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure) LIKE '%''disabled''%';
    END IF;
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    IF e = 'before' AND (v_tbl OR v_fn) THEN RAISE EXCEPTION 'STATE FAIL: 104 objects already exist'; END IF;
    IF e = 'applied' AND NOT (v_tbl AND v_fn AND NOT v_off) THEN RAISE EXCEPTION 'STATE FAIL: 104 is not fully applied (tables %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    IF e = 'rolled_back' AND NOT (v_tbl AND v_fn AND v_off) THEN RAISE EXCEPTION 'STATE FAIL: 104 is not rolled back (tables %, functions %, disabled %)', v_tbl, v_fn, v_off; END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
