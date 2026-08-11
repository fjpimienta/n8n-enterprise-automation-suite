-- Migration 043: Support PSG as a movement origin, not just a destination
--
-- Reverses a scope decision made during migration 039's design. At the
-- time, the client had not yet confirmed whether livestock ever moves OUT
-- of a PSG, so cattle_movement_events was built with origin restricted to
-- production_units only (YAGNI). The Aug 2026 audio transcript confirms
-- this DOES happen in practice: producers who own both UPPs and a PSG
-- move animals from their UPP into their own PSG first, and once an
-- animal is inside a PSG it can only move to another PSG (own or
-- third-party) or exit to RASTRO/EXPORTACION — never back to a UPP
-- (enforced by migration 042's PSG->UPP is_allowed=false rows).
--
-- This makes PSG a required possible origin, symmetric with how it's
-- already handled as a destination in migration 039.

BEGIN;

-- Preflight: confirm the table is still empty before loosening a NOT NULL
-- constraint and restructuring its exclusivity check.
DO $$
DECLARE
    v_row_count INTEGER;
BEGIN
    SELECT count(*) INTO v_row_count FROM cattle_movement_events;
    IF v_row_count > 0 THEN
        RAISE EXCEPTION 'Aborting 043: cattle_movement_events has % row(s). This migration assumes an empty table; review before proceeding.', v_row_count;
    END IF;
END $$;

ALTER TABLE cattle_movement_events
    ALTER COLUMN production_unit_origin_id DROP NOT NULL;

ALTER TABLE cattle_movement_events
    ADD COLUMN psg_facility_origin_id UUID REFERENCES psg_facilities(id);

ALTER TABLE cattle_movement_events
    ADD CONSTRAINT chk_origin_exclusive CHECK (
        (production_unit_origin_id IS NOT NULL AND psg_facility_origin_id IS NULL)
        OR
        (production_unit_origin_id IS NULL AND psg_facility_origin_id IS NOT NULL)
    );

CREATE INDEX idx_movement_events_psg_origin ON cattle_movement_events(psg_facility_origin_id);

COMMENT ON COLUMN cattle_movement_events.production_unit_origin_id IS
    'Origin production unit, if the movement originates from a UPP. Exactly one of production_unit_origin_id / psg_facility_origin_id must be set (chk_origin_exclusive).';
COMMENT ON COLUMN cattle_movement_events.psg_facility_origin_id IS
    'Origin PSG facility, if the movement originates from a PSG (e.g. PSG-to-PSG transfer, or PSG-to-RASTRO/EXPORTACION exit). Per migration 042, a PSG-origin movement can never target a UPP destination — enforced at the cattle_movement_rules level, not by a database constraint here.';

-- Replace the tenant-isolation trigger to validate whichever origin type
-- is actually set (mirrors the three-way destination logic already in
-- place from migration 039).
CREATE OR REPLACE FUNCTION trg_validate_movement_event_tenant()
RETURNS TRIGGER AS $$
DECLARE
    v_origin_company INTEGER;
    v_destination_company INTEGER;
BEGIN
    IF NEW.production_unit_origin_id IS NOT NULL THEN
        SELECT id_company INTO v_origin_company
        FROM production_units WHERE id = NEW.production_unit_origin_id;

        IF v_origin_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: origin production_unit % not found', NEW.production_unit_origin_id;
        END IF;

        IF v_origin_company <> NEW.id_company THEN
            RAISE EXCEPTION 'cattle_movement_events: origin production_unit belongs to a different tenant (event id_company=%, origin id_company=%)',
                NEW.id_company, v_origin_company;
        END IF;
    END IF;

    IF NEW.psg_facility_origin_id IS NOT NULL THEN
        SELECT id_company INTO v_origin_company
        FROM psg_facilities WHERE id = NEW.psg_facility_origin_id;

        IF v_origin_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: origin psg_facility % not found', NEW.psg_facility_origin_id;
        END IF;

        IF v_origin_company <> NEW.id_company THEN
            RAISE EXCEPTION 'cattle_movement_events: origin psg_facility belongs to a different tenant (event id_company=%, origin id_company=%)',
                NEW.id_company, v_origin_company;
        END IF;
    END IF;

    IF NEW.production_unit_destination_id IS NOT NULL THEN
        SELECT id_company INTO v_destination_company
        FROM production_units WHERE id = NEW.production_unit_destination_id;

        IF v_destination_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: destination production_unit % not found', NEW.production_unit_destination_id;
        END IF;

        IF v_destination_company <> NEW.id_company THEN
            RAISE EXCEPTION 'cattle_movement_events: cross-tenant movement is not allowed (event id_company=%, destination id_company=%). Use an ownership transfer process instead.',
                NEW.id_company, v_destination_company;
        END IF;
    END IF;

    IF NEW.psg_facility_destination_id IS NOT NULL THEN
        SELECT id_company INTO v_destination_company
        FROM psg_facilities WHERE id = NEW.psg_facility_destination_id;

        IF v_destination_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: psg_facility % not found', NEW.psg_facility_destination_id;
        END IF;

        IF v_destination_company <> NEW.id_company THEN
            RAISE EXCEPTION 'cattle_movement_events: cross-tenant movement to a PSG facility is not allowed (event id_company=%, facility id_company=%). Use an ownership transfer process instead.',
                NEW.id_company, v_destination_company;
        END IF;
    END IF;

    IF NEW.external_destination_id IS NOT NULL THEN
        SELECT id_company INTO v_destination_company
        FROM external_destinations WHERE id = NEW.external_destination_id;

        IF v_destination_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: external_destination % not found', NEW.external_destination_id;
        END IF;

        IF v_destination_company <> NEW.id_company THEN
            RAISE EXCEPTION 'cattle_movement_events: external_destination belongs to a different tenant (event id_company=%, destination id_company=%)',
                NEW.id_company, v_destination_company;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;
