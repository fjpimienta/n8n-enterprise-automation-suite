-- Migration 041: Add normative_type to external_destinations
--
-- Bridges the operational/commercial destination_type vocabulary (039:
-- THIRD_PARTY_RANCH, BUYER, SLAUGHTERHOUSE, EXPORT, OTHER) with the
-- normative/compliance vocabulary used by cattle_movement_rules (020:
-- UPP, PSG, RASTRO, EXPORTACION).
--
-- Rejected alternative: a hardcoded CASE mapping in the movement-tenant
-- trigger. That couples two independent domains (commercial destination
-- type vs. SENASICA-facing movement classification) inside trigger logic,
-- and cannot represent destination_type values with no fixed normative
-- equivalent (e.g. BUYER can legally operate as a UPP, a PSG, or ship
-- straight to RASTRO depending on the specific buyer). Delegating the
-- classification to a column on the row lets the person registering the
-- destination make that call explicitly, and keeps the eventual
-- rule_id-matching logic a plain equality check instead of embedded
-- business logic.
--
-- Safe to apply as NOT NULL with no backfill: external_destinations is
-- confirmed empty in both the local clone and production (the only row
-- that ever existed was a test insert, already cleaned up during 039
-- verification).

BEGIN;

ALTER TABLE external_destinations
    ADD COLUMN normative_type TEXT NOT NULL
        CHECK (normative_type IN ('UPP', 'PSG', 'RASTRO', 'EXPORTACION'));

COMMENT ON COLUMN external_destinations.normative_type IS
    'Compliance-facing classification matching cattle_movement_rules.destination_type (020). Set by whoever registers the destination — e.g. a BUYER destination_type may be classified as UPP, PSG, or RASTRO depending on how that specific buyer operates.';

COMMIT;
