-- 112_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 112_state_check.sql
--
-- * 112 adds two columns, two constraints, one insert trigger and its function to agri_sale_invoices, replaces sp_agri_register_sale and appends two columns
--   to vw_agri_sale_list and vw_agri_sale_ui_list. Everything else must be identical in every state: the FINGERPRINT block below must not change between
--   "before", "applied" and "rolled_back" (save the three outputs and diff that block).
-- * The rollback keeps the columns, constraints, trigger and view columns on purpose; only the procedure goes back to the exact 104 text.
-- * Older fingerprints of 104 / 105 that cover the procedure, the table columns, the views or the trigger count (105_state_check.sql: m104_functions,
--   m104_table_columns, m104_views, m104_guard_triggers, ui_list_view_definition) change on purpose across 112: compare them only within the same side of 112.
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t112.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version, now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (identical at every step)
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL SELECT 'sale_columns_without_112', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position))
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_sale_invoices' AND column_name NOT IN ('concept_count', 'ticket_detail')
UNION ALL SELECT 'sale_audit_columns', md5(string_agg(column_name || ':' || data_type, '|' ORDER BY ordinal_position))
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_sale_audit'
UNION ALL SELECT 'sp_agri_void_sale', md5(pg_get_functiondef('public.sp_agri_void_sale(integer,text,uuid,text)'::regprocedure))
UNION ALL SELECT 'sp_agri_sales_balance', md5(pg_get_functiondef('public.sp_agri_sales_balance(integer,date,date,character varying,uuid,uuid,character varying)'::regprocedure))
UNION ALL SELECT 'fn_trg_agri_sale_invoices_guard', md5(pg_get_functiondef('public.fn_trg_agri_sale_invoices_guard()'::regprocedure))
UNION ALL SELECT 'vw_agri_sale_summary', md5(pg_get_viewdef('public.vw_agri_sale_summary'::regclass))
UNION ALL SELECT 'm104_guard_triggers_without_112', count(*)::text FROM pg_trigger
 WHERE tgrelid IN ('public.agri_sale_invoices'::regclass, 'public.agri_sale_audit'::regclass, 'public.company_flags'::regclass, 'public.company_issuer_rfcs'::regclass)
   AND NOT tgisinternal AND tgenabled = 'O' AND tgname <> 'trg_agri_sale_invoices_detail_guard'
UNION ALL SELECT 'company_issuer_rfcs_rows', md5(coalesce(string_agg(concat_ws('|', id_company::text, rfc, is_active::text), '#' ORDER BY id_company, rfc), '')) FROM public.company_issuer_rfcs;

\echo === 112 OBJECTS (information)
SELECT md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure)) AS register_sale_md5,
       pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure) LIKE '%TNE%' AS register_sale_has_112_text,
       (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_sale_invoices' AND column_name IN ('concept_count', 'ticket_detail')) AS new_columns,
       (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.agri_sale_invoices'::regclass AND conname IN ('ck_agri_sale_invoices_concept_count', 'ck_agri_sale_invoices_ticket_detail')) AS new_constraints,
       (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.agri_sale_invoices'::regclass AND tgname = 'trg_agri_sale_invoices_detail_guard' AND NOT tgisinternal AND tgenabled = 'O') AS detail_trigger,
       (SELECT count(*) FROM public.agri_sale_invoices) AS sale_rows_info,
       (SELECT count(*) FROM public.agri_sale_invoices s WHERE (to_jsonb(s) ->> 'concept_count')::integer > 1) AS multi_concept_rows_info;

\echo === ASSERTIONS
DO $$
DECLARE
    e        text := current_setting('t112.expect');
    c_sp104  constant text := '425229fb6036884d5c5dcd7527d7c674';
    c_sp112  constant text := '83a5d0a7bad97dcfe1372aa4db961d49';
    c_list   constant text := 'id,id_company,uuid,cfdi_folio,issued_at,sale_date,buyer_name,buyer_rfc,quantity,unit_code,unit_price,subtotal_amount,discount_amount,total_amount,payment_form,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,sat_status,is_test,status,void_reason,voided_by_email,voided_at,registered_by_email,created_at';
    c_ui     constant text := 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at';
    v_sp     text;
    v_def    text;
    v_cols   integer;
    v_cons   integer;
    v_trg    integer;
    v_list   text;
    v_ui     text;
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', e; END IF;
    IF to_regclass('public.agri_sale_invoices') IS NULL OR to_regclass('public.vw_agri_sale_ui_list') IS NULL
       OR to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migrations 104 and 105 are missing - 112 needs them in every state';
    END IF;
    v_def := pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure);
    v_sp := md5(v_def);
    SELECT count(*) INTO v_cols FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_sale_invoices' AND column_name IN ('concept_count', 'ticket_detail');
    SELECT count(*) INTO v_cons FROM pg_constraint WHERE conrelid = 'public.agri_sale_invoices'::regclass AND conname IN ('ck_agri_sale_invoices_concept_count', 'ck_agri_sale_invoices_ticket_detail');
    SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgrelid = 'public.agri_sale_invoices'::regclass AND tgname = 'trg_agri_sale_invoices_detail_guard' AND NOT tgisinternal AND tgenabled = 'O';
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_list FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_list';
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_ui FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';

    IF e = 'before' THEN
        IF v_cols <> 0 OR v_cons <> 0 OR v_trg <> 0 OR to_regprocedure('public.fn_trg_agri_sale_invoices_detail_guard()') IS NOT NULL THEN
            RAISE EXCEPTION 'FAIL: 112 objects already exist (columns %, constraints %, trigger %)', v_cols, v_cons, v_trg;
        END IF;
        IF v_sp <> c_sp104 THEN RAISE EXCEPTION 'FAIL: sp_agri_register_sale is not the repository 104 text (md5 %)', v_sp; END IF;
        IF v_list <> c_list OR v_ui <> c_ui THEN RAISE EXCEPTION 'FAIL: the sale views are not the 104 / 105 ones (list: %, ui: %)', v_list, v_ui; END IF;
    ELSE
        -- applied and rolled_back keep every addition except the procedure text
        IF v_cols <> 2 OR v_cons <> 2 OR v_trg <> 1 THEN
            RAISE EXCEPTION 'FAIL: 112 additions missing (columns %, constraints %, trigger %)', v_cols, v_cons, v_trg;
        END IF;
        IF v_list <> c_list || ',concept_count,ticket_detail' OR v_ui <> c_ui || ',concept_count,ticket_detail' THEN
            RAISE EXCEPTION 'FAIL: unexpected view columns (list: %, ui: %)', v_list, v_ui;
        END IF;
        IF e = 'applied' THEN
            IF v_sp <> c_sp112 THEN RAISE EXCEPTION 'FAIL: sp_agri_register_sale is not the 112 text (md5 %)', v_sp; END IF;
            IF v_def LIKE '%disabled%' THEN RAISE EXCEPTION 'FAIL: the procedure carries the word used by the 104 rollback stub'; END IF;
        ELSE
            IF v_sp <> c_sp104 THEN RAISE EXCEPTION 'FAIL: the rollback did not restore the 104 text (md5 %)', v_sp; END IF;
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
