-- Migration 048: Document the requires_valid_psg / requires_health_tests distinction
--
-- Clarifies an ambiguity inherited from the original 020 draft and left
-- unresolved through 042: these are two distinct concepts, not a
-- duplicate pair. No data changes -- this is purely documentation via
-- COMMENT ON COLUMN, since the underlying data these concepts refer to
-- already exists (herd_free_certificates for health tests since 045;
-- psg_licenses.expires_at for PSG license validity since the original
-- schema).
--
-- requires_valid_psg: when the movement involves a PSG (as origin or
-- destination), that PSG facility's own operating license
-- (psg_facilities.psg_license_id -> psg_licenses.expires_at) must be
-- current. Not about the animal's health status.
--
-- requires_health_tests: the animal's own TB/BR status must be current
-- (valid herd_free_certificates) or the origin UPP must have herd-free
-- status. Not about the PSG's license.
--
-- No enforcement logic changes: all 16 rows in cattle_movement_rules
-- remain exactly as set in 042/044, is_confirmed unchanged.

BEGIN;

COMMENT ON COLUMN cattle_movement_rules.requires_valid_psg IS
    'Whether a PSG facility involved in the movement (as origin or destination) must have a currently valid operating license -- i.e. psg_facilities.psg_license_id references a psg_licenses row with expires_at in the future. This is about the PSG facility''s own license, NOT the animal''s health status (see requires_health_tests for that). Irrelevant for pure UPP-to-UPP movements with no PSG involved.';
COMMENT ON COLUMN cattle_movement_rules.requires_health_tests IS
    'Whether the animal(s) being moved must have current TB/BR status -- either valid herd_free_certificates for the relevant disease(s), or herd-free status at the origin production unit. This is about animal sanitary status, NOT any PSG facility''s operating license (see requires_valid_psg for that).';

COMMIT;
