-- Migration 040: Register migration 039 tables in the Meta-CRUD gateway
--
-- Registers psg_facilities, external_destinations, cattle_movement_events,
-- and cattle_movement_event_animals in crud_models so the n8n gateway
-- (06-dynamic-crud-engine) and the Angular frontend can read/write them.
--
-- Role pattern:
--   - psg_facilities, external_destinations: reference catalogs, same
--     pattern as production_units/psg_licenses (ADMIN,OWNER can write,
--     ADMIN,EDITOR,CUSTOMER can read).
--   - cattle_movement_events, cattle_movement_event_animals: editable per
--     client decision, restricted to ADMIN,OWNER for INSERT/UPDATE (not
--     EDITOR/CUSTOMER), same as production_units. No DELETE op exposed.
--     NOTE: editing a movement event after capture has compliance
--     implications (REEMO folio is a legal record of movement). If this
--     becomes a real workflow need, consider replacing UPDATE with an
--     append-only correction pattern (a new event referencing the
--     original, same idea as historico_movimientos' REVERSION type in
--     migration 025) instead of loosening this further.

BEGIN;

INSERT INTO crud_models
    (model_name, table_name, primary_key, allowed_fields, schema_json,
     allowed_ops, allowed_roles_select, allowed_roles_insert,
     allowed_roles_update, allowed_roles_delete, joins, is_global)
VALUES
(
    'psg_facilities',
    'psg_facilities',
    'id',
    '["id", "id_company", "psg_license_id", "name", "location", "notes", "created_at"]',
    '{"id": {"type": "text", "required": false}, "id_company": {"type": "number", "required": true}, "psg_license_id": {"type": "text", "required": false}, "name": {"type": "text", "required": true}, "location": {"type": "text", "required": false}, "notes": {"type": "text", "required": false}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,OWNER',
    'ADMIN,OWNER',
    'ADMIN',
    '[{"table": "companys", "fields": {"company_name": "tenant_name"}, "own_col": "id_company", "foreign_col": "id_company"}]',
    false
),
(
    'external_destinations',
    'external_destinations',
    'id',
    '["id", "id_company", "name", "contact_info", "destination_type", "notes", "created_at"]',
    '{"id": {"type": "text", "required": false}, "id_company": {"type": "number", "required": true}, "name": {"type": "text", "required": true}, "contact_info": {"type": "text", "required": false}, "destination_type": {"type": "select", "options": ["THIRD_PARTY_RANCH", "BUYER", "SLAUGHTERHOUSE", "EXPORT", "OTHER"], "required": true}, "notes": {"type": "text", "required": false}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,OWNER',
    'ADMIN,OWNER',
    'ADMIN',
    '[{"table": "companys", "fields": {"company_name": "tenant_name"}, "own_col": "id_company", "foreign_col": "id_company"}]',
    false
),
(
    'cattle_movement_events',
    'cattle_movement_events',
    'id',
    '["id", "id_company", "production_unit_origin_id", "production_unit_destination_id", "psg_facility_destination_id", "external_destination_id", "rule_id", "reemo_folio", "movement_date", "captured_at", "captured_by", "status", "acknowledged_at", "acknowledged_by", "notes", "created_at"]',
    '{"id": {"type": "text", "required": false}, "id_company": {"type": "number", "required": true}, "production_unit_origin_id": {"type": "text", "required": true}, "production_unit_destination_id": {"type": "text", "required": false}, "psg_facility_destination_id": {"type": "text", "required": false}, "external_destination_id": {"type": "text", "required": false}, "rule_id": {"type": "text", "required": false}, "reemo_folio": {"type": "text", "required": false}, "movement_date": {"type": "text", "required": true}, "captured_at": {"type": "text", "required": false}, "captured_by": {"type": "text", "required": false}, "status": {"type": "select", "options": ["COMPLETED", "PENDING_ACK", "ACKNOWLEDGED"], "required": false, "default": "COMPLETED"}, "acknowledged_at": {"type": "text", "required": false}, "acknowledged_by": {"type": "text", "required": false}, "notes": {"type": "text", "required": false}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,OWNER',
    'ADMIN,OWNER',
    'ADMIN',
    '[{"table": "companys", "fields": {"company_name": "tenant_name"}, "own_col": "id_company", "foreign_col": "id_company"}]',
    false
),
(
    'cattle_movement_event_animals',
    'cattle_movement_event_animals',
    'id',
    '["id", "event_id", "cattle_livestock_id", "fire_number_snapshot", "created_at"]',
    '{"id": {"type": "text", "required": false}, "event_id": {"type": "text", "required": true}, "cattle_livestock_id": {"type": "text", "required": true}, "fire_number_snapshot": {"type": "text", "required": false}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,OWNER',
    'ADMIN,OWNER',
    'ADMIN',
    '[{"table": "cattle_livestock", "fields": {"rfid_siniiga": "rfid_siniiga", "numero_fuego": "numero_fuego"}, "own_col": "cattle_livestock_id", "foreign_col": "id"}]',
    false
);

COMMIT;
