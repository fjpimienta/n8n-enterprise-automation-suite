-- 107 ROLLBACK. No DROP, no DELETE, no TRUNCATE.
--   * The two models (agri_sale_void, agri_sale_balance) are disabled: no operation and no role (a model that existed before 107 would be
--     restored from crud_models_backup_20261112_107 instead; none is expected). The rows stay registered.
--   * Every other crud_models row and every object of migrations 104 and 105 are untouched.
-- Re-applying 107 re-enables the two models.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 107_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 107_rollback.sql  -> commit
-- Then: 107_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
BEGIN
    IF to_regclass('public.crud_models_backup_20261112_107') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261112_107 not found - 107 was never applied here.';
    END IF;
END $$;

-- 1) Models created by 107 (absent from the backup): disabled, never deleted
UPDATE crud_models c
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE c.model_name IN ('agri_sale_void', 'agri_sale_balance')
   AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261112_107 b WHERE b.model_name = c.model_name);

-- 2) Models that existed before 107 (none expected): restore every column 107 upserts
UPDATE crud_models c
   SET table_name = b.table_name, primary_key = b.primary_key, allowed_fields = b.allowed_fields,
       default_filter = b.default_filter, schema_json = b.schema_json, allowed_ops = b.allowed_ops,
       hooks = b.hooks, allowed_roles_select = b.allowed_roles_select,
       allowed_roles_insert = b.allowed_roles_insert, allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete, joins = b.joins, is_global = b.is_global,
       sp_requires_tenant = b.sp_requires_tenant
  FROM crud_models_backup_20261112_107 b
 WHERE c.model_name = b.model_name AND c.model_name IN ('agri_sale_void', 'agri_sale_balance');

SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
  FROM crud_models
 WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')
 ORDER BY 1;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 107 ROLLBACK COMMITTED - verify with 107_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 107 ROLLBACK DRY RUN: nothing changed ***'
\endif
\endif
