-- 107_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 107_state_check.sql
--
-- * 107 touches two crud_models rows (agri_sale_void, agri_sale_balance). The fingerprint of EVERY OTHER crud_models row, the migration 104
--   objects (tables, procedures, views, guard triggers) and the migration 105 objects (browser view and its six model rows) must be identical
--   in every state.
-- * Save the output of "before", "applied" and "rolled_back" in the runbook record and diff the FINGERPRINT blocks.
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t107.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (identical at every step)
SELECT 'other_crud_models' AS fingerprint,
       coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS md5
  FROM crud_models c
 WHERE c.model_name NOT IN ('agri_sale_void', 'agri_sale_balance')
UNION ALL SELECT 'other_crud_models_count', count(*)::text FROM crud_models
 WHERE model_name NOT IN ('agri_sale_void', 'agri_sale_balance')
UNION ALL SELECT 'm104_table_columns', md5(string_agg(table_name || '.' || column_name || ':' || data_type, '|' ORDER BY table_name, ordinal_position))
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
UNION ALL SELECT 'm104_functions', md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.proname))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('sp_agri_register_sale', 'sp_agri_void_sale', 'sp_agri_sales_balance')
UNION ALL SELECT 'm104_views', md5(coalesce(pg_get_viewdef('public.vw_agri_sale_list'::regclass), '') || coalesce(pg_get_viewdef('public.vw_agri_sale_summary'::regclass), ''))
UNION ALL SELECT 'm104_guard_triggers', count(*)::text FROM pg_trigger
 WHERE tgrelid IN ('public.agri_sale_invoices'::regclass, 'public.agri_sale_audit'::regclass, 'public.company_flags'::regclass, 'public.company_issuer_rfcs'::regclass)
   AND NOT tgisinternal AND tgenabled = 'O'
UNION ALL SELECT 'm105_ui_list_view', coalesce(md5(pg_get_viewdef(to_regclass('public.vw_agri_sale_ui_list'))), 'absent')
UNION ALL SELECT 'm105_model_rows', coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
  FROM crud_models c WHERE c.model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs');

\echo === THE TWO ROWS (information)
SELECT model_name, table_name, primary_key, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
       is_global, sp_requires_tenant, allowed_fields
  FROM crud_models
 WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')
 ORDER BY model_name;
SELECT to_regclass('public.crud_models_backup_20261112_107') AS backup_table;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t107.expect');
    v_backup boolean := to_regclass('public.crud_models_backup_20261112_107') IS NOT NULL;
    v_rows   integer;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;
    IF to_regprocedure('public.sp_agri_void_sale(integer,text,uuid,text)') IS NULL
       OR to_regprocedure('public.sp_agri_sales_balance(integer,date,date,character varying,uuid,uuid,character varying)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 104 procedures are missing - 107 needs them in every state';
    END IF;
    SELECT count(*) INTO v_rows FROM crud_models
     WHERE model_name IN ('agri_sale_void', 'agri_sale_balance') OR table_name IN ('sp_agri_void_sale', 'sp_agri_sales_balance');

    IF v_expect = 'before' THEN
        IF v_rows <> 0 OR v_backup THEN
            RAISE EXCEPTION 'FAIL: expected neither model nor backup before 107, found % row(s), backup %. Review them before applying.', v_rows, v_backup;
        END IF;
    ELSE
        IF NOT v_backup THEN RAISE EXCEPTION 'FAIL: the backup table is missing'; END IF;
        IF v_rows <> 2 THEN RAISE EXCEPTION 'FAIL: expected exactly the two rows serving the procedures, found %', v_rows; END IF;
        IF v_expect = 'applied' THEN
            IF (SELECT count(*) FROM crud_models
                 WHERE ((model_name = 'agri_sale_void' AND table_name = 'sp_agri_void_sale' AND primary_key = 'sale_id'
                         AND allowed_fields = '["sale_id","reason","actor_email"]'::jsonb)
                     OR (model_name = 'agri_sale_balance' AND table_name = 'sp_agri_sales_balance' AND primary_key = 'date_from'
                         AND allowed_fields = '["date_from","date_to","grain","plantation_id","lot_id","actor_email"]'::jsonb))
                   AND allowed_ops = '{INSERT}' AND allowed_roles_insert = 'ADMIN' AND allowed_roles_select = 'NONE'
                   AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE' AND is_global = false AND sp_requires_tenant = true
                   AND default_filter IS NULL AND joins = '[]'::jsonb AND schema_json = '{}'::jsonb AND hooks = '{"pre":[],"post":[]}'::jsonb) <> 2 THEN
                RAISE EXCEPTION 'FAIL: the two models are missing or have other values';
            END IF;
        ELSE
            IF (SELECT count(*) FROM crud_models
                 WHERE model_name IN ('agri_sale_void', 'agri_sale_balance') AND cardinality(allowed_ops) = 0
                   AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE') <> 2 THEN
                RAISE EXCEPTION 'FAIL: the two models are not disabled after the rollback';
            END IF;
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_expect;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
