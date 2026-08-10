-- Migration 032: Ranch management / sanitary protocol.
--
-- SOURCE: Rancho El Triunfo notebook (2026), which records pasture type, water source,
-- supplements and four recurring sanitary periods (vaccination, deworming, vitamins,
-- tick/fly bath) as a block at the end of the herd inventory. This is reusable operational
-- knowledge per site, not a per-animal fact — modeled as its own entity rather than a note
-- buried in cattle_livestock.metadata.
--
-- SCOPE: applies to either a registered production_unit OR a leased_land_site — same
-- mutual-exclusion pattern as compliance_certificates (migration 013) and
-- cattle_livestock's own location columns (migration 031).
BEGIN;

CREATE TABLE IF NOT EXISTS public.ranch_management_protocols (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid,
    leased_site_id      uuid,

    pasture_type        character varying(100),
    water_source        character varying(100),
    supplements         text,
    supplements_frequency character varying(50),

    vaccination_period_days    integer,
    deworming_period_days      integer,
    vitamins_period_days       integer,
    tick_fly_bath_period_days  integer,

    effective_date      date NOT NULL DEFAULT CURRENT_DATE,
    source              character varying(30) NOT NULL DEFAULT 'FIELD_NOTEBOOK',
    notes               text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT ranch_protocol_single_location_check
        CHECK (num_nonnulls(production_unit_id, leased_site_id) = 1),
    CONSTRAINT ranch_protocol_periods_positive_check
        CHECK (
            (vaccination_period_days IS NULL OR vaccination_period_days > 0) AND
            (deworming_period_days   IS NULL OR deworming_period_days   > 0) AND
            (vitamins_period_days    IS NULL OR vitamins_period_days    > 0) AND
            (tick_fly_bath_period_days IS NULL OR tick_fly_bath_period_days > 0)
        ),
    CONSTRAINT fk_ranch_protocol_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_ranch_protocol_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE,
    CONSTRAINT fk_ranch_protocol_leased_site
        FOREIGN KEY (leased_site_id) REFERENCES public.leased_land_sites(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ranch_protocol_unit ON public.ranch_management_protocols (production_unit_id);
CREATE INDEX IF NOT EXISTS idx_ranch_protocol_site ON public.ranch_management_protocols (leased_site_id);

COMMENT ON TABLE public.ranch_management_protocols IS
    'Reusable operational protocol (pasture, water, supplements, sanitary periods) per production unit or leased site. Periods stored in days for consistent math (e.g. next-due-date calculations); the source notebook wrote them in months, converted at load time (1 mes = 30 días, documented per row in notes).';

-- ---------------------------------------------------------------------------
-- Seed: Rancho El Triunfo protocol, transcribed from the notebook verbatim where
-- possible. Month-based periods converted to days (1 mes ≈ 30 días) — flagged in notes
-- so nobody mistakes the stored number for something more precise than it is.
-- ---------------------------------------------------------------------------
INSERT INTO public.ranch_management_protocols
    (id_company, leased_site_id, pasture_type, water_source, supplements,
     supplements_frequency, vaccination_period_days, deworming_period_days,
     vitamins_period_days, tick_fly_bath_period_days, notes)
SELECT ls.id_company, ls.id,
       'Camalote',
       'Pozo profundo',
       'Sal mineral, melaza, coquillo',
       'Diaria',
       180,  -- "cada 06 meses" -> 6 * 30
       90,   -- "cada 03 meses" -> 3 * 30
       90,   -- "cada 03 meses" -> 3 * 30
       8,    -- "cada 08 días", already in days
       'Periodos convertidos de meses a días (1 mes = 30 días) desde la libreta original; '
       || 'no son un valor clínico exacto, son la unidad de captura del sistema. '
       || 'Transcrito de la libreta de Rancho El Triunfo, 2026.'
  FROM public.leased_land_sites ls
 WHERE ls.id_company = 6 AND upper(ls.site_name) = 'RANCHO EL TRIUNFO'
   AND NOT EXISTS (
        SELECT 1 FROM public.ranch_management_protocols rmp
         WHERE rmp.leased_site_id = ls.id);

COMMIT;
