-- 114_identifier_history_tenant_guards.sql (step 1 of the identifier change-control work). Migration 114 (113 is reserved for the audit work).
--
-- What it does (cattle_identifier_history, the change log of fire number / ear tag / chip):
--   1. Adds id_company (backfilled from the animal), NOT NULL, with indexes by company.
--   2. BEFORE INSERT trigger: id_company is always taken from the animal, never from the caller (a different value is refused, P0130).
--   3. Append-only: UPDATE, DELETE and TRUNCATE are refused (P0131).
--   4. trg_log_identifier_changes rewritten: real actor (app.identifier_change_user), reason (app.identifier_change_reason) and free text
--      (app.identifier_change_notes -> notes); 'UNKNOWN' when no actor was set; no row when the only change is NULL <-> '' or edge spaces.
--   5. Reason list extended: INITIAL_ASSIGNMENT, AUTHORIZED_CHANGE (the old four stay).
--   6. Gateway model 'cattle_identifier_history': INSERT removed (the trigger is the only writer), id_company added to allowed_fields so the
--      gateway filters by company (decision: readable by every role, filtered by company).
--
-- NOT in this step: any change to cattle_livestock, to the authorization flow or to sp_update_livestock_tag (step 2).
--
-- BACKUP (before applying to any database that matters):
--   pg_dump -Fc -t public.cattle_identifier_history -t public.crud_models -f history_before_<date>.dump hosting3m_db
--   and save the text of public.trg_log_identifier_changes (its md5 is checked below).
--
-- DRY RUN (default): everything runs inside BEGIN ... ROLLBACK and prints "OK" with the counts it would change.
--   psql -X -v ON_ERROR_STOP=1 -f 114_identifier_history_tenant_guards.sql                 -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 114_identifier_history_tenant_guards.sql   -> commit
-- Idempotent: running it again changes nothing. Rollback: 114_rollback.sql. Tests: ..._tests.sql (throwaway DB only).
-- Error codes: P0130 (company mismatch / animal not found), P0131 (append-only), P0132 (unknown app.identifier_change_reason).

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

-- 0. Preconditions and drift guard ---------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_md5 text;
    v_models integer;
    v_orphans integer;
BEGIN
    IF to_regclass('public.cattle_identifier_history') IS NULL OR to_regclass('public.cattle_livestock') IS NULL THEN
        RAISE EXCEPTION 'ABORT: cattle_identifier_history or cattle_livestock not found.';
    END IF;
    IF to_regprocedure('public.trg_log_identifier_changes()') IS NULL THEN
        RAISE EXCEPTION 'ABORT: trg_log_identifier_changes() not found.';
    END IF;
    -- Either the text of migration 047 (LOCAL md5 below), the hardened text the rollback leaves, or this migration's own text. Anything else = drift: compare with the VPS first.
    SELECT md5(pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure)) INTO v_md5;
    IF v_md5 <> '7068e9a8e4af7364d16c41c2b77c7570'
       AND pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%identifier_change_notes%'
       AND pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%hardened-047-logger%' THEN
        RAISE EXCEPTION 'ABORT: trg_log_identifier_changes() is neither the 047 text, the hardened rollback text nor this migration''s text (md5 %). Nothing was changed.', v_md5;
    END IF;
    SELECT count(*) INTO v_models FROM public.crud_models WHERE model_name = 'cattle_identifier_history';
    IF v_models <> 1 THEN
        RAISE EXCEPTION 'ABORT: expected exactly one crud_models row for cattle_identifier_history, found %.', v_models;
    END IF;
    SELECT count(*) INTO v_orphans FROM public.cattle_identifier_history h
     WHERE NOT EXISTS (SELECT 1 FROM public.cattle_livestock c WHERE c.id = h.cattle_livestock_id);
    IF v_orphans > 0 THEN
        RAISE EXCEPTION 'ABORT: % history rows have no animal; resolve them first.', v_orphans;
    END IF;
END $$;

-- 1. Column, backfill (before the append-only trigger exists), NOT NULL, indexes ----------------------------------------------------
ALTER TABLE public.cattle_identifier_history ADD COLUMN IF NOT EXISTS id_company integer;

UPDATE public.cattle_identifier_history h
   SET id_company = c.tenant_id
  FROM public.cattle_livestock c
 WHERE c.id = h.cattle_livestock_id AND h.id_company IS NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE id_company IS NULL) THEN
        RAISE EXCEPTION 'ABORT: backfill left rows without id_company.';
    END IF;
END $$;

ALTER TABLE public.cattle_identifier_history ALTER COLUMN id_company SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_identifier_history_company_new  ON public.cattle_identifier_history (id_company, identifier_type, new_value);
CREATE INDEX IF NOT EXISTS idx_identifier_history_company_prev ON public.cattle_identifier_history (id_company, identifier_type, previous_value);

-- 2. Reason list (superset of the old CHECK) ------------------------------------------------------------------------------------------
ALTER TABLE public.cattle_identifier_history DROP CONSTRAINT IF EXISTS cattle_identifier_history_reason_check;
ALTER TABLE public.cattle_identifier_history ADD CONSTRAINT cattle_identifier_history_reason_check
    CHECK (reason = ANY (ARRAY['LOST', 'REPLACED', 'CAPTURE_CORRECTION', 'FOUND_LOOSE_REASSIGNED', 'INITIAL_ASSIGNMENT', 'AUTHORIZED_CHANGE']));

-- 3. id_company always comes from the animal ------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_identifier_history_set_company()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
    v_company integer;
BEGIN
    SELECT c.tenant_id INTO v_company FROM public.cattle_livestock c WHERE c.id = NEW.cattle_livestock_id;
    IF NOT FOUND OR v_company IS NULL THEN
        RAISE EXCEPTION 'History row refused: the animal was not found' USING ERRCODE = 'P0130';
    END IF;
    IF NEW.id_company IS NOT NULL AND NEW.id_company <> v_company THEN
        RAISE EXCEPTION 'History row refused: company does not match the animal' USING ERRCODE = 'P0130';
    END IF;
    NEW.id_company := v_company;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_identifier_history_set_company
    BEFORE INSERT ON public.cattle_identifier_history
    FOR EACH ROW EXECUTE FUNCTION public.trg_identifier_history_set_company();

-- 4. Append-only ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_identifier_history_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
    RAISE EXCEPTION 'cattle_identifier_history is append-only' USING ERRCODE = 'P0131';
END;
$$;

CREATE OR REPLACE TRIGGER trg_identifier_history_no_update_delete
    BEFORE UPDATE OR DELETE ON public.cattle_identifier_history
    FOR EACH ROW EXECUTE FUNCTION public.trg_identifier_history_immutable();

CREATE OR REPLACE TRIGGER trg_identifier_history_no_truncate
    BEFORE TRUNCATE ON public.cattle_identifier_history
    FOR EACH STATEMENT EXECUTE FUNCTION public.trg_identifier_history_immutable();

-- 5. The logger: real actor, reason and notes -----------------------------------------------------------------------------------------
-- Callers set, in the SAME transaction as the UPDATE (set_config(..., true)):
--   app.identifier_change_user   actor e-mail (verified by the caller)      -> changed_by ('UNKNOWN' if missing)
--   app.identifier_change_reason one of the CHECK values                    -> reason (CAPTURE_CORRECTION if unset/empty; any other value raises P0132)
--   app.identifier_change_notes  free text (the requester's reason)         -> notes
-- A change that only turns NULL into '' (or the reverse) or adds/removes edge spaces is not a change and writes nothing.
CREATE OR REPLACE FUNCTION public.trg_log_identifier_changes()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
    v_reason TEXT;
    v_changed_by TEXT;
    v_notes TEXT;
BEGIN
    v_reason     := COALESCE(NULLIF(btrim(current_setting('app.identifier_change_reason', true)), ''), 'CAPTURE_CORRECTION');
    -- An unknown reason is refused here with a named error instead of reaching the CHECK constraint (keep this list equal to that CHECK).
    IF v_reason <> ALL (ARRAY['LOST', 'REPLACED', 'CAPTURE_CORRECTION', 'FOUND_LOOSE_REASSIGNED', 'INITIAL_ASSIGNMENT', 'AUTHORIZED_CHANGE']) THEN
        RAISE EXCEPTION 'Unknown identifier change reason (app.identifier_change_reason)' USING ERRCODE = 'P0132';
    END IF;
    v_changed_by := COALESCE(NULLIF(btrim(current_setting('app.identifier_change_user', true)), ''), 'UNKNOWN');
    v_notes      := NULLIF(btrim(current_setting('app.identifier_change_notes', true)), '');

    IF NULLIF(btrim(NEW.numero_fuego), '') IS DISTINCT FROM NULLIF(btrim(OLD.numero_fuego), '') THEN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, id_company, identifier_type, previous_value, new_value, reason, changed_by, notes)
        VALUES (NEW.id, NEW.tenant_id, 'FUEGO', OLD.numero_fuego, NEW.numero_fuego, v_reason, v_changed_by, v_notes);
    END IF;

    IF NULLIF(btrim(NEW.rfid_siniiga), '') IS DISTINCT FROM NULLIF(btrim(OLD.rfid_siniiga), '') THEN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, id_company, identifier_type, previous_value, new_value, reason, changed_by, notes)
        VALUES (NEW.id, NEW.tenant_id, 'SINIIGA', OLD.rfid_siniiga, NEW.rfid_siniiga, v_reason, v_changed_by, v_notes);
    END IF;

    IF NULLIF(btrim(NEW.electronic_rfid), '') IS DISTINCT FROM NULLIF(btrim(OLD.electronic_rfid), '') THEN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, id_company, identifier_type, previous_value, new_value, reason, changed_by, notes)
        VALUES (NEW.id, NEW.tenant_id, 'CHIP', OLD.electronic_rfid, NEW.electronic_rfid, v_reason, v_changed_by, v_notes);
    END IF;

    RETURN NEW;
END;
$$;

-- 6. Gateway model (idempotent) ------------------------------------------------------------------------------------------------------
UPDATE public.crud_models
   SET allowed_ops = array_remove(allowed_ops, 'INSERT'),
       allowed_roles_insert = 'NONE',
       allowed_fields = CASE WHEN allowed_fields::jsonb ? 'id_company'
                             THEN allowed_fields::jsonb
                             ELSE allowed_fields::jsonb || '["id_company"]'::jsonb END,
       schema_json = jsonb_set(
                         schema_json::jsonb || jsonb_build_object('id_company', jsonb_build_object('type', 'number', 'required', false)),
                         '{reason,options}',
                         '["LOST", "REPLACED", "CAPTURE_CORRECTION", "FOUND_LOOSE_REASSIGNED", "INITIAL_ASSIGNMENT", "AUTHORIZED_CHANGE"]'::jsonb)
 WHERE model_name = 'cattle_identifier_history';

-- 7. Post-checks ----------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_rows integer;
BEGIN
    SELECT count(*) INTO v_rows FROM public.cattle_identifier_history;
    IF (SELECT is_nullable FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'cattle_identifier_history' AND column_name = 'id_company') <> 'NO' THEN
        RAISE EXCEPTION 'POST-CHECK: id_company is nullable.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.cattle_identifier_history'::regclass AND tgname = 'trg_identifier_history_no_update_delete' AND tgenabled = 'O')
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.cattle_identifier_history'::regclass AND tgname = 'trg_identifier_history_no_truncate' AND tgenabled = 'O')
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.cattle_identifier_history'::regclass AND tgname = 'trg_identifier_history_set_company' AND tgenabled = 'O') THEN
        RAISE EXCEPTION 'POST-CHECK: a history trigger is missing or disabled.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'cattle_identifier_history'
                      AND NOT ('INSERT' = ANY (allowed_ops)) AND allowed_fields::jsonb ? 'id_company') THEN
        RAISE EXCEPTION 'POST-CHECK: gateway model not in the expected state.';
    END IF;
    RAISE NOTICE '114_identifier_history_tenant_guards: OK (history rows now carrying id_company: %)', v_rows;
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '114_identifier_history_tenant_guards: COMMITTED'
\else
ROLLBACK;
\echo '114_identifier_history_tenant_guards: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
