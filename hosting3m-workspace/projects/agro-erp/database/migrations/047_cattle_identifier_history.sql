-- Migration 047: Cattle identifier change history (fuego/siniiga/chip)
--
-- Confirmed by Francisco (Aug 2026): three identifiers exist or will exist
-- on cattle_livestock -- numero_fuego, rfid_siniiga, and electronic_rfid
-- (chip, column already exists, not yet in active use). All three are
-- searchable and all three need history: which value an animal had
-- before, and why it changed.
--
-- Design: a single generic history table (identifier_type dimension)
-- rather than three parallel tables, since the query pattern is identical
-- across all three ("what value did this animal have before/after a
-- given date").
--
-- Automation strategy (per requirement: "mostly automated, manual only in
-- the rare case, ideally eliminated"): an AFTER UPDATE trigger on
-- cattle_livestock ALWAYS logs a history row when any of the three
-- identifier columns changes -- nothing is ever silently lost, regardless
-- of which script performs the update. The change reason defaults to
-- CAPTURE_CORRECTION (the common case for an unannotated edit). A caller
-- that knows the real reason can set it explicitly via a session-local
-- Postgres setting immediately before the UPDATE:
--
--   SET LOCAL app.identifier_change_reason = 'FOUND_LOOSE_REASSIGNED';
--   SET LOCAL app.identifier_change_user = 'jperez';
--   UPDATE cattle_livestock SET rfid_siniiga = '...' WHERE id = '...';
--
-- Neither SET LOCAL call is required for the trigger to work -- both fall
-- back to sensible defaults (NULL for user, CAPTURE_CORRECTION for
-- reason) if omitted, so existing load scripts need no changes to keep
-- working, and only intentional re-tagging workflows need to adopt the
-- richer path.
--
-- The trigger fires only on UPDATE, not INSERT: an animal's first
-- identifier assignment isn't a "change" -- there is no "before" to log.
-- A single UPDATE statement that changes more than one identifier column
-- at once produces one history row per changed column.

BEGIN;

CREATE TABLE cattle_identifier_history (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cattle_livestock_id   UUID NOT NULL REFERENCES cattle_livestock(id),
    identifier_type       TEXT NOT NULL CHECK (identifier_type IN ('FUEGO', 'SINIIGA', 'CHIP')),
    previous_value        TEXT,
    new_value             TEXT,
    reason                TEXT NOT NULL CHECK (reason IN ('LOST', 'REPLACED', 'CAPTURE_CORRECTION', 'FOUND_LOOSE_REASSIGNED')),
    changed_by            TEXT,
    notes                 TEXT,
    changed_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_identifier_history_livestock ON cattle_identifier_history(cattle_livestock_id);
CREATE INDEX idx_identifier_history_type_new ON cattle_identifier_history(identifier_type, new_value);
CREATE INDEX idx_identifier_history_type_prev ON cattle_identifier_history(identifier_type, previous_value);

COMMENT ON TABLE cattle_identifier_history IS
    'Change history for the three animal identifiers (numero_fuego/FUEGO, rfid_siniiga/SINIIGA, electronic_rfid/CHIP). Populated automatically by trg_log_identifier_changes on cattle_livestock -- do not rely on application code to insert these rows for normal edits.';
COMMENT ON COLUMN cattle_identifier_history.previous_value IS
    'Value before the change. NULL only if the identifier previously had no value (e.g. an animal without a fire number gaining one for the first time via UPDATE, not INSERT).';
COMMENT ON COLUMN cattle_identifier_history.reason IS
    'Defaults to CAPTURE_CORRECTION when the update did not specify app.identifier_change_reason. LOST/REPLACED/FOUND_LOOSE_REASSIGNED require the caller to set that session variable explicitly to be recorded accurately.';

CREATE OR REPLACE FUNCTION trg_log_identifier_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_reason TEXT;
    v_changed_by TEXT;
BEGIN
    v_reason := COALESCE(current_setting('app.identifier_change_reason', true), 'CAPTURE_CORRECTION');
    v_changed_by := current_setting('app.identifier_change_user', true);

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

CREATE TRIGGER trg_cattle_livestock_identifier_history
    AFTER UPDATE ON cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION trg_log_identifier_changes();

COMMENT ON TRIGGER trg_cattle_livestock_identifier_history ON cattle_livestock IS
    'Auto-logs every change to numero_fuego, rfid_siniiga, or electronic_rfid into cattle_identifier_history. Fires unconditionally; app.identifier_change_reason / app.identifier_change_user session variables (SET LOCAL before the UPDATE) enrich the logged reason/actor but are optional.';

INSERT INTO crud_models
    (model_name, table_name, primary_key, allowed_fields, schema_json,
     allowed_ops, allowed_roles_select, allowed_roles_insert,
     allowed_roles_update, allowed_roles_delete, joins, is_global)
VALUES
(
    'cattle_identifier_history',
    'cattle_identifier_history',
    'id',
    '["id", "cattle_livestock_id", "identifier_type", "previous_value", "new_value", "reason", "changed_by", "notes", "changed_at"]',
    '{"id": {"type": "text", "required": false}, "cattle_livestock_id": {"type": "text", "required": true}, "identifier_type": {"type": "select", "options": ["FUEGO", "SINIIGA", "CHIP"], "required": true}, "previous_value": {"type": "text", "required": false}, "new_value": {"type": "text", "required": false}, "reason": {"type": "select", "options": ["LOST", "REPLACED", "CAPTURE_CORRECTION", "FOUND_LOOSE_REASSIGNED"], "required": true}, "changed_by": {"type": "text", "required": false}, "notes": {"type": "text", "required": false}, "changed_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,EDITOR',
    'NONE',
    'NONE',
    '[{"table": "cattle_livestock", "fields": {"rfid_siniiga": "current_rfid_siniiga", "numero_fuego": "current_numero_fuego", "category": "animal_category"}, "own_col": "cattle_livestock_id", "foreign_col": "id"}]',
    false
);

COMMIT;
