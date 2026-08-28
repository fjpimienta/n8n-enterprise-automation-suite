-- Migration 039: Lotes (agrupación física dentro de una UPP).
--
-- WHY: a single registered UPP can span several physically distinct land parcels —
-- some owned, some rented — that the client tracks separately day to day even though
-- they all report under the same SENASICA registration. Confirmed case (2026-08-25):
-- UPP 54 (Puyacatengo, Jalapa, Tabasco) has three: "El Triunfo" (rented, arrendador
-- Eladio Alejandro Navarro Ble — already loaded as a leased_land_sites row),
-- "Rancho 54" (propio), "La Calzada" (propio).
--
-- RELATIONSHIP TO EXISTING TABLES (read before touching any of these again)
--   * production_unit_paddocks (potrero) = a grazing subdivision INSIDE one physical
--     parcel. Unchanged by this migration; a paddock still belongs to a
--     production_unit directly, not to a lot. Whether paddocks should nest inside a
--     lot is an open question, deliberately not answered here — nothing in the current
--     data requires it.
--   * leased_land_sites = land with NO known UPP assignment at all (the genuinely
--     ambiguous case — e.g. Ganado Rojo, which the client said could belong to "any of
--     Alejandro's 3 UPPs"). That ambiguity is NOT what a lot solves. A lot always has a
--     known, single production_unit_id. El Triunfo is being migrated OUT of
--     leased_land_sites and INTO a lot precisely because its UPP (54) is now confirmed.
--     leased_land_sites is NOT deprecated by this migration — it stays the right tool
--     for the still-ambiguous case.
--
-- DESIGN: general-purpose, not hardcoded to UPP 54. Any production_unit_id may have one
-- or more lots. tenure_type covers both owned and rented parcels (unlike
-- leased_land_sites.tenure_type, which only ever meant "not owned").
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. production_unit_lots
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.production_unit_lots (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid NOT NULL,
    lot_name            character varying(100) NOT NULL,
    tenure_type         character varying(20) NOT NULL,
    lessor_name         character varying(255),
    location_notes      text,
    is_active           boolean NOT NULL DEFAULT true,
    notes               text,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT production_unit_lots_tenure_check
        CHECK (tenure_type IN ('PROPIO', 'RENTADA', 'COMODATO', 'OTRA')),
    CONSTRAINT production_unit_lots_lessor_only_if_rented_check
        CHECK (tenure_type = 'RENTADA' OR lessor_name IS NULL),
    CONSTRAINT fk_lot_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_lot_production_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_lot_name_per_unit
    ON public.production_unit_lots (production_unit_id, upper(lot_name))
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_lot_company ON public.production_unit_lots (id_company);

COMMENT ON TABLE public.production_unit_lots IS
    'Physically distinct land parcels (owned or rented) grouped under one registered production_unit. Not to be confused with production_unit_paddocks (a grazing subdivision inside one parcel) or leased_land_sites (land with no confirmed UPP at all).';

-- ---------------------------------------------------------------------------
-- 2. cattle_livestock.lot_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_livestock
    ADD COLUMN IF NOT EXISTS lot_id uuid;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_lot;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_lot
    FOREIGN KEY (lot_id) REFERENCES public.production_unit_lots(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_livestock_lot ON public.cattle_livestock (lot_id);

COMMENT ON COLUMN public.cattle_livestock.lot_id IS
    'Physical parcel within the animal''s production_unit. Nullable: not every animal has been assigned a lot yet.';

-- Fail-closed guard: a lot belongs to exactly one production unit, so it cannot be
-- assigned to an animal standing in a different one. Same pattern as
-- fn_guard_livestock_paddock (migration 030) and fn_guard_livestock_leased_site
-- (migration 031).
CREATE OR REPLACE FUNCTION public.fn_guard_livestock_lot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_lot_unit uuid;
BEGIN
    IF NEW.lot_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT production_unit_id INTO v_lot_unit
      FROM public.production_unit_lots
     WHERE id = NEW.lot_id;

    IF v_lot_unit IS NULL THEN
        RAISE EXCEPTION 'lot_id % does not exist', NEW.lot_id USING ERRCODE = 'P0002';
    END IF;

    IF NEW.production_unit_id IS NULL OR v_lot_unit <> NEW.production_unit_id THEN
        RAISE EXCEPTION 'Lot % belongs to a different production unit than the animal (%)',
            NEW.lot_id, NEW.production_unit_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_livestock_lot ON public.cattle_livestock;
CREATE TRIGGER trg_guard_livestock_lot
    BEFORE INSERT OR UPDATE OF lot_id, production_unit_id
    ON public.cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION public.fn_guard_livestock_lot();

COMMIT;
