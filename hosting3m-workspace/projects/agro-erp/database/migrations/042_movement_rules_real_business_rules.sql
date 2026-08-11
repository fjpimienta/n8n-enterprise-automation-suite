-- Migration 042: Restructure cattle_movement_rules with real business rules
--
-- Confirmed by Alejandro/Pedro (audio transcript, Aug 2026), replacing the
-- draft matrix seeded in migration 020. Key corrections vs. the draft:
--
--   - PSG -> UPP is NEVER allowed, in any circumstance. Once an animal
--     enters a PSG, it can only move to another PSG (own or third-party).
--     The draft had this as allowed by default — wrong.
--   - What's required depends on whether the movement is INTERSTATE, not
--     on the origin/destination pair alone. A same-state UPP->UPP or
--     UPP->PSG movement needs only a transit guide (no health tests, no
--     OIRSA screwworm certificate, no introduction permit). The same pair,
--     interstate, needs all of: valid TB/BR status (or herd-free), OIRSA
--     certificate, and the destination state's introduction permit.
--     This is why is_interstate is now a row dimension (origin_type,
--     destination_type, is_interstate), not a boolean attribute — the
--     matrix goes from 8 rows to 16.
--   - Real example of the interstate case: Tenosique (Tabasco) -> Palenque
--     (Chiapas), already loaded in migration 038.
--
-- requires_destination_ack is intentionally NOT flipped to true anywhere
-- in this migration, and is_confirmed stays false for every row except
-- PSG->UPP (see below). The ack question was sent to Alejandro/Pedro
-- separately and has not been answered yet. Storing the now-known values
-- while withholding is_confirmed keeps the fail-closed guarantee intact:
-- no enforcement activates until every relevant field for a row is
-- actually confirmed, per the original design intent documented on this
-- table (see migration 020's COMMENT ON COLUMN is_confirmed).
--
-- PSG->UPP is the one exception: it's marked is_confirmed = true
-- immediately, because the movement is disallowed outright — there is
-- nothing left to acknowledge on a movement that can never happen.
--
-- OIRSA (Organismo Internacional Regional de Sanidad Agropecuaria) issues
-- the screwworm-free certificate required for any interstate movement.
-- The introduction permit is issued separately by the destination state's
-- government. Neither has a supporting table yet — both are conceptually
-- close to compliance_certificates (a new certificate_type each), to be
-- addressed in a follow-up migration once the document structure is
-- confirmed in more detail. RASTRO and EXPORTACION requirements remain
-- unconfirmed drafts (is_confirmed = false), split into interstate/local
-- rows for schema consistency but not yet validated with the client.

BEGIN;

-- Preflight: nothing in cattle_movement_events references a rule yet,
-- so this table is safe to fully restructure without orphaning data.
DO $$
DECLARE
    v_ref_count INTEGER;
BEGIN
    SELECT count(*) INTO v_ref_count FROM cattle_movement_events WHERE rule_id IS NOT NULL;
    IF v_ref_count > 0 THEN
        RAISE EXCEPTION 'Aborting 042: % cattle_movement_events rows already reference a cattle_movement_rules row. Restructuring would orphan them.', v_ref_count;
    END IF;
END $$;

ALTER TABLE cattle_movement_rules
    ADD COLUMN is_interstate BOOLEAN,
    ADD COLUMN requires_oirsa_certificate BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN requires_introduction_permit BOOLEAN NOT NULL DEFAULT false;

-- Clear the 8 draft rows from 020 — safe per the preflight check above.
DELETE FROM cattle_movement_rules;

ALTER TABLE cattle_movement_rules
    ALTER COLUMN is_interstate SET NOT NULL,
    DROP COLUMN allows_interstate;

ALTER TABLE cattle_movement_rules
    DROP CONSTRAINT IF EXISTS uq_movement_rules_pair;

ALTER TABLE cattle_movement_rules
    ADD CONSTRAINT uq_movement_rules_pair UNIQUE (origin_type, destination_type, is_interstate);

COMMENT ON COLUMN cattle_movement_rules.is_interstate IS
    'Whether this rule applies to a same-state or cross-state movement. Requirements differ substantially: interstate movements require TB/BR status, an OIRSA screwworm certificate, and the destination state''s introduction permit, in addition to the transit guide required in all cases.';
COMMENT ON COLUMN cattle_movement_rules.requires_oirsa_certificate IS
    'Whether an OIRSA (Organismo Internacional Regional de Sanidad Agropecuaria) screwworm-free certificate is required before the transit guide can be issued. Confirmed applicable to interstate movements only.';
COMMENT ON COLUMN cattle_movement_rules.requires_introduction_permit IS
    'Whether the destination state''s government must issue an introduction permit before the animal can cross state lines. Confirmed applicable to interstate movements only.';

INSERT INTO cattle_movement_rules
    (origin_type, destination_type, is_interstate, is_allowed, requires_valid_psg,
     requires_health_tests, requires_oirsa_certificate, requires_introduction_permit,
     requires_destination_ack, is_confirmed, notes)
VALUES
    -- UPP -> UPP
    ('UPP', 'UPP', false, true, false, false, false, false, false, false,
     'CONFIRMED (audio, Aug 2026): same-owner, same-state movement between two UPPs only needs a simple transit guide. No health tests, no OIRSA, no introduction permit. requires_destination_ack left at proposed default (false, single-party WhatsApp capture); is_confirmed withheld pending stakeholder sign-off on that specific question.'),
    ('UPP', 'UPP', true, true, true, true, true, true, false, false,
     'CONFIRMED (audio, Aug 2026): interstate UPP-to-UPP requires valid TB/BR status (or herd-free), an OIRSA screwworm certificate, and the destination state''s introduction permit, in addition to the transit guide. Real example already in the system: Tenosique (Tabasco) -> Palenque (Chiapas), migration 038. is_confirmed withheld pending requires_destination_ack sign-off.'),

    -- UPP -> PSG
    ('UPP', 'PSG', false, true, false, false, false, false, false, false,
     'CONFIRMED (audio, Aug 2026): same-state UPP-to-PSG only needs the transit guide, same as UPP-to-UPP local. is_confirmed withheld pending requires_destination_ack sign-off.'),
    ('UPP', 'PSG', true, true, true, true, true, true, false, false,
     'CONFIRMED (audio, Aug 2026): interstate UPP-to-PSG follows the full interstate protocol, same requirements as interstate UPP-to-UPP. is_confirmed withheld pending requires_destination_ack sign-off.'),

    -- PSG -> PSG
    ('PSG', 'PSG', false, true, false, false, false, false, false, false,
     'CONFIRMED (audio, Aug 2026): same-state PSG-to-PSG only needs the transit guide. This is the ONLY movement a PSG-resident animal can make besides RASTRO/EXPORTACION. is_confirmed withheld pending requires_destination_ack sign-off.'),
    ('PSG', 'PSG', true, true, true, true, true, true, false, false,
     'CONFIRMED (audio, Aug 2026): interstate PSG-to-PSG follows the full interstate protocol. is_confirmed withheld pending requires_destination_ack sign-off.'),

    -- PSG -> UPP: never allowed, fully confirmed, no ack dependency
    ('PSG', 'UPP', false, false, false, false, false, false, false, true,
     'CONFIRMED (audio, Aug 2026): a PSG-resident animal can NEVER move back to a UPP, under any circumstance, same-state or interstate. Fully confirmed and blocked outright -- no destination-ack dependency since the movement itself is disallowed.'),
    ('PSG', 'UPP', true, false, false, false, false, false, false, true,
     'CONFIRMED (audio, Aug 2026): see PSG->UPP local -- rule is identical and unconditional regardless of interstate status.'),

    -- UPP -> RASTRO: draft, unconfirmed, preserved from migration 020
    ('UPP', 'RASTRO', false, true, true, true, false, false, false, false,
     'DRAFT carried over from migration 020, NOT covered by the Aug 2026 audio. Definitive exit to slaughter; no destination acknowledgement since the animal leaves the traceability chain. Currently handled by sp_procesar_salida_ganado as VENTA. Needs explicit client confirmation, especially on whether OIRSA/introduction-permit requirements apply here too when interstate.'),
    ('UPP', 'RASTRO', true, true, true, true, false, false, false, false,
     'DRAFT, unconfirmed -- see UPP->RASTRO local. Whether OIRSA/introduction-permit apply to an interstate RASTRO shipment is not yet confirmed.'),

    -- PSG -> RASTRO: draft, unconfirmed
    ('PSG', 'RASTRO', false, true, true, true, false, false, false, false,
     'DRAFT carried over from migration 020, NOT covered by the Aug 2026 audio. Consistent with PSG''s stated purpose as a direct exit point to slaughter or export.'),
    ('PSG', 'RASTRO', true, true, true, true, false, false, false, false,
     'DRAFT, unconfirmed -- see PSG->RASTRO local.'),

    -- UPP -> EXPORTACION: draft, unconfirmed
    ('UPP', 'EXPORTACION', false, true, true, true, false, false, false, false,
     'DRAFT carried over from migration 020, NOT covered by the Aug 2026 audio. Almost certainly needs additional federal documentation not modelled here yet.'),
    ('UPP', 'EXPORTACION', true, true, true, true, false, false, false, false,
     'DRAFT, unconfirmed -- see UPP->EXPORTACION local.'),

    -- PSG -> EXPORTACION: draft, unconfirmed
    ('PSG', 'EXPORTACION', false, true, true, true, false, false, false, false,
     'DRAFT carried over from migration 020, NOT covered by the Aug 2026 audio. Consistent with PSG''s stated purpose as a direct exit point to slaughter or export.'),
    ('PSG', 'EXPORTACION', true, true, true, true, false, false, false, false,
     'DRAFT, unconfirmed -- see PSG->EXPORTACION local.');

COMMIT;
