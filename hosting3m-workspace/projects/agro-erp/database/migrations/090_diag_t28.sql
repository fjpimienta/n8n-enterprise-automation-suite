-- 090_diag_t28.sql — DIAGNOSTIC for test 28 of 090_tests.sql ("B NO APTO alone on a PREÑADA animal ... / vacía NO APTO ...").
--
-- ##########################################################################################################################
-- #  LOCAL / THROWAWAY DATABASE ONLY. DO NOT RUN THIS AGAINST PRODUCTION.                                                  #
-- #  It builds ONLY the fixture of test 28 inside ONE transaction that ENDS IN ROLLBACK (nothing is left behind, and the   #
-- #  script proves it at the end). Even so, never point it at production: a rolled-back write still takes locks and fires  #
-- #  triggers, and SQL cannot tell a throwaway database from production - read the "WHERE AM I" line first.                 #
-- ##########################################################################################################################
--
-- What it does: loads 084 - 088 and 090 inside the transaction (embedded, exactly like the tests; harmless if they are already
-- applied), picks the first active non-palm company and the first user, makes that user an ADMIN of it (inside the transaction),
-- gives the company the same mapping as the tests (NR / RP / NO APTO with meanings, UNE, UTC2), creates two PREÑADA animals
-- (T090D-NP2, T090D-NP3), then makes the two calls of test 28 and prints BOTH answers in full as readable JSON, plus the animal
-- statuses and the palpation / details counts before and after each call. It also evaluates, at the end, the exact comparison the
-- OLD test 28 made ("nothing written since the snapshot taken before the FIRST call") so you can see why it was false.
-- It prints no e-mail.
--
-- Run it from the migrations folder INSIDE the container (it includes the migrations with \ir), like the tests:
--   docker exec n8n-enterprise-db rm -rf /tmp/m090
--   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m090
--   docker exec -w /tmp/m090 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -X -v ON_ERROR_STOP=1 -f /tmp/m090/090_diag_t28.sql > /tmp/090_diag_t28.txt 2>&1

\set ON_ERROR_STOP on
\set embedded true
\pset format unaligned
\pset tuples_only on
\pset footer off
\pset null '(null)'

\echo '################################################################################'
\echo '#  090_diag_t28 - THROWAWAY / LOCAL ONLY - ends in ROLLBACK                    #'
\echo '################################################################################'
\echo '=== WHERE AM I (stop here if this is production)'
SELECT 'database=' || current_database() || '  server_addr=' || coalesce(host(inet_server_addr()), '(unix socket)')
       || '  companies=' || (SELECT count(*) FROM companys) || '  animals=' || (SELECT count(*) FROM cattle_livestock);

BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql
\ir 086_repro_palpation.sql
\ir 087_repro_births.sql
\ir 088_repro_services.sql
\ir 090_repro_vet_code_semantics.sql

CREATE TEMP TABLE d_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
INSERT INTO d_ctx VALUES ('txid', txid_current()::text);

-- the company, the user and the membership (inside the transaction only)
DO $$
DECLARE
    v_a integer;
    v_e text;
BEGIN
    SELECT c.id_company INTO v_a FROM companys c
     WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM' ORDER BY c.id_company LIMIT 1;
    SELECT u.email INTO v_e FROM users u ORDER BY u.email LIMIT 1;
    IF v_a IS NULL OR v_e IS NULL THEN
        RAISE EXCEPTION 'this database needs one active non-palm company and one user';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T090D-%') THEN
        RAISE EXCEPTION 'T090D fixtures already exist here';
    END IF;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e, v_a, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e AND id_company = v_a);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e AND id_company = v_a;
    DELETE FROM repro_condition_codes WHERE id_company = v_a;
    INSERT INTO repro_condition_codes (id_company, code, repro_condition, meaning, source, confirmed_by, confirmed_at) VALUES
        (v_a, 'UNE', 'ESTATICA', NULL, 'T090D', 'T090D', now()),
        (v_a, 'NR', NULL, 'NOT_EXAMINED', 'SEED_090_FOREMAN_CONFIRMED', 'T090D', now()),
        (v_a, 'RP', NULL, 'POSTPARTUM', 'SEED_090_FOREMAN_CONFIRMED', 'T090D', now()),
        (v_a, 'NO APTO', NULL, 'UNFIT', 'SEED_090_FOREMAN_CONFIRMED', 'T090D', now()),
        (v_a, 'UTC2', NULL, NULL, 'pending veterinarian confirmation', NULL, NULL);
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status)
    VALUES (v_a, 'T090D-NP2', 'CRIA', 'VACA', 'PREÑADA'), (v_a, 'T090D-NP3', 'CRIA', 'VACA', 'PREÑADA');
    INSERT INTO d_ctx VALUES ('A', v_a::text), ('u1', v_e);
END $$;

-- the same helpers the tests use (counts and statuses), session-private
CREATE FUNCTION pg_temp.n_det() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM palpation_repro_details $$;
CREATE FUNCTION pg_temp.n_logs() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_health_logs $$;
CREATE FUNCTION pg_temp.st(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT current_status FROM cattle_livestock WHERE rfid_siniiga = 'T090D-' || p_k $$;
CREATE TEMP TABLE d_ans (k text PRIMARY KEY, r jsonb) ON COMMIT DROP;

\echo
\echo '=== BEFORE any call'
SELECT 'palpation_repro_details=' || pg_temp.n_det() || '  health_logs=' || pg_temp.n_logs() || '  T090D-NP2=' || pg_temp.st('NP2') || '  T090D-NP3=' || pg_temp.st('NP3');
-- the snapshot the OLD test took before the first call (test 28 compared against THIS after BOTH calls)
INSERT INTO d_ctx VALUES ('snap_det', pg_temp.n_det()::text), ('snap_logs', pg_temp.n_logs()::text);

-- CALL 1 (test: b15) - "No apto" alone on a PREÑADA animal
INSERT INTO d_ans
SELECT 'call1', sp_repro_log_palpation_batch((SELECT v FROM d_ctx WHERE k = 'A'), (SELECT v FROM d_ctx WHERE k = 'u1'),
                                             '[{"identifier":"T090D-NP2","raw_diagnosis":"No apto"}]', NULL, NULL);
\echo
\echo '=== CALL 1: items = [{"identifier":"T090D-NP2","raw_diagnosis":"No apto"}]  (expected: rejected / NEEDS_EXPLICIT_RESULT)'
SELECT jsonb_pretty(r) FROM d_ans WHERE k = 'call1';
\echo '--- after call 1'
SELECT 'palpation_repro_details=' || pg_temp.n_det() || '  health_logs=' || pg_temp.n_logs() || '  T090D-NP2=' || pg_temp.st('NP2') || '  T090D-NP3=' || pg_temp.st('NP3');
INSERT INTO d_ctx VALUES ('after1_det', pg_temp.n_det()::text), ('after1_logs', pg_temp.n_logs()::text);

-- CALL 2 (test: b15b) - "vacía NO APTO" on a PREÑADA animal
INSERT INTO d_ans
SELECT 'call2', sp_repro_log_palpation_batch((SELECT v FROM d_ctx WHERE k = 'A'), (SELECT v FROM d_ctx WHERE k = 'u1'),
                                             '[{"identifier":"T090D-NP3","raw_diagnosis":"vacía NO APTO"}]', NULL, NULL);
\echo
\echo '=== CALL 2: items = [{"identifier":"T090D-NP3","raw_diagnosis":"vacía NO APTO"}]  (expected: recorded, 1 written, VACÍA, vet_flag UNFIT)'
SELECT jsonb_pretty(r) FROM d_ans WHERE k = 'call2';
\echo '--- after call 2'
SELECT 'palpation_repro_details=' || pg_temp.n_det() || '  health_logs=' || pg_temp.n_logs() || '  T090D-NP2=' || pg_temp.st('NP2') || '  T090D-NP3=' || pg_temp.st('NP3');

\echo
\echo '=== what test 28 asserted, one piece at a time (t = true)'
SELECT 'call1 status = rejected ............................ ' || ((SELECT r->>'status' FROM d_ans WHERE k = 'call1') = 'rejected')
UNION ALL SELECT 'call1 issue code = NEEDS_EXPLICIT_RESULT ........... ' || ((SELECT r->'issues'->0->>'code' FROM d_ans WHERE k = 'call1') = 'NEEDS_EXPLICIT_RESULT')
UNION ALL SELECT 'T090D-NP2 still PREÑADA ......................... ' || (pg_temp.st('NP2') = 'PREÑADA')
UNION ALL SELECT 'call2 status = recorded ......................... ' || ((SELECT r->>'status' FROM d_ans WHERE k = 'call2') = 'recorded')
UNION ALL SELECT 'call2 written = 1 .............................. ' || ((SELECT (r->>'written')::integer FROM d_ans WHERE k = 'call2') = 1)
UNION ALL SELECT 'call2 result_used = VACÍA ....................... ' || ((SELECT r->'results'->0->>'result_used' FROM d_ans WHERE k = 'call2') = 'VACÍA')
UNION ALL SELECT 'call2 vet_flag = UNFIT .......................... ' || ((SELECT r->'results'->0->>'vet_flag' FROM d_ans WHERE k = 'call2') = 'UNFIT')
UNION ALL SELECT 'call2 mapping_status = NOT_APPLICABLE ........... ' || ((SELECT r->'results'->0->>'mapping_status' FROM d_ans WHERE k = 'call2') = 'NOT_APPLICABLE')
UNION ALL SELECT 'T090D-NP3 is now VACÍA ......................... ' || (pg_temp.st('NP3') = 'VACÍA')
UNION ALL SELECT 'OLD test: "nothing written since the snapshot before CALL 1", evaluated after CALL 2 .... ' ||
       ((SELECT v FROM d_ctx WHERE k = 'snap_det')::integer = pg_temp.n_det() AND (SELECT v FROM d_ctx WHERE k = 'snap_logs')::integer = pg_temp.n_logs())
UNION ALL SELECT 'same check evaluated right after CALL 1 (what the test meant) ...... ' ||
       ((SELECT v FROM d_ctx WHERE k = 'snap_det')::integer = (SELECT v FROM d_ctx WHERE k = 'after1_det')::integer
        AND (SELECT v FROM d_ctx WHERE k = 'snap_logs')::integer = (SELECT v FROM d_ctx WHERE k = 'after1_logs')::integer);

\echo
\echo '=== proof that nothing is left behind: this must be 0 after the ROLLBACK (checked in the next statement)'
SELECT 'same transaction as the start: ' || (txid_current()::text = (SELECT v FROM d_ctx WHERE k = 'txid'));
ROLLBACK;
SELECT 'fixture animals left behind (must be 0): ' || count(*) FROM cattle_livestock WHERE rfid_siniiga LIKE 'T090D-%';
\echo '*** 090_diag_t28: everything rolled back ***'
