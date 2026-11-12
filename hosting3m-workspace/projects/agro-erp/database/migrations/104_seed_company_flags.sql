-- 104_seed_company_flags.sql: platform seed. Marks company 10 (palm test company) as a test company in company_flags.
-- NOT part of migration 104. Dry run by default (ends in ROLLBACK); -v apply=true commits. Contains no personal or fiscal data.
-- Refuses to run unless company 10 exists and is a palm company. Re-running is harmless.
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 104_seed_company_flags.sql  |  ... -v apply=true -f 104_seed_company_flags.sql
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SELECT set_config('app.platform_seed', 'on', true) AS platform_seed;

DO $$
BEGIN
    IF to_regclass('public.company_flags') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 104 is not applied here.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.companys WHERE id_company = 10) THEN
        RAISE EXCEPTION 'ABORT: company 10 does not exist here.';
    END IF;
    IF public.fn_company_business_domain(10) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'ABORT: company 10 is not a palm company.';
    END IF;
END $$;

INSERT INTO public.company_flags (id_company, is_test) VALUES (10, true)
ON CONFLICT (id_company) DO UPDATE SET is_test = true;

SELECT id_company, is_test, created_by FROM public.company_flags WHERE id_company = 10;

\if :apply
COMMIT;
\echo '*** company_flags seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: company_flags seed rolled back ***'
\endif
