-- 088_state_check.sql — READ-ONLY state assertions for migration 088 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 088_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 088_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 088_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 088 -> applied -> rollback -> rolled_back -> 088 -> applied.
-- The FINGERPRINT lines must be identical at every step. 088 adds objects and one nullable column (cattle_breeding_events.birth_event_id)
-- and REPLACES TWO procedures (sp_log_breeding_event, sp_void_event): those are asserted on their own LEGACY_* lines (original
-- production md5 before and after a rollback, 088 marker when applied), not in the fingerprints. cattle_breeding_events is
-- fingerprinted by its ORIGINAL columns only; the links made so far are counted on the PHASE4B_ROWS line (they survive a rollback).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t088.expect', :'expect', false) AS expect;

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
SELECT 'birth_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM birth_events b
UNION ALL
SELECT 'breeding_events_original_columns',
       md5(string_agg(concat_ws('|', e.id::text, e.livestock_id::text, e.tenant_id::text, e.breeding_date::text, e.method, e.sire_identifier,
                                e.semen_batch, e.estimated_due_date::text, e.registered_by_email, e.notes, e.created_at::text), '#' ORDER BY e.id))
  FROM cattle_breeding_events e
UNION ALL
SELECT 'health_logs_data', md5(string_agg(row_to_json(h)::text, '|' ORDER BY h.id)) FROM cattle_health_logs h
UNION ALL
SELECT 'weight_logs_data', md5(string_agg(row_to_json(w)::text, '|' ORDER BY w.id)) FROM cattle_weight_logs w
UNION ALL
SELECT 'event_voids_data', md5(string_agg(row_to_json(v)::text, '|' ORDER BY v.id)) FROM event_voids v
UNION ALL
SELECT 'sp_register_birth_event_all_overloads',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_register_birth_event'
UNION ALL
SELECT 'sp_log_palpation_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_log_palpation_event'
UNION ALL
SELECT 'phase1_parser_helpers_view',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_txt', 'fn_repro_int', 'fn_repro_date', 'fn_repro_ctx',
                                          'fn_is_placeholder_birth_date', 'fn_fire_number_shape',
                                          'fn_estimate_birth_from_fire_number',
                                          'sp_repro_list_births', 'sp_repro_dam_birth_history', 'sp_repro_births_summary',
                                          'sp_repro_list_unregistered_historical_births', 'sp_repro_identifier_quality_report')), '')
           || coalesce(pg_get_viewdef('public.vw_animal_effective_birth'::regclass, true), ''))
UNION ALL
SELECT 'phase2_empadre_functions',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_today', 'fn_repro_member_role', 'fn_repro_empadre_cfg', 'fn_repro_resolve_animal',
                                          'fn_repro_empadre_eval', 'fn_repro_empadre_check_item', 'fn_repro_empadre_date',
                                          'fn_trg_empadre_append_only', 'fn_trg_empadre_entry_tenant', 'fn_trg_empadre_void_tenant',
                                          'sp_repro_empadre_get_config', 'sp_repro_empadre_set_config',
                                          'sp_repro_list_heifers_eligible_for_empadre', 'sp_repro_log_empadre_entry',
                                          'sp_repro_log_empadre_entry_batch', 'sp_void_empadre_entry',
                                          'sp_repro_list_empadre_entries', 'sp_repro_list_open_cows')), ''))
UNION ALL
SELECT 'phase3_palpation_functions',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_norm_code', 'fn_uterine_split', 'fn_parse_uterine_code', 'fn_repro_diagnosis_kind',
                                          'fn_repro_palpations', 'fn_trg_palp_details_tenant', 'sp_repro_log_palpation_batch',
                                          'sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings',
                                          'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set')), ''))
UNION ALL
SELECT 'phase4a_birth_functions',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_is_member', 'fn_repro_births_cfg', 'fn_repro_birth_dam', 'fn_repro_birth_exact_retry',
                                          'fn_repro_birth_window_matches', 'fn_repro_birth_check_line', 'fn_repro_births_batch_validate',
                                          'fn_trg_hist_birth_tenant', 'fn_trg_hist_birth_void_tenant',
                                          'sp_repro_births_get_config', 'sp_repro_births_set_config', 'sp_repro_register_birth',
                                          'sp_repro_births_batch_preview', 'sp_repro_births_batch_register',
                                          'sp_repro_register_historical_birth', 'sp_repro_void_historical_birth',
                                          'sp_repro_list_historical_births')), ''))
UNION ALL
SELECT 'phase4a_rows',
       md5(coalesce((SELECT string_agg(row_to_json(h)::text, '|' ORDER BY h.id) FROM repro_historical_births h), '')
           || coalesce((SELECT string_agg(row_to_json(v)::text, '|' ORDER BY v.id) FROM repro_historical_birth_voids v), '')
           || coalesce((SELECT string_agg(row_to_json(c)::text, '|' ORDER BY c.id_company) FROM repro_births_config c), ''));

\echo === LEGACY_BREEDING / LEGACY_VOID (replaced on purpose by 088, restored by its rollback)
SELECT 'LEGACY_BREEDING' AS item, md5(pg_get_functiondef(p.oid)) AS md5, (p.prosrc LIKE '%088:legacy-breeding-v1%') AS has_088_marker
  FROM pg_proc p WHERE p.oid = to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)')
UNION ALL
SELECT 'LEGACY_VOID', md5(pg_get_functiondef(p.oid)), (p.prosrc LIKE '%088:legacy-void-v1%')
  FROM pg_proc p WHERE p.oid = to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)');

\echo === PHASE4B_ROWS (the links survive a rollback + re-apply)
DO $$
DECLARE
    n bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_breeding_events' AND column_name = 'birth_event_id') THEN
        EXECUTE 'SELECT count(*) FROM public.cattle_breeding_events WHERE birth_event_id IS NOT NULL' INTO n;
        RAISE NOTICE 'PHASE4B_ROWS services_linked_to_a_birth=%', n;
    ELSE
        RAISE NOTICE 'PHASE4B_ROWS cattle_breeding_events.birth_event_id=absent';
    END IF;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t088.expect');
    v_brd     oid := to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)');
    v_void    oid := to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)');
    v_helpers text[] := ARRAY['fn_trg_breeding_birth_link_guard', 'fn_repro_gestation_bounds', 'fn_repro_link_birth_service'];
    v_found   integer;
    v_company integer;
    v_email   text;
    v_status  text;
    v_blocked boolean;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;
    IF to_regprocedure('public.fn_repro_is_member(integer,text)') IS NULL OR to_regclass('public.repro_historical_births') IS NULL
       OR to_regprocedure('public.fn_repro_palpations(integer)') IS NULL OR to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migrations 084 - 087 must be applied (088 requires them)';
    END IF;
    IF v_brd IS NULL OR v_void IS NULL THEN
        RAISE EXCEPTION 'FAIL: sp_log_breeding_event / sp_void_event not found with their production signatures';
    END IF;

    IF v_expect IN ('before', 'rolled_back') THEN
        IF md5(pg_get_functiondef(v_brd)) <> '2c1ff0adf25284e069ebf46ddc3108f8' THEN
            RAISE EXCEPTION 'FAIL: sp_log_breeding_event is not the verified production body (md5 %)', md5(pg_get_functiondef(v_brd));
        END IF;
        IF md5(pg_get_functiondef(v_void)) <> 'c81f6faec5e61a28eca5d24b0f62a61c' THEN
            RAISE EXCEPTION 'FAIL: sp_void_event is not the verified production body (md5 %)', md5(pg_get_functiondef(v_void));
        END IF;
    ELSE
        IF (SELECT prosrc FROM pg_proc WHERE oid = v_brd) NOT LIKE '%088:legacy-breeding-v1%'
           OR (SELECT prosrc FROM pg_proc WHERE oid = v_void) NOT LIKE '%088:legacy-void-v1%' THEN
            RAISE EXCEPTION 'FAIL: a legacy procedure does not carry the 088 body';
        END IF;
    END IF;

    IF v_expect = 'before' THEN
        IF to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'FAIL: sp_repro_get_dam_history already exists'; END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_breeding_events' AND column_name = 'birth_event_id') THEN
            RAISE EXCEPTION 'FAIL: cattle_breeding_events.birth_event_id already exists';
        END IF;
        RAISE NOTICE '088 state check (before): OK';
        RETURN;
    END IF;

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 3 THEN RAISE EXCEPTION 'FAIL: expected 3 helper functions, found %', v_found; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_breeding_events'
                      AND column_name = 'birth_event_id' AND is_nullable = 'YES' AND column_default IS NULL) THEN
        RAISE EXCEPTION 'FAIL: cattle_breeding_events.birth_event_id must exist, nullable and without a default';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgname = 'trg_breeding_birth_link_guard'
                      AND g.tgrelid = 'public.cattle_breeding_events'::regclass AND NOT g.tgisinternal) THEN
        RAISE EXCEPTION 'FAIL: the link guard trigger is missing';
    END IF;
    IF (SELECT provolatile FROM pg_proc WHERE oid = to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)')) <> 's' THEN
        RAISE EXCEPTION 'FAIL: get_dam_reproductive_history must be STABLE (read-only)';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models cm WHERE cm.table_name = 'sp_repro_get_dam_history' OR cm.model_name = 'sp_repro_get_dam_history') THEN
        RAISE EXCEPTION 'FAIL: the dam history tool is exposed through crud_models';
    END IF;

    -- every link is consistent: the birth belongs to the same company and the same dam, and the service is not voided
    IF EXISTS (SELECT 1 FROM cattle_breeding_events e
                 LEFT JOIN birth_events b ON b.id = e.birth_event_id AND b.id_company = e.tenant_id AND b.dam_id = e.livestock_id
                WHERE e.birth_event_id IS NOT NULL AND b.id IS NULL) THEN
        RAISE EXCEPTION 'FAIL: a service is linked to a birth of another company or another dam';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_breeding_events e JOIN event_voids v ON v.event_table = 'cattle_breeding_events' AND v.event_id = e.id
                WHERE e.birth_event_id IS NOT NULL) THEN
        RAISE NOTICE 'note: a service linked to a birth was voided before it was linked or by the original sp_void_event (rolled-back state)';
    END IF;
    IF (SELECT count(*) FROM (SELECT birth_event_id FROM cattle_breeding_events WHERE birth_event_id IS NOT NULL GROUP BY birth_event_id HAVING count(*) > 1) q) > 0 THEN
        RAISE EXCEPTION 'FAIL: a birth has more than one linked service';
    END IF;

    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
     WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
     ORDER BY uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
    RAISE NOTICE 'probe: company % (user not shown)', v_company;

    IF v_expect = 'applied' THEN
        v_status := sp_repro_get_dam_history(v_company::text, v_email)->>'code';
        IF v_status IS DISTINCT FROM 'DAM_MISSING' THEN RAISE EXCEPTION 'FAIL: get_dam_reproductive_history(no dam) answered % (expected DAM_MISSING)', v_status; END IF;
        v_blocked := false;
        BEGIN
            PERFORM sp_repro_get_dam_history(v_company::text, 'nadie@example.test', 'x');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer from get_dam_reproductive_history'; END IF;
        -- the two hardened procedures refuse a non-member BEFORE reading or writing anything (so these probes cannot write)
        v_blocked := false;
        BEGIN
            PERFORM sp_log_breeding_event('x', v_company, CURRENT_DATE, 'MONTA_NATURAL', NULL, NULL, 'nadie@example.test', NULL);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: sp_log_breeding_event accepted a non-member e-mail'; END IF;
        v_blocked := false;
        BEGIN
            PERFORM sp_void_event('cattle_breeding_events', gen_random_uuid(), v_company, 'nadie@example.test', 'x');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: sp_void_event accepted a non-member e-mail'; END IF;
        v_blocked := false;
        BEGIN
            PERFORM sp_void_event('cattle_breeding_events', gen_random_uuid(), v_company, NULL, 'x');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: sp_void_event accepted a NULL e-mail'; END IF;
    ELSE
        v_status := sp_repro_get_dam_history(v_company::text, v_email)->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: get_dam_reproductive_history answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '088 state check (%): OK', v_expect;
END $$;

ROLLBACK;
