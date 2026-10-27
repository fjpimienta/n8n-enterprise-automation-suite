-- 086_seed_tenant5_uterine_codes.sql
-- Seed of the confirmed uterine-code mapping of company 5 (UPP La Bendicion). SEPARATE from migration 086 on purpose:
-- it is DATA, it is applied only by the owner, and only after 086 itself is applied and verified.
--
--   UNE   -> ESTATICA     (Utero Normal Estatico)
--   UTCL1 -> CICLANDO     (cuerpo luteo temprano)
--   UTCL2 -> CICLANDO     (cuerpo luteo maduro)
--   UTCL3 -> CICLANDO     (cuerpo luteo tardio / en regresion)
--
-- NOT seeded (the veterinarians gave ambiguous answers; they stay UNMAPPED): RP, UTC2, NR, 'No apto', 'Matriz ocupada'.
-- Consequently 'UNE/NR' keeps a NULL condition until NR is confirmed.
--
-- Safe by construction: it only INSERTs the 4 rows; an existing row for the same (company, code) is NEVER overwritten
-- (ON CONFLICT DO NOTHING). It aborts when 086 is not applied, when the company does not exist / is not active, or when
-- the company is a palm company. It touches no other table.
--
-- Usage (dry run is the default; the e-mail is who confirms the mapping, recorded in confirmed_by):
--   psql -v ON_ERROR_STOP=1 -v confirmed_by='owner@example.com' -f 086_seed_tenant5_uterine_codes.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v confirmed_by='owner@example.com' -v apply=true -f 086_seed_tenant5_uterine_codes.sql   -> commit
-- Undo (only the 4 rows this file inserted; dry run by default; take a backup first, see 086_RUNBOOK.md):
--   psql -v ON_ERROR_STOP=1 -v undo=true [-v apply=true] -f 086_seed_tenant5_uterine_codes.sql
-- Palpations logged while the mapping existed keep the condition they were given (palpation_repro_details is a snapshot).

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?undo}
\else
\set undo false
\endif
\if :{?confirmed_by}
\else
\echo 'ABORT: pass -v confirmed_by=<e-mail of the person who confirms the mapping>'
\quit
\endif

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.repro_condition_codes') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 086 is not applied here (repro_condition_codes missing).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.companys WHERE id_company = 5 AND is_active IS TRUE) THEN
        RAISE EXCEPTION 'ABORT: company 5 does not exist or is not active here.';
    END IF;
    IF coalesce(public.fn_company_business_domain(5), '') = 'PALM' THEN
        RAISE EXCEPTION 'ABORT: company 5 is a palm company.';
    END IF;
END $$;

\echo === company 5 (must be the livestock company you expect)
SELECT id_company, company_name, is_active FROM public.companys WHERE id_company = 5;

\echo === BEFORE: mapping rows of company 5
SELECT code, repro_condition, source, confirmed_by, confirmed_at FROM public.repro_condition_codes WHERE id_company = 5 ORDER BY code;

\if :undo
    -- Exact keys AND the seed source: a row someone re-confirmed through sp_repro_condition_code_set is never touched.
    DELETE FROM public.repro_condition_codes
     WHERE id_company = 5 AND source = 'SEED_086_VET_CONFIRMED' AND code IN ('UNE', 'UTCL1', 'UTCL2', 'UTCL3');
\else
    INSERT INTO public.repro_condition_codes (id_company, code, repro_condition, source, confirmed_by, confirmed_at)
    SELECT 5, v.code, v.cond, 'SEED_086_VET_CONFIRMED', lower(btrim(:'confirmed_by')), now()
      FROM (VALUES ('UNE', 'ESTATICA'), ('UTCL1', 'CICLANDO'), ('UTCL2', 'CICLANDO'), ('UTCL3', 'CICLANDO')) AS v (code, cond)
    ON CONFLICT (id_company, code) DO NOTHING;
\endif

\echo === AFTER: mapping rows of company 5
SELECT code, repro_condition, source, confirmed_by, confirmed_at FROM public.repro_condition_codes WHERE id_company = 5 ORDER BY code;

\echo === rows of OTHER companies (must be unchanged by this file)
SELECT id_company, count(*) AS rows FROM public.repro_condition_codes WHERE id_company <> 5 GROUP BY id_company ORDER BY id_company;

\if :apply
COMMIT;
\echo '*** seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
