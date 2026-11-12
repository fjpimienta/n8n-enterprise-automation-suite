-- 103_panel_livestock_gateway_model.sql
-- Registers the Meta-CRUD gateway model for the panel livestock intake procedure created by migration 102.
--
-- WHAT IT DOES. ONE row in crud_models (data only, no DDL, no function change):
--   model_name 'register_livestock_panel' -> table_name 'sp_register_livestock_panel' (the procedure of migration 102).
--   * allowed_ops {INSERT}: v6/CRUD validates a call_sp as an INSERT, so the permission lives in allowed_roles_insert.
--   * allowed_roles_insert 'ADMIN,EDITOR'. OWNER is NOT added on purpose: the direct insert of cattle_livestock does not grant it
--     today and this migration does not widen who can create animals. select / update / delete are 'NONE'.
--   * is_global = false, sp_requires_tenant = true: the gateway requires a tenant (x-tenant-id, checked against the caller's
--     membership) and passes it as the first argument; the procedure validates the session again (fail-closed).
--   * allowed_fields = the 18 arguments after the tenant, in the order of the gateway's spConfigByModel entry.
--   * schema_json '{}' (no required fields: the procedure answers need_info with the missing ones).
-- The row follows the pattern of the other call_sp models (081: agri_record_expense, agri_void_expense).
--
-- Nothing changes for users until a screen calls the model: the frontend is a later PR.
-- Needs: migration 102 applied (the function with 19 parameters). Aborts otherwise, and aborts if a model with this name already
-- exists pointing somewhere else. Re-running it on its own row is harmless (the row is rewritten with the same values).
--
-- Rollback: 103_rollback.sql (deletes only this row). State: 103_state_check.sql -v expect=before|applied (read-only).
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 103_panel_livestock_gateway_model.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 103_panel_livestock_gateway_model.sql  -> commit
-- 103_tests.sql includes this file with `embedded` set: it then neither opens nor ends the transaction.

\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions --------------------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_register_livestock_panel (19 parameters) does not exist - apply migration 102 first.';
    END IF;
    IF to_regclass('public.crud_models') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models does not exist.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.crud_models
                WHERE model_name = 'register_livestock_panel' AND table_name <> 'sp_register_livestock_panel') THEN
        RAISE EXCEPTION 'ABORT: a crud_models row named register_livestock_panel already points at another table. Not touching it.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.crud_models
                WHERE table_name = 'sp_register_livestock_panel' AND model_name <> 'register_livestock_panel') THEN
        RAISE EXCEPTION 'ABORT: the procedure is already exposed under another model name. Not adding a second one.';
    END IF;
END $$;

-- 1) The model ------------------------------------------------------------------------------------------
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json,
                         allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                         allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  ('register_livestock_panel', 'sp_register_livestock_panel', 'ear_tag',
   '["upp","lot","species","category","business_model","ear_tag","fire_number","electronic_rfid","weight_kg","birth_date","origin_upp","tb_test_date","br_test_date","notes","confirmed","preview_hash","force_duplicate","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN,EDITOR', 'NONE', 'NONE', '[]', false, true)
ON CONFLICT (model_name) DO UPDATE SET
    table_name = EXCLUDED.table_name, primary_key = EXCLUDED.primary_key,
    allowed_fields = EXCLUDED.allowed_fields, default_filter = EXCLUDED.default_filter,
    schema_json = EXCLUDED.schema_json, allowed_ops = EXCLUDED.allowed_ops, hooks = EXCLUDED.hooks,
    allowed_roles_select = EXCLUDED.allowed_roles_select, allowed_roles_insert = EXCLUDED.allowed_roles_insert,
    allowed_roles_update = EXCLUDED.allowed_roles_update, allowed_roles_delete = EXCLUDED.allowed_roles_delete,
    joins = EXCLUDED.joins, is_global = EXCLUDED.is_global, sp_requires_tenant = EXCLUDED.sp_requires_tenant;

-- 2) Check ----------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_n integer;
BEGIN
    SELECT count(*) INTO v_n FROM public.crud_models WHERE model_name = 'register_livestock_panel';
    IF v_n <> 1 THEN RAISE EXCEPTION '103: expected 1 model row, found %', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.crud_models
                    WHERE model_name = 'register_livestock_panel' AND table_name = 'sp_register_livestock_panel'
                      AND allowed_ops = '{INSERT}' AND allowed_roles_insert = 'ADMIN,EDITOR'
                      AND allowed_roles_select = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                      AND is_global = false AND sp_requires_tenant = true
                      AND jsonb_array_length(allowed_fields) = 18
                      AND NOT (allowed_fields ? 'id') AND NOT (allowed_fields ? 'tenant_id') AND NOT (allowed_fields ? 'id_company')) THEN
        RAISE EXCEPTION '103: the model row does not have the expected values';
    END IF;
    RAISE NOTICE '103: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 103 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 103 rolled back ***'
\endif
\endif
