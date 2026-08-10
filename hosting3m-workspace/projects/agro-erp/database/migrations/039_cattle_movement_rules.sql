-- Migration 039: cattle_movement_rules — cross-property movement tracking
-- Complements migration 020 (cattle_movement_rules policy catalog, still
-- is_confirmed = false for every row). 020 is the RULE catalog (what kinds
-- of movement are policy-permitted); 039 is the EVENT log (what actually
-- happened). 039 links to 020 via rule_id so enforcement can be switched on
-- later, but does not enforce it today since no rule in 020 is confirmed.
--
-- Confirmed by client:
--   - PSG is a real physical destination (a facility ganado is transported
--     to), not just a certificate. Modeled here as psg_facilities.
--   - Cross-tenant movement does not happen in practice (Alejandro and
--     Pedro's herds never mix except via a formal ownership transfer,
--     a separate not-yet-designed process). Enforced fail-closed via trigger.
--   - Destination acknowledgement is NOT part of today's real workflow
--     (WhatsApp capture + photo evidence + REEMO folio is considered
--     sufficient by the client today), but the client wants this to be
--     ready for a future acknowledgement step as a best practice. Modeled
--     as a status column that defaults to auto-completed, so today's
--     single-party flow requires zero extra steps, and a future
--     two-party ack flow can be turned on without another migration.

BEGIN;

-- 1. PSG as a physical facility (not just a license/certificate)
CREATE TABLE psg_facilities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company      INTEGER NOT NULL,
    psg_license_id  UUID REFERENCES psg_licenses(id), -- links facility to its actual PSG permit
    name            TEXT NOT NULL,
    location        TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now() -- required by Meta-CRUD gateway
);

CREATE INDEX idx_psg_facilities_company ON psg_facilities(id_company);

-- 2. Catalog of external (non-tenant) destinations
CREATE TABLE external_destinations (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company        INTEGER NOT NULL,
    name              TEXT NOT NULL,
    contact_info      TEXT,
    destination_type  TEXT NOT NULL CHECK (destination_type IN
                          ('THIRD_PARTY_RANCH', 'BUYER', 'SLAUGHTERHOUSE', 'EXPORT', 'OTHER')),
    notes             TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Movement event header
CREATE TABLE cattle_movement_events (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company                      INTEGER NOT NULL,

    production_unit_origin_id       UUID NOT NULL REFERENCES production_units(id),

    -- Exactly one of these three is set: internal UPP, internal PSG facility,
    -- or external (non-tenant) third party
    production_unit_destination_id  UUID REFERENCES production_units(id),
    psg_facility_destination_id     UUID REFERENCES psg_facilities(id),
    external_destination_id         UUID REFERENCES external_destinations(id),

    rule_id                         UUID REFERENCES cattle_movement_rules(id), -- link to policy rule (020); nullable, not enforced until rules are confirmed
    reemo_folio                     TEXT, -- reference only, not validated against any external catalog
    movement_date                   DATE NOT NULL, -- date of PHYSICAL movement per REEMO guide; this is the date of record for PSG validity, NOT captured_at
    captured_at                     TIMESTAMPTZ NOT NULL DEFAULT now(), -- when the WhatsApp/system entry was actually made, may lag movement_date by days
    captured_by                     TEXT,

    -- Acknowledgement is NOT used today (single-party flow: capture + photo
    -- evidence + REEMO folio is enough per the client). Defaults to
    -- COMPLETED so nothing changes in today's workflow. If a future
    -- destination-confirmation step is needed, set status to PENDING_ACK
    -- at capture time and fill acknowledged_at/acknowledged_by when the
    -- destination confirms — no schema change required.
    status                          TEXT NOT NULL DEFAULT 'COMPLETED'
                                       CHECK (status IN ('COMPLETED', 'PENDING_ACK', 'ACKNOWLEDGED')),
    acknowledged_at                 TIMESTAMPTZ,
    acknowledged_by                 TEXT,

    notes                           TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_destination_exclusive CHECK (
        (CASE WHEN production_unit_destination_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN psg_facility_destination_id    IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN external_destination_id        IS NOT NULL THEN 1 ELSE 0 END) = 1
    )
);

-- 4. Movement event detail — one row per animal, whether the event is
-- an individual movement or a batch (same mechanism, just N rows)
CREATE TABLE cattle_movement_event_animals (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id              UUID NOT NULL REFERENCES cattle_movement_events(id) ON DELETE CASCADE,
    cattle_livestock_id   UUID NOT NULL REFERENCES cattle_livestock(id), -- authoritative reference
    fire_number_snapshot  TEXT, -- non-authoritative copy of numero_fuego at time of movement, for field lookups only. Fire numbers CAN repeat by capture error — never use this as a join key or unique identifier.
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, cattle_livestock_id)
);

CREATE INDEX idx_movement_event_animals_event ON cattle_movement_event_animals(event_id);
CREATE INDEX idx_movement_event_animals_livestock ON cattle_movement_event_animals(cattle_livestock_id);
CREATE INDEX idx_movement_events_company ON cattle_movement_events(id_company);

-- 5. Fail-closed tenant isolation trigger
-- Blocks at the database level regardless of what the Meta-CRUD gateway
-- does upstream, since n8n_user is superuser and there is no RLS.
CREATE OR REPLACE FUNCTION trg_validate_movement_event_tenant()
RETURNS TRIGGER AS $$
DECLARE
    v_origin_company INTEGER;
    v_destination_company INTEGER;
BEGIN
    SELECT id_company INTO v_origin_company
    FROM production_units WHERE id = NEW.production_unit_origin_id;

    IF v_origin_company IS NULL THEN
        RAISE EXCEPTION 'cattle_movement_events: origin production_unit % not found', NEW.production_unit_origin_id;
    END IF;

    IF v_origin_company <> NEW.id_company THEN
        RAISE EXCEPTION 'cattle_movement_events: origin production_unit belongs to a different tenant (event id_company=%, origin id_company=%)',
            NEW.id_company, v_origin_company;
    END IF;

    IF NEW.production_unit_destination_id IS NOT NULL THEN
        SELECT id_company INTO v_destination_company
        FROM production_units WHERE id = NEW.production_unit_destination_id;

        IF v_destination_company IS NULL THEN
            RAISE EXCEPTION 'cattle_movement_events: destination production_unit % not found', NEW.production_unit_destination_id;
        END IF;

        -- Cross-tenant movement is explicitly rejected. Cross-tenant
        -- transfers must go through the (not-yet-built) ownership
        -- transfer process, never through this table.
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

CREATE TRIGGER trg_check_movement_event_tenant
    BEFORE INSERT OR UPDATE ON cattle_movement_events
    FOR EACH ROW EXECUTE FUNCTION trg_validate_movement_event_tenant();

-- Each animal in the detail table must belong to the same tenant as the event
CREATE OR REPLACE FUNCTION trg_validate_movement_animal_tenant()
RETURNS TRIGGER AS $$
DECLARE
    v_event_company INTEGER;
    v_animal_company INTEGER;
BEGIN
    SELECT id_company INTO v_event_company
    FROM cattle_movement_events WHERE id = NEW.event_id;

    SELECT pu.id_company INTO v_animal_company
    FROM cattle_livestock cl
    JOIN production_units pu ON pu.id = cl.production_unit_id
    WHERE cl.id = NEW.cattle_livestock_id;

    IF v_animal_company IS NULL THEN
        RAISE EXCEPTION 'cattle_movement_event_animals: cattle_livestock % has no resolvable tenant (missing production_unit_id?)', NEW.cattle_livestock_id;
    END IF;

    IF v_animal_company <> v_event_company THEN
        RAISE EXCEPTION 'cattle_movement_event_animals: animal % belongs to a different tenant than the movement event (animal id_company=%, event id_company=%)',
            NEW.cattle_livestock_id, v_animal_company, v_event_company;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_movement_animal_tenant
    BEFORE INSERT OR UPDATE ON cattle_movement_event_animals
    FOR EACH ROW EXECUTE FUNCTION trg_validate_movement_animal_tenant();

COMMIT;
