-- Migration 030: Paddocks (potreros) and birth events.
--
-- SOURCE: field notebooks supplied 2026-07-28/29 (2023-2026) and PARTOS_2020_LB.xlsx
-- (417 births). Both record the same shape by hand: "parió <dam tag> - <dam fire number>
-- - <calf sex> <brand> <consecutive>", dated, sometimes with a potrero and a rancho/anexo
-- label. This migration gives that shape a table instead of a notebook.
--
-- DESIGN DECISIONS
--   * paddocks belong to a production_unit, not to a tenant directly: "potrero 2" only
--     means something inside a specific UPP.
--   * birth_events references the calf via calf_id (nullable) because THE CALF IS BORN
--     WITHOUT A TAG. The notebooks show ear-tagging as a separate, later event — sometimes
--     weeks afterward ("Aretes toretes: 0647, 0594" recorded days after the births). The
--     calf row in cattle_livestock may not exist yet when the birth is logged.
--   * dam identification is captured as free text (dam_ear_tag, dam_fire_number), NOT as a
--     FK to cattle_livestock, because the notebooks record dams that have no tag at all
--     ("S/A"), and because a fire number can legitimately repeat by data-entry error — the
--     client confirmed this ("el número quemado no debe repetirse pero se podría dar el
--     caso por error"). Forcing a FK here would either silently pick the wrong dam on a
--     duplicate or block capture of the exact scenario the client described.
--   * dam_id (nullable FK) is populated separately, after a human resolves which exact row
--     the free-text dam reference points to. See fn_flag_duplicate_fire_numbers below for
--     the alert the client asked for instead of a hard UNIQUE constraint.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Paddocks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.production_unit_paddocks (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid NOT NULL,
    paddock_label       character varying(50) NOT NULL,
    area_ha             numeric(10,2),
    notes               text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT fk_paddock_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_paddock_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_paddock_label_per_unit
    ON public.production_unit_paddocks (production_unit_id, upper(paddock_label))
    WHERE is_active = true;

COMMENT ON TABLE public.production_unit_paddocks IS
    'Potreros. A label like "2" is only meaningful inside its production unit: two different UPP each have their own "potrero 2".';

-- Track the animal's current paddock without a full occupancy history yet: that is a
-- larger feature (paddock rotation / grazing management) out of scope for this migration.
ALTER TABLE public.cattle_livestock
    ADD COLUMN IF NOT EXISTS paddock_id uuid;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_paddock;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_paddock
    FOREIGN KEY (paddock_id) REFERENCES public.production_unit_paddocks(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_livestock_paddock ON public.cattle_livestock (paddock_id);

-- Same fail-closed guard used for production_unit_id in migration 016: a paddock belongs
-- to one production unit, so it cannot be assigned to an animal standing in a different one.
CREATE OR REPLACE FUNCTION public.fn_guard_livestock_paddock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_paddock_unit uuid;
BEGIN
    IF NEW.paddock_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT production_unit_id INTO v_paddock_unit
      FROM public.production_unit_paddocks
     WHERE id = NEW.paddock_id;

    IF v_paddock_unit IS NULL THEN
        RAISE EXCEPTION 'paddock_id % does not exist', NEW.paddock_id USING ERRCODE = 'P0002';
    END IF;

    IF NEW.production_unit_id IS NULL OR v_paddock_unit <> NEW.production_unit_id THEN
        RAISE EXCEPTION 'Paddock % belongs to a different production unit than the animal (%)',
            NEW.paddock_id, NEW.production_unit_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_livestock_paddock ON public.cattle_livestock;
CREATE TRIGGER trg_guard_livestock_paddock
    BEFORE INSERT OR UPDATE OF paddock_id, production_unit_id
    ON public.cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION public.fn_guard_livestock_paddock();

-- ---------------------------------------------------------------------------
-- 2. Birth events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.birth_events (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid,
    paddock_id          uuid,

    -- Dam, captured as free text as printed in the source (notebook or spreadsheet).
    -- See header note: intentionally NOT a hard FK at capture time.
    dam_ear_tag         character varying(100),
    dam_fire_number     character varying(50),
    dam_id              uuid,

    -- Calf: born untagged. calf_id is filled in later, by the ear-tagging event.
    calf_sex            character varying(10) NOT NULL,
    calf_brand_id       uuid,
    calf_id             uuid,

    birth_date          date NOT NULL,
    source              character varying(20) NOT NULL DEFAULT 'FIELD_NOTEBOOK',
    notes               text,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT birth_events_sex_check
        CHECK (calf_sex IN ('MACHO', 'HEMBRA')),
    CONSTRAINT birth_events_source_check
        CHECK (source IN ('FIELD_NOTEBOOK', 'SPREADSHEET_IMPORT', 'MANUAL', 'MOBILE_APP')),
    CONSTRAINT birth_events_dam_reference_check
        CHECK (dam_id IS NOT NULL OR dam_ear_tag IS NOT NULL OR dam_fire_number IS NOT NULL),
    CONSTRAINT fk_birth_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_birth_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE SET NULL,
    CONSTRAINT fk_birth_paddock
        FOREIGN KEY (paddock_id) REFERENCES public.production_unit_paddocks(id) ON DELETE SET NULL,
    CONSTRAINT fk_birth_dam
        FOREIGN KEY (dam_id) REFERENCES public.cattle_livestock(id) ON DELETE SET NULL,
    CONSTRAINT fk_birth_brand
        FOREIGN KEY (calf_brand_id) REFERENCES public.brand_registrations(id) ON DELETE SET NULL,
    CONSTRAINT fk_birth_calf
        FOREIGN KEY (calf_id) REFERENCES public.cattle_livestock(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_birth_events_company ON public.birth_events (id_company);
CREATE INDEX IF NOT EXISTS idx_birth_events_dam ON public.birth_events (dam_id);
CREATE INDEX IF NOT EXISTS idx_birth_events_dam_fire ON public.birth_events (dam_fire_number);
CREATE INDEX IF NOT EXISTS idx_birth_events_calf ON public.birth_events (calf_id);
CREATE INDEX IF NOT EXISTS idx_birth_events_date ON public.birth_events (birth_date);
-- A calf can only be born once: once tagged and linked, the same calf_id cannot appear twice.
CREATE UNIQUE INDEX IF NOT EXISTS uq_birth_events_calf
    ON public.birth_events (calf_id) WHERE calf_id IS NOT NULL;

COMMENT ON TABLE public.birth_events IS
    'Digitized birth log. Mirrors the field notebook shape: dam identified by tag/fire number (which may be duplicated by error, or absent), calf recorded by sex only until it is later tagged and linked via calf_id. calf_brand_id defaults to the dam''s brand via fn_apply_birth_brand_inheritance below, but may be overridden.';
COMMENT ON COLUMN public.birth_events.dam_id IS
    'Resolved link to the dam''s row, filled in once a human disambiguates dam_ear_tag / dam_fire_number against the herd. NULL is normal for freshly captured or historical records.';

-- ---------------------------------------------------------------------------
-- 3. Duplicate fire-number alert (not a constraint — the client explicitly wants
--    duplicates to be POSSIBLE and FLAGGED, never silently rejected)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_duplicate_fire_numbers AS
 SELECT tenant_id AS id_company, numero_fuego, count(*) AS cuantos,
        array_agg(id) AS livestock_ids,
        array_agg(rfid_siniiga) AS rfids
   FROM public.cattle_livestock
  WHERE current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD')
    AND numero_fuego IS NOT NULL
    AND btrim(numero_fuego) <> ''
  GROUP BY tenant_id, numero_fuego
 HAVING count(*) > 1;

COMMENT ON VIEW public.vw_duplicate_fire_numbers IS
    'Fire numbers repeated within the same tenant. Per the client ("el número quemado no debe repetirse pero se podría dar el caso por error"), this is a reviewable alert, not a rejected write.';

-- ---------------------------------------------------------------------------
-- 4. Brand inheritance applied to a birth event
-- ---------------------------------------------------------------------------
-- Complements fn_inherit_brand_from_mother (migration 028), which fires on
-- cattle_livestock when mother_id is already known. This one resolves the brand from a
-- birth_events row when only the free-text dam reference is available, so capture from a
-- notebook does not require the dam to already be linked by dam_id.
CREATE OR REPLACE FUNCTION public.fn_apply_birth_brand_inheritance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.calf_brand_id IS NULL THEN
        IF NEW.dam_id IS NOT NULL THEN
            SELECT brand_id INTO NEW.calf_brand_id
              FROM public.cattle_livestock WHERE id = NEW.dam_id;
        ELSIF NEW.dam_fire_number IS NOT NULL THEN
            SELECT brand_id INTO NEW.calf_brand_id
              FROM public.cattle_livestock
             WHERE tenant_id = NEW.id_company
               AND numero_fuego = NEW.dam_fire_number
               AND current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD')
             LIMIT 1;  -- ambiguous on a duplicate fire number; resolved manually later
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_birth_brand_inheritance ON public.birth_events;
CREATE TRIGGER trg_apply_birth_brand_inheritance
    BEFORE INSERT OR UPDATE OF dam_id, dam_fire_number, calf_brand_id
    ON public.birth_events
    FOR EACH ROW EXECUTE FUNCTION public.fn_apply_birth_brand_inheritance();

-- ---------------------------------------------------------------------------
-- 5. Herd fertility view (server-computed, no client math)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_birth_events_summary AS
 SELECT be.id_company,
        c.company_name,
        pu.upp_code,
        pu.ranch_name,
        pp.paddock_label,
        be.birth_date,
        date_trunc('month', be.birth_date)::date AS birth_month,
        be.dam_ear_tag,
        be.dam_fire_number,
        be.dam_id,
        be.calf_sex,
        b.brand_code AS calf_brand_code,
        be.calf_id,
        (be.calf_id IS NOT NULL) AS calf_tagged,
        be.source,
        be.created_at
   FROM public.birth_events be
   LEFT JOIN public.companys c ON c.id_company = be.id_company
   LEFT JOIN public.production_units pu ON pu.id = be.production_unit_id
   LEFT JOIN public.production_unit_paddocks pp ON pp.id = be.paddock_id
   LEFT JOIN public.brand_registrations b ON b.id = be.calf_brand_id;

COMMENT ON VIEW public.vw_birth_events_summary IS
    'Read model for the birth log. calf_tagged distinguishes calves already linked to a cattle_livestock row from those still identified only by the birth record, mirroring the real gap between birth and ear-tagging seen in the field notebooks.';

COMMIT;
