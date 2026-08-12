-- Migration 046: Fix compliance_certificates subject constraint for movement documents
--
-- Corrects a gap flagged (and initially mis-described) in migration 044's
-- commit message. The original compliance_certificates_single_subject_check
-- (from 013) requires exactly one of production_unit_id / psg_license_id --
-- it does NOT allow movement_event_id to stand in as the subject on its
-- own, so today it is actually IMPOSSIBLE to insert a REEMO_TRANSIT_GUIDE
-- or CZM_MOVEMENT_CERTIFICATE without also forcing an unrelated
-- production_unit_id or psg_license_id. The real documents (REEMO guide,
-- CZM, GBG constancia, state permit, ownership letter) describe a
-- movement -- an origin and destination that may each be UPP or PSG --
-- not a single unit; that information already lives on
-- cattle_movement_events.
--
-- Two constraints replace the old one:
--   1. Widens "exactly one subject" to include movement_event_id as a
--      third valid option.
--   2. Ties each certificate_type to its correct subject, so a movement
--      document can't be attached to a bare production_unit_id/
--      psg_license_id instead of the movement it actually describes, and
--      vice versa for the PGN_* unit-registration types.
--
-- Preflight-verified: compliance_certificates had 0 rows with
-- movement_event_id set in both environments before this migration, so
-- no existing data is affected by tightening the type/subject pairing.

BEGIN;

DO $$
DECLARE
    v_row_count INTEGER;
BEGIN
    SELECT count(*) INTO v_row_count FROM compliance_certificates WHERE movement_event_id IS NOT NULL;
    IF v_row_count > 0 THEN
        RAISE EXCEPTION 'Aborting 046: % compliance_certificates rows already have movement_event_id set. Review the certificate_type/subject pairing constraint against real data before proceeding.', v_row_count;
    END IF;
END $$;

ALTER TABLE compliance_certificates
    DROP CONSTRAINT IF EXISTS compliance_certificates_single_subject_check;

ALTER TABLE compliance_certificates
    ADD CONSTRAINT compliance_certificates_single_subject_check
        CHECK (num_nonnulls(production_unit_id, psg_license_id, movement_event_id) = 1);

ALTER TABLE compliance_certificates
    ADD CONSTRAINT compliance_certificates_type_subject_check CHECK (
        (certificate_type IN ('PGN_UPP_REGISTRATION', 'PGN_UPP_UPDATE', 'PGN_PSG_UPDATE')
            AND movement_event_id IS NULL)
        OR
        (certificate_type IN ('REEMO_TRANSIT_GUIDE', 'CZM_MOVEMENT_CERTIFICATE', 'GBG_TREATMENT_CERTIFICATE', 'STATE_INTRODUCTION_PERMIT', 'OWNERSHIP_TRANSFER_LETTER')
            AND movement_event_id IS NOT NULL
            AND production_unit_id IS NULL
            AND psg_license_id IS NULL)
    );

COMMENT ON CONSTRAINT compliance_certificates_single_subject_check ON compliance_certificates IS
    'Exactly one subject per certificate: a production_unit, a psg_license, or a movement_event. Widened in 046 to include movement_event_id, since movement documents (REEMO guide, CZM, etc.) describe a movement rather than a single unit.';
COMMENT ON CONSTRAINT compliance_certificates_type_subject_check ON compliance_certificates IS
    'Ties each certificate_type to its correct subject: PGN_* unit-registration types must use production_unit_id/psg_license_id (never movement_event_id); movement-related types (REEMO_TRANSIT_GUIDE, CZM_MOVEMENT_CERTIFICATE, GBG_TREATMENT_CERTIFICATE, STATE_INTRODUCTION_PERMIT, OWNERSHIP_TRANSFER_LETTER) must use movement_event_id exclusively.';

COMMIT;
