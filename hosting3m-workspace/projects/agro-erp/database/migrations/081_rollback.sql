-- 081 ROLLBACK. No DROP / DELETE.
--   * The 7 models that 081 CREATED (absent from crud_models_backup_20261020_081) are disabled
--     (allowed_ops '{}', roles 'NONE'); a same-named model that already existed before 081 (none expected)
--     is restored from the backup instead. Every other model is untouched.
--   * trg_agri_plantations_seed_expense_categories is DISABLED (not dropped), so a new plantation no longer
--     seeds categories while 081 is rolled back. Re-applying 081 enables it again.
--   * Tables, data (expenses, categories, units), the other triggers, procedures, views and the
--     agri_lots (id, plantation_id, id_company) unique constraint stay in place, unreachable through the
--     gateway once the models are disabled (same approach as the 073 / 074 / 080 rollbacks).
-- The v6/CRUD Build Query entries for the three procedures can stay: without enabled models they are unused.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 081_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 081_rollback.sql  -> commit
-- Then: 081_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.crud_models_backup_20261020_081') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261020_081 not found - 081 was never applied here.';
    END IF;
END $$;

-- 1) Models created by 081 (not in the pre-081 backup): disabled, never deleted
UPDATE crud_models c
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE c.model_name IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                        'agri_record_expense', 'agri_void_expense', 'agri_expense_balance')
   AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261020_081 b WHERE b.model_name = c.model_name);

-- 2) Same-named models that existed before 081 (none expected): restore every column 081 upserts
UPDATE crud_models c
   SET table_name = b.table_name, primary_key = b.primary_key, allowed_fields = b.allowed_fields,
       default_filter = b.default_filter, schema_json = b.schema_json, allowed_ops = b.allowed_ops,
       hooks = b.hooks, allowed_roles_select = b.allowed_roles_select,
       allowed_roles_insert = b.allowed_roles_insert, allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete, joins = b.joins, is_global = b.is_global,
       sp_requires_tenant = b.sp_requires_tenant
  FROM crud_models_backup_20261020_081 b
 WHERE c.model_name = b.model_name;

-- 3) Category seeding on new plantations: disabled, not dropped
ALTER TABLE public.agri_plantations DISABLE TRIGGER trg_agri_plantations_seed_expense_categories;

SELECT model_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
  FROM crud_models
 WHERE model_name IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                      'agri_record_expense', 'agri_void_expense', 'agri_expense_balance')
 ORDER BY 1;

\if :apply
COMMIT;
\echo '*** 081 ROLLBACK COMMITTED - verify with 081_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 081 ROLLBACK DRY RUN: nothing changed ***'
\endif
