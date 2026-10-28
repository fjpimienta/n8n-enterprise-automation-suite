-- 089 ROLLBACK. Restores crud_models id 70 (nacimiento) EXACTLY from the backup taken by 089_disable_nacimiento_gateway.sql.
-- No DROP / DELETE / TRUNCATE: the backup table crud_models_backup_089 and all its rows stay (append-only); the restore itself is
-- recorded in it as a RESTORE row holding the state the row had just before the restore.
--
-- What it does, on the ONE row id = 70 (model_name nacimiento, table_name sp_register_birth_event):
--   * takes the most recent DISABLE backup row (the original), and sets allowed_ops and allowed_roles_select / insert / update / delete
--     back to the backed-up values (jsonb_populate_record over the crud_models row type, so the types are exact);
--   * then compares the WHOLE row with the backed-up one and aborts (rolling everything back) if they differ in any column.
-- If the row is not disabled it does nothing. Re-applying 089 afterwards takes a NEW backup of the restored (original) row.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 089_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 089_rollback.sql  -> commit
-- Then: 089_state_check.sql -v expect=rolled_back

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
DECLARE
    r        record;
    bk       record;
    o        record;
    v_n      integer;
BEGIN
    IF to_regclass('public.crud_models_backup_089') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_089 not found - 089 was never applied here.';
    END IF;
    SELECT * INTO r FROM public.crud_models WHERE id = 70 AND model_name = 'nacimiento' AND table_name = 'sp_register_birth_event';
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models id 70 is not the nacimiento model here. Not touching it.';
    END IF;
    IF NOT (cardinality(coalesce(r.allowed_ops, ARRAY[]::text[])) = 0 AND r.allowed_roles_select = 'NONE' AND r.allowed_roles_insert = 'NONE'
            AND r.allowed_roles_update = 'NONE' AND r.allowed_roles_delete = 'NONE') THEN
        RAISE NOTICE '089 rollback: crud_models id 70 is not disabled; nothing to restore';
        RETURN;
    END IF;
    SELECT * INTO bk FROM public.crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE' ORDER BY done_at DESC, id LIMIT 1;
    IF bk.id IS NULL THEN
        RAISE EXCEPTION 'ABORT: no DISABLE backup of crud_models id 70: cannot restore the original.';
    END IF;

    o := jsonb_populate_record(NULL::public.crud_models, bk.row_data);
    INSERT INTO public.crud_models_backup_089 (crud_model_id, model_name, action, row_data) VALUES (70, r.model_name, 'RESTORE', to_jsonb(r));

    UPDATE public.crud_models c
       SET allowed_ops = o.allowed_ops,
           allowed_roles_select = o.allowed_roles_select, allowed_roles_insert = o.allowed_roles_insert,
           allowed_roles_update = o.allowed_roles_update, allowed_roles_delete = o.allowed_roles_delete
     WHERE c.id = 70 AND c.model_name = 'nacimiento' AND c.table_name = 'sp_register_birth_event';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'ABORT: expected to restore exactly one row, restored %', v_n;
    END IF;
    IF (SELECT to_jsonb(c) FROM public.crud_models c WHERE c.id = 70) IS DISTINCT FROM bk.row_data THEN
        RAISE EXCEPTION 'ABORT: the restored row is not identical to the backup (something else changed in the row since the backup). Rolled back.';
    END IF;
    RAISE NOTICE '089 rollback: crud_models id 70 restored exactly from backup %', bk.id;
END $$;

\echo === crud_models id 70 AFTER the restore
SELECT id, model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, sp_requires_tenant
  FROM public.crud_models WHERE id = 70;

\if :{?embedded}
\echo '*** 089 rollback loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 089 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
