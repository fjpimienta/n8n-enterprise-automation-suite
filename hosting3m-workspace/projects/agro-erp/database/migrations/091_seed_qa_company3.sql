-- 091_seed_qa_company3.sql: QA only. Registers the generic test RFC XAXX010101000 for company 3 ("Rancho El Palomar") with qa_skip_sat = true,
-- so test invoices (modified, no valid stamp) can be registered there. Aborts if company 3 is not that company. Dry run by default.
-- psql -v ON_ERROR_STOP=1 -f 091_seed_qa_company3.sql | -v apply=true -f ...
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
DO $$
BEGIN
    IF to_regclass('public.company_tax_ids') IS NULL THEN RAISE EXCEPTION 'ABORT: 091 is not applied here.'; END IF;
    IF (SELECT company_name FROM public.companys WHERE id_company = 3) IS DISTINCT FROM 'Rancho El Palomar' THEN
        RAISE EXCEPTION 'ABORT: company 3 is not "Rancho El Palomar" here.';
    END IF;
    INSERT INTO public.company_tax_ids (id_company, rfc, label, qa_skip_sat, created_by_email)
    VALUES (3, 'XAXX010101000', 'QA test RFC (SAT check skipped)', true, 'qa seed')
    ON CONFLICT (id_company, rfc) DO NOTHING;
END $$;
SELECT id_company, rfc, label, is_active, qa_skip_sat FROM public.company_tax_ids WHERE id_company = 3;
\if :apply
COMMIT;
\echo '*** seed COMMITTED (company 3) ***'
\else
ROLLBACK;
\echo '*** DRY RUN: seed rolled back ***'
\endif
