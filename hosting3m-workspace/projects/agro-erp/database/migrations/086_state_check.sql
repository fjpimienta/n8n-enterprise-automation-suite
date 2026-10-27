-- 086_state_check.sql — READ-ONLY state assertions for migration 086 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 086_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 086_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 086_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 086 -> applied -> rollback -> rolled_back -> 086 -> applied.
-- The FINGERPRINT lines must be identical at every step: 086 creates new tables, triggers and functions only and never
-- touches an existing table, trigger, crud_models row, company, membership, animal, event, or pre-existing function.
-- sp_log_palpation_event (which the new wrapper CALLS) and the other pre-existing reproduction procedures are
-- fingerprinted by their full definition, and so are the 084 and 085 objects. The two phase-3 tables are NOT in the
-- fingerprints (they are the thing being added); their row counts are printed on PHASE3_ROWS lines, which must be
-- identical after a rollback + re-apply (the rollback keeps the rows).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t086.expect', :'expect', false) AS expect;

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
SELECT 'breeding_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM cattle_breeding_events b
UNION ALL
SELECT 'health_logs_data', md5(string_agg(row_to_json(h)::text, '|' ORDER BY h.id)) FROM cattle_health_logs h
UNION ALL
SELECT 'weight_logs_data', md5(string_agg(row_to_json(w)::text, '|' ORDER BY w.id)) FROM cattle_weight_logs w
UNION ALL
SELECT 'event_voids_data', md5(string_agg(row_to_json(v)::text, '|' ORDER BY v.id)) FROM event_voids v
UNION ALL
SELECT 'preexisting_repro_procedures',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('sp_register_birth_event', 'sp_log_breeding_event', 'sp_log_palpation_event', 'sp_void_event')
UNION ALL
-- the procedure the wrapper calls, on its own: it must be byte-identical before and after
SELECT 'sp_log_palpation_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_log_palpation_event'
UNION ALL
SELECT 'sp_void_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_void_event'
UNION ALL
-- Phase 1 (084) objects: 086 must not change them.
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
-- Phase 2 (085) objects: 086 must not change them (the tools may be 'disabled' bodies if 085 was rolled back, but that is
-- the same before and after 086).
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
SELECT 'phase2_empadre_rows',
       md5(coalesce((SELECT string_agg(row_to_json(e)::text, '|' ORDER BY e.id) FROM repro_empadre_entries e), '')
           || coalesce((SELECT string_agg(row_to_json(v)::text, '|' ORDER BY v.id) FROM repro_empadre_voids v), '')
           || coalesce((SELECT string_agg(row_to_json(c)::text, '|' ORDER BY c.id_company) FROM repro_empadre_config c), ''));

\echo === PHASE3_ROWS (row counts of the 086 tables; must be identical after rollback + re-apply)
DO $$
DECLARE
    t text;
    n bigint;
    s text := '';
BEGIN
    FOREACH t IN ARRAY ARRAY['repro_condition_codes', 'palpation_repro_details'] LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            s := s || t || '=absent ';
        ELSE
            EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
            s := s || t || '=' || n || ' ';
        END IF;
    END LOOP;
    RAISE NOTICE 'PHASE3_ROWS %', s;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t086.expect');
    v_tools   text[] := ARRAY['sp_repro_log_palpation_batch', 'sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings',
                              'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set'];
    v_reads   text[] := ARRAY['sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings', 'sp_repro_list_unmapped_uterine_codes'];
    v_helpers text[] := ARRAY['fn_repro_norm_code', 'fn_uterine_split', 'fn_parse_uterine_code', 'fn_repro_palpations',
                              'fn_trg_palp_details_tenant'];
    v_tables  text[] := ARRAY['repro_condition_codes', 'palpation_repro_details'];
    v_found   integer;
    v_company integer;
    v_email   text;
    v_other   text;
    v_status  text;
    v_blocked boolean := false;
    pr        record;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;

    -- 086 sits on top of 084 and 085 in every state.
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL OR to_regclass('public.vw_animal_effective_birth') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 084 is not applied here (086 requires it)';
    END IF;
    IF to_regclass('public.repro_empadre_entries') IS NULL OR to_regprocedure('public.fn_repro_empadre_cfg(integer)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 085 is not applied here (086 requires it)';
    END IF;

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_tools);

    IF v_expect = 'before' THEN
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: % phase-3 tool function(s) already exist', v_found; END IF;
        IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NOT NULL) THEN
            RAISE EXCEPTION 'FAIL: a phase-3 table already exists';
        END IF;
        RAISE NOTICE '086 state check (before): OK';
        RETURN;
    END IF;

    IF v_found <> 5 THEN RAISE EXCEPTION 'FAIL: expected 5 phase-3 tool functions, found %', v_found; END IF;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 5 THEN RAISE EXCEPTION 'FAIL: expected 5 helper functions, found %', v_found; END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NULL) THEN
        RAISE EXCEPTION 'FAIL: a phase-3 table is missing';
    END IF;

    -- Shape of the tools: text parameters, reads STABLE, writes VOLATILE, never exposed through the gateway.
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_tools)
                  AND (p.proargtypes[0] <> 'text'::regtype OR p.proargtypes[1] <> 'text'::regtype)) THEN
        RAISE EXCEPTION 'FAIL: a tool does not take (text, text, ...) as first parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_reads)
                  AND p.provolatile <> 's') THEN
        RAISE EXCEPTION 'FAIL: a read tool is not STABLE';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
                  AND p.proname = ANY (v_tools) AND NOT (p.proname = ANY (v_reads)) AND p.provolatile <> 'v') THEN
        RAISE EXCEPTION 'FAIL: a write tool is not VOLATILE';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models cm WHERE cm.table_name = ANY (v_tables) OR cm.model_name = ANY (v_tables)
                  OR cm.table_name = ANY (v_tools) OR cm.model_name = ANY (v_tools)) THEN
        RAISE EXCEPTION 'FAIL: a phase-3 table or tool is exposed through crud_models';
    END IF;

    -- Structure: id_company on every row, append-only + tenant triggers on the side table, condition only on VACÍA.
    IF (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = ANY (v_tables) AND column_name = 'id_company' AND is_nullable = 'NO') <> 2 THEN
        RAISE EXCEPTION 'FAIL: id_company must be NOT NULL on both phase-3 tables';
    END IF;
    IF (SELECT count(*) FROM pg_trigger g
         WHERE NOT g.tgisinternal AND g.tgrelid = 'public.palpation_repro_details'::regclass AND g.tgname LIKE 'trg_palp_details_%') <> 3 THEN
        RAISE EXCEPTION 'FAIL: expected 3 triggers on palpation_repro_details (append-only, no-truncate, tenant)';
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.palpation_repro_details'::regclass
           AND conname IN ('ck_palp_det_only_vacia', 'ck_palp_det_status_condition', 'ck_palp_det_status',
                           'ck_palp_det_condition', 'ck_palp_det_side', 'ck_palp_det_result')) <> 6 THEN
        RAISE EXCEPTION 'FAIL: a check constraint of palpation_repro_details is missing';
    END IF;
    IF EXISTS (SELECT 1 FROM public.palpation_repro_details WHERE repro_condition IS NOT NULL AND result <> 'VACÍA') THEN
        RAISE EXCEPTION 'FAIL: a condition exists on a result that is not VACÍA';
    END IF;
    IF EXISTS (SELECT 1 FROM public.palpation_repro_details d
                 JOIN cattle_health_logs h ON h.id = d.health_log_id
                 JOIN cattle_livestock l ON l.id = h.livestock_id
                WHERE l.tenant_id <> d.id_company OR h.livestock_id <> d.livestock_id) THEN
        RAISE EXCEPTION 'FAIL: a palpation detail belongs to another company than its animal';
    END IF;

    -- Parser probes (pure: no data needed). The "applied" state must interpret; "rolled_back" keeps the helpers too.
    SELECT * INTO pr FROM fn_parse_uterine_code('N/A', NULL);
    IF pr.mapping_status <> 'NOT_APPLICABLE' THEN RAISE EXCEPTION 'FAIL: parser(N/A) = %', pr.mapping_status; END IF;
    SELECT * INTO pr FROM fn_parse_uterine_code('UNE/NR', NULL);
    IF pr.mapping_status <> 'UNMAPPED' OR pr.repro_condition IS NOT NULL THEN RAISE EXCEPTION 'FAIL: parser(UNE/NR) must be UNMAPPED with a NULL condition'; END IF;
    SELECT * INTO pr FROM fn_parse_uterine_code('VACÍA Estática', NULL);
    IF pr.mapping_status <> 'EXPLICIT' OR pr.repro_condition <> 'ESTATICA' THEN RAISE EXCEPTION 'FAIL: parser(explicit word) is wrong'; END IF;

    -- A real member of a non-palm company to probe the tools (read-only calls; nothing is shown but the company number).
    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
     WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
     ORDER BY uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
    RAISE NOTICE 'probe: company % (user not shown)', v_company;

    IF v_expect = 'applied' THEN
        v_status := sp_repro_list_palpation_due(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_palpation_due answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_list_upcoming_calvings(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_upcoming_calvings answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_list_unmapped_uterine_codes(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_unmapped_uterine_codes answered % (expected ok)', v_status; END IF;
        BEGIN
            PERFORM sp_repro_list_palpation_due(v_company::text, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;  -- expected: fail-closed
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer'; END IF;

        -- a member who is not ADMIN must be refused by condition_code_set (the refusal happens before any write)
        SELECT uc.email INTO v_other FROM user_companies uc
         WHERE uc.id_company = v_company AND uc.is_active AND upper(uc.role) <> 'ADMIN' ORDER BY uc.email LIMIT 1;
        IF v_other IS NOT NULL THEN
            v_status := sp_repro_condition_code_set(v_company::text, v_other, 'ZZPROBE', 'OTRO')->>'status';
            IF v_status <> 'forbidden' THEN RAISE EXCEPTION 'FAIL: condition_code_set answered % to a non-ADMIN (expected forbidden)', v_status; END IF;
        ELSE
            RAISE NOTICE 'note: company % has no non-ADMIN member; the forbidden probe was skipped', v_company;
        END IF;
    ELSE
        v_status := sp_repro_list_palpation_due(v_company::text, v_email)->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: list_palpation_due answered % (expected disabled)', v_status; END IF;
        v_status := sp_repro_log_palpation_batch(v_company::text, v_email, '[]')->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: log_palpation_with_condition answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '086 state check (%): OK', v_expect;
END $$;

ROLLBACK;
