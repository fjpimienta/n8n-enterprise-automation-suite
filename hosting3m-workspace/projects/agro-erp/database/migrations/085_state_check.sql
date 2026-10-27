-- 085_state_check.sql — READ-ONLY state assertions for migration 085 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an
-- assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 085_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 085_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 085_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 085 -> applied -> rollback -> rolled_back -> 085 -> applied.
-- The FINGERPRINT lines must be identical at every step: 085 creates new tables, triggers and functions only and
-- never touches an existing table, trigger, crud_models row, company, membership, animal, event, or pre-existing
-- function (sp_void_event, sp_register_birth_event, sp_log_breeding_event, sp_log_palpation_event and every 084
-- object are fingerprinted). The three empadre tables are NOT in the fingerprints (they are the thing being added);
-- their row counts are printed on separate EMPADRE_ROWS lines, which must be identical after a rollback + re-apply
-- (the rollback keeps the rows).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t085.expect', :'expect', false) AS expect;

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
SELECT 'sp_void_event_only',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_void_event'
UNION ALL
-- Phase 1 (084) objects: 085 must not change them. Skipped (NULL) when the rollback of 084 replaced the tools.
SELECT 'phase1_parser_helpers_view',
       md5(coalesce((SELECT string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)
                       FROM pg_proc p
                      WHERE p.pronamespace = 'public'::regnamespace
                        AND p.proname IN ('fn_repro_txt', 'fn_repro_int', 'fn_repro_date', 'fn_repro_ctx',
                                          'fn_is_placeholder_birth_date', 'fn_fire_number_shape',
                                          'fn_estimate_birth_from_fire_number',
                                          'sp_repro_list_births', 'sp_repro_dam_birth_history', 'sp_repro_births_summary',
                                          'sp_repro_list_unregistered_historical_births', 'sp_repro_identifier_quality_report')), '')
           || coalesce(pg_get_viewdef('public.vw_animal_effective_birth'::regclass, true), ''));

\echo === EMPADRE_ROWS (row counts of the 085 tables; must be identical after rollback + re-apply)
DO $$
DECLARE
    t text;
    n bigint;
    s text := '';
BEGIN
    FOREACH t IN ARRAY ARRAY['repro_empadre_config', 'repro_empadre_entries', 'repro_empadre_voids'] LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            s := s || t || '=absent ';
        ELSE
            EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
            s := s || t || '=' || n || ' ';
        END IF;
    END LOOP;
    RAISE NOTICE 'EMPADRE_ROWS %', s;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect  text := current_setting('t085.expect');
    v_tools   text[] := ARRAY['sp_repro_empadre_get_config', 'sp_repro_empadre_set_config',
                              'sp_repro_list_heifers_eligible_for_empadre', 'sp_repro_log_empadre_entry',
                              'sp_repro_log_empadre_entry_batch', 'sp_void_empadre_entry', 'sp_repro_list_empadre_entries',
                              'sp_repro_list_open_cows'];
    v_reads   text[] := ARRAY['sp_repro_empadre_get_config', 'sp_repro_list_heifers_eligible_for_empadre',
                              'sp_repro_list_empadre_entries', 'sp_repro_list_open_cows'];
    v_helpers text[] := ARRAY['fn_repro_today', 'fn_repro_member_role', 'fn_repro_empadre_cfg', 'fn_repro_resolve_animal',
                              'fn_repro_empadre_eval', 'fn_repro_empadre_check_item', 'fn_repro_empadre_date'];
    v_tables  text[] := ARRAY['repro_empadre_config', 'repro_empadre_entries', 'repro_empadre_voids'];
    v_found   integer;
    v_company integer;
    v_email   text;
    v_other   text;
    v_status  text;
    v_blocked boolean := false;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;

    -- 085 sits on top of 084 in every state.
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL OR to_regclass('public.vw_animal_effective_birth') IS NULL THEN
        RAISE EXCEPTION 'FAIL: migration 084 is not applied here (085 requires it)';
    END IF;

    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_tools);

    IF v_expect = 'before' THEN
        IF v_found <> 0 THEN RAISE EXCEPTION 'FAIL: % empadre tool function(s) already exist', v_found; END IF;
        IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NOT NULL) THEN
            RAISE EXCEPTION 'FAIL: an empadre table already exists';
        END IF;
        RAISE NOTICE '085 state check (before): OK';
        RETURN;
    END IF;

    IF v_found <> 8 THEN RAISE EXCEPTION 'FAIL: expected 8 empadre tool functions, found %', v_found; END IF;
    SELECT count(*) INTO v_found FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY (v_helpers);
    IF v_found <> 7 THEN RAISE EXCEPTION 'FAIL: expected 7 helper functions, found %', v_found; END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_tables) t WHERE to_regclass('public.' || t) IS NULL) THEN
        RAISE EXCEPTION 'FAIL: an empadre table is missing';
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
        RAISE EXCEPTION 'FAIL: an empadre table or tool is exposed through crud_models';
    END IF;

    -- Structure: id_company on every row, append-only + tenant triggers, notify stays off.
    IF (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = ANY (v_tables) AND column_name = 'id_company' AND is_nullable = 'NO') <> 3 THEN
        RAISE EXCEPTION 'FAIL: id_company must be NOT NULL on all three empadre tables';
    END IF;
    IF (SELECT count(*) FROM pg_trigger g
         WHERE NOT g.tgisinternal AND g.tgrelid IN ('public.repro_empadre_entries'::regclass, 'public.repro_empadre_voids'::regclass)
           AND g.tgname LIKE 'trg_empadre_%') <> 6 THEN
        RAISE EXCEPTION 'FAIL: expected 6 empadre triggers (append-only, no-truncate, tenant on entries and voids)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_empadre_cfg_notify_off'
                      AND conrelid = 'public.repro_empadre_config'::regclass) THEN
        RAISE EXCEPTION 'FAIL: the notify_enabled = false check is missing';
    END IF;
    IF EXISTS (SELECT 1 FROM public.repro_empadre_config WHERE notify_enabled) THEN
        RAISE EXCEPTION 'FAIL: a company has notify_enabled = true (phase 2b is spec only)';
    END IF;

    -- A real member of a non-palm company to probe the tools (read-only calls; nothing is shown but the company number).
    SELECT uc.id_company, uc.email INTO v_company, v_email
      FROM user_companies uc JOIN companys c ON c.id_company = uc.id_company AND c.is_active
     WHERE uc.is_active AND coalesce(fn_company_business_domain(uc.id_company), '') <> 'PALM'
     ORDER BY uc.id_company LIMIT 1;
    IF v_company IS NULL THEN RAISE EXCEPTION 'FAIL: no active livestock membership to probe'; END IF;
    RAISE NOTICE 'probe: company % (user not shown)', v_company;

    IF v_expect = 'applied' THEN
        v_status := sp_repro_list_open_cows(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_open_cows answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_empadre_get_config(v_company::text, v_email)->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: get_config answered % (expected ok)', v_status; END IF;
        v_status := sp_repro_list_heifers_eligible_for_empadre(v_company::text, v_email, '1')->>'status';
        IF v_status <> 'ok' THEN RAISE EXCEPTION 'FAIL: list_heifers_eligible_for_empadre answered % (expected ok)', v_status; END IF;
        BEGIN
            PERFORM sp_repro_list_open_cows(v_company::text, 'nadie@example.test');
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_blocked := true;  -- expected: fail-closed
        END;
        IF NOT v_blocked THEN RAISE EXCEPTION 'FAIL: a stranger got an answer'; END IF;

        -- a member who is not ADMIN must be refused by set_config (the refusal happens before any write)
        SELECT uc.email INTO v_other FROM user_companies uc
         WHERE uc.id_company = v_company AND uc.is_active AND upper(uc.role) <> 'ADMIN' ORDER BY uc.email LIMIT 1;
        IF v_other IS NOT NULL THEN
            v_status := sp_repro_empadre_set_config(v_company::text, v_other, '15')->>'status';
            IF v_status <> 'forbidden' THEN RAISE EXCEPTION 'FAIL: set_config answered % to a non-ADMIN (expected forbidden)', v_status; END IF;
        ELSE
            RAISE NOTICE 'note: company % has no non-ADMIN member; the forbidden probe was skipped', v_company;
        END IF;
    ELSE
        v_status := sp_repro_list_open_cows(v_company::text, v_email)->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: list_open_cows answered % (expected disabled)', v_status; END IF;
        v_status := sp_repro_log_empadre_entry(v_company::text, v_email, 'x')->>'status';
        IF v_status <> 'disabled' THEN RAISE EXCEPTION 'FAIL: log_empadre_entry answered % (expected disabled)', v_status; END IF;
    END IF;
    RAISE NOTICE '085 state check (%): OK', v_expect;
END $$;

ROLLBACK;
