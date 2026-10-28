-- 087_state_check.sql — READ-ONLY state assertions for migration 087 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 087_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 087_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 087_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 087 -> applied -> rollback -> rolled_back -> 087 -> applied.
-- The FINGERPRINT lines must be identical at every step: 087 only adds objects, one nullable column
-- (birth_events.reported_by_email) and REPLACES ONE procedure (sp_register_birth_event, 13 parameters). That procedure is
-- therefore NOT in the fingerprints; it is asserted on its own LEGACY_BIRTH line: its md5 must be the verified production
-- one (8eaf6f52716165a6bc59f8f4a6a7ce4a) before and after a rollback, and must carry the 087 marker when applied.
-- Production has ONE overload of that procedure (13 parameters); the check also works when another overload exists: any other
-- overload is fingerprinted as other_birth_overloads and must not change.
-- birth_events and cattle_breeding_events are fingerprinted by their ORIGINAL columns only (087 / 088 add one column each).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t087.expect', :'expect', false) AS expect;

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
SELECT 'birth_events_original_columns',
       md5(string_agg(concat_ws('|', b.id::text, b.id_company::text, b.production_unit_id::text, b.paddock_id::text, b.dam_ear_tag, b.dam_fire_number,
                                b.dam_id::text, b.calf_sex, b.calf_brand_id::text, b.calf_id::text, b.birth_date::text, b.source, b.notes,
                                b.created_at::text, b.species), '#' ORDER BY b.id))
  FROM birth_events b
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
-- the procedures 087 must NOT touch (sp_register_birth_event is checked on its own LEGACY_BIRTH line)
SELECT 'sp_log_breeding_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_log_breeding_event'
UNION ALL
SELECT 'sp_void_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_void_event'
UNION ALL
SELECT 'sp_log_palpation_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_log_palpation_event'
UNION ALL
SELECT 'other_birth_overloads',
       md5(coalesce(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text), ''))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_register_birth_event' AND p.pronargs <> 13
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
                                          'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set')), ''));

\echo === LEGACY_BIRTH (sp_register_birth_event, 13 parameters: replaced on purpose by 087, restored by its rollback)
SELECT 'LEGACY_BIRTH' AS item, md5(pg_get_functiondef(p.oid)) AS md5,
       (p.prosrc LIKE '%087:legacy-birth-v1%') AS has_087_marker,
       (SELECT count(*) FROM pg_proc q WHERE q.pronamespace = 'public'::regnamespace AND q.proname = 'sp_register_birth_event') AS overloads_by_name
  FROM pg_proc p WHERE p.oid = to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)');

\echo === PHASE4A_ROWS (row counts of the 087 tables; must be identical after rollback + re-apply)
DO $$
DECLARE
    t text;
    n bigint;
    s text := '';
BEGIN
    FOREACH t IN ARRAY ARRAY['repro_births_config', 'repro_historical_births', 'repro_historical_birth_voids'] LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            s := s || t || '=absent ';
        ELSE
            EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
            s := s || t || '=' || n || ' ';
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'birth_events' AND column_name = 'reported_by_email') THEN
        EXECUTE 'SELECT count(*) FROM public.birth_events WHERE reported_by_email IS NOT NULL' INTO n;
        s := s || 'birth_events_with_reporter=' || n;
    ELSE
        s := s || 'birth_events.reported_by_email=absent';
    END IF;
    RAISE NOTICE 'PHASE4A_ROWS %', s;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t087.expect');
    v_tools   text[] := ARRAY['sp_repro_births_get_config', 'sp_repro_births_set_config', 'sp_repro_register_birth',
                              'sp_repro_births_batch_preview', 'sp_repro_births_batch_register', 'sp_repro_register_historical_birth',
                              'sp_repro_void_historical_birth', 'sp_repro_list_historical_births'];
    v_reads   text[] := ARRAY['sp_repro_births_get_config', 'sp_repro_births_batch_preview', 'sp_repro_list_historical_births'];
    v_helpers text[] := ARRAY['fn_repro_is_member', 'fn_repro_births_cfg', 'fn_repro_birth_dam', 'fn_repro_birth_exact_retry',
                              'fn_repro_birth_window_matches', 'fn_repro_birth_check_line', 'fn_repro_births_batch_validate',
                              'fn_trg_hist_birth_tenant', 'fn_trg_hist_birth_void_tenant'];
    v_tables  text[] := ARRAY['repro_births_config', 'repro_historical_births', 'repro_historical_birth_voids'];
    v_legacy  oid := to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)');
    v_found   integer;
    v_company integer;
    v_email   text;
    v_status  text;
    v_blocked boolean := false;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL OR to_regclass('public.vw_animal_effective_birth') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 084 is not applied here (087 requires it)';
    END IF;
    IF to_regclass('public.repro_empadre_entries') IS NULL OR to_regprocedure('public.fn_trg_empadre_append_only()') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 085 is not applied here (087 requires it)';
    END IF;
    IF v_legacy IS NULL THEN
        RAISE EXCEPTION 'FAIL: sp_register_birth_event (13 parameters) not found';
    END IF;

    -- the legacy procedure: verified production body before and after a rollback, marked body when applied
    IF v_expect IN ('before', 'rolled_back') AND md5(pg_get_functiondef(v_legacy)) <> '8eaf6f52716165a6bc59f8f4a6a7ce4a' THEN
        RAISE EXCEPTION 'FAIL: sp_register_birth_event is not the verified production body (md5 %)', md5(pg_get_functiondef(v_legacy));
    END IF;
    IF v_expect = 'applied' AND (SELECT prosrc FROM pg_proc WHERE oid = v_legacy) NOT LIKE '%087:legacy-birth-v1%' THEN
        RAISE EXCEPTION 'FAIL: sp_register_birth_event does not carry the 087 body';
    END IF;
    RAISE NOTICE 'sp_register_birth_event overloads in this database: %', (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_register_birth_event');

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_tools);

    IF v_expect = 'before' THEN
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: % phase-4a tool function(s) already exist', v_found; END IF;
        IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NOT NULL) THEN
            RAISE EXCEPTION 'FAIL: a phase-4a table already exists';
        END IF;
        RAISE NOTICE '087 state check (before): OK';
        RETURN;
    END IF;

    IF v_found <> 8 THEN RAISE EXCEPTION 'FAIL: expected 8 phase-4a tool functions, found %', v_found; END IF;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 9 THEN RAISE EXCEPTION 'FAIL: expected 9 helper functions, found %', v_found; END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NULL) THEN
        RAISE EXCEPTION 'FAIL: a phase-4a table is missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'birth_events'
                      AND column_name = 'reported_by_email' AND is_nullable = 'YES' AND column_default IS NULL) THEN
        RAISE EXCEPTION 'FAIL: birth_events.reported_by_email must exist, nullable and without a default';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_tools)
                  AND (p.proargtypes[0] <> 'text'::regtype OR p.proargtypes[1] <> 'text'::regtype)) THEN
        RAISE EXCEPTION 'FAIL: a tool does not take (text, text, ...) as first parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_reads) AND p.provolatile <> 's') THEN
        RAISE EXCEPTION 'FAIL: a read tool is not STABLE';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
                  AND p.proname = ANY (v_tools) AND NOT (p.proname = ANY (v_reads)) AND p.provolatile <> 'v') THEN
        RAISE EXCEPTION 'FAIL: a write tool is not VOLATILE';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models cm WHERE cm.table_name = ANY (v_tables) OR cm.model_name = ANY (v_tables)
                  OR cm.table_name = ANY (v_tools) OR cm.model_name = ANY (v_tools)) THEN
        RAISE EXCEPTION 'FAIL: a phase-4a table or tool is exposed through crud_models';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = ANY (v_tables) AND column_name = 'id_company' AND is_nullable = 'NO') <> 3 THEN
        RAISE EXCEPTION 'FAIL: id_company must be NOT NULL on the three phase-4a tables';
    END IF;
    IF (SELECT count(*) FROM pg_trigger g
         WHERE NOT g.tgisinternal AND g.tgrelid IN ('public.repro_historical_births'::regclass, 'public.repro_historical_birth_voids'::regclass)
           AND g.tgname LIKE 'trg_hist_%') <> 6 THEN
        RAISE EXCEPTION 'FAIL: expected 6 triggers on the historical birth tables';
    END IF;
    IF EXISTS (SELECT 1 FROM public.repro_historical_births h
                 LEFT JOIN cattle_livestock l ON l.id = h.dam_id AND l.tenant_id = h.id_company WHERE l.id IS NULL) THEN
        RAISE EXCEPTION 'FAIL: a historical birth belongs to another company than its dam';
    END IF;
    IF EXISTS (SELECT 1 FROM public.repro_historical_birth_voids v
                 LEFT JOIN public.repro_historical_births h ON h.id = v.historical_birth_id AND h.id_company = v.id_company WHERE h.id IS NULL) THEN
        RAISE EXCEPTION 'FAIL: a historical-birth void belongs to another company than its birth';
    END IF;

    -- a real member of a non-palm company to probe the tools (read-only calls)
    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
     WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
     ORDER BY uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
    RAISE NOTICE 'probe: company % (user not shown)', v_company;

    IF v_expect = 'applied' THEN
        v_status := sp_repro_births_get_config(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: get_births_config answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_list_historical_births(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_historical_births answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_births_batch_preview(v_company::text, v_email, '[]')->>'code';
        IF v_status IS DISTINCT FROM 'BAD_ITEMS' THEN RAISE EXCEPTION 'FAIL: births_batch_preview([]) answered % (expected BAD_ITEMS)', v_status; END IF;
        BEGIN
            PERFORM sp_repro_list_historical_births(v_company::text, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer from list_historical_births'; END IF;
        -- the legacy procedure now refuses a non-member e-mail BEFORE writing anything (so this probe cannot write)
        v_blocked := false;
        BEGIN
            PERFORM sp_register_birth_event(v_company, 'MACHO', 'BOVINO', NULL, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: sp_register_birth_event accepted a non-member e-mail'; END IF;
    ELSE
        v_status := sp_repro_register_birth(v_company::text, v_email, 'MACHO')->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: register_birth_checked answered % (expected disabled)', v_status; END IF;
        v_status := sp_repro_list_historical_births(v_company::text, v_email)->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: list_historical_births answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '087 state check (%): OK', v_expect;
END $$;

ROLLBACK;
