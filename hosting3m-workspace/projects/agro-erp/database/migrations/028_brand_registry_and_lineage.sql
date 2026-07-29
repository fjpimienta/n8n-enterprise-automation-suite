-- Migration 028: Brand registry (fierro marcador), ownership and maternal lineage.
--
-- WHY THIS EXISTS
--   Two people run cattle across the same set of predios. The client stated it plainly:
--   "Manejamos dos fierros. Uno es fierro del rancho ... y el otro que es aR es mío", and
--   "lo ideal es que sean reporte por fierro". So the brand is not a label: it is who owns
--   the animal, and it is the required dimension of every financial report.
--
--   The brand is also a registered title. Pedro's credential (SEDAFOP Tabasco) carries a
--   state registry number, a municipal registry number, the owner's CURP and the drawing
--   of the mark. It is the document a state transit guide is issued against under the Ley
--   de Desarrollo Pecuario de Tabasco.
--
-- KEY CONSEQUENCE FOR THE DATA MODEL
--   Brand and production unit are INDEPENDENT dimensions. An 'aR' animal may stand in
--   Pedro's unit and an 'R' animal in Alejandro's. Until now the system assumed the tenant
--   implied ownership; it does not. The tenant is WHERE the animal is, the brand is WHOSE
--   it is.
--
-- SCOPE DECISION — brands are a GLOBAL catalog, not tenant-scoped.
--   A brand is a publicly registered mark, physically burned onto animals that cross
--   predios: it is not confidential tenant data, and replicating it per tenant would make
--   the by-brand consolidated report the client asked for impossible without a cross-tenant
--   query. Isolation is still enforced where it matters — on cattle_livestock.
--   Same treatment as cattle_breed_catalog. Note this one ships with is_global = true,
--   unlike cattle_lifestage_catalog which is mislabelled (see DT-10).
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Brand registry
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.brand_registrations (
    id                    uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,

    brand_code            character varying(10) NOT NULL,
    brand_description     character varying(255),

    owner_name            character varying(255) NOT NULL,
    owner_curp_enc        bytea,
    owner_curp_hash       text,

    state_registry        character varying(50),
    municipal_registry    character varying(100),
    issuing_authority     character varying(255),
    state_name            character varying(100),
    municipality_name     character varying(255),

    registration_year     integer,
    issued_at             date,
    expires_at            date,

    is_active             boolean NOT NULL DEFAULT true,
    notes                 text,
    created_at            timestamp without time zone DEFAULT now(),

    CONSTRAINT brand_registrations_dates_check
        CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at > issued_at),
    CONSTRAINT brand_registrations_year_check
        CHECK (registration_year IS NULL OR registration_year BETWEEN 1900 AND 2100)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_brand_registrations_active_code
    ON public.brand_registrations (upper(brand_code))
    WHERE is_active = true;

COMMENT ON TABLE public.brand_registrations IS
    'Registered branding irons (fierro marcador). GLOBAL catalog: a brand is a public state-registered mark that crosses predios, and the client requires consolidated financial reporting by brand.';
COMMENT ON COLUMN public.brand_registrations.brand_code IS
    'Short label as written in the field notebooks: R, aR. Case-insensitive unique among active brands.';

-- Pedro's brand, from the SEDAFOP Tabasco credential supplied 2026-07-28.
INSERT INTO public.brand_registrations
    (brand_code, brand_description, owner_name, state_registry, municipal_registry,
     issuing_authority, state_name, municipality_name, registration_year, issued_at, notes)
SELECT 'R',
       'Fierro del rancho, titular Pedro Aguilar Reséndez',
       'PEDRO AGUILAR RESENDEZ',
       'P01-27-009-01462',
       '009 L01-H155 REVERSO 2019',
       'SEDAFOP - Padrón Estatal de Productores Agropecuarios, Forestales y Pesqueros (Tabasco)',
       'Tabasco',
       'Jalapa',
       2019,
       NULL,
       'Patente 155, coincide con fire_brand_patent de la UPP 27-009-4146-002. La credencial no imprime fecha de expedición legible; queda NULL en lugar de inventarse.'
 WHERE NOT EXISTS (
        SELECT 1 FROM public.brand_registrations b WHERE upper(b.brand_code) = 'R');

-- The owner's CURP is personal data: it goes through the same encrypt-and-hash path as
-- livestock_producers, so no caller ever handles the key.
CREATE OR REPLACE FUNCTION public.sp_upsert_brand_owner_pii(
    p_brand_id uuid,
    p_curp text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.brand_registrations
       SET owner_curp_enc  = COALESCE(public.fn_encrypt_pii(p_curp), owner_curp_enc),
           owner_curp_hash = COALESCE(public.fn_hash_pii(p_curp),    owner_curp_hash)
     WHERE id = p_brand_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Brand % not found', p_brand_id USING ERRCODE = 'P0002';
    END IF;

    RETURN jsonb_build_object('success', true, 'brand_id', p_brand_id);
END;
$$;

SELECT public.sp_upsert_brand_owner_pii(b.id, 'AURP630925HTCGSD05')
  FROM public.brand_registrations b
 WHERE upper(b.brand_code) = 'R' AND b.owner_curp_hash IS NULL;

-- Alejandro's brand. Registered separately (client confirmed he holds his own title),
-- but the credential has not been supplied: the registry numbers stay NULL rather than
-- being guessed, and the row is marked so it is visibly incomplete.
INSERT INTO public.brand_registrations
    (brand_code, brand_description, owner_name, issuing_authority, state_name, notes)
SELECT 'aR',
       'Fierro propio de Alejandro Aguilar Reséndez (monograma a + R)',
       'ALEJANDRO AGUILAR RESENDEZ',
       NULL, NULL,
       'INCOMPLETO: el cliente confirmó que tiene título propio, pero la credencial no ha sido entregada. Faltan registro estatal, municipal, autoridad emisora y fechas.'
 WHERE NOT EXISTS (
        SELECT 1 FROM public.brand_registrations b WHERE upper(b.brand_code) = UPPER('aR'));

-- ---------------------------------------------------------------------------
-- 2. Ownership and lineage on the animal
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_livestock
    ADD COLUMN IF NOT EXISTS brand_id uuid,
    ADD COLUMN IF NOT EXISTS mother_id uuid;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_brand;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_brand
    FOREIGN KEY (brand_id) REFERENCES public.brand_registrations(id) ON DELETE SET NULL;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_mother;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_mother
    FOREIGN KEY (mother_id) REFERENCES public.cattle_livestock(id) ON DELETE SET NULL;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS cattle_livestock_not_own_mother_check;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT cattle_livestock_not_own_mother_check
    CHECK (mother_id IS NULL OR mother_id <> id);

CREATE INDEX IF NOT EXISTS idx_livestock_brand ON public.cattle_livestock (brand_id);
CREATE INDEX IF NOT EXISTS idx_livestock_mother ON public.cattle_livestock (mother_id);

COMMENT ON COLUMN public.cattle_livestock.brand_id IS
    'Owning brand. Independent of tenant_id: an animal may stand in one holder''s unit while belonging to the other. Required dimension for financial reporting.';
COMMENT ON COLUMN public.cattle_livestock.mother_id IS
    'Dam. The field notebooks record every birth as "parió <dam tag> - <dam fire number> - <calf sex> <brand>", so lineage is already tracked on paper.';

-- ---------------------------------------------------------------------------
-- 3. Brand inheritance
-- ---------------------------------------------------------------------------
-- Client rule, verbatim: "No se reparten las crías. A cada cría se le pone el mismo
-- fierro de la madre." Applied only when brand_id was not supplied, so an explicit value
-- always wins over the inheritance.
CREATE OR REPLACE FUNCTION public.fn_inherit_brand_from_mother()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.brand_id IS NULL AND NEW.mother_id IS NOT NULL THEN
        SELECT brand_id INTO NEW.brand_id
          FROM public.cattle_livestock
         WHERE id = NEW.mother_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inherit_brand_from_mother ON public.cattle_livestock;
CREATE TRIGGER trg_inherit_brand_from_mother
    BEFORE INSERT OR UPDATE OF mother_id, brand_id
    ON public.cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION public.fn_inherit_brand_from_mother();

COMMENT ON FUNCTION public.fn_inherit_brand_from_mother() IS
    'A calf carries its dam''s brand. Never overwrites an explicitly supplied brand_id.';

-- ---------------------------------------------------------------------------
-- 4. Ownership reporting view
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_livestock_by_brand AS
 SELECT b.id                       AS brand_id,
        b.brand_code,
        b.owner_name,
        cl.tenant_id               AS id_company,
        c.company_name,
        pu.upp_code,
        pu.ranch_name,
        cl.category,
        count(*)                   AS head_count,
        sum(cl.current_weight_kg)  AS total_weight_kg,
        min(b.created_at)          AS created_at
   FROM public.cattle_livestock cl
   JOIN public.brand_registrations b ON b.id = cl.brand_id
   LEFT JOIN public.companys c ON c.id_company = cl.tenant_id
   LEFT JOIN public.production_units pu ON pu.id = cl.production_unit_id
  WHERE cl.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD')
  GROUP BY b.id, b.brand_code, b.owner_name, cl.tenant_id, c.company_name,
           pu.upp_code, pu.ranch_name, cl.category;

COMMENT ON VIEW public.vw_livestock_by_brand IS
    'Head and biomass by brand, tenant, unit and category. Animals with brand_id NULL are excluded on purpose: an unassigned brand is missing data, not a fourth owner.';

COMMIT;
