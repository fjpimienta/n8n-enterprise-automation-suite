-- 105_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 105_state_check.sql
--
-- * 105 touches six crud_models rows (agri_sales, agri_sale_summary and the four restricted models) and adds one view.
--   The fingerprint of EVERY OTHER crud_models row, the migration 104 objects and the older sale views must be identical in every state.
-- * Save the output of "before", "applied" and "rolled_back" in the runbook record and diff the FINGERPRINT blocks: nothing but the six rows
--   and the view may differ. The view definition md5 (VIEW block) must be identical in "applied" and "rolled_back" (the rollback leaves it in place).
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t105.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (identical at every step)
SELECT 'other_crud_models' AS fingerprint,
       coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS md5
  FROM crud_models c
 WHERE c.model_name NOT IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
UNION ALL SELECT 'other_crud_models_count', count(*)::text FROM crud_models
 WHERE model_name NOT IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
UNION ALL SELECT 'm104_table_columns', md5(string_agg(table_name || '.' || column_name || ':' || data_type, '|' ORDER BY table_name, ordinal_position))
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
UNION ALL SELECT 'm104_functions', md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.proname))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('sp_agri_register_sale', 'sp_agri_void_sale', 'sp_agri_sales_balance')
UNION ALL SELECT 'm104_views', md5(coalesce(pg_get_viewdef('public.vw_agri_sale_list'::regclass), '') || coalesce(pg_get_viewdef('public.vw_agri_sale_summary'::regclass), ''))
UNION ALL SELECT 'm104_guard_triggers', count(*)::text FROM pg_trigger
 WHERE tgrelid IN ('public.agri_sale_invoices'::regclass, 'public.agri_sale_audit'::regclass, 'public.company_flags'::regclass, 'public.company_issuer_rfcs'::regclass)
   AND NOT tgisinternal AND tgenabled = 'O';

\echo === VIEW (identical in applied and rolled_back; absent before)
SELECT 'ui_list_view_definition' AS fingerprint,
       coalesce(md5(pg_get_viewdef(to_regclass('public.vw_agri_sale_ui_list'))), 'absent') AS md5;

\echo === THE SIX ROWS AND THE VIEW (information)
SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
       is_global, sp_requires_tenant, allowed_fields
  FROM crud_models
 WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
 ORDER BY model_name;
SELECT to_regclass('public.vw_agri_sale_ui_list') AS vw_agri_sale_ui_list,
       (SELECT md5(string_agg(column_name, ',' ORDER BY ordinal_position)) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list') AS view_columns_md5;

\echo === TENANT COLUMN CHECK OF ALL MODELS (information; names of models whose table has id_company but does not list it in allowed_fields)
SELECT coalesce(string_agg(m.model_name, ', ' ORDER BY m.model_name), '(none)') AS models_without_id_company_in_allowed_fields
  FROM crud_models m
  JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'id_company'
 WHERE NOT (m.allowed_fields ? 'id_company');

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t105.expect');
    v_view   boolean := to_regclass('public.vw_agri_sale_ui_list') IS NOT NULL;
    v_six    integer;
    v_cols   text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;
    IF to_regclass('public.agri_sale_invoices') IS NULL OR to_regclass('public.vw_agri_sale_summary') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 104 is missing - 105 needs it in every state';
    END IF;
    SELECT count(*) INTO v_six FROM crud_models
     WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
        OR table_name IN ('vw_agri_sale_ui_list', 'vw_agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs');

    IF v_expect = 'before' THEN
        IF v_six <> 0 OR v_view THEN
            RAISE EXCEPTION 'FAIL: expected none of the six models nor the view before 105, found % row(s), view %. Review them before applying.', v_six, v_view;
        END IF;
    ELSE
        -- the four restricted models: present with no operation and no role, in BOTH applied and rolled_back
        IF (SELECT count(*) FROM crud_models
             WHERE model_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs') AND table_name = model_name
               AND cardinality(allowed_ops) = 0 AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE'
               AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE' AND allowed_fields ? 'id_company') <> 4 THEN
            RAISE EXCEPTION 'FAIL: the four restricted models are missing or have an operation / role';
        END IF;
        -- the browser view exists, with the exact column list, in BOTH applied and rolled_back (the rollback does not touch it)
        IF NOT v_view THEN RAISE EXCEPTION 'FAIL: vw_agri_sale_ui_list is missing'; END IF;
        SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols
          FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';
        IF v_cols <> 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at' THEN
            RAISE EXCEPTION 'FAIL: unexpected columns in vw_agri_sale_ui_list: %', v_cols;
        END IF;
        IF v_expect = 'applied' THEN
            IF (SELECT count(*) FROM crud_models
                 WHERE ((model_name = 'agri_sales' AND table_name = 'vw_agri_sale_ui_list' AND primary_key = 'id'
                         AND allowed_fields = '["id_company","sale_date","status","plantation_id","lot_id","ticket_ref"]'::jsonb)
                     OR (model_name = 'agri_sale_summary' AND table_name = 'vw_agri_sale_summary' AND primary_key = 'id'
                         AND allowed_fields = '["id_company","grain","period_start","plantation_id","lot_id"]'::jsonb))
                   AND allowed_ops = '{SELECT,GETONE,GETALL}' AND allowed_roles_select = 'ADMIN' AND allowed_roles_insert = 'NONE'
                   AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE' AND is_global = false AND sp_requires_tenant = true
                   AND default_filter IS NULL AND joins = '[]'::jsonb) <> 2 THEN
                RAISE EXCEPTION 'FAIL: the read models are missing or have other values';
            END IF;
        ELSE
            IF (SELECT count(*) FROM crud_models
                 WHERE model_name IN ('agri_sales', 'agri_sale_summary') AND cardinality(allowed_ops) = 0
                   AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE') <> 2 THEN
                RAISE EXCEPTION 'FAIL: the read models are not disabled after the rollback';
            END IF;
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_expect;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
