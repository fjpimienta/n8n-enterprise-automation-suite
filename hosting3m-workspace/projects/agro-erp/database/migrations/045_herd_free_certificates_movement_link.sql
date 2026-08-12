-- Migration 045: Link herd_free_certificates (TB/BR) to movement events
--
-- Rejected a simple movement_event_id FK on herd_free_certificates (the
-- pattern used for compliance_certificates in 044). herd_free_certificates
-- models a TIME-BOUND sanitary status (issued_at/valid_until/is_active),
-- not a one-time-use document tied to a single movement: the same TB/BR
-- folio can legitimately back several different movements while it
-- remains valid, and real CZM examples confirm this -- they cite specific
-- TB/BR folios as references, not as consumed/single-use documents.
--
-- Uses a bridge table instead (same many-to-many pattern already used for
-- cattle_movement_event_animals): a movement event can cite 0-2 health
-- certificates (TB and/or BR), and the same certificate can be cited by
-- many events across its validity window.
--
-- Also registers herd_free_certificates in crud_models -- it existed in
-- the schema but was never registered with the Meta-CRUD gateway, so the
-- frontend could not read or write it until now. Registers the new bridge
-- table for the same reason.
--
-- NOTE (flagged, not resolved here): cattle_movement_rules has two
-- separate columns, requires_valid_psg and requires_health_tests, whose
-- exact distinction is inherited from the original 020 draft and was
-- never clarified. Migration 042 set both to the same values for every
-- confirmed row, assuming they cover the same TB/BR/herd-free concept --
-- this may be wrong if requires_valid_psg was meant to refer to something
-- else (e.g. the PSG facility's own psg_licenses status). Left as a
-- follow-up, not guessed at here.

BEGIN;

CREATE TABLE cattle_movement_event_health_certs (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id                  UUID NOT NULL REFERENCES cattle_movement_events(id) ON DELETE CASCADE,
    herd_free_certificate_id  UUID NOT NULL REFERENCES herd_free_certificates(id),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, herd_free_certificate_id)
);

CREATE INDEX idx_movement_event_health_certs_event ON cattle_movement_event_health_certs(event_id);
CREATE INDEX idx_movement_event_health_certs_cert ON cattle_movement_event_health_certs(herd_free_certificate_id);

COMMENT ON TABLE cattle_movement_event_health_certs IS
    'Bridge table: which TB/BR herd_free_certificates were cited to support a given movement event. Many-to-many by design -- a single valid certificate can back multiple movements during its validity window, unlike the one-time-use documents tracked in compliance_certificates (044).';

INSERT INTO crud_models
    (model_name, table_name, primary_key, allowed_fields, schema_json,
     allowed_ops, allowed_roles_select, allowed_roles_insert,
     allowed_roles_update, allowed_roles_delete, joins, is_global)
VALUES
(
    'herd_free_certificates',
    'herd_free_certificates',
    'id',
    '["id", "id_company", "production_unit_id", "disease", "folio", "issued_at", "valid_until", "issuing_authority", "veterinarian_name", "veterinarian_license", "is_active", "created_at"]',
    '{"id": {"type": "text", "required": false}, "id_company": {"type": "number", "required": true}, "production_unit_id": {"type": "text", "required": true}, "disease": {"type": "select", "options": ["TB", "BR"], "required": true}, "folio": {"type": "text", "required": true}, "issued_at": {"type": "text", "required": true}, "valid_until": {"type": "text", "required": true}, "issuing_authority": {"type": "text", "required": false}, "veterinarian_name": {"type": "text", "required": false}, "veterinarian_license": {"type": "text", "required": false}, "is_active": {"type": "boolean", "required": false, "default": true}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,EDITOR',
    'ADMIN',
    'NONE',
    '[{"table": "companys", "fields": {"company_name": "tenant_name"}, "own_col": "id_company", "foreign_col": "id_company"}]',
    false
),
(
    'cattle_movement_event_health_certs',
    'cattle_movement_event_health_certs',
    'id',
    '["id", "event_id", "herd_free_certificate_id", "created_at"]',
    '{"id": {"type": "text", "required": false}, "event_id": {"type": "text", "required": true}, "herd_free_certificate_id": {"type": "text", "required": true}, "created_at": {"type": "text", "required": false}}',
    '{SELECT,INSERT,UPDATE,GETONE,GETALL}',
    'ADMIN,EDITOR,CUSTOMER',
    'ADMIN,OWNER',
    'ADMIN,OWNER',
    'ADMIN',
    '[{"table": "herd_free_certificates", "fields": {"disease": "disease", "folio": "folio", "valid_until": "valid_until"}, "own_col": "herd_free_certificate_id", "foreign_col": "id"}]',
    false
);

COMMIT;
