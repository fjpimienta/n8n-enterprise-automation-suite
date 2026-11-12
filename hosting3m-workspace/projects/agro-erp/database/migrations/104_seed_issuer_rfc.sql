-- 104_seed_issuer_rfc.sql: platform seed. Registers one issuer RFC for a TEST company (default: company 10).
-- NOT part of migration 104. Dry run by default; -v apply=true commits. The RFC is supplied ONLY at apply time through the psql
-- variable issuer_rfc; this file contains no RFC and the script never prints it (only a short fingerprint).
-- Refuses to run for a company that is not flagged is_test in company_flags, unless -v allow_non_test=yes is passed explicitly.
-- Usage: psql -X -v ON_ERROR_STOP=1 -v issuer_rfc="$RFC" [-v company=10] -f 104_seed_issuer_rfc.sql
--        ... -v apply=true ... to commit. Re-running with the same RFC is harmless (it only re-activates the row).
\set ON_ERROR_STOP on
\if :{?issuer_rfc}
\else
\echo 'usage: psql -v issuer_rfc=RFC [-v company=10] [-v allow_non_test=yes] [-v apply=true] -f 104_seed_issuer_rfc.sql'
\quit
\endif
\if :{?company}
\else
\set company 10
\endif
\if :{?allow_non_test}
\else
\set allow_non_test no
\endif
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SELECT set_config('app.platform_seed', 'on', true) AS platform_seed,
       set_config('t104.company', :'company', true) AS company,
       set_config('t104.allow', :'allow_non_test', true) AS allow_non_test;

DO $$
DECLARE
    v_co   integer := current_setting('t104.company')::integer;
    v_test boolean;
BEGIN
    IF to_regclass('public.company_issuer_rfcs') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 104 is not applied here.';
    END IF;
    IF public.fn_company_business_domain(v_co) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'ABORT: company % is not a palm company.', v_co;
    END IF;
    SELECT f.is_test INTO v_test FROM public.company_flags f WHERE f.id_company = v_co;
    IF v_test IS NOT TRUE AND current_setting('t104.allow') <> 'yes' THEN
        RAISE EXCEPTION 'ABORT: company % is not flagged is_test; pass -v allow_non_test=yes only for a real company.', v_co;
    END IF;
END $$;

INSERT INTO public.company_issuer_rfcs (id_company, rfc, created_by)
VALUES (:company::integer, upper(btrim(:'issuer_rfc')), current_user)
ON CONFLICT (id_company, rfc) DO UPDATE SET is_active = true;

-- Fingerprint only (never the RFC itself).
SELECT id_company, is_test, is_active, left(md5(rfc), 8) AS rfc_fingerprint
  FROM public.company_issuer_rfcs WHERE id_company = :company::integer ORDER BY created_at;

\if :apply
COMMIT;
\echo '*** issuer RFC seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: issuer RFC seed rolled back ***'
\endif
