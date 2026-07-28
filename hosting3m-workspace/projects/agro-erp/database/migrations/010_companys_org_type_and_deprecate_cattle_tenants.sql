-- Migration 010: Promotes org_type from the dead-end cattle_tenants table into companys
-- (the real tenant axis) and formally deprecates cattle_tenants.
--
-- cattle_tenants holds a single row with a generic RFC (XAXX010101000) and is referenced
-- by ZERO foreign keys in the production dump. It is NOT dropped (production safety):
-- it is documented as deprecated and its Meta-CRUD model is downgraded to read-only so
-- no new writes can land there.
--
-- Also adds `metadata` to companys IF NOT EXISTS: the committed schema.sql does not have
-- this column but `\d companys` in production does. schema.sql is stale — this migration
-- is written to be safe under either state.
BEGIN;

-- 1. Tenant-level configuration bag (already present in production, absent in schema.sql)
ALTER TABLE public.companys
    ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb;

-- 2. Organization type, migrated from cattle_tenants.org_type
ALTER TABLE public.companys
    ADD COLUMN IF NOT EXISTS org_type character varying(50);

ALTER TABLE public.companys
    DROP CONSTRAINT IF EXISTS companys_org_type_check;

ALTER TABLE public.companys
    ADD CONSTRAINT companys_org_type_check
    CHECK (org_type IS NULL OR org_type IN ('GANADERO', 'UNION', 'GOBIERNO'));

COMMENT ON COLUMN public.companys.org_type IS
    'Organization type migrated from the deprecated cattle_tenants table. NULL for non-livestock verticals (hotel, ice rink, agriculture).';

-- 3. Backfill for the livestock tenants that already exist
UPDATE public.companys
   SET org_type = 'GANADERO'
 WHERE org_type IS NULL
   AND industry ILIKE '%Ganader%';

-- 4. Deprecation marker on the legacy table (no DROP, no data loss)
COMMENT ON TABLE public.cattle_tenants IS
    'DEPRECATED (migration 010). Superseded by companys.org_type. Retained read-only for historical reference; not referenced by any FK. Do not write new rows.';

-- 5. Downgrade the Meta-CRUD model (id 36) to read-only so the gateway cannot write to it
UPDATE public.crud_models
   SET allowed_ops           = '{SELECT,GETONE,GETALL}'::text[],
       allowed_roles_insert  = 'NONE',
       allowed_roles_update  = 'NONE',
       allowed_roles_delete  = 'NONE'
 WHERE model_name = 'cattle_tenants';

COMMIT;
