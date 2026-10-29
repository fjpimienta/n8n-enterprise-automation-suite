-- 090_state_check.sql — READ-ONLY state assertions for migration 090 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 090_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 090_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 090_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 090 -> applied -> rollback -> rolled_back -> 090 -> applied.
-- The FINGERPRINT lines must be identical at every step. 090 REPLACES 7 bodies on purpose, so those are asserted on their own
-- BODY_* lines (the md5 created by 086 / 088 before and after a rollback, the 090 marker when applied) and are NOT in the fingerprints.
-- The column repro_condition_codes.meaning and the 3 helpers STAY after a rollback (nothing is dropped); the codes that carry a meaning
-- are counted on the PHASE3B_ROWS line (they survive a rollback + re-apply).
-- ⚠️ After 090 the older state checks (086, 088) will report a different 'phase3_palpation_functions' fingerprint: that is expected,
-- those 7 functions are the ones 090 replaces. Use THIS file for them.

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t090.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'crud_models' AS fingerprint, md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5 FROM crud_models c
UNION ALL
SELECT 'companys_data', md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text, metadata::text), '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company))
  FROM user_companies
UNION ALL
SELECT 'cattle_livestock_data', md5(string_agg(row_to_json(l)::text, '|' ORDER BY l.id)) FROM cattle_livestock l
UNION ALL
SELECT 'health_logs_data', md5(string_agg(row_to_json(h)::text, '|' ORDER BY h.id)) FROM cattle_health_logs h
UNION ALL
SELECT 'palpation_repro_details_data', md5(coalesce(string_agg(row_to_json(d)::text, '|' ORDER BY d.id), '')) FROM palpation_repro_details d
UNION ALL
SELECT 'birth_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM birth_events b
UNION ALL
SELECT 'breeding_events_data', md5(coalesce(string_agg(row_to_json(e)::text, '|' ORDER BY e.id), '')) FROM cattle_breeding_events e
UNION ALL
SELECT 'condition_codes_with_a_condition',
       md5(coalesce(string_agg(concat_ws('|', cc.id_company::text, cc.code, cc.repro_condition), '#' ORDER BY cc.id_company, cc.code), ''))
  FROM repro_condition_codes cc WHERE cc.repro_condition IS NOT NULL
UNION ALL
SELECT 'sp_log_palpation_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_log_palpation_event'
UNION ALL
SELECT 'phase3_unreplaced_helpers',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_norm_code', 'fn_uterine_split', 'fn_parse_uterine_code',
                                          'fn_repro_palpations', 'fn_trg_palp_details_tenant')), ''))
UNION ALL
SELECT 'phase4_births_and_services_functions',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_birth_window_matches', 'fn_repro_birth_check_line', 'sp_repro_register_birth',
                                          'sp_repro_births_batch_register', 'fn_repro_gestation_bounds', 'fn_repro_link_birth_service',
                                          'sp_register_birth_event', 'sp_log_breeding_event', 'sp_void_event')), ''));

\echo === BODY_* (the 7 replaced bodies: md5 and whether the 090 marker is present)
SELECT 'BODY_' || v.name AS item, md5(pg_get_functiondef(p.oid)) AS md5, (p.prosrc LIKE '%090:vet-codes-v1%') AS has_090_marker,
       (md5(pg_get_functiondef(p.oid)) = v.orig) AS is_original_086_088_body
  FROM (VALUES
    ('fn_repro_diagnosis_kind',              'public.fn_repro_diagnosis_kind(text,integer)',                       'c14027757d85c745756a704ced03ab5f'),
    ('sp_repro_log_palpation_batch',         'public.sp_repro_log_palpation_batch(text,text,text,text,text)',      '845854fd40df5406c8c4f1f90fd558c9'),
    ('sp_repro_list_palpation_due',          'public.sp_repro_list_palpation_due(text,text,text,text,text)',       'd04d1f85f5d3aadae7d7bf1b8df73518'),
    ('sp_repro_list_upcoming_calvings',      'public.sp_repro_list_upcoming_calvings(text,text,text,text,text)',   '0fab0832c5818b6be09cd94efb826ddb'),
    ('sp_repro_list_unmapped_uterine_codes', 'public.sp_repro_list_unmapped_uterine_codes(text,text,text)',        '4f682a0ea099c051d5b3b95a8eb553d0'),
    ('sp_repro_condition_code_set',          'public.sp_repro_condition_code_set(text,text,text,text,text)',       '46e720910cf97de3eb3921fb83f820b3'),
    ('sp_repro_get_dam_history',             'public.sp_repro_get_dam_history(text,text,text,text)',               '79927c5b2478ae8f31307b9eb89d97d7')
  ) AS v (name, sig, orig)
  JOIN pg_proc p ON p.oid = to_regprocedure(v.sig)
 ORDER BY v.name;

\echo === PHASE3B_ROWS (codes that carry a meaning survive a rollback + re-apply)
DO $$
DECLARE
    n bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes' AND column_name = 'meaning') THEN
        EXECUTE 'SELECT count(*) FROM public.repro_condition_codes WHERE meaning IS NOT NULL' INTO n;
        RAISE NOTICE 'PHASE3B_ROWS codes_with_a_meaning=%', n;
    ELSE
        RAISE NOTICE 'PHASE3B_ROWS repro_condition_codes.meaning=absent';
    END IF;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t090.expect');
    v_sigs    text[] := ARRAY['public.fn_repro_diagnosis_kind(text,integer)', 'public.sp_repro_log_palpation_batch(text,text,text,text,text)',
                              'public.sp_repro_list_palpation_due(text,text,text,text,text)', 'public.sp_repro_list_upcoming_calvings(text,text,text,text,text)',
                              'public.sp_repro_list_unmapped_uterine_codes(text,text,text)', 'public.sp_repro_condition_code_set(text,text,text,text,text)',
                              'public.sp_repro_get_dam_history(text,text,text,text)'];
    v_orig    text[] := ARRAY['c14027757d85c745756a704ced03ab5f', '845854fd40df5406c8c4f1f90fd558c9', 'd04d1f85f5d3aadae7d7bf1b8df73518',
                              '0fab0832c5818b6be09cd94efb826ddb', '4f682a0ea099c051d5b3b95a8eb553d0', '46e720910cf97de3eb3921fb83f820b3',
                              '79927c5b2478ae8f31307b9eb89d97d7'];
    v_helpers text[] := ARRAY['fn_repro_code_meaning', 'fn_repro_palp_text', 'fn_repro_palp_code_info'];
    i         integer;
    v_want    integer;
    v_have    integer;
    v_oid     oid;
    v_col     boolean;
    v_found   integer;
    v_company integer;
    v_email   text;
    v_j       jsonb;
    v_blocked boolean;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;
    IF to_regclass('public.repro_condition_codes') IS NULL OR to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migrations 084 - 088 must be applied (090 requires them)';
    END IF;
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes' AND column_name = 'meaning') INTO v_col;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);

    FOR i IN 1 .. 7 LOOP
        v_oid := to_regprocedure(v_sigs[i]);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'FAIL: % not found with its signature (one overload only)', v_sigs[i]; END IF;
        IF v_expect IN ('before', 'rolled_back') THEN
            IF md5(pg_get_functiondef(v_oid)) <> v_orig[i] THEN
                RAISE EXCEPTION 'FAIL: % is not the 086 / 088 body (md5 %)', v_sigs[i], md5(pg_get_functiondef(v_oid));
            END IF;
        ELSE
            IF (SELECT prosrc FROM pg_proc WHERE oid = v_oid) NOT LIKE '%090:vet-codes-v1%' THEN
                RAISE EXCEPTION 'FAIL: % does not carry the 090 body', v_sigs[i];
            END IF;
        END IF;
    END LOOP;
    -- (no CASE inside an IF condition: PL/pgSQL ends the condition at the first top-level THEN, which would be the CASE's own THEN)
    v_want := 0;
    IF v_expect = 'applied' THEN v_want := 7; END IF;
    SELECT count(*) INTO v_have FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%090:vet-codes-v1%';
    IF v_have <> v_want THEN
        RAISE EXCEPTION 'FAIL: % bodies carry the 090 marker, expected % for state %', v_have, v_want, v_expect;
    END IF;

    IF v_expect = 'before' THEN
        IF v_col THEN RAISE EXCEPTION 'FAIL: repro_condition_codes.meaning already exists'; END IF;
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: a 090 helper already exists'; END IF;
        RAISE NOTICE '090 state check (before): OK';
        RETURN;
    END IF;

    -- applied and rolled_back: the column and the helpers stay (nothing is dropped)
    IF NOT v_col THEN RAISE EXCEPTION 'FAIL: repro_condition_codes.meaning is missing'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes'
                      AND column_name = 'meaning' AND is_nullable = 'YES' AND column_default IS NULL AND data_type = 'text') THEN
        RAISE EXCEPTION 'FAIL: meaning must be text, nullable, without a default';
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.repro_condition_codes'::regclass
           AND conname IN ('ck_cond_code_meaning', 'ck_cond_code_meaning_no_condition')) <> 2 THEN
        RAISE EXCEPTION 'FAIL: the two meaning CHECKs are missing';
    END IF;
    IF v_found <> 3 THEN RAISE EXCEPTION 'FAIL: expected 3 helper functions, found %', v_found; END IF;
    IF EXISTS (SELECT 1 FROM repro_condition_codes WHERE meaning IS NOT NULL AND (repro_condition IS NOT NULL OR meaning NOT IN ('NOT_EXAMINED', 'POSTPARTUM', 'UNFIT'))) THEN
        RAISE EXCEPTION 'FAIL: a code has a meaning together with a condition, or an unknown meaning';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models cm WHERE cm.table_name IN ('fn_repro_code_meaning', 'fn_repro_palp_text', 'fn_repro_palp_code_info')) THEN
        RAISE EXCEPTION 'FAIL: a helper is exposed through crud_models';
    END IF;

    IF v_expect = 'applied' THEN
        -- pure probes (no company data involved; p_tenant NULL looks up no mapping)
        IF public.fn_repro_diagnosis_kind('MATRIZ OCUPADA', NULL) <> 'PRENADA' THEN RAISE EXCEPTION 'FAIL: MATRIZ OCUPADA is not a PREÑADA phrase'; END IF;
        IF public.fn_repro_diagnosis_kind('VACIA MATRIZ OCUPADA', NULL) <> 'CONFLICT' THEN RAISE EXCEPTION 'FAIL: VACIA + MATRIZ OCUPADA must be a conflict'; END IF;
        IF public.fn_repro_diagnosis_kind('PREÑADA 3 MESES', NULL) <> 'PRENADA' OR public.fn_repro_diagnosis_kind('VACIA', NULL) <> 'VACIA' THEN
            RAISE EXCEPTION 'FAIL: the explicit words changed';
        END IF;
        IF public.fn_repro_diagnosis_kind('NR', NULL) <> 'UNRECOGNIZED' OR public.fn_repro_diagnosis_kind('ok', NULL) <> 'UNRECOGNIZED' THEN
            RAISE EXCEPTION 'FAIL: a bare code without a company must stay UNRECOGNIZED';
        END IF;
        IF (SELECT uterine_code IS NOT NULL OR vet_flag IS NOT NULL FROM public.fn_repro_palp_code_info(NULL, 'N/A')) THEN
            RAISE EXCEPTION 'FAIL: N/A must still mean "no code"';
        END IF;
        IF (SELECT mapping_status FROM public.fn_parse_uterine_code('N/A', NULL)) <> 'NOT_APPLICABLE' THEN
            RAISE EXCEPTION 'FAIL: the parser handles N/A differently';
        END IF;

        SELECT uc.id_company, uc.email INTO v_company, v_email
          FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
         WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
         ORDER BY uc.id_company LIMIT 1;
        IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
        RAISE NOTICE 'probe: company % (user not shown)', v_company;

        v_j := sp_repro_list_unmapped_uterine_codes(v_company::text, v_email);
        IF v_j->>'status' <> 'ok' OR NOT (v_j ? 'known_meanings') OR NOT (v_j ? 'composite_unconfirmed') OR NOT (v_j ? 'meanings_configured') THEN
            RAISE EXCEPTION 'FAIL: list_unmapped_uterine_codes did not answer with the new keys';
        END IF;
        v_blocked := false;
        BEGIN
            PERFORM sp_repro_list_unmapped_uterine_codes(v_company::text, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer from list_unmapped_uterine_codes'; END IF;
        v_blocked := false;
        BEGIN
            PERFORM sp_repro_get_dam_history(v_company::text, 'nadie@example.test', 'x');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer from get_dam_reproductive_history'; END IF;
        IF (SELECT provolatile FROM pg_proc WHERE oid = to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)')) <> 's'
           OR (SELECT provolatile FROM pg_proc WHERE oid = to_regprocedure('public.sp_repro_list_unmapped_uterine_codes(text,text,text)')) <> 's' THEN
            RAISE EXCEPTION 'FAIL: the read tools must stay STABLE';
        END IF;
    END IF;
    RAISE NOTICE '090 state check (%): OK', v_expect;
END $$;

ROLLBACK;
