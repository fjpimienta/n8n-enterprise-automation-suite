-- Migration 049: Fix destination_type/normative_type correspondence where unambiguous
--
-- Confirmed empty (0 rows) in external_destinations before this migration
-- in both environments, so safe to tighten the CHECK without a backfill.
--
-- normative_type (041) already solved the core BUYER ambiguity: whoever
-- registers a destination must explicitly classify it as UPP/PSG/RASTRO/
-- EXPORTACION, since a buyer might legally operate as any of those. What
-- was still missing: nothing stopped a nonsensical pairing for the three
-- destination_type values where the correspondence IS fixed and
-- unambiguous -- e.g. destination_type='SLAUGHTERHOUSE' with
-- normative_type='UPP' made no sense, but nothing rejected it.
--
-- This adds a CHECK enforcing the fixed pairings for SLAUGHTERHOUSE,
-- EXPORT, and THIRD_PARTY_RANCH, while leaving BUYER and OTHER free to
-- take any of the four normative_type values -- that's precisely where
-- the real ambiguity lives (a buyer's own operation could be any of the
-- four), so those two are deliberately left unconstrained.

BEGIN;

DO $$
DECLARE
    v_row_count INTEGER;
BEGIN
    SELECT count(*) INTO v_row_count FROM external_destinations;
    IF v_row_count > 0 THEN
        RAISE EXCEPTION 'Aborting 049: external_destinations has % row(s). This migration assumes an empty table; verify no existing row would violate the new fixed-pairing CHECK before proceeding.', v_row_count;
    END IF;
END $$;

ALTER TABLE external_destinations
    ADD CONSTRAINT chk_normative_type_fixed_mapping CHECK (
        (destination_type = 'SLAUGHTERHOUSE' AND normative_type = 'RASTRO')
        OR (destination_type = 'EXPORT' AND normative_type = 'EXPORTACION')
        OR (destination_type = 'THIRD_PARTY_RANCH' AND normative_type = 'UPP')
        OR (destination_type IN ('BUYER', 'OTHER'))
    );

COMMENT ON CONSTRAINT chk_normative_type_fixed_mapping ON external_destinations IS
    'Enforces the fixed, unambiguous destination_type -> normative_type pairings (a slaughterhouse is always RASTRO, an export destination is always EXPORTACION, a third-party ranch is always UPP). BUYER and OTHER are deliberately left unconstrained: a buyer''s actual operation may legally be a UPP, a PSG, or ship straight to RASTRO, which is exactly the ambiguity normative_type (041) exists to let the registrant resolve case by case.';

COMMIT;
