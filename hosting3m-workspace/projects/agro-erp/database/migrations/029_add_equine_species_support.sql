-- Migration 029: Adds EQUIDO as a supported species.
--
-- CONFIRMED GAP (2026-07-29): the client's field notebooks for UPP 54 register 8 horses
-- with full detail (yeguas crianderas, potro, caballos castrados, potranca), but neither
-- cattle_livestock.species, cattle_breed_catalog.especie, nor cattle_lifestage_catalog.especie
-- admit EQUIDO. Only BOVINO, BUFALO, BORREGO exist today. This was verified directly
-- against production, not assumed.
--
-- SCOPE: this migration only opens the door (CHECK constraints + category values). It does
-- NOT seed breed standards or lifestage transitions for equines — those need the client's
-- input on target weights, gestation, and category thresholds, same as was done for bovine
-- in migrations 006/008. Seeding equine data without that input would repeat the mistake
-- of inventing zootechnical numbers.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. cattle_livestock.species
-- ---------------------------------------------------------------------------
-- species has no CHECK constraint of its own (free VARCHAR with DEFAULT 'BOVINO' per
-- DATABASE_SCHEMA.md), so no ALTER is needed there. Verified: only BOVINO/BUFALO appear
-- in production today, but the column accepts any value already.

-- ---------------------------------------------------------------------------
-- 2. cattle_livestock.category — add equine categories
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS cattle_livestock_category_check;

ALTER TABLE public.cattle_livestock
ADD CONSTRAINT cattle_livestock_category_check
CHECK (
    category IN (
        'VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO',
        'BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA',
        -- Equine, from the UPP 54 field notebooks (2026-07-29):
        'CABALLO','YEGUA','POTRO','POTRANCA','CABALLO_CASTRADO'
    )
);

COMMENT ON CONSTRAINT cattle_livestock_category_check ON public.cattle_livestock IS
    'Equine categories added in migration 029. YEGUA_CRIANDERA is deliberately not a separate category: breeding status belongs in current_status / reproductive tracking, not in the animal type.';

-- ---------------------------------------------------------------------------
-- 3. cattle_breed_catalog.especie — global standards catalog
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_breed_catalog
    DROP CONSTRAINT IF EXISTS cattle_breed_catalog_especie_check;

ALTER TABLE public.cattle_breed_catalog
ADD CONSTRAINT cattle_breed_catalog_especie_check
CHECK (especie IN ('BOVINO', 'BUFALO', 'BORREGO', 'EQUIDO'));

-- ---------------------------------------------------------------------------
-- 4. cattle_lifestage_catalog.especie — global transitions catalog
-- ---------------------------------------------------------------------------
ALTER TABLE public.cattle_lifestage_catalog
    DROP CONSTRAINT IF EXISTS cattle_lifestage_catalog_especie_check;

ALTER TABLE public.cattle_lifestage_catalog
ADD CONSTRAINT cattle_lifestage_catalog_especie_check
CHECK (especie IN ('BOVINO', 'BUFALO', 'BORREGO', 'EQUIDO'));

-- The categoria_origen/categoria_destino CHECKs on this table also need the equine values
-- to ever host an equine transition, even though no such row is seeded yet.
ALTER TABLE public.cattle_lifestage_catalog
    DROP CONSTRAINT IF EXISTS cattle_lifestage_catalog_categoria_origen_check;
ALTER TABLE public.cattle_lifestage_catalog
ADD CONSTRAINT cattle_lifestage_catalog_categoria_origen_check
CHECK (categoria_origen IN (
    'VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO',
    'BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA',
    'CABALLO','YEGUA','POTRO','POTRANCA','CABALLO_CASTRADO'
));

ALTER TABLE public.cattle_lifestage_catalog
    DROP CONSTRAINT IF EXISTS cattle_lifestage_catalog_categoria_destino_check;
ALTER TABLE public.cattle_lifestage_catalog
ADD CONSTRAINT cattle_lifestage_catalog_categoria_destino_check
CHECK (categoria_destino IN (
    'VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO',
    'BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA',
    'CABALLO','YEGUA','POTRO','POTRANCA','CABALLO_CASTRADO'
));

COMMIT;
