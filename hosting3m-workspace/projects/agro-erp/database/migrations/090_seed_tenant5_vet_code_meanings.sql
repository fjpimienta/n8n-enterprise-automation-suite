-- 090_seed_tenant5_vet_code_meanings.sql
-- Meanings of three ranch codes for company 5 (UPP La Bendicion). SEPARATE from migration 090 and from the 086 seed on purpose:
-- it is DATA, it is applied only by the owner, and only after 090 itself is applied and verified.
--
--   NR       -> meaning NOT_EXAMINED   (No Revision: the animal was not examined; not a diagnosis)
--   RP       -> meaning POSTPARTUM     (Recien Parida)
--   NO APTO  -> meaning UNFIT          (unfit for breeding: reproductive tract too small or uterine cysts)
--
-- ⚠️ WHO CONFIRMED THIS: the ranch FOREMAN (capataz), NOT a veterinarian. The 086 seed (UNE, UTCL1, UTCL2, UTCL3) came from the
-- veterinarians' interpretation and keeps its own source ('SEED_086_VET_CONFIRMED') and its own confirmed_by; this file uses the source
-- 'SEED_090_FOREMAN_CONFIRMED' and the confirmed_by you pass, so the two origins stay distinguishable in repro_condition_codes.
-- Run it with:  -v confirmed_by='capataz (sin confirmacion veterinaria)'
--
-- NOT in this file (unchanged on purpose):
--   * UTC2 stays known-pending (NULL condition, NULL meaning): it is a general uterine tone, NOT ciclando.
--   * MATRIZ OCUPADA needs no row: since 090 it is a fixed PREÑADA phrase for every company. The pending row that the 086 seed created
--     stays as it is (harmless: the code looks at the phrase first, and the reserved word cannot be redefined).
--   * No condition is ever set: a code with a meaning has a NULL repro_condition (CHECK ck_cond_code_meaning_no_condition).
--
-- Safe by construction: it only sets `meaning` / source / confirmed_by / confirmed_at on rows that are STILL pending (condition NULL and
-- meaning NULL), or creates the row if the 086 seed was never applied. It ABORTS if one of the three codes already has a condition or a
-- different meaning (nothing is overwritten). It aborts when 090 is not applied, when the company does not exist / is not active, or when
-- the company is a palm company. It touches no other table and no other company.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -v confirmed_by='capataz (sin confirmacion veterinaria)' -f 090_seed_tenant5_vet_code_meanings.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v confirmed_by='capataz (sin confirmacion veterinaria)' -v apply=true -f 090_seed_tenant5_vet_code_meanings.sql   -> commit
-- Undo (only rows this file set and nobody changed since; they go back to the pending state of the 086 seed, nothing is deleted;
-- dry run by default; take a backup first, see 090_RUNBOOK.md):
--   psql -v ON_ERROR_STOP=1 -v confirmed_by=x -v undo=true [-v apply=true] -f 090_seed_tenant5_vet_code_meanings.sql
-- Palpations logged while the meanings existed keep what they were given (palpation_repro_details is a snapshot).

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
\echo 'ABORT: pass -v confirmed_by=<who confirmed the meanings, e.g. ''capataz (sin confirmacion veterinaria)''>'
\quit
\endif

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.repro_condition_codes') IS NULL
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes' AND column_name = 'meaning') THEN
        RAISE EXCEPTION 'ABORT: migration 090 is not applied here (repro_condition_codes.meaning missing).';
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
SELECT code, repro_condition, meaning, source, confirmed_by, confirmed_at FROM public.repro_condition_codes WHERE id_company = 5 ORDER BY code;

CREATE TEMP TABLE t_other_before ON COMMIT DROP AS
SELECT id_company, count(*) AS n, md5(string_agg(concat_ws('|', code, repro_condition, meaning, source, confirmed_by), '#' ORDER BY code)) AS fp
  FROM public.repro_condition_codes WHERE id_company <> 5 GROUP BY id_company;

\if :undo
    UPDATE public.repro_condition_codes
       SET meaning = NULL, source = 'pending veterinarian confirmation', confirmed_by = NULL, confirmed_at = NULL
     WHERE id_company = 5 AND source = 'SEED_090_FOREMAN_CONFIRMED' AND repro_condition IS NULL
       AND ((code = 'NR' AND meaning = 'NOT_EXAMINED') OR (code = 'RP' AND meaning = 'POSTPARTUM') OR (code = 'NO APTO' AND meaning = 'UNFIT'));
\else
    DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM public.repro_condition_codes
                    WHERE id_company = 5 AND code IN ('NR', 'RP', 'NO APTO')
                      AND (repro_condition IS NOT NULL
                           OR (meaning IS NOT NULL AND meaning IS DISTINCT FROM CASE code WHEN 'NR' THEN 'NOT_EXAMINED' WHEN 'RP' THEN 'POSTPARTUM' ELSE 'UNFIT' END))) THEN
            RAISE EXCEPTION 'ABORT: NR / RP / NO APTO already has a condition or a different meaning in company 5. Nothing is overwritten; review it by hand.';
        END IF;
    END $$;

    INSERT INTO public.repro_condition_codes AS cc (id_company, code, repro_condition, meaning, source, confirmed_by, confirmed_at)
    SELECT 5, v.code, NULL::text, v.meaning, 'SEED_090_FOREMAN_CONFIRMED', btrim(:'confirmed_by'), now()
      FROM (VALUES ('NR', 'NOT_EXAMINED'), ('RP', 'POSTPARTUM'), ('NO APTO', 'UNFIT')) AS v (code, meaning)
    ON CONFLICT (id_company, code) DO UPDATE
       SET meaning = excluded.meaning, source = excluded.source, confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at
     WHERE cc.id_company = 5 AND cc.repro_condition IS NULL AND cc.meaning IS NULL;
\endif

\echo === AFTER: mapping rows of company 5
SELECT code, repro_condition, meaning, source, confirmed_by, confirmed_at FROM public.repro_condition_codes WHERE id_company = 5 ORDER BY code;

\echo === rows of OTHER companies (must be unchanged by this file: expect 0 differences)
SELECT count(*) AS differences
  FROM (SELECT id_company, count(*) AS n, md5(string_agg(concat_ws('|', code, repro_condition, meaning, source, confirmed_by), '#' ORDER BY code)) AS fp
          FROM public.repro_condition_codes WHERE id_company <> 5 GROUP BY id_company) a
  FULL JOIN t_other_before b USING (id_company)
 WHERE a.fp IS DISTINCT FROM b.fp OR a.n IS DISTINCT FROM b.n;

\if :apply
COMMIT;
\echo '*** seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
