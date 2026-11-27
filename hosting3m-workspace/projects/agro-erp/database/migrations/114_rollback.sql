-- 114_rollback.sql. No DROP / DELETE / TRUNCATE of data.
-- Restores: a HARDENED version of the 047 logger (not the exact 047 text) and the gateway INSERT of the history model.
-- Why hardened: 047 reads COALESCE(current_setting(..., true), default). Once a custom setting has been used in a session it reads '' (not NULL), so the
-- reason became '' and broke the CHECK. The hardened logger uses NULLIF(current_setting(..., true), '') with the same defaults. It still has NO reason
-- validation, NO company column and NO notes (as in 047); its body carries the marker 'hardened-047-logger'. Do not expect md5 7068e9a8... after this rollback.
-- ROLLBACK ORDER: step 2 (tag change authorization) first, then this step 1. Never roll step 1 back while step 2 is applied.
-- Switched off (not dropped): the append-only triggers.
-- Kept on purpose (all are supersets and harmless to the old behaviour): the id_company column and its indexes, the BEFORE INSERT trigger that fills
-- id_company (it makes the old logger work, because the old text does not write that column), the wider reason CHECK, id_company in allowed_fields
-- (so the gateway keeps filtering by company) and every history row written while the migration was applied.
-- Re-applying 114_identifier_history_tenant_guards.sql restores the new rules.
--
--   psql -X -v ON_ERROR_STOP=1 -f 114_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 114_rollback.sql  -> commit

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

DO $$
BEGIN
    IF to_regprocedure('public.trg_log_identifier_changes()') IS NULL THEN
        RAISE EXCEPTION 'ABORT rollback: trg_log_identifier_changes() not found.';
    END IF;
    IF pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%identifier_change_notes%'
       AND pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%hardened-047-logger%'
       AND md5(pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure)) <> '7068e9a8e4af7364d16c41c2b77c7570' THEN
        RAISE EXCEPTION 'ABORT rollback: the live logger is neither the new text, the hardened text nor the 047 text. Nothing was changed.';
    END IF;
END $$;

-- Hardened 047 logger (marker below is checked by the tests and by the drift guard of the migration).
CREATE OR REPLACE FUNCTION trg_log_identifier_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_reason TEXT;
    v_changed_by TEXT;
BEGIN
    -- hardened-047-logger: NULLIF turns '' (what a session reads after a custom setting was used) into NULL, so the default applies.
    v_reason := COALESCE(NULLIF(current_setting('app.identifier_change_reason', true), ''), 'CAPTURE_CORRECTION');
    v_changed_by := NULLIF(current_setting('app.identifier_change_user', true), '');

    IF NEW.numero_fuego IS DISTINCT FROM OLD.numero_fuego THEN
        INSERT INTO cattle_identifier_history (cattle_livestock_id, identifier_type, previous_value, new_value, reason, changed_by)
        VALUES (NEW.id, 'FUEGO', OLD.numero_fuego, NEW.numero_fuego, v_reason, v_changed_by);
    END IF;

    IF NEW.rfid_siniiga IS DISTINCT FROM OLD.rfid_siniiga THEN
        INSERT INTO cattle_identifier_history (cattle_livestock_id, identifier_type, previous_value, new_value, reason, changed_by)
        VALUES (NEW.id, 'SINIIGA', OLD.rfid_siniiga, NEW.rfid_siniiga, v_reason, v_changed_by);
    END IF;

    IF NEW.electronic_rfid IS DISTINCT FROM OLD.electronic_rfid THEN
        INSERT INTO cattle_identifier_history (cattle_livestock_id, identifier_type, previous_value, new_value, reason, changed_by)
        VALUES (NEW.id, 'CHIP', OLD.electronic_rfid, NEW.electronic_rfid, v_reason, v_changed_by);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE public.cattle_identifier_history DISABLE TRIGGER trg_identifier_history_no_update_delete;
ALTER TABLE public.cattle_identifier_history DISABLE TRIGGER trg_identifier_history_no_truncate;

UPDATE public.crud_models
   SET allowed_ops = CASE WHEN 'INSERT' = ANY (allowed_ops) THEN allowed_ops ELSE array_append(allowed_ops, 'INSERT') END,
       allowed_roles_insert = 'ADMIN,EDITOR'
 WHERE model_name = 'cattle_identifier_history';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'cattle_identifier_history' AND 'INSERT' = ANY (allowed_ops)) THEN
        RAISE EXCEPTION 'POST-CHECK rollback: gateway INSERT was not restored.';
    END IF;
    RAISE NOTICE '114_identifier_history_tenant_guards rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo 'rollback: COMMITTED'
\else
ROLLBACK;
\echo 'rollback: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
