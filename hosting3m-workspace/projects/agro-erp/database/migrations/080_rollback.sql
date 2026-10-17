-- 080 ROLLBACK. No DROP / DELETE: touches only crud_models, and nothing is deleted.
--   * The 10 agri_* models that 080 CREATED (absent from crud_models_backup_20261017_080) are disabled
--     (allowed_ops '{}', roles 'NONE'); a same-named model that already existed before 080 (none expected)
--     is restored from the backup instead.
--   * PalmTelemetry: allowed_ops, allowed_roles_update and allowed_roles_delete are restored from the backup
--     (the three columns 080 edits). Every other column and every other model is untouched.
--   * Tables, data, triggers, procedures and views stay in place, unreachable through the gateway once the
--     models are disabled (same approach as the 073 / 074 rollbacks). The census history is kept.
-- Re-applying 080 afterwards restores the full 080 configuration (its model inserts are upserts).
-- The v6/CRUD Build Query entries for the three procedures can stay: without enabled models they are unused.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 080_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 080_rollback.sql  -> commit
-- Then: 080_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.crud_models_backup_20261017_080') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261017_080 not found - 080 was never applied here.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM crud_models_backup_20261017_080 WHERE model_name = 'PalmTelemetry') THEN
        RAISE EXCEPTION 'ABORT: the backup does not hold the PalmTelemetry row.';
    END IF;
END $$;

-- 1) PalmTelemetry: the three columns 080 edits
UPDATE crud_models c
   SET allowed_ops          = b.allowed_ops,
       allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete
  FROM crud_models_backup_20261017_080 b
 WHERE c.model_name = b.model_name
   AND c.model_name = 'PalmTelemetry';

-- 2) Models created by 080 (not in the pre-080 backup): disabled, never deleted
UPDATE crud_models c
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE c.model_name IN ('agri_variety_catalog', 'agri_plantations', 'agri_lots', 'agri_rows',
                        'agri_row_census_history', 'agri_lot_summary', 'agri_plantation_summary',
                        'agri_set_default_plantation', 'agri_bulk_create_rows', 'agri_record_row_census')
   AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261017_080 b WHERE b.model_name = c.model_name);

-- 3) Same-named models that existed before 080 (none expected): restore every column 080 upserts
UPDATE crud_models c
   SET table_name = b.table_name, primary_key = b.primary_key, allowed_fields = b.allowed_fields,
       default_filter = b.default_filter, schema_json = b.schema_json, allowed_ops = b.allowed_ops,
       hooks = b.hooks, allowed_roles_select = b.allowed_roles_select,
       allowed_roles_insert = b.allowed_roles_insert, allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete, joins = b.joins, is_global = b.is_global,
       sp_requires_tenant = b.sp_requires_tenant
  FROM crud_models_backup_20261017_080 b
 WHERE c.model_name = b.model_name
   AND c.model_name LIKE 'agri\_%';

SELECT model_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
  FROM crud_models
 WHERE model_name = 'PalmTelemetry' OR model_name LIKE 'agri\_%'
 ORDER BY 1;

\if :apply
COMMIT;
\echo '*** 080 ROLLBACK COMMITTED - verify with 080_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 080 ROLLBACK DRY RUN: nothing changed ***'
\endif
