-- 105 ROLLBACK. No DROP, no DELETE, no TRUNCATE.
--   * The two read models (agri_sales, agri_sale_summary) are disabled: no operation and no role (a model that existed before 105 would be
--     restored from crud_models_backup_20261112_105 instead; none is expected). The rows stay registered.
--   * The browser view vw_agri_sale_ui_list stays (a definition only: it holds no data and nothing serves it while the models are disabled).
--   * The four restricted models (agri_sale_invoices, agri_sale_audit, company_flags, company_issuer_rfcs) stay registered.
--   * Every other crud_models row, the migration 104 tables, procedures and views (vw_agri_sale_list, vw_agri_sale_summary) are untouched.
-- Re-applying 105 keeps using CREATE OR REPLACE VIEW and re-enables the two models.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 105_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 105_rollback.sql  -> commit
-- Then: 105_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.crud_models_backup_20261112_105') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261112_105 not found - 105 was never applied here.';
    END IF;
END $$;

-- 1) Read models created by 105 (absent from the backup): disabled, never deleted
UPDATE crud_models c
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE c.model_name IN ('agri_sales', 'agri_sale_summary')
   AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261112_105 b WHERE b.model_name = c.model_name);

-- 2) Read models that existed before 105 (none expected): restore every column 105 upserts
UPDATE crud_models c
   SET table_name = b.table_name, primary_key = b.primary_key, allowed_fields = b.allowed_fields,
       default_filter = b.default_filter, schema_json = b.schema_json, allowed_ops = b.allowed_ops,
       hooks = b.hooks, allowed_roles_select = b.allowed_roles_select,
       allowed_roles_insert = b.allowed_roles_insert, allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete, joins = b.joins, is_global = b.is_global,
       sp_requires_tenant = b.sp_requires_tenant
  FROM crud_models_backup_20261112_105 b
 WHERE c.model_name = b.model_name AND c.model_name IN ('agri_sales', 'agri_sale_summary');

SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
  FROM crud_models
 WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
 ORDER BY 1;

\if :apply
COMMIT;
\echo '*** 105 ROLLBACK COMMITTED - verify with 105_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 105 ROLLBACK DRY RUN: nothing changed ***'
\endif
