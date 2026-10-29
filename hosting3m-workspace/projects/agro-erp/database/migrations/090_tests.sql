-- 090_tests.sql — functional checks for migration 090 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It loads 084 - 088 and then 090 inside this transaction (embedded mode). Same requirements as 088_tests.sql: a database with the real
-- schema, AT LEAST two ACTIVE non-palm companies and two users, and NO palpations in those two companies (a schema-only copy; see
-- 090_RUNBOOK.md, "Test database"). Memberships are arranged INSIDE the transaction:
--     user 1: ACTIVE ADMIN of A, INACTIVE in B        user 2: ACTIVE ADMIN of B, INACTIVE in A
-- Fixture animals use identifiers prefixed T090. Every write goes through pg_temp.call(key, sql) in its own statement and is asserted
-- in the NEXT statement (a statement never sees rows its own write functions created). Every assertion goes through pg_temp.t(), which
-- records an error as a FAIL with its SQLSTATE, and every FAIL fills the `detail` column.
--
-- Company A gets the mapping the seed would give company 5, replicated INSIDE the transaction (the seed file itself targets company 5):
--     UNE ESTATICA, UTCL1-3 CICLANDO, NR NOT_EXAMINED, RP POSTPARTUM, NO APTO UNFIT, UTC2 pending, and a pending MATRIZ OCUPADA row
--     (the leftover of the 086 seed: it must NOT matter, the phrase is fixed). Company B only has UNE.
--
-- Part A  pure functions: diagnosis kind, meaning, code info, parser unchanged (N/A), column CHECKs
-- Part B  log_palpation_with_condition: MATRIZ OCUPADA, NR, RP, NO APTO, UTC2, conflicts, birth flag, isolation, regression
-- Part C  the read tools: list_palpation_due, list_upcoming_calvings, dam history flags, list_unmapped_uterine_codes
-- Part D  condition_code_set
-- Part E  fail-closed
-- Part F  nothing else was written
--
-- Run (the test files must be INSIDE the container):
--   docker exec n8n-enterprise-db rm -rf /tmp/m090
--   docker cp database/migrations n8n-enterprise-db:/tmp/m090
--   docker exec -w /tmp/m090 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m090/090_tests.sql

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql
\ir 086_repro_palpation.sql
\ir 087_repro_births.sql
\ir 088_repro_services.sql

-- The functions 090 must NOT touch, fingerprinted BEFORE 090 is loaded (compared again at the end of the run).
CREATE TEMP TABLE t_proc_before ON COMMIT DROP AS
SELECT p.oid::regprocedure::text AS sig, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('sp_log_palpation_event', 'sp_register_birth_event', 'sp_log_breeding_event', 'sp_void_event',
                     'fn_uterine_split', 'fn_parse_uterine_code', 'fn_repro_palpations', 'fn_repro_norm_code', 'fn_trg_palp_details_tenant',
                     'fn_repro_birth_window_matches', 'fn_repro_ctx', 'sp_repro_empadre_get_config');

\ir 090_repro_vet_code_semantics.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE t_res (k text PRIMARY KEY, r jsonb) ON COMMIT DROP;
INSERT INTO t_ctx VALUES ('txid', txid_current()::text);

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

-- Runs ONE assertion given as SQL text. An error inside the expression (including assert_failure / P0004, which `WHEN OTHERS` alone
-- does not catch) is recorded as a FAIL with the SQLSTATE and message instead of aborting the script. p_detail is SQL text too: it is
-- evaluated only when the assertion fails, and its value goes to the detail column.
CREATE FUNCTION pg_temp.t(p_test text, p_expr text, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v boolean;
    d text;
BEGIN
    BEGIN
        EXECUTE 'SELECT (' || p_expr || ')::boolean' INTO v;
    EXCEPTION WHEN assert_failure THEN
        v := false; d := 'ERROR ' || SQLSTATE || ': ' || SQLERRM;
    WHEN OTHERS THEN
        v := false; d := 'ERROR ' || SQLSTATE || ': ' || SQLERRM;
    END;
    IF d IS NULL AND NOT coalesce(v, false) THEN
        IF p_detail IS NULL THEN
            d := 'expression returned ' || coalesce(v::text, 'NULL');
        ELSE
            BEGIN
                EXECUTE 'SELECT (' || p_detail || ')::text' INTO d;
            EXCEPTION WHEN OTHERS THEN
                d := 'detail error: ' || SQLERRM;
            END;
        END IF;
    END IF;
    INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(v, false), d);
END $$;

CREATE FUNCTION pg_temp.cx(p_key text) RETURNS text
LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;
-- An error inside a tool call is stored as {"__error", "__sqlstate"} (the call's own writes are rolled back) instead of aborting the
-- script: the assertions that depend on it then FAIL one by one.
CREATE FUNCTION pg_temp.call(p_key text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    BEGIN
        EXECUTE p_sql INTO v;
    EXCEPTION WHEN assert_failure THEN
        v := jsonb_build_object('__error', SQLERRM, '__sqlstate', SQLSTATE);
    WHEN OTHERS THEN
        v := jsonb_build_object('__error', SQLERRM, '__sqlstate', SQLSTATE);
    END;
    INSERT INTO t_res (k, r) VALUES (p_key, v);
END $$;
CREATE FUNCTION pg_temp.rs(p_key text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT r FROM t_res WHERE k = p_key $$;
-- NOTE: `WHEN OTHERS` does NOT catch assert_failure (SQLSTATE P0004): it is named explicitly.
CREATE FUNCTION pg_temp.raises(p_sql text, p_state text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN assert_failure THEN
    RETURN SQLSTATE = p_state;
WHEN OTHERS THEN
    RETURN SQLSTATE = p_state;
END $$;

-- items for the wrapper: pairs (animal key, raw diagnosis); the identifier is 'T090-' || key
CREATE FUNCTION pg_temp.items(VARIADIC p text[]) RETURNS text
LANGUAGE sql AS $$
    SELECT jsonb_agg(jsonb_build_object('identifier', 'T090-' || p[i], 'raw_diagnosis', p[i + 1]) ORDER BY i)::text
      FROM generate_series(1, array_length(p, 1), 2) AS i
$$;
CREATE FUNCTION pg_temp.plog(p_key text, p_items text, p_date text DEFAULT NULL,
                             p_who text DEFAULT 'u1', p_company text DEFAULT 'A') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_log_palpation_batch(%L, %L, %L, %L, NULL)',
                                       pg_temp.cx(p_company), pg_temp.cx(p_who), p_items, p_date));
END $$;
-- the element of results[] / issues[] for an animal key
CREATE FUNCTION pg_temp.rl(p_key text, p_animal text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT e FROM jsonb_array_elements(pg_temp.rs(p_key)->'results') e WHERE e->>'identifier' = 'T090-' || p_animal $$;
CREATE FUNCTION pg_temp.iss(p_key text, p_animal text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT e FROM jsonb_array_elements(pg_temp.rs(p_key)->'issues') e WHERE e->>'identifier' = 'T090-' || p_animal $$;
-- a fixture animal's latest details row
CREATE FUNCTION pg_temp.det(p_animal text) RETURNS jsonb
LANGUAGE sql AS $$
    SELECT to_jsonb(d) FROM palpation_repro_details d JOIN cattle_livestock l ON l.id = d.livestock_id
     WHERE l.rfid_siniiga = 'T090-' || p_animal ORDER BY d.created_at DESC, d.id LIMIT 1
$$;
CREATE FUNCTION pg_temp.n_det() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM palpation_repro_details $$;
CREATE FUNCTION pg_temp.n_logs() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_health_logs $$;
CREATE FUNCTION pg_temp.status_of(p_animal text) RETURNS text
LANGUAGE sql AS $$ SELECT current_status FROM cattle_livestock WHERE rfid_siniiga = 'T090-' || p_animal $$;
CREATE FUNCTION pg_temp.category_of(p_animal text) RETURNS text
LANGUAGE sql AS $$ SELECT category FROM cattle_livestock WHERE rfid_siniiga = 'T090-' || p_animal $$;
CREATE FUNCTION pg_temp.aid(p_animal text) RETURNS uuid
LANGUAGE sql AS $$ SELECT id FROM cattle_livestock WHERE rfid_siniiga = 'T090-' || p_animal $$;
-- snapshot counters (a statement never sees its own writes, so the counts are stored by a statement of their own)
CREATE FUNCTION pg_temp.snap(p_key text) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_ctx VALUES (p_key || '_det', pg_temp.n_det()::text), (p_key || '_logs', pg_temp.n_logs()::text) $$;
CREATE FUNCTION pg_temp.same(p_key text) RETURNS boolean
LANGUAGE sql AS $$ SELECT pg_temp.cx(p_key || '_det')::integer = pg_temp.n_det() AND pg_temp.cx(p_key || '_logs')::integer = pg_temp.n_logs() $$;
CREATE FUNCTION pg_temp.kind(p_text text, p_company text DEFAULT 'A') RETURNS text
LANGUAGE sql AS $$ SELECT fn_repro_diagnosis_kind(p_text, pg_temp.cx(p_company)::integer) $$;
-- parser result as 'raw|side|condition|status' (empty string for NULL)
CREATE FUNCTION pg_temp.pc(p_text text, p_tenant text DEFAULT NULL) RETURNS text
LANGUAGE sql AS $$
    SELECT concat_ws('|', coalesce(raw_code, ''), coalesce(ovary_side, ''), coalesce(repro_condition, ''), mapping_status)
      FROM fn_parse_uterine_code(p_text, p_tenant::integer)
$$;
-- code info as 'code|vet_flag|pregnant|nr_composite|unknown_tokens'
CREATE FUNCTION pg_temp.ci(p_text text, p_company text DEFAULT 'A') RETURNS text
LANGUAGE sql AS $$
    SELECT concat_ws('|', coalesce(uterine_code, ''), coalesce(vet_flag, ''), CASE WHEN means_pregnant THEN 't' ELSE 'f' END,
                     CASE WHEN nr_composite THEN 't' ELSE 'f' END, unknown_tokens::text)
      FROM fn_repro_palp_code_info(pg_temp.cx(p_company)::integer, p_text)
$$;
CREATE FUNCTION pg_temp.setrole(p_email text, p_company text, p_role text) RETURNS void
LANGUAGE sql AS $$ UPDATE user_companies SET role = p_role WHERE email = p_email AND id_company = p_company::integer $$;
-- an element of a result array of a stored tool answer, by animal
CREATE FUNCTION pg_temp.row_of(p_key text, p_array text, p_animal text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT e FROM jsonb_array_elements(pg_temp.rs(p_key)->p_array) e WHERE e->>'livestock_id' = pg_temp.aid(p_animal)::text $$;
-- does a stored answer's array of objects contain an element whose `key` equals p_val?
CREATE FUNCTION pg_temp.has_code(p_key text, p_array text, p_val text, p_field text DEFAULT 'code') RETURNS boolean
LANGUAGE sql AS $$ SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.rs(p_key)->p_array) e WHERE e->>p_field = p_val) $$;
CREATE FUNCTION pg_temp.elem(p_key text, p_array text, p_val text, p_field text DEFAULT 'code') RETURNS jsonb
LANGUAGE sql AS $$ SELECT e FROM jsonb_array_elements(pg_temp.rs(p_key)->p_array) e WHERE e->>p_field = p_val LIMIT 1 $$;

-- =============================================================================================================
-- Setup
-- =============================================================================================================

DO $$
DECLARE
    v_a  integer;
    v_b  integer;
    v_e1 text;
    v_e2 text;
BEGIN
    SELECT c.id_company INTO v_a FROM companys c
     WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM' ORDER BY c.id_company LIMIT 1;
    SELECT c.id_company INTO v_b FROM companys c
     WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM' AND c.id_company <> v_a ORDER BY c.id_company LIMIT 1;
    IF v_a IS NULL OR v_b IS NULL THEN
        RAISE EXCEPTION '090 tests need two active non-palm companies in the database (see 090_RUNBOOK.md, Test database).';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '090 tests need two users in the database (see 090_RUNBOOK.md, Test database).';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T090%') THEN
        RAISE EXCEPTION '090 tests: T090 fixtures already exist in this database; run the tests on a clean copy.';
    END IF;
    IF EXISTS (SELECT 1 FROM fn_repro_palpations(v_a)) OR EXISTS (SELECT 1 FROM fn_repro_palpations(v_b)) THEN
        RAISE EXCEPTION '090 tests need companies A and B WITHOUT palpations (the import-date flag counts them): use the schema-only copy.';
    END IF;

    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e1, v_a, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e1 AND id_company = v_a);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e1 AND id_company = v_a;
    UPDATE user_companies SET is_active = false WHERE email = v_e1 AND id_company = v_b;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e2, v_b, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e2 AND id_company = v_b);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e2 AND id_company = v_b;
    UPDATE user_companies SET is_active = false WHERE email = v_e2 AND id_company = v_a;

    DELETE FROM repro_condition_codes WHERE id_company IN (v_a, v_b);
    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

-- the mapping of company A (the veterinarians' four codes + the foreman's three meanings + the pending ones)
INSERT INTO repro_condition_codes (id_company, code, repro_condition, meaning, source, confirmed_by, confirmed_at) VALUES
    (pg_temp.cx('A')::integer, 'UNE',   'ESTATICA', NULL, 'T090 vet', 'T090 vet', now()),
    (pg_temp.cx('A')::integer, 'UTCL1', 'CICLANDO', NULL, 'T090 vet', 'T090 vet', now()),
    (pg_temp.cx('A')::integer, 'UTCL2', 'CICLANDO', NULL, 'T090 vet', 'T090 vet', now()),
    (pg_temp.cx('A')::integer, 'UTCL3', 'CICLANDO', NULL, 'T090 vet', 'T090 vet', now()),
    (pg_temp.cx('A')::integer, 'NR',      NULL, 'NOT_EXAMINED', 'SEED_090_FOREMAN_CONFIRMED', 'T090 capataz', now()),
    (pg_temp.cx('A')::integer, 'RP',      NULL, 'POSTPARTUM',   'SEED_090_FOREMAN_CONFIRMED', 'T090 capataz', now()),
    (pg_temp.cx('A')::integer, 'NO APTO', NULL, 'UNFIT',        'SEED_090_FOREMAN_CONFIRMED', 'T090 capataz', now()),
    (pg_temp.cx('A')::integer, 'UTC2',           NULL, NULL, 'pending veterinarian confirmation', NULL, NULL),
    (pg_temp.cx('A')::integer, 'MATRIZ OCUPADA', NULL, NULL, 'pending veterinarian confirmation', NULL, NULL);
INSERT INTO repro_condition_codes (id_company, code, repro_condition, meaning, source, confirmed_by, confirmed_at) VALUES
    (pg_temp.cx('B')::integer, 'UNE', 'ESTATICA', NULL, 'T090 vet', 'T090 vet', now());

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_key text, p_cat text, p_status text) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status)
    VALUES (p_tenant, 'T090-' || p_key, 'CRIA', p_cat, p_status)
    RETURNING id
$$;
-- a palpation written directly, as the 2023 bulk load did (Spanish keys + condicion_utero)
CREATE FUNCTION pg_temp.pal(p_id uuid, p_days_ago integer, p_result text, p_gest text DEFAULT NULL, p_cond text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
    VALUES (p_id, 'PALPACION', 'T090 fixture',
            jsonb_strip_nulls(jsonb_build_object('resultado', p_result, 'dias_gestacion', p_gest, 'condicion_utero', p_cond)),
            fn_repro_today()::timestamp - make_interval(days => p_days_ago))
$$;

DO $$
DECLARE
    v_a  integer := pg_temp.cx('A')::integer;
    v_b  integer := pg_temp.cx('B')::integer;
    v_id uuid;
    v_k  text;
BEGIN
    -- animals the wrapper will palpate (ACTIVO unless said otherwise)
    FOREACH v_k IN ARRAY ARRAY['A-MO1','A-MO2','A-MO3','A-MO4','A-NR1','A-NR2','A-NR3','A-NR4','A-V1','A-V2','A-V3','A-V4','A-V5','A-V6',
                               'A-RP1','A-RP4','A-RPB1','A-RPB2','A-NP1','A-UT1','A-RETRY'] LOOP
        v_id := pg_temp.mk(v_a, v_k, 'VACA', 'ACTIVO');
    END LOOP;
    FOREACH v_k IN ARRAY ARRAY['A-RP2','A-RP3','A-NP2','A-NP3','A-UT2','A-RP5','A-UE1','A-UE2','A-UL1','A-UC1','A-UC2','A-NRP'] LOOP
        v_id := pg_temp.mk(v_a, v_k, 'VACA', 'PREÑADA');
    END LOOP;
    v_id := pg_temp.mk(v_a, 'A-NRSOLD', 'VACA', 'VENDIDO');
    -- bulk-loaded palpations (read side)
    v_id := pg_temp.mk(v_a, 'A-DU1', 'VACA', 'PREÑADA'); PERFORM pg_temp.pal(v_id, 120, 'VACIA', NULL, 'RP');
    v_id := pg_temp.mk(v_a, 'A-DU2', 'VACA', 'PREÑADA'); PERFORM pg_temp.pal(v_id, 120, 'VACIA', NULL, 'MATRIZ OCUPADA');
    v_id := pg_temp.mk(v_a, 'A-CV1', 'VACA', 'PREÑADA'); PERFORM pg_temp.pal(v_id, 100, 'PRENADA', '240', NULL); PERFORM pg_temp.pal(v_id, 10, 'VACIA', NULL, 'RP');
    v_id := pg_temp.mk(v_a, 'A-HD1', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'MATRIZ OCUPADA');
    v_id := pg_temp.mk(v_a, 'A-HD2', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'RP');
    v_id := pg_temp.mk(v_a, 'A-HD3', 'VACA', 'PREÑADA'); PERFORM pg_temp.pal(v_id, 200, 'PRENADA', NULL, 'N/A');
    v_id := pg_temp.mk(v_a, 'A-HD4', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'UNE/NR');
    v_id := pg_temp.mk(v_a, 'A-HD5', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'NR');
    v_id := pg_temp.mk(v_a, 'A-UN1', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'NO APTO');
    v_id := pg_temp.mk(v_a, 'A-UN2', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'UTC2/OD');
    v_id := pg_temp.mk(v_a, 'A-UN3', 'VACA', 'VACÍA');   PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'ZZZ');
    -- registered births around the RP animals: RPB1 gave birth 30 days ago, RPB2 200 days ago
    INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, entered_by_email)
    VALUES (v_a, pg_temp.aid('A-RPB1'), fn_repro_today() - 30, 'DAY', 'T090'),
           (v_a, pg_temp.aid('A-RPB2'), fn_repro_today() - 200, 'DAY', 'T090');
    -- company B
    v_id := pg_temp.mk(v_b, 'B-BM1', 'VACA', 'ACTIVO');
    v_id := pg_temp.mk(v_b, 'B-BN1', 'VACA', 'ACTIVO');
    v_id := pg_temp.mk(v_b, 'B-BN2', 'VACA', 'ACTIVO');
    v_id := pg_temp.mk(v_b, 'B-BU1', 'VACA', 'VACÍA');  PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'NR');
    v_id := pg_temp.mk(v_b, 'B-BU2', 'VACA', 'VACÍA');  PERFORM pg_temp.pal(v_id, 200, 'VACIA', NULL, 'RP');
END $$;

-- From here on an unexpected error in a statement does not stop the run: psql rolls back to a savepoint of that statement only
-- (ON_ERROR_ROLLBACK) and goes on, and every assertion runs inside pg_temp.t(), which records errors as FAILs.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

-- =============================================================================================================
-- PART A. pure functions
-- =============================================================================================================

SELECT pg_temp.t('A MATRIZ OCUPADA is a PREÑADA phrase for every company (also without a company), case / accent / spacing insensitive, with months',
    $qq$pg_temp.kind('MATRIZ OCUPADA') = 'PRENADA' AND pg_temp.kind('Matriz  ocupada', 'B') = 'PRENADA'
        AND pg_temp.kind('matriz ocupada 3 meses') = 'PRENADA' AND fn_repro_diagnosis_kind('MATRIZ OCUPADA', NULL) = 'PRENADA'$qq$,
    $qq$concat_ws(',', pg_temp.kind('MATRIZ OCUPADA'), pg_temp.kind('Matriz  ocupada', 'B'), pg_temp.kind('matriz ocupada 3 meses'), fn_repro_diagnosis_kind('MATRIZ OCUPADA', NULL))$qq$);
SELECT pg_temp.t('A MATRIZ OCUPADA together with VACIA / an explicit word / RP / NO APTO is a CONFLICT; so is RP or NO APTO with a PREÑADA word',
    $qq$pg_temp.kind('VACIA MATRIZ OCUPADA') = 'CONFLICT' AND pg_temp.kind('ciclando matriz ocupada') = 'CONFLICT'
        AND pg_temp.kind('MATRIZ OCUPADA RP') = 'CONFLICT' AND pg_temp.kind('PREÑADA RP') = 'CONFLICT' AND pg_temp.kind('PREÑADA NO APTO') = 'CONFLICT'
        AND pg_temp.kind('PREÑADA/RP') = 'CONFLICT'$qq$,
    $qq$concat_ws(',', pg_temp.kind('VACIA MATRIZ OCUPADA'), pg_temp.kind('ciclando matriz ocupada'), pg_temp.kind('MATRIZ OCUPADA RP'), pg_temp.kind('PREÑADA RP'), pg_temp.kind('PREÑADA NO APTO'), pg_temp.kind('PREÑADA/RP'))$qq$);
SELECT pg_temp.t('A NR alone is NOT_EXAMINED for a company that has the meaning, UNRECOGNIZED for one that does not and without a company',
    $qq$pg_temp.kind('NR') = 'NOT_EXAMINED' AND pg_temp.kind('nr') = 'NOT_EXAMINED' AND pg_temp.kind('NR', 'B') = 'UNRECOGNIZED'
        AND fn_repro_diagnosis_kind('NR', NULL) = 'UNRECOGNIZED'$qq$,
    $qq$concat_ws(',', pg_temp.kind('NR'), pg_temp.kind('nr'), pg_temp.kind('NR', 'B'), fn_repro_diagnosis_kind('NR', NULL))$qq$);
SELECT pg_temp.t('A NR inside a composite (UNE/NR) is a normal CODE: unchanged from 086',
    $qq$pg_temp.kind('UNE/NR') = 'CODE'$qq$, $qq$pg_temp.kind('UNE/NR')$qq$);
SELECT pg_temp.t('A RP / NO APTO without a result word are CODE_FLAG; with an explicit VACIA word they are VACIA; unknown for a company without the meaning',
    $qq$pg_temp.kind('RP') = 'CODE_FLAG' AND pg_temp.kind('No apto') = 'CODE_FLAG' AND pg_temp.kind('RP/OI') = 'CODE_FLAG'
        AND pg_temp.kind('VACIA RP') = 'VACIA' AND pg_temp.kind('vacía NO APTO') = 'VACIA'
        AND pg_temp.kind('RP', 'B') = 'UNRECOGNIZED' AND pg_temp.kind('NO APTO', 'B') = 'UNRECOGNIZED'$qq$,
    $qq$concat_ws(',', pg_temp.kind('RP'), pg_temp.kind('No apto'), pg_temp.kind('RP/OI'), pg_temp.kind('VACIA RP'), pg_temp.kind('vacía NO APTO'), pg_temp.kind('RP', 'B'), pg_temp.kind('NO APTO', 'B'))$qq$);
SELECT pg_temp.t('A UTC2 (pending) and the vet codes stay plain CODE kinds',
    $qq$pg_temp.kind('UTC2') = 'CODE' AND pg_temp.kind('UNE') = 'CODE' AND pg_temp.kind('UTCL2/OI') = 'CODE' AND pg_temp.kind('UTC2/OD') = 'CODE'$qq$,
    $qq$concat_ws(',', pg_temp.kind('UTC2'), pg_temp.kind('UNE'), pg_temp.kind('UTCL2/OI'), pg_temp.kind('UTC2/OD'))$qq$);
SELECT pg_temp.t('A the explicit words and the rejections are unchanged (PREÑADA, VACIA, ciclando, estática, PREÑDA, ok, pre, xyz, N/A, empty, NULL)',
    $qq$pg_temp.kind('PREÑADA') = 'PRENADA' AND pg_temp.kind('PREÑADA 3 MESES') = 'PRENADA' AND pg_temp.kind('VACIA') = 'VACIA' AND pg_temp.kind('vacía') = 'VACIA'
        AND pg_temp.kind('ciclando') = 'VACIA' AND pg_temp.kind('estática') = 'VACIA' AND pg_temp.kind('PREÑADA ciclando') = 'CONFLICT'
        AND pg_temp.kind('PREÑDA') = 'UNRECOGNIZED' AND pg_temp.kind('ok') = 'UNRECOGNIZED' AND pg_temp.kind('pre') = 'UNRECOGNIZED'
        AND pg_temp.kind('xyz') = 'UNRECOGNIZED' AND pg_temp.kind('N/A') = 'UNRECOGNIZED' AND pg_temp.kind('') = 'UNRECOGNIZED'
        AND fn_repro_diagnosis_kind(NULL, pg_temp.cx('A')::integer) = 'UNRECOGNIZED'$qq$,
    $qq$concat_ws(',', pg_temp.kind('PREÑADA'), pg_temp.kind('VACIA'), pg_temp.kind('ciclando'), pg_temp.kind('PREÑADA ciclando'), pg_temp.kind('PREÑDA'), pg_temp.kind('N/A'), pg_temp.kind(''))$qq$);
SELECT pg_temp.t('A fn_repro_code_meaning: the phrase is PREGNANT for every company even next to a pending row; RP / NR / NO APTO only where configured; UTC2 and UNE have none',
    $qq$fn_repro_code_meaning(pg_temp.cx('A')::integer, 'MATRIZ OCUPADA') = 'PREGNANT' AND fn_repro_code_meaning(pg_temp.cx('B')::integer, 'MATRIZ OCUPADA') = 'PREGNANT'
        AND fn_repro_code_meaning(NULL, 'MATRIZ OCUPADA') = 'PREGNANT'
        AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'RP') = 'POSTPARTUM' AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'NR') = 'NOT_EXAMINED'
        AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'NO APTO') = 'UNFIT' AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'no  apto') = 'UNFIT'
        AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'UTC2') IS NULL AND fn_repro_code_meaning(pg_temp.cx('A')::integer, 'UNE') IS NULL
        AND fn_repro_code_meaning(pg_temp.cx('B')::integer, 'RP') IS NULL AND fn_repro_code_meaning(NULL, 'RP') IS NULL$qq$);
SELECT pg_temp.t('A fn_repro_palp_code_info: flags, composite NR, unknown tokens, the phrase, N/A and NULL',
    $qq$pg_temp.ci('RP') = 'RP|POSTPARTUM|f|f|0' AND pg_temp.ci('NO APTO') = 'NO APTO|UNFIT|f|f|0' AND pg_temp.ci('NR') = 'NR|NOT_EXAMINED|f|f|0'
        AND pg_temp.ci('UNE/NR') = 'UNE/NR||f|t|0' AND pg_temp.ci('RP/XYZ') = 'RP/XYZ|POSTPARTUM|f|f|1' AND pg_temp.ci('MATRIZ OCUPADA') = 'MATRIZ OCUPADA||t|f|0'
        AND pg_temp.ci('MATRIZ OCUPADA 3 MESES') LIKE '%|t|f|%' AND pg_temp.ci('UTC2') = 'UTC2||f|f|0' AND pg_temp.ci('VACIA UTCL2/OI') = 'UTCL2/OI||f|f|0'
        AND pg_temp.ci('N/A') = '||f|f|0' AND pg_temp.ci(NULL) = '||f|f|0' AND pg_temp.ci('RP', 'B') = 'RP||f|f|1'$qq$,
    $qq$concat_ws(' ; ', pg_temp.ci('RP'), pg_temp.ci('NO APTO'), pg_temp.ci('NR'), pg_temp.ci('UNE/NR'), pg_temp.ci('RP/XYZ'), pg_temp.ci('MATRIZ OCUPADA'), pg_temp.ci('MATRIZ OCUPADA 3 MESES'), pg_temp.ci('UTC2'), pg_temp.ci('N/A'), pg_temp.ci('RP', 'B'))$qq$);
SELECT pg_temp.t('A the parser is untouched: N/A is still "no code", UNE/NR is UNMAPPED, a vet code maps as before, RP alone stays UNMAPPED at parser level',
    $qq$pg_temp.pc('N/A', pg_temp.cx('A')) = '|||NOT_APPLICABLE' AND pg_temp.pc('UNE/NR', pg_temp.cx('A')) = 'UNE/NR|||UNMAPPED'
        AND pg_temp.pc('UTCL2/OI', pg_temp.cx('A')) = 'UTCL2/OI|OI|CICLANDO|MAPPED' AND pg_temp.pc('RP', pg_temp.cx('A')) = 'RP|||UNMAPPED'$qq$,
    $qq$concat_ws(' ; ', pg_temp.pc('N/A', pg_temp.cx('A')), pg_temp.pc('UNE/NR', pg_temp.cx('A')), pg_temp.pc('UTCL2/OI', pg_temp.cx('A')), pg_temp.pc('RP', pg_temp.cx('A')))$qq$);
SELECT pg_temp.t('A the CHECKs: a code with a meaning cannot get a condition, and an unknown meaning is refused (23514)',
    $qq$pg_temp.raises(format('UPDATE repro_condition_codes SET repro_condition = ''OTRO'' WHERE id_company = %s AND code = ''RP''', pg_temp.cx('A')), '23514')
        AND pg_temp.raises(format('INSERT INTO repro_condition_codes (id_company, code, meaning, source) VALUES (%s, ''ZZMEAN'', ''FOO'', ''T090'')', pg_temp.cx('A')), '23514')
        AND pg_temp.raises(format('INSERT INTO repro_condition_codes (id_company, code, repro_condition, meaning, source, confirmed_by) VALUES (%s, ''ZZMEAN2'', ''OTRO'', ''UNFIT'', ''T090'', ''T090'')', pg_temp.cx('A')), '23514')$qq$);

-- =============================================================================================================
-- PART B. log_palpation_with_condition
-- =============================================================================================================

-- B1 MATRIZ OCUPADA alone
SELECT pg_temp.snap('b1');
SELECT pg_temp.plog('b1', pg_temp.items('A-MO1', 'MATRIZ OCUPADA'));
SELECT pg_temp.t('B MATRIZ OCUPADA alone is recorded as PREÑADA (never VACÍA), no gestation days needed, and the animal becomes PREÑADA',
    $qq$pg_temp.rs('b1')->>'status' = 'recorded' AND (pg_temp.rs('b1')->>'written')::integer = 1 AND pg_temp.rl('b1', 'A-MO1')->>'result_used' = 'PREÑADA'
        AND pg_temp.rl('b1', 'A-MO1')->>'gestation_days_used' IS NULL AND pg_temp.rl('b1', 'A-MO1')->>'line_status' = 'recorded'
        AND pg_temp.status_of('A-MO1') = 'PREÑADA'$qq$,
    $qq$pg_temp.rs('b1')::text || ' status=' || coalesce(pg_temp.status_of('A-MO1'), 'NULL')$qq$);
SELECT pg_temp.t('B the details row of MATRIZ OCUPADA: PREÑADA, wording kept in raw_code, no condition, NOT_APPLICABLE',
    $qq$pg_temp.det('A-MO1')->>'result' = 'PREÑADA' AND pg_temp.det('A-MO1')->>'raw_code' = 'MATRIZ OCUPADA' AND pg_temp.det('A-MO1')->>'repro_condition' IS NULL
        AND pg_temp.det('A-MO1')->>'mapping_status' = 'NOT_APPLICABLE'$qq$, $qq$pg_temp.det('A-MO1')::text$qq$);

-- B2 with months
SELECT pg_temp.plog('b2', pg_temp.items('A-MO2', 'MATRIZ OCUPADA 3 MESES'));
SELECT pg_temp.t('B MATRIZ OCUPADA 3 MESES is PREÑADA with 90 gestation days',
    $qq$pg_temp.rs('b2')->>'status' = 'recorded' AND pg_temp.rl('b2', 'A-MO2')->>'result_used' = 'PREÑADA' AND (pg_temp.rl('b2', 'A-MO2')->>'gestation_days_used')::integer = 90
        AND pg_temp.status_of('A-MO2') = 'PREÑADA'$qq$, $qq$pg_temp.rs('b2')::text$qq$);

-- B3 conflict
SELECT pg_temp.snap('b3');
SELECT pg_temp.plog('b3', pg_temp.items('A-MO3', 'VACIA MATRIZ OCUPADA'));
SELECT pg_temp.t('B VACIA + MATRIZ OCUPADA is a DIAGNOSIS_CONFLICT: nothing written, the animal keeps its status',
    $qq$pg_temp.rs('b3')->>'status' = 'rejected' AND pg_temp.iss('b3', 'A-MO3')->>'code' = 'DIAGNOSIS_CONFLICT' AND (pg_temp.rs('b3')->>'written')::integer = 0
        AND pg_temp.status_of('A-MO3') = 'ACTIVO' AND pg_temp.same('b3')$qq$, $qq$pg_temp.rs('b3')::text$qq$);

-- B4 regression: a plain PREÑADA with months keeps its details unchanged
SELECT pg_temp.plog('b4', pg_temp.items('A-MO4', 'PREÑADA 4 MESES'));
SELECT pg_temp.t('B regression: PREÑADA 4 MESES is PREÑADA with 120 days, no raw code, NOT_APPLICABLE',
    $qq$pg_temp.rl('b4', 'A-MO4')->>'result_used' = 'PREÑADA' AND (pg_temp.rl('b4', 'A-MO4')->>'gestation_days_used')::integer = 120
        AND pg_temp.det('A-MO4')->>'raw_code' IS NULL AND pg_temp.det('A-MO4')->>'mapping_status' = 'NOT_APPLICABLE'$qq$, $qq$pg_temp.rs('b4')::text || pg_temp.det('A-MO4')::text$qq$);

-- B5 NR alone
SELECT pg_temp.snap('b5');
SELECT pg_temp.plog('b5', pg_temp.items('A-NR1', 'NR'));
SELECT pg_temp.t('B a batch of only NR lines answers recorded with written 0; the line is not_examined; no palpation, no details row, no status change',
    $qq$pg_temp.rs('b5')->>'status' = 'recorded' AND (pg_temp.rs('b5')->>'written')::integer = 0 AND (pg_temp.rs('b5')->>'not_examined')::integer = 1
        AND pg_temp.rs('b5')->'not_examined_lines'->0->>'line_status' = 'not_examined' AND pg_temp.rs('b5')->'not_examined_lines'->0->>'identifier' = 'T090-A-NR1'
        AND pg_temp.status_of('A-NR1') = 'ACTIVO' AND pg_temp.same('b5') AND pg_temp.det('A-NR1') IS NULL$qq$, $qq$pg_temp.rs('b5')::text$qq$);

-- B6 NR with a valid line: the other line is processed
SELECT pg_temp.plog('b6', pg_temp.items('A-NR2', 'NR', 'A-V1', 'VACIA UTCL2/OI'));
SELECT pg_temp.t('B NR next to a valid line: the other line is written (VACÍA, CICLANDO, side OI), the NR animal is untouched',
    $qq$pg_temp.rs('b6')->>'status' = 'recorded' AND (pg_temp.rs('b6')->>'written')::integer = 1 AND (pg_temp.rs('b6')->>'not_examined')::integer = 1
        AND pg_temp.rl('b6', 'A-V1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b6', 'A-V1')->>'repro_condition' = 'CICLANDO' AND pg_temp.rl('b6', 'A-V1')->>'ovary_side' = 'OI'
        AND pg_temp.status_of('A-V1') = 'VACÍA' AND pg_temp.status_of('A-NR2') = 'ACTIVO' AND pg_temp.det('A-NR2') IS NULL$qq$, $qq$pg_temp.rs('b6')::text$qq$);

-- B7 NR line is still validated: unknown animal rejects the whole batch
SELECT pg_temp.snap('b7');
SELECT pg_temp.plog('b7', pg_temp.items('A-NOPE', 'NR', 'A-V2', 'VACIA'));
SELECT pg_temp.t('B an NR line is still validated: an unknown identifier rejects the whole batch (ANIMAL_NOT_FOUND), the valid line is not written',
    $qq$pg_temp.rs('b7')->>'status' = 'rejected' AND pg_temp.iss('b7', 'A-NOPE')->>'code' = 'ANIMAL_NOT_FOUND' AND pg_temp.status_of('A-V2') = 'ACTIVO' AND pg_temp.same('b7')$qq$,
    $qq$pg_temp.rs('b7')::text$qq$);

-- B8 NR twice / NR on a sold animal
SELECT pg_temp.plog('b8', pg_temp.items('A-NR4', 'NR', 'A-NR4', 'NR'));
SELECT pg_temp.plog('b8s', pg_temp.items('A-NRSOLD', 'NR'));
SELECT pg_temp.t('B NR twice for the same animal is DUPLICATE_IN_BATCH, and NR on a sold animal is NOT_ACTIVE (still validated)',
    $qq$pg_temp.rs('b8')->>'status' = 'rejected' AND pg_temp.has_code('b8', 'issues', 'DUPLICATE_IN_BATCH')
        AND pg_temp.rs('b8s')->>'status' = 'rejected' AND pg_temp.iss('b8s', 'A-NRSOLD')->>'code' = 'NOT_ACTIVE'$qq$,
    $qq$pg_temp.rs('b8')::text || ' / ' || pg_temp.rs('b8s')::text$qq$);

-- B9 UNE/NR composite: unchanged
SELECT pg_temp.plog('b9', pg_temp.items('A-NR3', 'UNE/NR'));
SELECT pg_temp.t('B UNE/NR (NR inside a composite) is unchanged: a real VACÍA palpation, condition NULL, UNMAPPED, raw code kept; not counted as not examined',
    $qq$pg_temp.rs('b9')->>'status' = 'recorded' AND (pg_temp.rs('b9')->>'written')::integer = 1 AND (pg_temp.rs('b9')->>'not_examined')::integer = 0
        AND pg_temp.rl('b9', 'A-NR3')->>'result_used' = 'VACÍA' AND pg_temp.rl('b9', 'A-NR3')->>'repro_condition' IS NULL
        AND pg_temp.rl('b9', 'A-NR3')->>'mapping_status' = 'UNMAPPED' AND pg_temp.rl('b9', 'A-NR3')->>'raw_code' = 'UNE/NR' AND pg_temp.status_of('A-NR3') = 'VACÍA'$qq$,
    $qq$pg_temp.rs('b9')::text$qq$);

-- B10 RP alone on an ACTIVO animal without a registered birth
SELECT pg_temp.plog('b10', pg_temp.items('A-RP1', 'RP'));
SELECT pg_temp.t('B RP alone on a non-PREÑADA animal: VACÍA, condition NULL, NOT_APPLICABLE, vet_flag POSTPARTUM, wording kept, category untouched',
    $qq$pg_temp.rs('b10')->>'status' = 'recorded' AND pg_temp.rl('b10', 'A-RP1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b10', 'A-RP1')->>'repro_condition' IS NULL
        AND pg_temp.rl('b10', 'A-RP1')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.rl('b10', 'A-RP1')->>'vet_flag' = 'POSTPARTUM' AND pg_temp.rl('b10', 'A-RP1')->>'raw_code' = 'RP'
        AND pg_temp.status_of('A-RP1') = 'VACÍA' AND pg_temp.category_of('A-RP1') = 'VACA'
        AND pg_temp.det('A-RP1')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.det('A-RP1')->>'raw_code' = 'RP' AND pg_temp.det('A-RP1')->>'repro_condition' IS NULL$qq$,
    $qq$pg_temp.rs('b10')::text || pg_temp.det('A-RP1')::text$qq$);
SELECT pg_temp.t('B RP with no registered birth near the date is flagged rp_without_registered_birth (line and batch count)',
    $qq$pg_temp.rl('b10', 'A-RP1')->>'rp_without_registered_birth' = 'true' AND (pg_temp.rs('b10')->>'rp_without_registered_birth')::integer = 1$qq$, $qq$pg_temp.rs('b10')::text$qq$);

-- B11 RP alone on a PREÑADA animal: needs_explicit_result, whole batch rejected
SELECT pg_temp.snap('b11');
SELECT pg_temp.plog('b11', pg_temp.items('A-RP2', 'RP', 'A-V3', 'VACIA'));
SELECT pg_temp.t('B RP alone on a PREÑADA animal is rejected (NEEDS_EXPLICIT_RESULT / needs_explicit_result) and so is the batch: the pregnancy is not erased, nothing written',
    $qq$pg_temp.rs('b11')->>'status' = 'rejected' AND pg_temp.iss('b11', 'A-RP2')->>'code' = 'NEEDS_EXPLICIT_RESULT' AND pg_temp.iss('b11', 'A-RP2')->>'line_status' = 'needs_explicit_result'
        AND (pg_temp.rs('b11')->>'written')::integer = 0 AND pg_temp.status_of('A-RP2') = 'PREÑADA' AND pg_temp.status_of('A-V3') = 'ACTIVO' AND pg_temp.same('b11')$qq$,
    $qq$pg_temp.rs('b11')::text$qq$);

-- B12 restated with an explicit VACIA
SELECT pg_temp.plog('b12', pg_temp.items('A-RP3', 'VACIA RP'));
SELECT pg_temp.t('B restated as "VACIA RP" the same PREÑADA animal is accepted: VACÍA, vet_flag POSTPARTUM, NOT_APPLICABLE, category untouched',
    $qq$pg_temp.rs('b12')->>'status' = 'recorded' AND pg_temp.rl('b12', 'A-RP3')->>'result_used' = 'VACÍA' AND pg_temp.rl('b12', 'A-RP3')->>'vet_flag' = 'POSTPARTUM'
        AND pg_temp.rl('b12', 'A-RP3')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.rl('b12', 'A-RP3')->>'repro_condition' IS NULL
        AND pg_temp.status_of('A-RP3') = 'VACÍA' AND pg_temp.category_of('A-RP3') = 'VACA'$qq$, $qq$pg_temp.rs('b12')::text$qq$);

-- B13 conflicts with a PREÑADA word
SELECT pg_temp.snap('b13');
SELECT pg_temp.plog('b13', pg_temp.items('A-RP4', 'PREÑADA RP'));
SELECT pg_temp.plog('b13b', pg_temp.items('A-RP5', 'MATRIZ OCUPADA RP'));
SELECT pg_temp.t('B RP with a PREÑADA word or with the MATRIZ OCUPADA phrase is a DIAGNOSIS_CONFLICT: nothing written, statuses untouched',
    $qq$pg_temp.rs('b13')->>'status' = 'rejected' AND pg_temp.iss('b13', 'A-RP4')->>'code' = 'DIAGNOSIS_CONFLICT'
        AND pg_temp.rs('b13b')->>'status' = 'rejected' AND pg_temp.iss('b13b', 'A-RP5')->>'code' = 'DIAGNOSIS_CONFLICT'
        AND pg_temp.status_of('A-RP4') = 'ACTIVO' AND pg_temp.status_of('A-RP5') = 'PREÑADA' AND pg_temp.same('b13')$qq$,
    $qq$pg_temp.rs('b13')::text || ' / ' || pg_temp.rs('b13b')::text$qq$);

-- B14 NO APTO
SELECT pg_temp.plog('b14', pg_temp.items('A-NP1', 'NO APTO'));
SELECT pg_temp.t('B NO APTO alone on a non-PREÑADA animal: VACÍA, condition NULL, NOT_APPLICABLE, vet_flag UNFIT, wording kept, category untouched, no birth flag',
    $qq$pg_temp.rs('b14')->>'status' = 'recorded' AND pg_temp.rl('b14', 'A-NP1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b14', 'A-NP1')->>'repro_condition' IS NULL
        AND pg_temp.rl('b14', 'A-NP1')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.rl('b14', 'A-NP1')->>'vet_flag' = 'UNFIT' AND pg_temp.rl('b14', 'A-NP1')->>'raw_code' = 'NO APTO'
        AND pg_temp.rl('b14', 'A-NP1')->>'rp_without_registered_birth' IS NULL AND pg_temp.status_of('A-NP1') = 'VACÍA' AND pg_temp.category_of('A-NP1') = 'VACA'$qq$,
    $qq$pg_temp.rs('b14')::text$qq$);
SELECT pg_temp.snap('b15');
SELECT pg_temp.plog('b15', pg_temp.items('A-NP2', 'No apto'));
-- the "nothing written" check of b15 must run BEFORE the next call writes (b15b legitimately writes one palpation)
SELECT pg_temp.t('B NO APTO alone on a PREÑADA animal is rejected (needs_explicit_result): nothing written, the animal stays PREÑADA',
    $qq$pg_temp.rs('b15')->>'status' = 'rejected' AND pg_temp.iss('b15', 'A-NP2')->>'code' = 'NEEDS_EXPLICIT_RESULT' AND pg_temp.iss('b15', 'A-NP2')->>'line_status' = 'needs_explicit_result'
        AND pg_temp.status_of('A-NP2') = 'PREÑADA' AND pg_temp.same('b15')$qq$,
    $qq$pg_temp.rs('b15')::text$qq$);
SELECT pg_temp.plog('b15b', pg_temp.items('A-NP3', 'vacía NO APTO'));
SELECT pg_temp.t('B "vacía NO APTO" on a PREÑADA animal is accepted: recorded, 1 written, VACÍA, vet_flag UNFIT, NOT_APPLICABLE, condition NULL, the animal becomes VACÍA',
    $qq$pg_temp.rs('b15b')->>'status' = 'recorded' AND (pg_temp.rs('b15b')->>'written')::integer = 1 AND pg_temp.rl('b15b', 'A-NP3')->>'result_used' = 'VACÍA'
        AND pg_temp.rl('b15b', 'A-NP3')->>'vet_flag' = 'UNFIT' AND pg_temp.rl('b15b', 'A-NP3')->>'mapping_status' = 'NOT_APPLICABLE'
        AND pg_temp.rl('b15b', 'A-NP3')->>'repro_condition' IS NULL AND pg_temp.status_of('A-NP3') = 'VACÍA'$qq$,
    $qq$pg_temp.rs('b15b')::text || ' status=' || coalesce(pg_temp.status_of('A-NP3'), 'NULL')$qq$);

-- B16 the RP birth flag
SELECT pg_temp.plog('b16', pg_temp.items('A-RPB1', 'RP', 'A-RPB2', 'RP'));
SELECT pg_temp.t('B the RP birth flag: a birth registered 30 days before clears it, one registered 200 days before does not',
    $qq$pg_temp.rs('b16')->>'status' = 'recorded' AND pg_temp.rl('b16', 'A-RPB1')->>'rp_without_registered_birth' = 'false'
        AND pg_temp.rl('b16', 'A-RPB2')->>'rp_without_registered_birth' = 'true' AND (pg_temp.rs('b16')->>'rp_without_registered_birth')::integer = 1$qq$,
    $qq$pg_temp.rs('b16')::text$qq$);

-- B17 UTC2 on a non-PREÑADA animal is unchanged
SELECT pg_temp.plog('b17', pg_temp.items('A-UT1', 'UTC2'));
SELECT pg_temp.t('B UTC2 stays known-pending: VACÍA, condition NULL, UNMAPPED, no vet_flag',
    $qq$pg_temp.rs('b17')->>'status' = 'recorded' AND pg_temp.rl('b17', 'A-UT1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b17', 'A-UT1')->>'repro_condition' IS NULL
        AND pg_temp.rl('b17', 'A-UT1')->>'mapping_status' = 'UNMAPPED' AND pg_temp.rl('b17', 'A-UT1')->>'vet_flag' IS NULL$qq$, $qq$pg_temp.rs('b17')::text$qq$);
-- B17b the guard covers EVERY code-only line, not just RP / NO APTO (owner decision)
SELECT pg_temp.snap('b17b');
SELECT pg_temp.plog('b17b', pg_temp.items('A-UT2', 'UTC2', 'A-V2', 'VACIA'));
SELECT pg_temp.t('B a bare UTC2 on a PREÑADA animal is rejected (NEEDS_EXPLICIT_RESULT) and so is the batch: the animal stays PREÑADA, the valid line is not written',
    $qq$pg_temp.rs('b17b')->>'status' = 'rejected' AND pg_temp.iss('b17b', 'A-UT2')->>'code' = 'NEEDS_EXPLICIT_RESULT' AND pg_temp.iss('b17b', 'A-UT2')->>'line_status' = 'needs_explicit_result'
        AND (pg_temp.rs('b17b')->>'written')::integer = 0 AND pg_temp.status_of('A-UT2') = 'PREÑADA' AND pg_temp.status_of('A-V2') = 'ACTIVO' AND pg_temp.same('b17b')$qq$,
    $qq$pg_temp.rs('b17b')::text$qq$);
SELECT pg_temp.snap('b17c');
SELECT pg_temp.plog('b17c', pg_temp.items('A-UE1', 'UNE', 'A-UL1', 'UTCL1/OI', 'A-UC1', 'UNE/NR'));
SELECT pg_temp.t('B bare UNE, UTCL1/OI and the composite UNE/NR on PREÑADA animals are each rejected (NEEDS_EXPLICIT_RESULT); nothing written, all stay PREÑADA',
    $qq$pg_temp.rs('b17c')->>'status' = 'rejected' AND pg_temp.iss('b17c', 'A-UE1')->>'code' = 'NEEDS_EXPLICIT_RESULT' AND pg_temp.iss('b17c', 'A-UL1')->>'code' = 'NEEDS_EXPLICIT_RESULT'
        AND pg_temp.iss('b17c', 'A-UC1')->>'code' = 'NEEDS_EXPLICIT_RESULT' AND jsonb_array_length(pg_temp.rs('b17c')->'issues') = 3
        AND pg_temp.status_of('A-UE1') = 'PREÑADA' AND pg_temp.status_of('A-UL1') = 'PREÑADA' AND pg_temp.status_of('A-UC1') = 'PREÑADA' AND pg_temp.same('b17c')$qq$,
    $qq$pg_temp.rs('b17c')::text$qq$);
SELECT pg_temp.plog('b17d', pg_temp.items('A-UE1', 'VACIA UNE', 'A-UL1', 'PREÑADA UTCL1/OI', 'A-UE2', 'ciclando', 'A-UC2', 'estática'));
SELECT pg_temp.t('B restated with an explicit result word the same PREÑADA animals are accepted: "VACIA UNE" -> VACÍA ESTATICA, "PREÑADA UTCL1/OI" -> stays PREÑADA, "ciclando" and "estática" -> VACÍA',
    $qq$pg_temp.rs('b17d')->>'status' = 'recorded' AND (pg_temp.rs('b17d')->>'written')::integer = 4
        AND pg_temp.rl('b17d', 'A-UE1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b17d', 'A-UE1')->>'repro_condition' = 'ESTATICA' AND pg_temp.status_of('A-UE1') = 'VACÍA'
        AND pg_temp.rl('b17d', 'A-UL1')->>'result_used' = 'PREÑADA' AND pg_temp.status_of('A-UL1') = 'PREÑADA'
        AND pg_temp.rl('b17d', 'A-UE2')->>'repro_condition' = 'CICLANDO' AND pg_temp.status_of('A-UE2') = 'VACÍA'
        AND pg_temp.rl('b17d', 'A-UC2')->>'repro_condition' = 'ESTATICA' AND pg_temp.status_of('A-UC2') = 'VACÍA'$qq$,
    $qq$pg_temp.rs('b17d')::text$qq$);
SELECT pg_temp.snap('b17e');
SELECT pg_temp.plog('b17e', pg_temp.items('A-NRP', 'NR'));
SELECT pg_temp.t('B NR alone on a PREÑADA animal is NOT rejected: not examined, nothing written, the animal stays PREÑADA (it never infers a result)',
    $qq$pg_temp.rs('b17e')->>'status' = 'recorded' AND (pg_temp.rs('b17e')->>'not_examined')::integer = 1 AND (pg_temp.rs('b17e')->>'written')::integer = 0
        AND pg_temp.status_of('A-NRP') = 'PREÑADA' AND pg_temp.same('b17e')$qq$, $qq$pg_temp.rs('b17e')::text$qq$);
SELECT pg_temp.plog('b17f', pg_temp.items('A-UT1', 'UTC2'));
SELECT pg_temp.t('B the same bare codes on a NON-PREÑADA animal are unchanged (UTC2 on ACTIVO already tested in B17; here again after the guard)',
    $qq$pg_temp.rs('b17f')->>'status' = 'recorded' AND pg_temp.rl('b17f', 'A-UT1')->>'result_used' = 'VACÍA' AND pg_temp.rl('b17f', 'A-UT1')->>'mapping_status' = 'UNMAPPED'$qq$, $qq$pg_temp.rs('b17f')::text$qq$);

-- B18 isolation: company B has no NR / RP meaning, but the phrase works there
SELECT pg_temp.plog('b18', pg_temp.items('B-BM1', 'MATRIZ OCUPADA'), NULL, 'u2', 'B');
SELECT pg_temp.plog('b18n', pg_temp.items('B-BN1', 'NR'), NULL, 'u2', 'B');
SELECT pg_temp.plog('b18r', pg_temp.items('B-BN2', 'RP'), NULL, 'u2', 'B');
SELECT pg_temp.t('B company isolation: in B the phrase MATRIZ OCUPADA works, but NR and RP (meanings of A only) are DIAGNOSIS_UNRECOGNIZED',
    $qq$pg_temp.rs('b18')->>'status' = 'recorded' AND pg_temp.rl('b18', 'B-BM1')->>'result_used' = 'PREÑADA' AND pg_temp.status_of('B-BM1') = 'PREÑADA'
        AND pg_temp.rs('b18n')->>'status' = 'rejected' AND pg_temp.iss('b18n', 'B-BN1')->>'code' = 'DIAGNOSIS_UNRECOGNIZED'
        AND pg_temp.rs('b18r')->>'status' = 'rejected' AND pg_temp.iss('b18r', 'B-BN2')->>'code' = 'DIAGNOSIS_UNRECOGNIZED'$qq$,
    $qq$pg_temp.rs('b18')::text || ' / ' || pg_temp.rs('b18n')::text || ' / ' || pg_temp.rs('b18r')::text$qq$);
SELECT pg_temp.t('B user 2 cannot log in company A and user 1 cannot log in B (fail-closed, P0001)',
    $qq$pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u2'), pg_temp.items('A-V4', 'VACIA')), 'P0001')
        AND pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), pg_temp.items('B-BN1', 'VACIA')), 'P0001')$qq$);

-- B19 N/A and empty are still not a diagnosis
SELECT pg_temp.plog('b19', pg_temp.items('A-V4', 'N/A'));
SELECT pg_temp.plog('b19b', pg_temp.items('A-V4', ''));
SELECT pg_temp.t('B N/A is still not a diagnosis (DIAGNOSIS_UNRECOGNIZED) and an empty one is ITEM_INCOMPLETE: unchanged',
    $qq$pg_temp.iss('b19', 'A-V4')->>'code' = 'DIAGNOSIS_UNRECOGNIZED' AND pg_temp.iss('b19b', 'A-V4')->>'code' = 'ITEM_INCOMPLETE' AND pg_temp.status_of('A-V4') = 'ACTIVO'$qq$,
    $qq$pg_temp.rs('b19')::text || ' / ' || pg_temp.rs('b19b')::text$qq$);

-- B20 idempotent retry
SELECT pg_temp.snap('b20');
SELECT pg_temp.plog('b20', pg_temp.items('A-MO1', 'MATRIZ OCUPADA'));
SELECT pg_temp.t('B an identical retry within 5 minutes is duplicate_skipped (line_status) and writes nothing new',
    $qq$pg_temp.rs('b20')->>'status' = 'recorded' AND pg_temp.rl('b20', 'A-MO1')->>'line_status' = 'duplicate_skipped' AND (pg_temp.rs('b20')->>'duplicate_skipped')::integer = 1
        AND pg_temp.same('b20')$qq$, $qq$pg_temp.rs('b20')::text$qq$);

-- B21 regression of the vet codes and explicit words
SELECT pg_temp.plog('b21', pg_temp.items('A-V5', 'ciclando', 'A-V6', 'UTCL1'));
SELECT pg_temp.t('B regression: "ciclando" is EXPLICIT CICLANDO and a bare UTCL1 is MAPPED CICLANDO, both VACÍA',
    $qq$pg_temp.rs('b21')->>'status' = 'recorded' AND pg_temp.rl('b21', 'A-V5')->>'repro_condition' = 'CICLANDO' AND pg_temp.rl('b21', 'A-V5')->>'mapping_status' = 'EXPLICIT'
        AND pg_temp.rl('b21', 'A-V6')->>'repro_condition' = 'CICLANDO' AND pg_temp.rl('b21', 'A-V6')->>'mapping_status' = 'MAPPED' AND pg_temp.status_of('A-V6') = 'VACÍA'$qq$,
    $qq$pg_temp.rs('b21')::text$qq$);

-- B22 all or nothing is intact
SELECT pg_temp.snap('b22');
SELECT pg_temp.plog('b22', pg_temp.items('A-RETRY', 'PREÑADA', 'A-V2', 'PREÑDA'));
SELECT pg_temp.t('B all-or-nothing is intact: one unrecognised line rejects the batch and the valid line is not written',
    $qq$pg_temp.rs('b22')->>'status' = 'rejected' AND pg_temp.status_of('A-RETRY') = 'ACTIVO' AND pg_temp.same('b22')$qq$, $qq$pg_temp.rs('b22')::text$qq$);

-- =============================================================================================================
-- PART C. the read tools
-- =============================================================================================================

SELECT pg_temp.call('c1', format('SELECT sp_repro_list_palpation_due(%L, %L, ''90'', ''100'', ''0'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('C list_palpation_due shows the last palpation''s code and vet_flag of bulk-loaded rows (RP -> POSTPARTUM; MATRIZ OCUPADA -> means pregnant)',
    $qq$pg_temp.row_of('c1', 'cows', 'A-DU1')->>'last_palpation_code' = 'RP' AND pg_temp.row_of('c1', 'cows', 'A-DU1')->>'last_palpation_vet_flag' = 'POSTPARTUM'
        AND pg_temp.row_of('c1', 'cows', 'A-DU1')->>'last_palpation_code_means_pregnant' = 'false'
        AND pg_temp.row_of('c1', 'cows', 'A-DU2')->>'last_palpation_code' = 'MATRIZ OCUPADA' AND pg_temp.row_of('c1', 'cows', 'A-DU2')->>'last_palpation_code_means_pregnant' = 'true'
        AND pg_temp.row_of('c1', 'cows', 'A-DU2')->>'last_palpation_vet_flag' IS NULL$qq$,
    $qq$coalesce(pg_temp.row_of('c1', 'cows', 'A-DU1')::text, 'DU1 not listed') || ' / ' || coalesce(pg_temp.row_of('c1', 'cows', 'A-DU2')::text, 'DU2 not listed') || ' / ' || left(pg_temp.rs('c1')::text, 20000)$qq$);
SELECT pg_temp.t('C list_palpation_due keeps its old keys (status, total, cows, stale_import_date) and lists nothing of company B',
    $qq$pg_temp.rs('c1')->>'status' = 'ok' AND pg_temp.rs('c1') ? 'total' AND pg_temp.rs('c1') ? 'stale_import_date'
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.rs('c1')->'cows') e JOIN cattle_livestock l ON l.id = (e->>'livestock_id')::uuid WHERE l.tenant_id <> pg_temp.cx('A')::integer)$qq$,
    $qq$left(pg_temp.rs('c1')::text, 20000)$qq$);

SELECT pg_temp.call('c2', format('SELECT sp_repro_list_upcoming_calvings(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('C list_upcoming_calvings shows the newest palpation''s code / vet_flag next to the status conflict (CV1: PREÑADA 100 days ago, then VACÍA RP 10 days ago)',
    $qq$pg_temp.row_of('c2', 'overdue', 'A-CV1')->>'status_conflict' = 'true' AND pg_temp.row_of('c2', 'overdue', 'A-CV1')->>'last_palpation_vet_flag' = 'POSTPARTUM'
        AND pg_temp.row_of('c2', 'overdue', 'A-CV1')->>'last_palpation_code' = 'RP'$qq$,
    $qq$coalesce(pg_temp.row_of('c2', 'overdue', 'A-CV1')::text, 'CV1 not in overdue') || ' / ' || left(pg_temp.rs('c2')::text, 20000)$qq$);

SELECT pg_temp.snap('c3');
SELECT pg_temp.call('h1', format('SELECT sp_repro_get_dam_history(%L, %L, ''T090-A-HD1'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('h2', format('SELECT sp_repro_get_dam_history(%L, %L, ''T090-A-HD2'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('h3', format('SELECT sp_repro_get_dam_history(%L, %L, ''T090-A-HD3'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('h4', format('SELECT sp_repro_get_dam_history(%L, %L, ''T090-A-HD4'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('h5', format('SELECT sp_repro_get_dam_history(%L, %L, ''T090-A-HD5'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('C dam history: a stored code that means PREÑADA next to a stored result VACÍA raises palpation_code_contradicts_result (display only)',
    $qq$pg_temp.rs('h1')->>'status' = 'ok' AND pg_temp.rs('h1')->'palpations'->0->>'code_contradicts_result' = 'true' AND pg_temp.rs('h1')->'palpations'->0->>'code_means_pregnant' = 'true'
        AND pg_temp.rs('h1')->'palpations'->0->>'uterine_code' = 'MATRIZ OCUPADA' AND pg_temp.rs('h1')->'palpations'->0->>'result' = 'VACÍA'
        AND (pg_temp.rs('h1')->'quality_flags'->>'palpation_code_contradicts_result')::integer = 1$qq$,
    $qq$left(pg_temp.rs('h1')::text, 20000)$qq$);
SELECT pg_temp.t('C dam history: RP shows vet_flag POSTPARTUM without a contradiction; N/A shows no code and no flag (unchanged); UNE/NR is marked as a composite; bare NR is NOT_EXAMINED',
    $qq$pg_temp.rs('h2')->'palpations'->0->>'vet_flag' = 'POSTPARTUM' AND pg_temp.rs('h2')->'palpations'->0->>'code_contradicts_result' = 'false'
        AND (pg_temp.rs('h2')->'quality_flags'->>'palpations_with_vet_flag')::integer = 1 AND (pg_temp.rs('h2')->'quality_flags'->>'palpation_code_contradicts_result')::integer = 0
        AND pg_temp.rs('h3')->'palpations'->0->>'uterine_code' IS NULL AND pg_temp.rs('h3')->'palpations'->0->>'vet_flag' IS NULL AND pg_temp.rs('h3')->'palpations'->0->>'code_contradicts_result' = 'false'
        AND pg_temp.rs('h4')->'palpations'->0->>'code_nr_composite' = 'true' AND pg_temp.rs('h4')->'palpations'->0->>'vet_flag' IS NULL
        AND pg_temp.rs('h5')->'palpations'->0->>'vet_flag' = 'NOT_EXAMINED'$qq$,
    $qq$left(pg_temp.rs('h2')::text, 20000) || ' / ' || left(pg_temp.rs('h3')::text, 20000) || ' / ' || left(pg_temp.rs('h4')::text, 20000) || ' / ' || left(pg_temp.rs('h5')::text, 20000)$qq$);
SELECT pg_temp.t('C the history tool wrote nothing (no row anywhere changed)', $qq$pg_temp.same('c3')$qq$);

SELECT pg_temp.call('u1', format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('C list_unmapped: UTC2 stays known_pending, ZZZ is unknown; RP, NR, NO APTO, MATRIZ OCUPADA and N/A are NOT reported as unmapped',
    $qq$pg_temp.rs('u1')->>'status' = 'ok' AND pg_temp.has_code('u1', 'unmapped', 'UTC2') AND pg_temp.elem('u1', 'unmapped', 'UTC2')->>'known_pending' = 'true'
        AND pg_temp.has_code('u1', 'unmapped', 'ZZZ') AND pg_temp.elem('u1', 'unmapped', 'ZZZ')->>'known_pending' = 'false'
        AND NOT pg_temp.has_code('u1', 'unmapped', 'RP') AND NOT pg_temp.has_code('u1', 'unmapped', 'NR') AND NOT pg_temp.has_code('u1', 'unmapped', 'NO APTO')
        AND NOT pg_temp.has_code('u1', 'unmapped', 'MATRIZ OCUPADA') AND NOT pg_temp.has_code('u1', 'unmapped', 'N/A') AND NOT pg_temp.has_code('u1', 'unmapped', 'N')$qq$,
    $qq$(SELECT string_agg(e->>'code', ',') FROM jsonb_array_elements(pg_temp.rs('u1')->'unmapped') e)$qq$);
SELECT pg_temp.t('C list_unmapped: known_meanings lists RP (POSTPARTUM), NO APTO (UNFIT), NR (NOT_EXAMINED, standalone) and the MATRIZ OCUPADA phrase (PREGNANT)',
    $qq$pg_temp.elem('u1', 'known_meanings', 'RP')->>'meaning' = 'POSTPARTUM' AND pg_temp.elem('u1', 'known_meanings', 'NO APTO')->>'meaning' = 'UNFIT'
        AND pg_temp.elem('u1', 'known_meanings', 'NR')->>'meaning' = 'NOT_EXAMINED' AND pg_temp.elem('u1', 'known_meanings', 'MATRIZ OCUPADA')->>'meaning' = 'PREGNANT'$qq$,
    $qq$pg_temp.rs('u1')->'known_meanings'$qq$);
SELECT pg_temp.t('C list_unmapped: NR next to another code (UNE/NR) is reported separately in composite_unconfirmed, not in known_meanings counts of standalone NR and not as unmapped',
    $qq$pg_temp.has_code('u1', 'composite_unconfirmed', 'NR') AND (pg_temp.elem('u1', 'composite_unconfirmed', 'NR')->>'palpations')::integer >= 2
        AND pg_temp.elem('u1', 'composite_unconfirmed', 'NR')->'example_values' ? 'UNE/NR' AND NOT pg_temp.has_code('u1', 'unmapped', 'NR')$qq$,
    $qq$pg_temp.rs('u1')->'composite_unconfirmed'$qq$);
SELECT pg_temp.t('C list_unmapped: meanings_configured shows who confirmed each meaning (the foreman, not a vet) and the old keys (unmapped_total, confirmed) are still there',
    $qq$(SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('u1')->'meanings_configured') e WHERE e->>'confirmed_by' = 'T090 capataz' AND e->>'source' = 'SEED_090_FOREMAN_CONFIRMED') = 3
        AND (pg_temp.rs('u1')->>'unmapped_total')::integer >= 2 AND pg_temp.has_code('u1', 'confirmed', 'UNE')$qq$,
    $qq$pg_temp.rs('u1')->'meanings_configured'$qq$);

SELECT pg_temp.call('u2', format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u2')));
SELECT pg_temp.t('C list_unmapped isolation: company B sees NR and RP as unknown (it has no meanings), never A''s ZZZ / UTC2, no configured meanings, but the fixed phrase is known there too',
    $qq$pg_temp.has_code('u2', 'unmapped', 'NR') AND pg_temp.has_code('u2', 'unmapped', 'RP') AND NOT pg_temp.has_code('u2', 'unmapped', 'ZZZ') AND NOT pg_temp.has_code('u2', 'unmapped', 'UTC2')
        AND jsonb_array_length(pg_temp.rs('u2')->'meanings_configured') = 0 AND pg_temp.has_code('u2', 'known_meanings', 'MATRIZ OCUPADA')$qq$,
    $qq$pg_temp.rs('u2')::text$qq$);

-- =============================================================================================================
-- PART D. condition_code_set
-- =============================================================================================================

SELECT pg_temp.call('d1', format('SELECT sp_repro_condition_code_set(%L, %L, ''MATRIZ OCUPADA'', ''OTRO'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('d2', format('SELECT sp_repro_condition_code_set(%L, %L, ''RP'', ''CICLANDO'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('D the phrase MATRIZ OCUPADA cannot be redefined and a code with a meaning cannot get a condition (friendly answer, rows unchanged)',
    $qq$pg_temp.rs('d1')->>'status' = 'invalid' AND pg_temp.rs('d2')->>'status' = 'invalid'
        AND (SELECT repro_condition FROM repro_condition_codes WHERE id_company = pg_temp.cx('A')::integer AND code = 'MATRIZ OCUPADA') IS NULL
        AND (SELECT repro_condition FROM repro_condition_codes WHERE id_company = pg_temp.cx('A')::integer AND code = 'RP') IS NULL
        AND (SELECT meaning FROM repro_condition_codes WHERE id_company = pg_temp.cx('A')::integer AND code = 'RP') = 'POSTPARTUM'$qq$,
    $qq$pg_temp.rs('d1')::text || ' / ' || pg_temp.rs('d2')::text$qq$);
SELECT pg_temp.call('d3', format('SELECT sp_repro_condition_code_set(%L, %L, ''ZZZ'', ''OTRO'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('d3b', format('SELECT sp_repro_condition_code_set(%L, %L, ''ZZZ'', ''OTRO'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('D regression: a new code is created and re-confirming it is updated (and keeps meaning NULL)',
    $qq$pg_temp.rs('d3')->>'status' = 'created' AND pg_temp.rs('d3b')->>'status' = 'updated'
        AND (SELECT meaning FROM repro_condition_codes WHERE id_company = pg_temp.cx('A')::integer AND code = 'ZZZ') IS NULL$qq$, $qq$pg_temp.rs('d3')::text || ' / ' || pg_temp.rs('d3b')::text$qq$);
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.call('d4', format('SELECT sp_repro_condition_code_set(%L, %L, ''QQ'', ''OTRO'')', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');
SELECT pg_temp.t('D only an ADMIN confirms a code: an EDITOR gets forbidden', $qq$pg_temp.rs('d4')->>'status' = 'forbidden'$qq$, $qq$pg_temp.rs('d4')::text$qq$);

-- =============================================================================================================
-- PART E. fail-closed
-- =============================================================================================================

SELECT pg_temp.t('E the five tools raise P0001 for the other company''s user, a stranger, a blank e-mail and bad tenants',
    $qq$(SELECT bool_and(pg_temp.raises(format(f.sql, t.tn, t.em), 'P0001'))
        FROM (VALUES ('SELECT sp_repro_log_palpation_batch(%L, %L, ''[]'')'), ('SELECT sp_repro_list_palpation_due(%L, %L)'), ('SELECT sp_repro_list_upcoming_calvings(%L, %L)'),
                     ('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)'), ('SELECT sp_repro_get_dam_history(%L, %L, ''x'')')) AS f (sql)
        CROSS JOIN (VALUES (pg_temp.cx('B'), pg_temp.cx('u1')), (pg_temp.cx('A'), 'nadie@example.test'), (pg_temp.cx('A'), ''), ('abc', pg_temp.cx('u1')),
                           ('', pg_temp.cx('u1')), (pg_temp.cx('A') || ' OR 1=1', pg_temp.cx('u1'))) AS t (tn, em))$qq$);
DO $$
DECLARE
    v_palm integer;
BEGIN
    SELECT c.id_company INTO v_palm FROM companys c WHERE c.is_active AND fn_company_business_domain(c.id_company) = 'PALM' ORDER BY c.id_company LIMIT 1;
    IF v_palm IS NULL THEN
        INSERT INTO t_result (test, ok, detail) VALUES ('E palm company is rejected (P0094) - skipped: no palm company in this database', true, 'skipped');
        RETURN;
    END IF;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT pg_temp.cx('u1'), v_palm, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = pg_temp.cx('u1') AND id_company = v_palm);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = pg_temp.cx('u1') AND id_company = v_palm;
    INSERT INTO t_result (test, ok, detail)
    VALUES ('E palm company is rejected (P0094) by the wrapper and the unmapped tool',
            pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, ''[]'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094'), 'palm company ' || v_palm);
END $$;

-- =============================================================================================================
-- PART F. nothing else was written
-- =============================================================================================================

SELECT pg_temp.t('F the functions 090 must not touch are byte-identical to the state before 090 was loaded (sp_log_palpation_event, the parser, the births / services procedures ...)',
    $qq$NOT EXISTS (SELECT 1 FROM t_proc_before b LEFT JOIN pg_proc p ON p.oid = to_regprocedure(b.sig) WHERE p.oid IS NULL OR md5(pg_get_functiondef(p.oid)) <> b.md5)
        AND (SELECT count(*) FROM t_proc_before) >= 12$qq$,
    $qq$(SELECT string_agg(b.sig, ', ') FROM t_proc_before b LEFT JOIN pg_proc p ON p.oid = to_regprocedure(b.sig) WHERE p.oid IS NULL OR md5(pg_get_functiondef(p.oid)) <> b.md5)$qq$);
SELECT pg_temp.t('F exactly 7 bodies carry the 090 marker, each function has ONE overload, and the 3 helpers are not in crud_models',
    $qq$(SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%090:vet-codes-v1%') = 7
        AND (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('fn_repro_diagnosis_kind', 'sp_repro_log_palpation_batch', 'sp_repro_list_palpation_due',
             'sp_repro_list_upcoming_calvings', 'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set', 'sp_repro_get_dam_history')) = 7
        AND NOT EXISTS (SELECT 1 FROM crud_models WHERE table_name IN ('fn_repro_code_meaning', 'fn_repro_palp_text', 'fn_repro_palp_code_info') OR model_name IN ('fn_repro_code_meaning', 'fn_repro_palp_text', 'fn_repro_palp_code_info'))$qq$);
SELECT pg_temp.t('F animals that were only "not examined" (NR alone) have no palpation, no details row and keep their status',
    $qq$NOT EXISTS (SELECT 1 FROM cattle_health_logs h JOIN cattle_livestock l ON l.id = h.livestock_id WHERE l.rfid_siniiga IN ('T090-A-NR1', 'T090-A-NR2', 'T090-A-NR4', 'T090-A-NRSOLD'))
        AND NOT EXISTS (SELECT 1 FROM palpation_repro_details d JOIN cattle_livestock l ON l.id = d.livestock_id WHERE l.rfid_siniiga IN ('T090-A-NR1', 'T090-A-NR2', 'T090-A-NR4', 'T090-A-NRSOLD'))$qq$);
SELECT pg_temp.t('F no RP / NO APTO / MATRIZ OCUPADA animal changed category, and no bulk-loaded palpation got a details row (the read tools wrote nothing)',
    $qq$NOT EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T090-%' AND category <> 'VACA')
        AND NOT EXISTS (SELECT 1 FROM palpation_repro_details d JOIN cattle_livestock l ON l.id = d.livestock_id
                         WHERE l.rfid_siniiga IN ('T090-A-DU1', 'T090-A-DU2', 'T090-A-CV1', 'T090-A-HD1', 'T090-A-HD2', 'T090-A-HD3', 'T090-A-HD4', 'T090-A-HD5', 'T090-A-UN1', 'T090-A-UN2', 'T090-A-UN3'))$qq$);
SELECT pg_temp.t('F the imported MATRIZ OCUPADA animal is NOT corrected (display only): result stays VACIA and status stays VACÍA',
    $qq$pg_temp.status_of('A-HD1') = 'VACÍA' AND (SELECT medicines_json->>'resultado' FROM cattle_health_logs WHERE livestock_id = pg_temp.aid('A-HD1')) = 'VACIA'$qq$);
SELECT pg_temp.t('F no details row has a condition on a PREÑADA result, and every NOT_APPLICABLE / UNMAPPED row has none (side-table CHECKs hold)',
    $qq$NOT EXISTS (SELECT 1 FROM palpation_repro_details WHERE repro_condition IS NOT NULL AND result <> 'VACÍA')
        AND NOT EXISTS (SELECT 1 FROM palpation_repro_details WHERE mapping_status IN ('NOT_APPLICABLE', 'UNMAPPED') AND repro_condition IS NOT NULL)$qq$);

SELECT pg_temp.t('090 tests ran inside ONE transaction: no included file committed or rolled back (the same txid is still current)',
    $qq$ txid_current()::text = (SELECT v FROM t_ctx WHERE k = 'txid') $qq$);

\echo === RESULTS
-- Any ERROR line printed above (outside this table) is an unexpected error in a fixture / helper statement, not a failed assertion.
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE detail END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
-- Every failure with its WHOLE detail, one field per line (the table above can be wider than the terminal):
\echo === FAILURES (full detail, expanded)
\x on
SELECT n, test, detail FROM t_result WHERE NOT ok ORDER BY n;
\x off
\set ON_ERROR_STOP on
\set ON_ERROR_ROLLBACK off
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '090 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 090 tests: everything rolled back ***'
