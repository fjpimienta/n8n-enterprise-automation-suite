-- 073 ROLLBACK. Touches only what 073 changed, and nothing is deleted:
--   * users / user_companies: restores ONLY allowed_ops and allowed_roles_select (the two columns 073
--     edits) from crud_models_backup_20261012_073. Every other column and every other model is untouched.
--   * company_members / access_add_user / access_update_member / access_set_active: the ones 073
--     CREATED (absent from the pre-073 backup) are disabled (allowed_ops '{}', roles 'NONE'); one that
--     already existed before 073 would be restored from the backup instead.
--   * access_audit_log is kept (audit history must survive a rollback); the view and the sp_access_* /
--     fn_access_* / email helper functions stay in place, unreachable through the gateway once their
--     models are disabled (same approach as the 066 rollback).
-- Re-applying 073 afterwards restores the full 073 config (its model inserts are upserts).
-- The v6/CRUD Build Query patch can stay: its `users` guards are independent of this migration.

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.crud_models_backup_20261012_073') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261012_073 not found - 073 was never applied here.';
    END IF;
    IF (SELECT count(*) FROM crud_models_backup_20261012_073 WHERE model_name IN ('users', 'user_companies')) <> 2 THEN
        RAISE EXCEPTION 'ABORT: the backup does not hold both users and user_companies rows.';
    END IF;
END $$;

-- 1) The two columns 073 edits on the raw models
UPDATE crud_models c
   SET allowed_ops          = b.allowed_ops,
       allowed_roles_select = b.allowed_roles_select
  FROM crud_models_backup_20261012_073 b
 WHERE c.model_name = b.model_name
   AND c.model_name IN ('users', 'user_companies');

-- 2) Models created by 073 (not in the pre-073 backup): disabled, never deleted
UPDATE crud_models c
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE c.model_name IN ('company_members', 'access_add_user', 'access_update_member', 'access_set_active')
   AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261012_073 b WHERE b.model_name = c.model_name);

-- 3) Same-named models that existed before 073 (none expected): restore the columns 073 upserts
UPDATE crud_models c
   SET table_name = b.table_name, primary_key = b.primary_key, allowed_fields = b.allowed_fields,
       default_filter = b.default_filter, schema_json = b.schema_json, allowed_ops = b.allowed_ops,
       hooks = b.hooks, allowed_roles_select = b.allowed_roles_select,
       allowed_roles_insert = b.allowed_roles_insert, allowed_roles_update = b.allowed_roles_update,
       allowed_roles_delete = b.allowed_roles_delete, joins = b.joins, is_global = b.is_global,
       sp_requires_tenant = b.sp_requires_tenant
  FROM crud_models_backup_20261012_073 b
 WHERE c.model_name = b.model_name
   AND c.model_name IN ('company_members', 'access_add_user', 'access_update_member', 'access_set_active');

SELECT model_name, allowed_ops, allowed_roles_select, allowed_roles_insert
  FROM crud_models
 WHERE model_name IN ('users', 'user_companies', 'company_members', 'access_add_user',
                      'access_update_member', 'access_set_active')
 ORDER BY 1;
-- Expected: users/user_companies with their pre-073 allowed_ops/allowed_roles_select; the four 073
-- models with {} / NONE. Verify with 073_state_check.sql -v expect=rolled_back.

COMMIT;
