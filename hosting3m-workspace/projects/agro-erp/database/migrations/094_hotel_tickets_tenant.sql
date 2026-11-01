-- 094_hotel_tickets_tenant.sql
-- Adds the tenant column to hotel_maintenance_tickets (the only hotel table without one that is tenant data).
-- id_company integer NOT NULL DEFAULT 1 (1 = "Hosting3m", the company that owns all hotel data today): every existing row and every insert from the OLD v5 workflow keeps working.
-- The DEFAULT is removed later by 095, after the patched v5 workflow (which always sends the token's company) is live.
-- Adds only: 1 column, 1 FK to companys, 1 index. No data is rewritten (PostgreSQL 11+ stores the default in the catalog). No DROP/DELETE/TRUNCATE.
-- Rollback: 094_rollback.sql. State: 094_state_check.sql. Usage:
--   psql -v ON_ERROR_STOP=1 -f 094_hotel_tickets_tenant.sql            (dry run: everything is rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 094_hotel_tickets_tenant.sql  (commit)
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
    IF to_regclass('public.hotel_maintenance_tickets') IS NULL THEN
        RAISE EXCEPTION 'ABORT: hotel_maintenance_tickets not found (wrong database?).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.companys WHERE id_company = 1) THEN
        RAISE EXCEPTION 'ABORT: company 1 does not exist; the default would violate the FK.';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'hotel_maintenance_tickets' AND column_name = 'id_company') THEN
        RAISE EXCEPTION 'ABORT: id_company already exists on hotel_maintenance_tickets (094 already applied?).';
    END IF;
END $$;

SELECT count(*) AS tickets_before FROM public.hotel_maintenance_tickets;

ALTER TABLE public.hotel_maintenance_tickets
    ADD COLUMN id_company integer NOT NULL DEFAULT 1;
ALTER TABLE public.hotel_maintenance_tickets
    ADD CONSTRAINT hotel_maintenance_tickets_id_company_fkey FOREIGN KEY (id_company) REFERENCES public.companys(id_company);
CREATE INDEX IF NOT EXISTS idx_hotel_maintenance_tickets_company ON public.hotel_maintenance_tickets (id_company);

SELECT id_company, count(*) AS tickets_after FROM public.hotel_maintenance_tickets GROUP BY id_company ORDER BY 1;

-- @@FINALIZE
\if :apply
COMMIT;
\echo '094 APPLIED (committed)'
\else
ROLLBACK;
\echo '094 DRY RUN: rolled back, nothing changed. Re-run with -v apply=true to commit.'
\endif
