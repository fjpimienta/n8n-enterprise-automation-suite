-- Migration 031: Leased land sites (predios arrendados sin UPP propia).
--
-- WHY: field notebooks confirm real cattle on rented land with no SENASICA registration
-- of their own (e.g. "Rancho El Triunfo", arrendador Eladio Alejandro Navarro Ble;
-- earlier notebooks also showed rented plots under "Ing. Alejandro Aguilar Reséndez").
-- production_units cannot represent this: it requires a valid upp_code (regex-checked)
-- because it IS the official SENASICA registry entity, and blending unregistered land
-- into it would let compliance_certificates / census snapshots spuriously attach to a
-- site that has no constancia.
--
-- DESIGN: a separate, lightweight table. production_unit_id is nullable and exists only
-- as a promotion path — once the client obtains a UPP code for a leased site, link it
-- here instead of migrating every cattle_livestock row to a new location.
--
-- cattle_livestock.leased_site_id is mutually exclusive with production_unit_id (an
-- animal stands on one or the other, never both), enforced by CHECK plus the same
-- fail-closed cross-tenant guard pattern already used for production_unit_id/paddock_id.
BEGIN;

CREATE TABLE IF NOT EXISTS public.leased_land_sites (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    site_name           character varying(255) NOT NULL,
    lessor_name         character varying(255),
    location_notes      text,
    tenure_type         character varying(30) NOT NULL DEFAULT 'RENTADA',

    -- Promotion path: filled in once this site gets its own SENASICA constancia.
    production_unit_id  uuid,

    is_active           boolean NOT NULL DEFAULT true,
    notes               text,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT leased_land_sites_tenure_check
        CHECK (tenure_type IN ('RENTADA', 'COMODATO', 'OTRA')),
    CONSTRAINT fk_leased_site_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_leased_site_promoted_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_leased_site_name_per_company
    ON public.leased_land_sites (id_company, upper(site_name))
    WHERE is_active = true;

COMMENT ON TABLE public.leased_land_sites IS
    'Rented/borrowed land holding registered cattle but with no SENASICA UPP of its own yet. production_unit_id is the promotion path once a constancia is obtained — animals stay linked to this row rather than being migrated.';

-- ---------------------------------------------------------------------------
-- cattle_livestock.leased_site_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_livestock
    ADD COLUMN IF NOT EXISTS leased_site_id uuid;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_leased_site;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_leased_site
    FOREIGN KEY (leased_site_id) REFERENCES public.leased_land_sites(id) ON DELETE SET NULL;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS cattle_livestock_single_location_check;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT cattle_livestock_single_location_check
    CHECK (production_unit_id IS NULL OR leased_site_id IS NULL);

CREATE INDEX IF NOT EXISTS idx_livestock_leased_site ON public.cattle_livestock (leased_site_id);

COMMENT ON COLUMN public.cattle_livestock.leased_site_id IS
    'Leased land the animal stands on, when it is not in a registered production unit. Mutually exclusive with production_unit_id.';

-- Same fail-closed pattern as fn_guard_livestock_production_unit (migration 016).
CREATE OR REPLACE FUNCTION public.fn_guard_livestock_leased_site()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_site_company integer;
BEGIN
    IF NEW.leased_site_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_company INTO v_site_company
      FROM public.leased_land_sites
     WHERE id = NEW.leased_site_id;

    IF v_site_company IS NULL THEN
        RAISE EXCEPTION 'leased_site_id % does not exist', NEW.leased_site_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_site_company <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-tenant assignment rejected: leased site belongs to company %, animal to company %',
            v_site_company, NEW.tenant_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_livestock_leased_site ON public.cattle_livestock;
CREATE TRIGGER trg_guard_livestock_leased_site
    BEFORE INSERT OR UPDATE OF leased_site_id, tenant_id
    ON public.cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION public.fn_guard_livestock_leased_site();

-- ---------------------------------------------------------------------------
-- Seed: Rancho El Triunfo
-- ASSUMPTION (flagged, not confirmed by client): attached to id_company 6 (UPP 54),
-- because Pedro Aguilar Reséndez — the notebook's declared owner — is titular there and
-- no separate tenant exists for him elsewhere. Correct with a plain UPDATE if wrong.
-- ---------------------------------------------------------------------------
INSERT INTO public.leased_land_sites (id_company, site_name, lessor_name, tenure_type, notes)
SELECT 6, 'Rancho El Triunfo', 'Eladio Alejandro Navarro Ble', 'RENTADA',
       'Ganado bovino raza Bill Master, propietario Pedro Aguilar Reséndez. '
       || 'ASUNCIÓN: tenant asignado por ausencia de uno propio para Pedro fuera de UPP 54; '
       || 'confirmar con el cliente. UPP pendiente de asignar.'
 WHERE NOT EXISTS (
        SELECT 1 FROM public.leased_land_sites
         WHERE id_company = 6 AND upper(site_name) = 'RANCHO EL TRIUNFO');

COMMIT;
