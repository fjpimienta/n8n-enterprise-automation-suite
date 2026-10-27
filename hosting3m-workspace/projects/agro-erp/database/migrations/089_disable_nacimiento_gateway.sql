-- 089_disable_nacimiento_gateway.sql
-- Reversibly DISABLES the Meta-CRUD gateway model 'nacimiento' (crud_models id 70, table_name sp_register_birth_event).
-- SEPARATE from 087 / 088 on purpose: it can be omitted without affecting them.
--
-- WHY. Through this model v6/CRUD calls sp_register_birth_event WITHOUT an e-mail, so the membership check added by 087 never runs
-- on that path. A repo-wide grep (2026-10-28) found no frontend consumer of the model (only comments); both AI agents call the MCP
-- tool register_birth_event, which always sends the verified e-mail.
--
-- HOW (read from workflows/06-dynamic-crud-engine/v6/v6-crud.json). The node "Get Model Config" runs
--   select * from crud_models where model_name = '<model>'
-- and "ModelExist" sends a MISSING row to the "Can Register Model" branch, where an ADMIN of the company can AUTO-REGISTER a model.
-- So the row is NEVER deleted. "Security Validation" then rejects the request with HTTP 403 "Operacion no permitida para este modelo"
-- when the requested operation is not in allowed_ops, before any role check or query. The disable is therefore:
--     allowed_ops = '{}'  and  allowed_roles_select / insert / update / delete = 'NONE'     (the 073 pattern)
-- on the ONE row id = 70 whose model_name = 'nacimiento' and table_name = 'sp_register_birth_event' (anything else aborts).
-- The ORIGINAL row is first copied, whole (to_jsonb), into the append-only table crud_models_backup_089. 089_rollback.sql restores
-- exactly those five columns from the backup and verifies the full row is identical to the backup.
--
-- Idempotent by STATE: if the row is already disabled by this file nothing is done and no second backup is taken (the backup must hold
-- the ORIGINAL row). If the row is disabled but there is no backup (someone did it by hand) it aborts: the original would be lost.
--
-- Touches: crud_models (one row, five columns) and the new table crud_models_backup_089. Nothing else.
-- Requires 085 (fn_trg_empadre_append_only). Rollback: 089_rollback.sql. State: 089_state_check.sql. Tests: 089_tests.sql.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 089_disable_nacimiento_gateway.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 089_disable_nacimiento_gateway.sql   -> commit
-- 089_tests.sql includes this file with `embedded` set.

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
    r record;
BEGIN
    IF to_regclass('public.crud_models') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models not found.';
    END IF;
    IF to_regprocedure('public.fn_trg_empadre_append_only()') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 085 is not applied here (fn_trg_empadre_append_only missing).';
    END IF;
    SELECT * INTO r FROM public.crud_models WHERE id = 70;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models id 70 does not exist here. Nothing to disable (and nothing is deleted or created).';
    END IF;
    IF r.model_name IS DISTINCT FROM 'nacimiento' OR r.table_name IS DISTINCT FROM 'sp_register_birth_event' THEN
        RAISE EXCEPTION 'ABORT: crud_models id 70 is % / % (expected nacimiento / sp_register_birth_event). Not touching it.', r.model_name, r.table_name;
    END IF;
    IF (SELECT count(*) FROM public.crud_models WHERE model_name = 'nacimiento') <> 1 THEN
        RAISE EXCEPTION 'ABORT: more than one crud_models row named nacimiento.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.crud_models_backup_089 (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    crud_model_id integer     NOT NULL,
    model_name    text        NOT NULL,
    action        text        NOT NULL CONSTRAINT ck_crud_bk089_action CHECK (action IN ('DISABLE', 'RESTORE')),
    row_data      jsonb       NOT NULL,      -- the WHOLE crud_models row as it was BEFORE the action
    done_by       text        NOT NULL DEFAULT current_user,
    done_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.crud_models_backup_089 IS '089: append-only copy of the crud_models row before a DISABLE / RESTORE of the nacimiento gateway model (id 70). Never deleted. Not in crud_models.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgname = 'trg_crud_bk089_append_only'
                      AND g.tgrelid = 'public.crud_models_backup_089'::regclass AND NOT g.tgisinternal) THEN
        CREATE TRIGGER trg_crud_bk089_append_only BEFORE UPDATE OR DELETE ON public.crud_models_backup_089
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_empadre_append_only();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgname = 'trg_crud_bk089_no_truncate'
                      AND g.tgrelid = 'public.crud_models_backup_089'::regclass AND NOT g.tgisinternal) THEN
        CREATE TRIGGER trg_crud_bk089_no_truncate BEFORE TRUNCATE ON public.crud_models_backup_089
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trg_empadre_append_only();
    END IF;
END $$;

\echo === crud_models id 70 BEFORE
SELECT id, model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, sp_requires_tenant
  FROM public.crud_models WHERE id = 70;

DO $$
DECLARE
    r        record;
    v_n      integer;
    v_before jsonb;
BEGIN
    SELECT * INTO r FROM public.crud_models WHERE id = 70;
    IF cardinality(coalesce(r.allowed_ops, ARRAY[]::text[])) = 0
       AND r.allowed_roles_select = 'NONE' AND r.allowed_roles_insert = 'NONE'
       AND r.allowed_roles_update = 'NONE' AND r.allowed_roles_delete = 'NONE' THEN
        IF NOT EXISTS (SELECT 1 FROM public.crud_models_backup_089 b WHERE b.crud_model_id = 70 AND b.action = 'DISABLE') THEN
            RAISE EXCEPTION 'ABORT: crud_models id 70 is already disabled but there is NO backup of its original row: it was disabled by hand. Not touching it.';
        END IF;
        RAISE NOTICE '089: crud_models id 70 is already disabled (backup exists); nothing to do';
        RETURN;
    END IF;

    v_before := to_jsonb(r);
    INSERT INTO public.crud_models_backup_089 (crud_model_id, model_name, action, row_data) VALUES (70, r.model_name, 'DISABLE', v_before);

    UPDATE public.crud_models
       SET allowed_ops = ARRAY[]::text[],
           allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE', allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
     WHERE id = 70 AND model_name = 'nacimiento' AND table_name = 'sp_register_birth_event';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'ABORT: expected to disable exactly one crud_models row, disabled %', v_n;
    END IF;
    RAISE NOTICE '089: crud_models id 70 (nacimiento) disabled; the original row is in crud_models_backup_089';
END $$;

\echo === crud_models id 70 AFTER
SELECT id, model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, sp_requires_tenant
  FROM public.crud_models WHERE id = 70;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.crud_models WHERE id = 70
                  AND (cardinality(coalesce(allowed_ops, ARRAY[]::text[])) <> 0
                       OR allowed_roles_select <> 'NONE' OR allowed_roles_insert <> 'NONE' OR allowed_roles_update <> 'NONE' OR allowed_roles_delete <> 'NONE')) THEN
        RAISE EXCEPTION '089: the row is not disabled';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE') THEN
        RAISE EXCEPTION '089: no backup of the original row';
    END IF;
    RAISE NOTICE '089: OK';
END $$;

\if :{?embedded}
\echo '*** 089 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 089 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
