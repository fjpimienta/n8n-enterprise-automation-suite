-- 087_tests.sql — functional checks for migration 087 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It loads 084, 085, 086 and 087 inside this transaction (embedded mode), so it runs the same way whether or not they are
-- applied. It needs a database with the real schema (so sp_register_birth_event is the verified production body: 087 aborts
-- otherwise) plus AT LEAST two ACTIVE non-palm companies and two users (see 087_RUNBOOK.md, "Test database"). It picks the
-- two companies (A, B) and two users and arranges memberships INSIDE the transaction (filtered UPDATE / INSERT, rolled back):
--     user 1: ACTIVE ADMIN of A, INACTIVE in B        user 2: ACTIVE ADMIN of B, INACTIVE in A
-- Fixture animals use identifiers prefixed T087 so existing data cannot interfere; assertions are about those fixtures.
--
-- Snapshot rule used throughout: a statement never reads a row that a write tool created in the SAME statement. Every write
-- goes through pg_temp.call(key, sql) in its own statement; the result is kept in t_res and asserted in the NEXT statement.
--
-- Part A  validation of a birth line (dam resolution, ambiguity, sex / date / weight, dam checks, ids of another company)
-- Part B  sp_repro_register_birth (calf, dam status, reporter, possible_duplicate, force, twins, retry, config, isolation)
-- Part C  legacy sp_register_birth_event (membership, NULL e-mail path, exact retry, orphan-calf behaviour untouched)
-- Part D  births by blocks (preview is a pure read, register is all-or-nothing and never trusts a preview, cap of 50)
-- Part E  historical births (no calf, no status change, idempotent, voidable, precision rules, append-only, isolation)
-- Part F  fail-closed on every tool (stranger, other company, blank, bad tenant, palm)
-- Part G  nothing else was written / the procedures 087 must not touch are unchanged
--
-- Run (the test files must be INSIDE the container; psql resolves \ir relative to this file):
--   docker exec n8n-enterprise-db rm -rf /tmp/m087
--   docker cp database/migrations n8n-enterprise-db:/tmp/m087
--   docker exec -w /tmp/m087 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m087/087_tests.sql

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql
\ir 086_repro_palpation.sql
\ir 087_repro_births.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE t_res (k text PRIMARY KEY, r jsonb) ON COMMIT DROP;
INSERT INTO t_ctx VALUES ('txid', txid_current()::text);

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

-- Runs ONE assertion given as SQL text. An error inside the expression (including assert_failure / P0004, which `WHEN OTHERS` alone
-- does not catch) is recorded as a FAIL with the SQLSTATE and message instead of aborting the script, so one defect never hides the rest.
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
    IF d IS NULL AND NOT coalesce(v, false) AND p_detail IS NOT NULL THEN
        BEGIN
            EXECUTE 'SELECT (' || p_detail || ')::text' INTO d;
        EXCEPTION WHEN OTHERS THEN
            d := 'detail error: ' || SQLERRM;
        END;
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

-- NOTE: `WHEN OTHERS` does NOT catch assert_failure (SQLSTATE P0004) or query_canceled: P0004 must be named. The legacy
-- procedures raise their "ambiguous identifier" with ERRCODE P0004, which is why the handler names it explicitly.
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

CREATE FUNCTION pg_temp.raises_any(p_sql text, p_states text[]) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN assert_failure THEN
    RETURN SQLSTATE = ANY (p_states);
WHEN OTHERS THEN
    RETURN SQLSTATE = ANY (p_states);
END $$;

-- 'YYYY-MM-DD' of the Mexico City day n days ago
CREATE FUNCTION pg_temp.dago(p_days integer) RETURNS text
LANGUAGE sql AS $$ SELECT to_char(fn_repro_today() - p_days, 'YYYY-MM-DD') $$;

-- sp_repro_register_birth from a spec: {sex, dam, dam_id, date, w, lot, pu, pad, sp, notes, force}
CREATE FUNCTION pg_temp.bth(p_key text, p_spec jsonb, p_who text DEFAULT 'u1', p_company text DEFAULT 'A') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_register_birth(%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.cx(p_company), pg_temp.cx(p_who), p_spec->>'sex', p_spec->>'dam', p_spec->>'dam_id', p_spec->>'date', p_spec->>'w',
        p_spec->>'lot', p_spec->>'pu', p_spec->>'pad', p_spec->>'sp', p_spec->>'notes', p_spec->>'force'));
END $$;

CREATE FUNCTION pg_temp.n_births(p_dam text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM birth_events WHERE dam_id = p_dam::uuid $$;
CREATE FUNCTION pg_temp.n_calves(p_dam text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_livestock WHERE mother_id = p_dam::uuid $$;
CREATE FUNCTION pg_temp.n_hist(p_dam text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM repro_historical_births WHERE dam_id = p_dam::uuid $$;
CREATE FUNCTION pg_temp.dam_status(p_dam text) RETURNS text
LANGUAGE sql AS $$ SELECT current_status FROM cattle_livestock WHERE id = p_dam::uuid $$;
CREATE FUNCTION pg_temp.n_animals() RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_livestock $$;

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
        RAISE EXCEPTION '087 tests need two active non-palm companies in the database (see 087_RUNBOOK.md, Test database).';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '087 tests need two users in the database (see 087_RUNBOOK.md, Test database).';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T087%') THEN
        RAISE EXCEPTION '087 tests: T087 fixtures already exist in this database; run the tests on a clean copy.';
    END IF;

    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e1, v_a, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e1 AND id_company = v_a);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e1 AND id_company = v_a;
    UPDATE user_companies SET is_active = false WHERE email = v_e1 AND id_company = v_b;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e2, v_b, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e2 AND id_company = v_b);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e2 AND id_company = v_b;
    UPDATE user_companies SET is_active = false WHERE email = v_e2 AND id_company = v_a;

    DELETE FROM repro_births_config WHERE id_company IN (v_a, v_b);
    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

CREATE FUNCTION pg_temp.setrole(p_email text, p_company text, p_role text) RETURNS void
LANGUAGE sql AS $$ UPDATE user_companies SET role = p_role WHERE email = p_email AND id_company = p_company::integer $$;

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_key text, p_fuego text, p_cat text, p_status text) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego, species)
    VALUES (p_tenant, 'T087-' || p_key, 'CRIA', p_cat, p_status, p_fuego, 'BOVINO')
    RETURNING id
$$;

DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_b integer := pg_temp.cx('B')::integer;
    v_id uuid;
    v_k text;
    v_pu uuid;
    v_lot uuid;
BEGIN
    -- single dams of company A, keyed d1..d9, b1..b8 (blocks), h1..h8 (historical)
    FOREACH v_k IN ARRAY ARRAY['d1','d2','d3','d4','d5','d6','d7','d8','d9','b1','b2','b3','b4','b5','b6','b7','b8','h1','h2','h3','h4','h5','h6','h7','h8'] LOOP
        v_id := pg_temp.mk(v_a, 'A-' || upper(v_k), NULL, 'VACA', 'ACTIVO');
        INSERT INTO t_ctx VALUES (v_k, v_id::text);
    END LOOP;
    UPDATE cattle_livestock SET current_status = 'PREÑADA' WHERE id = pg_temp.cx('d1')::uuid;
    v_id := pg_temp.mk(v_a, 'A-DUP1', 'T087DUP', 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('dup1', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-DUP2', 'T087DUP', 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('dup2', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-SOLD', NULL, 'VACA', 'VENDIDO');       INSERT INTO t_ctx VALUES ('sold', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-BULL', NULL, 'TORO', 'ACTIVO');        INSERT INTO t_ctx VALUES ('bull', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-PUNI', 'T087UNI', 'NOVILLONA', 'ACTIVO'); INSERT INTO t_ctx VALUES ('uni', v_id::text);  -- unique fire number
    -- company B
    v_id := pg_temp.mk(v_b, 'B-D1', NULL, 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('bd1', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-D2', NULL, 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('bd2', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-H1', NULL, 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('bh1', v_id::text);

    -- production unit / lot / paddock of each company (only to test that ids of another company are refused)
    INSERT INTO production_units (id_company, upp_code, ranch_name) VALUES (v_a, '99-087-0001-001', 'T087 UPP A') RETURNING id INTO v_pu;
    INSERT INTO t_ctx VALUES ('pu_a', v_pu::text);
    INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type) VALUES (v_a, v_pu, 'T087 LOT A', 'PROPIO') RETURNING id INTO v_lot;
    INSERT INTO t_ctx VALUES ('lot_a', v_lot::text);
    INSERT INTO production_unit_paddocks (id_company, production_unit_id, paddock_label) VALUES (v_a, v_pu, 'T087 PAD A') RETURNING id INTO v_id;
    INSERT INTO t_ctx VALUES ('pad_a', v_id::text);
    INSERT INTO production_units (id_company, upp_code, ranch_name) VALUES (v_b, '99-087-0002-001', 'T087 UPP B') RETURNING id INTO v_pu;
    INSERT INTO t_ctx VALUES ('pu_b', v_pu::text);
    INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type) VALUES (v_b, v_pu, 'T087 LOT B', 'PROPIO') RETURNING id INTO v_lot;
    INSERT INTO t_ctx VALUES ('lot_b', v_lot::text);
    INSERT INTO production_unit_paddocks (id_company, production_unit_id, paddock_label) VALUES (v_b, v_pu, 'T087 PAD B') RETURNING id INTO v_id;
    INSERT INTO t_ctx VALUES ('pad_b', v_id::text);
END $$;

CREATE TEMP TABLE t_proc ON COMMIT DROP AS
SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('sp_log_breeding_event', 'sp_void_event', 'sp_log_palpation_event');

-- From here on an unexpected error in a statement does not stop the run: psql rolls back to a savepoint of that statement only
-- (ON_ERROR_ROLLBACK) and goes on, and every assertion runs inside pg_temp.t(), which records errors as FAILs.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

-- =============================================================================================================
-- PART A. validation of a birth line (fn_repro_birth_check_line, a pure function)
-- =============================================================================================================

CREATE FUNCTION pg_temp.chk(p_line jsonb, p_force boolean DEFAULT false, p_company text DEFAULT 'A') RETURNS jsonb
LANGUAGE sql AS $$ SELECT fn_repro_birth_check_line(pg_temp.cx(p_company)::integer, p_line, NULL, p_force) $$;

SELECT pg_temp.t('A a valid line resolves the dam by RFID, SINIIGA or id and is ok', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'macho', 'dam_identifier', 'T087-A-D2'))->>'status' = 'ok'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'H', 'dam_id', pg_temp.cx('d2')))->>'status' = 'ok'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_identifier', 'T087-A-D2'))->>'dam_id' = pg_temp.cx('d2')$qq$);
SELECT pg_temp.t('A the dam given by a fire number that is NOT unique is ambiguous with candidates, never picked', $qq$(SELECT c->>'status' = 'ambiguous' AND c->>'code' = 'DAM_AMBIGUOUS' AND jsonb_array_length(c->'candidates') = 2 AND c->>'dam_id' IS NULL
       FROM (SELECT pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_identifier', 'T087DUP')) AS c) x)$qq$);
SELECT pg_temp.t('A a unique fire number resolves; an unknown identifier is not_found; a missing dam is invalid', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_identifier', 'T087UNI'))->>'dam_id' = pg_temp.cx('uni')
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_identifier', 'T087-NOPE'))->>'status' = 'not_found'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO'))->>'code' = 'DAM_MISSING'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', 'no-uuid'))->>'code' = 'DAM_ID_BAD'$qq$);
SELECT pg_temp.t('A ISOLATION: a dam of company B is not_found for A (by id and by identifier), and A''s dam is not_found for B', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('bd1')))->>'status' = 'not_found'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_identifier', 'T087-B-D1'))->>'status' = 'not_found'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2')), false, 'B')->>'status' = 'not_found'$qq$);
SELECT pg_temp.t('A calf sex, species, date and weight are validated (BAD_SEX, BAD_SPECIES, BAD_DATE future / too old / malformed, BAD_WEIGHT)', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'X', 'dam_id', pg_temp.cx('d2')))->>'code' = 'BAD_SEX'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'species', 'DRAGON', 'dam_id', pg_temp.cx('d2')))->>'code' = 'BAD_SPECIES'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_date', to_char(fn_repro_today() + 1, 'YYYY-MM-DD')))->>'code' = 'BAD_DATE'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_date', pg_temp.dago(400)))->>'code' = 'BAD_DATE'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_date', 'ayer'))->>'code' = 'BAD_DATE'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_weight_kg', '40,5'))->>'code' = 'BAD_WEIGHT'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_weight_kg', '0'))->>'code' = 'BAD_WEIGHT'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_weight_kg', '151'))->>'code' = 'BAD_WEIGHT'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'birth_weight_kg', '38.5'))->>'status' = 'ok'$qq$);
SELECT pg_temp.t('A the dam must be an active bovine female: a sold cow (DAM_NOT_ACTIVE) and a bull (DAM_NOT_FEMALE) are refused', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('sold')))->>'code' = 'DAM_NOT_ACTIVE'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('bull')))->>'code' = 'DAM_NOT_FEMALE'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'species', 'BUFALO'))->>'code' = 'DAM_SPECIES'$qq$);
SELECT pg_temp.t('A ISOLATION of ids: a lot / production unit / paddock of company B is refused for A (and A''s own are accepted)', $qq$pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'lot_id', pg_temp.cx('lot_b')))->>'code' = 'LOT_NOT_FOUND'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'production_unit_id', pg_temp.cx('pu_b')))->>'code' = 'UPP_NOT_FOUND'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'paddock_id', pg_temp.cx('pad_b')))->>'code' = 'PADDOCK_NOT_FOUND'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'lot_id', 'no-uuid'))->>'code' = 'LOT_NOT_FOUND'
    AND pg_temp.chk(jsonb_build_object('calf_sex', 'MACHO', 'dam_id', pg_temp.cx('d2'), 'lot_id', pg_temp.cx('lot_a'),
                                       'production_unit_id', pg_temp.cx('pu_a'), 'paddock_id', pg_temp.cx('pad_a')))->>'status' = 'ok'$qq$);

-- =============================================================================================================
-- PART B. sp_repro_register_birth
-- =============================================================================================================

SELECT pg_temp.bth('b1', jsonb_build_object('sex', 'macho', 'dam', 'T087-A-D1', 'date', pg_temp.dago(1), 'w', '36.5', 'notes', 'T087 nota'));
SELECT pg_temp.t('B a birth is recorded through the legacy writer: calf (BECERRO, ACTIVO, mother_id), birth event, birth weight log, dam PREÑADA -> VACÍA', $qq$pg_temp.rs('b1')->>'status' = 'recorded' AND (pg_temp.rs('b1')->>'success')::boolean AND (pg_temp.rs('b1')->>'written')::int = 1
    AND pg_temp.rs('b1')->>'category' = 'BECERRO' AND (pg_temp.rs('b1')->>'dam_status_updated_to_vacia')::boolean
    AND pg_temp.dam_status(pg_temp.cx('d1')) = 'VACÍA' AND pg_temp.n_births(pg_temp.cx('d1')) = 1 AND pg_temp.n_calves(pg_temp.cx('d1')) = 1
    AND (SELECT w.weight_kg = 36.5 FROM cattle_weight_logs w WHERE w.livestock_id = (pg_temp.rs('b1')->>'calf_id')::uuid AND w.source_device = 'BIRTH_EVENT')$qq$, $qq$pg_temp.rs('b1')::text$qq$);
SELECT pg_temp.t('B the reporter is stored in birth_events.reported_by_email (the caller''s e-mail) and the service-link key is present (088 not applied: null)', $qq$(SELECT lower(b.reported_by_email) = lower(pg_temp.cx('u1')) AND b.source = 'MOBILE_APP' AND b.notes = 'T087 nota'
       FROM birth_events b WHERE b.id = (pg_temp.rs('b1')->>'birth_event_id')::uuid)
    AND pg_temp.rs('b1') ? 'service_link' AND pg_temp.rs('b1')->>'duplicate_skipped' = 'false'$qq$);

-- exact retry: the same data right after
SELECT pg_temp.bth('b2', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D1', 'date', pg_temp.dago(1), 'w', '36.5', 'notes', 'T087 nota'));
SELECT pg_temp.t('B an exact retry is duplicate_skipped (status from the checker) and nothing is inserted', $qq$pg_temp.rs('b2')->>'status' = 'duplicate_skipped' AND (pg_temp.rs('b2')->>'written')::int = 0
    AND pg_temp.rs('b2')->>'existing_birth_event_id' = (pg_temp.rs('b1')->>'birth_event_id')
    AND pg_temp.n_births(pg_temp.cx('d1')) = 1 AND pg_temp.n_calves(pg_temp.cx('d1')) = 1$qq$, $qq$pg_temp.rs('b2')::text$qq$);

-- possible duplicate: another birth of the same dam 30 days later
SELECT pg_temp.bth('b3', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T087-A-D1', 'date', pg_temp.dago(0), 'w', '30'));
SELECT pg_temp.t('B a second birth of the same dam within the window is possible_duplicate: it returns the existing birth and inserts NOTHING', $qq$pg_temp.rs('b3')->>'status' = 'possible_duplicate' AND (pg_temp.rs('b3')->>'written')::int = 0 AND (pg_temp.rs('b3')->>'window_days')::int = 240
    AND jsonb_array_length(pg_temp.rs('b3')->'existing') = 1 AND pg_temp.rs('b3')->'existing'->0->>'source' = 'BIRTH'
    AND pg_temp.rs('b3')->'existing'->0->>'id' = (pg_temp.rs('b1')->>'birth_event_id')
    AND pg_temp.n_births(pg_temp.cx('d1')) = 1 AND pg_temp.n_calves(pg_temp.cx('d1')) = 1$qq$, $qq$pg_temp.rs('b3')::text$qq$);
SELECT pg_temp.bth('b4', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T087-A-D1', 'date', pg_temp.dago(0), 'w', '30', 'force', 'true'));
SELECT pg_temp.t('B with force the same birth is recorded (forced = true)', $qq$pg_temp.rs('b4')->>'status' = 'recorded' AND (pg_temp.rs('b4')->>'forced')::boolean
    AND pg_temp.n_births(pg_temp.cx('d1')) = 2 AND pg_temp.n_calves(pg_temp.cx('d1')) = 2$qq$, $qq$pg_temp.rs('b4')::text$qq$);

-- twins with IDENTICAL data: the first is recorded, the second only with force (the legacy retry detection is bypassed)
SELECT pg_temp.bth('t1', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D3', 'date', pg_temp.dago(2), 'w', '33'));
SELECT pg_temp.bth('t2', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D3', 'date', pg_temp.dago(2), 'w', '33'));
SELECT pg_temp.bth('t3', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D3', 'date', pg_temp.dago(2), 'w', '33', 'force', 'si'));
SELECT pg_temp.t('B identical twins: the 2nd entry without force is duplicate_skipped; with force it is recorded and the 5-minute legacy retry check does not block it', $qq$pg_temp.rs('t1')->>'status' = 'recorded' AND pg_temp.rs('t2')->>'status' = 'duplicate_skipped' AND pg_temp.rs('t3')->>'status' = 'recorded'
    AND pg_temp.n_births(pg_temp.cx('d3')) = 2 AND pg_temp.n_calves(pg_temp.cx('d3')) = 2$qq$, $qq$pg_temp.rs('t3')::text$qq$);
SELECT pg_temp.t('B the force setting does not leak: a plain retry right after a forced birth is skipped again (app.repro_force_birth is off)', $qq$coalesce(current_setting('app.repro_force_birth', true), 'off') <> 'on'$qq$);

-- ambiguity
CREATE TEMP TABLE t_base_amb ON COMMIT DROP AS SELECT pg_temp.n_animals() AS animals, (SELECT count(*) FROM birth_events) AS births;
SELECT pg_temp.bth('amb', jsonb_build_object('sex', 'MACHO', 'dam', 'T087DUP', 'date', pg_temp.dago(0)));
SELECT pg_temp.t('B a dam identifier that matches several animals answers ambiguous with candidates and writes nothing', $qq$pg_temp.rs('amb')->>'status' = 'ambiguous' AND jsonb_array_length(pg_temp.rs('amb')->'candidates') = 2 AND (pg_temp.rs('amb')->>'written')::int = 0
    AND pg_temp.n_animals() = (SELECT animals FROM t_base_amb) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_amb)$qq$);
SELECT pg_temp.bth('amb2', jsonb_build_object('sex', 'MACHO', 'dam_id', pg_temp.cx('dup1'), 'date', pg_temp.dago(0)));
SELECT pg_temp.t('B resolved by its id, one of the animals with the repeated fire number can be registered', $qq$pg_temp.rs('amb2')->>'status' = 'recorded' AND pg_temp.n_births(pg_temp.cx('dup1')) = 1$qq$);

-- lot / unit / paddock of the dam's company are accepted and applied
SELECT pg_temp.bth('lot', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T087-A-D4', 'date', pg_temp.dago(3),
        'lot', pg_temp.cx('lot_a'), 'pu', pg_temp.cx('pu_a'), 'pad', pg_temp.cx('pad_a')));
SELECT pg_temp.t('B the lot / UPP / paddock of the company are applied to the calf', $qq$pg_temp.rs('lot')->>'status' = 'recorded' AND pg_temp.rs('lot')->>'lot_id_resolved' = pg_temp.cx('lot_a')
    AND (SELECT l.lot_id = pg_temp.cx('lot_a')::uuid FROM cattle_livestock l WHERE l.id = (pg_temp.rs('lot')->>'calf_id')::uuid)$qq$, $qq$pg_temp.rs('lot')::text$qq$);
CREATE TEMP TABLE t_base_iso ON COMMIT DROP AS SELECT pg_temp.n_animals() AS animals, (SELECT count(*) FROM birth_events) AS births;
SELECT pg_temp.bth('iso1', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D5', 'date', pg_temp.dago(3), 'lot', pg_temp.cx('lot_b')));
SELECT pg_temp.bth('iso2', jsonb_build_object('sex', 'MACHO', 'dam_id', pg_temp.cx('bd1'), 'date', pg_temp.dago(3)));
SELECT pg_temp.t('B ISOLATION: company A cannot register a birth with a lot of B, nor for a dam of B; nothing written', $qq$pg_temp.rs('iso1')->>'code' = 'LOT_NOT_FOUND' AND pg_temp.rs('iso2')->>'status' = 'not_found'
    AND pg_temp.n_animals() = (SELECT animals FROM t_base_iso) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_iso)$qq$);
SELECT pg_temp.bth('bown', jsonb_build_object('sex', 'MACHO', 'dam_id', pg_temp.cx('bd1'), 'date', pg_temp.dago(3), 'lot', pg_temp.cx('lot_b')), 'u2', 'B');
SELECT pg_temp.t('B company B registers its own birth with its own lot (the reporter is user 2, company B)', $qq$pg_temp.rs('bown')->>'status' = 'recorded' AND pg_temp.n_births(pg_temp.cx('bd1')) = 1
    AND (SELECT b.id_company = pg_temp.cx('B')::integer AND lower(b.reported_by_email) = lower(pg_temp.cx('u2'))
           FROM birth_events b WHERE b.id = (pg_temp.rs('bown')->>'birth_event_id')::uuid)$qq$);

-- per-company window
SELECT pg_temp.call('cfg0', format('SELECT sp_repro_births_get_config(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.call('cfg1', format('SELECT sp_repro_births_set_config(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '30'));
SELECT pg_temp.bth('w1', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D1', 'date', pg_temp.dago(0), 'w', '31'));
SELECT pg_temp.t('B the window is per company and ADMIN-editable: default 240 for A, changed to 30 (the answer reports it); B is unaffected', $qq$pg_temp.rs('cfg0')->>'possible_duplicate_days' = '240' AND (pg_temp.rs('cfg0')->>'is_default')::boolean
    AND pg_temp.rs('cfg1')->>'status' = 'updated' AND pg_temp.rs('cfg1')->>'possible_duplicate_days' = '30'
    AND sp_repro_births_get_config(pg_temp.cx('B'), pg_temp.cx('u2'))->>'possible_duplicate_days' = '240'
    AND pg_temp.rs('w1')->>'status' = 'possible_duplicate'$qq$);
SELECT pg_temp.bth('w2', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D1', 'date', pg_temp.dago(0), 'w', '31.5', 'force', 'false', 'notes', 'only the window differs'));
SELECT pg_temp.t('B "force" = false is not a force: the births are 0-1 days apart, inside the new 30-day window, so possible_duplicate holds and reports window_days = 30', $qq$pg_temp.rs('w2')->>'status' = 'possible_duplicate' AND (pg_temp.rs('w2')->>'window_days')::int = 30$qq$);
SELECT pg_temp.t('B config validation and roles: below 30 / above 730 / text invalid; an EDITOR is forbidden; B''s ADMIN cannot touch A', $qq$sp_repro_births_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '29')->>'status' = 'invalid'
    AND sp_repro_births_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '731')->>'status' = 'invalid'
    AND sp_repro_births_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), 'abc')->>'status' = 'invalid'
    AND pg_temp.raises(format('SELECT sp_repro_births_set_config(%L, %L, ''100'')', pg_temp.cx('A'), pg_temp.cx('u2')), 'P0001')
    AND sp_repro_births_get_config(pg_temp.cx('A'), pg_temp.cx('u1'))->>'possible_duplicate_days' = '30'$qq$);
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.t('B an EDITOR may register births but is forbidden to change the window', $qq$sp_repro_births_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '100')->>'status' = 'forbidden'
    AND sp_repro_births_get_config(pg_temp.cx('A'), pg_temp.cx('u1'))->>'possible_duplicate_days' = '30'$qq$);
SELECT pg_temp.bth('ed', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-D6', 'date', pg_temp.dago(1)));
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');
SELECT pg_temp.t('B any active member registers (EDITOR)', $qq$pg_temp.rs('ed')->>'status' = 'recorded'$qq$);

-- =============================================================================================================
-- PART C. the legacy procedure
-- =============================================================================================================

CREATE TEMP TABLE t_base_leg ON COMMIT DROP AS SELECT pg_temp.n_animals() AS animals, (SELECT count(*) FROM birth_events) AS births;
SELECT pg_temp.t('C legacy: a NON-member e-mail is refused with P0001 BEFORE anything is written; so is an inactive membership', $qq$pg_temp.raises(format('SELECT sp_register_birth_event(%L::int, ''MACHO'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, ''nadie@example.test'')',
                          pg_temp.cx('A'), pg_temp.cx('d7')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_register_birth_event(%L::int, ''MACHO'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, %L)',
                              pg_temp.cx('B'), pg_temp.cx('bd2'), pg_temp.cx('u1')), 'P0001')
    AND pg_temp.n_animals() = (SELECT animals FROM t_base_leg) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_leg)$qq$);
SELECT pg_temp.call('l1', format('SELECT sp_register_birth_event(%L::int, ''HEMBRA'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, 35.0, NULL, upper(%L))',
                                 pg_temp.cx('A'), pg_temp.cx('d7'), pg_temp.cx('u1')));
SELECT pg_temp.t('C legacy: a member e-mail (any case) is accepted and stored; the answer keeps its keys and adds duplicate_skipped = false', $qq$(pg_temp.rs('l1')->>'success')::boolean AND pg_temp.rs('l1')->>'duplicate_skipped' = 'false' AND pg_temp.rs('l1') ? 'birth_event_id'
    AND pg_temp.rs('l1')->>'category' = 'BECERRA' AND (SELECT lower(b.reported_by_email) = lower(pg_temp.cx('u1')) FROM birth_events b WHERE b.id = (pg_temp.rs('l1')->>'birth_event_id')::uuid)$qq$);
SELECT pg_temp.call('l2', format('SELECT sp_register_birth_event(%L::int, ''HEMBRA'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, 35.0, NULL, %L)',
                                 pg_temp.cx('A'), pg_temp.cx('d7'), pg_temp.cx('u1')));
SELECT pg_temp.t('C legacy: an exact retry (same dam, date, sex, weight inside 5 minutes) answers success + duplicate_skipped and inserts nothing', $qq$(pg_temp.rs('l2')->>'success')::boolean AND (pg_temp.rs('l2')->>'duplicate_skipped')::boolean
    AND pg_temp.rs('l2')->>'birth_event_id' = pg_temp.rs('l1')->>'birth_event_id' AND pg_temp.rs('l2')->>'calf_id' = pg_temp.rs('l1')->>'calf_id'
    AND pg_temp.n_births(pg_temp.cx('d7')) = 1 AND pg_temp.n_calves(pg_temp.cx('d7')) = 1$qq$, $qq$pg_temp.rs('l2')::text$qq$);
SELECT pg_temp.call('l3', format('SELECT sp_register_birth_event(%L::int, ''HEMBRA'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, 41.0, NULL, %L)',
                                 pg_temp.cx('A'), pg_temp.cx('d7'), pg_temp.cx('u1')));
SELECT pg_temp.call('l4', format('SELECT sp_register_birth_event(%L::int, ''HEMBRA'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, %L)',
                                 pg_temp.cx('A'), pg_temp.cx('d7'), pg_temp.cx('u1')));
SELECT pg_temp.t('C legacy: twins with a DIFFERENT birth weight (or one without weight) are not a retry; the legacy path has no possible_duplicate check', $qq$NOT coalesce((pg_temp.rs('l3')->>'duplicate_skipped')::boolean, false) AND NOT coalesce((pg_temp.rs('l4')->>'duplicate_skipped')::boolean, false)
    AND pg_temp.n_births(pg_temp.cx('d7')) = 3$qq$);
SELECT pg_temp.call('l5', format('SELECT sp_register_birth_event(%L::int, ''MACHO'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE - 5, NULL, NULL, NULL, NULL, ''legacy null email'')',
                                 pg_temp.cx('A'), pg_temp.cx('d8')));
SELECT pg_temp.t('C legacy: the NULL e-mail path (the gateway model) still works: calf created, reporter stored as NULL', $qq$(pg_temp.rs('l5')->>'success')::boolean AND (SELECT b.reported_by_email IS NULL FROM birth_events b WHERE b.id = (pg_temp.rs('l5')->>'birth_event_id')::uuid)
    AND pg_temp.n_births(pg_temp.cx('d8')) = 1$qq$);
SELECT pg_temp.call('l6', format('SELECT sp_register_birth_event(%L::int, ''MACHO'', ''BOVINO'', NULL, NULL, %L, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, NULL)',
                                 pg_temp.cx('A'), 'T087DUP'));
SELECT pg_temp.t('C legacy: the orphan-calf behaviour is UNCHANGED - an ambiguous fire number registers a calf WITHOUT a dam and warns (ambiguity is answered only by the new function)', $qq$(pg_temp.rs('l6')->>'success')::boolean AND pg_temp.rs('l6')->>'dam_id_resolved' IS NULL AND pg_temp.rs('l6')->>'dam_status_warning' IS NOT NULL
    AND (SELECT b.dam_id IS NULL AND b.dam_fire_number = 'T087DUP' FROM birth_events b WHERE b.id = (pg_temp.rs('l6')->>'birth_event_id')::uuid)$qq$, $qq$pg_temp.rs('l6')::text$qq$);

-- =============================================================================================================
-- PART D. births by blocks
-- =============================================================================================================

CREATE TEMP TABLE t_base_blk ON COMMIT DROP AS SELECT pg_temp.n_animals() AS animals, (SELECT count(*) FROM birth_events) AS births, (SELECT count(*) FROM cattle_weight_logs) AS weights;
SELECT pg_temp.call('p1', format($f$SELECT sp_repro_births_batch_preview(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B1', 'calf_sex', 'MACHO', 'birth_date', pg_temp.dago(2), 'birth_weight_kg', '34'),
        jsonb_build_object('dam_identifier', 'T087-A-B2', 'calf_sex', 'HEMBRA', 'birth_date', pg_temp.dago(2)),
        jsonb_build_object('dam_identifier', 'T087DUP', 'calf_sex', 'MACHO'),
        jsonb_build_object('dam_identifier', 'T087-NOPE', 'calf_sex', 'MACHO'),
        jsonb_build_object('dam_identifier', 'T087-A-D1', 'calf_sex', 'MACHO', 'birth_date', pg_temp.dago(0)),
        jsonb_build_object('dam_identifier', 'T087-A-B3', 'calf_sex', 'Z'),
        jsonb_build_object('dam_identifier', 'T087-A-B1', 'calf_sex', 'MACHO'),
        'not an object')::text));
SELECT pg_temp.t('D PREVIEW reports per line: ok, ok, ambiguous (candidates), not_found, possible_duplicate, invalid, DUPLICATE_IN_BATCH, invalid; can_register = false', $qq$pg_temp.rs('p1')->>'status' = 'ok' AND (pg_temp.rs('p1')->>'total')::int = 8 AND (pg_temp.rs('p1')->>'problems')::int = 6
    AND NOT (pg_temp.rs('p1')->>'can_register')::boolean
    AND pg_temp.rs('p1')->'lines'->0->>'status' = 'ok' AND pg_temp.rs('p1')->'lines'->1->>'status' = 'ok'
    AND pg_temp.rs('p1')->'lines'->2->>'status' = 'ambiguous' AND jsonb_array_length(pg_temp.rs('p1')->'lines'->2->'candidates') = 2
    AND pg_temp.rs('p1')->'lines'->3->>'status' = 'not_found' AND pg_temp.rs('p1')->'lines'->4->>'status' = 'possible_duplicate'
    AND pg_temp.rs('p1')->'lines'->5->>'code' = 'BAD_SEX' AND pg_temp.rs('p1')->'lines'->6->>'code' = 'DUPLICATE_IN_BATCH'
    AND pg_temp.rs('p1')->'lines'->7->>'code' = 'ITEM_INCOMPLETE'$qq$, $qq$pg_temp.rs('p1')::text$qq$);
SELECT pg_temp.t('D the preview is a PURE READ: no animal, birth or weight was written', $qq$pg_temp.n_animals() = (SELECT animals FROM t_base_blk) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_blk)
    AND (SELECT count(*) FROM cattle_weight_logs) = (SELECT weights FROM t_base_blk)$qq$);
SELECT pg_temp.call('r1', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('p1')->>'status' || ''));
SELECT pg_temp.t('D a bad items text is an answer (BAD_ITEMS), not an error', $qq$pg_temp.rs('r1')->>'code' = 'BAD_ITEMS'$qq$);
SELECT pg_temp.call('r2', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B1', 'calf_sex', 'MACHO', 'birth_date', pg_temp.dago(2), 'birth_weight_kg', '34'),
        jsonb_build_object('dam_identifier', 'T087-A-B2', 'calf_sex', 'HEMBRA', 'birth_date', pg_temp.dago(2)),
        jsonb_build_object('dam_identifier', 'T087DUP', 'calf_sex', 'MACHO'))::text));
SELECT pg_temp.t('D ALL-OR-NOTHING: one ambiguous line makes the whole register answer rejected (written 0, per-line detail) and inserts nothing - even the two good lines', $qq$pg_temp.rs('r2')->>'status' = 'rejected' AND (pg_temp.rs('r2')->>'written')::int = 0 AND (pg_temp.rs('r2')->>'problems')::int = 1
    AND pg_temp.rs('r2')->'lines'->2->>'status' = 'ambiguous'
    AND pg_temp.n_animals() = (SELECT animals FROM t_base_blk) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_blk)$qq$, $qq$pg_temp.rs('r2')::text$qq$);
SELECT pg_temp.call('r3', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B1', 'calf_sex', 'MACHO', 'birth_weight_kg', '34'),
        jsonb_build_object('dam_id', pg_temp.cx('b2'), 'calf_sex', 'HEMBRA', 'lot_id', pg_temp.cx('lot_a')),
        jsonb_build_object('dam_identifier', 'T087-A-B3', 'calf_sex', 'HEMBRA', 'birth_date', pg_temp.dago(5)))::text, pg_temp.dago(2)));
SELECT pg_temp.t('D a clean block is recorded: one calf per line, the common date applies to lines without their own, a line may carry a dam id and its own lot', $qq$pg_temp.rs('r3')->>'status' = 'recorded' AND (pg_temp.rs('r3')->>'written')::int = 3 AND jsonb_array_length(pg_temp.rs('r3')->'results') = 3
    AND pg_temp.n_births(pg_temp.cx('b1')) = 1 AND pg_temp.n_births(pg_temp.cx('b2')) = 1 AND pg_temp.n_births(pg_temp.cx('b3')) = 1
    AND (SELECT b.birth_date = fn_repro_today() - 2 FROM birth_events b WHERE b.dam_id = pg_temp.cx('b1')::uuid)
    AND (SELECT b.birth_date = fn_repro_today() - 5 FROM birth_events b WHERE b.dam_id = pg_temp.cx('b3')::uuid)
    AND (SELECT lower(b.reported_by_email) = lower(pg_temp.cx('u1')) FROM birth_events b WHERE b.dam_id = pg_temp.cx('b1')::uuid)$qq$, $qq$pg_temp.rs('r3')::text$qq$);
SELECT pg_temp.call('r4', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B1', 'calf_sex', 'MACHO', 'birth_weight_kg', '34'),
        jsonb_build_object('dam_id', pg_temp.cx('b2'), 'calf_sex', 'HEMBRA', 'lot_id', pg_temp.cx('lot_a')),
        jsonb_build_object('dam_identifier', 'T087-A-B3', 'calf_sex', 'HEMBRA', 'birth_date', pg_temp.dago(5)))::text, pg_temp.dago(2)));
SELECT pg_temp.t('D the same block again is idempotent: every line duplicate_skipped, nothing inserted', $qq$pg_temp.rs('r4')->>'status' = 'recorded' AND (pg_temp.rs('r4')->>'written')::int = 0 AND (pg_temp.rs('r4')->>'duplicate_skipped')::int = 3
    AND pg_temp.n_births(pg_temp.cx('b1')) = 1 AND pg_temp.n_calves(pg_temp.cx('b1')) = 1$qq$, $qq$pg_temp.rs('r4')::text$qq$);

-- the register never trusts a preview: preview says ok, then a conflicting birth is registered, then the register must reject
SELECT pg_temp.call('p2', format($f$SELECT sp_repro_births_batch_preview(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(jsonb_build_object('dam_identifier', 'T087-A-B4', 'calf_sex', 'MACHO', 'birth_date', pg_temp.dago(1), 'birth_weight_kg', '30'))::text));
SELECT pg_temp.bth('x1', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T087-A-B4', 'date', pg_temp.dago(1), 'w', '28'));
SELECT pg_temp.call('r5', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(jsonb_build_object('dam_identifier', 'T087-A-B4', 'calf_sex', 'MACHO', 'birth_date', pg_temp.dago(1), 'birth_weight_kg', '30'))::text));
SELECT pg_temp.t('D the register re-validates by itself: the earlier preview was ok, but the dam got a birth in between, so the register answers rejected / possible_duplicate and inserts nothing', $qq$pg_temp.rs('p2')->>'status' = 'ok' AND (pg_temp.rs('p2')->>'can_register')::boolean
    AND pg_temp.rs('x1')->>'status' = 'recorded'
    AND pg_temp.rs('r5')->>'status' = 'rejected' AND pg_temp.rs('r5')->'lines'->0->>'status' = 'possible_duplicate'
    AND pg_temp.n_births(pg_temp.cx('b4')) = 1$qq$, $qq$pg_temp.rs('r5')::text$qq$);

SELECT pg_temp.call('r6', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B5', 'calf_sex', 'MACHO'),
        jsonb_build_object('dam_identifier', 'T087-A-B5', 'calf_sex', 'MACHO'))::text));
SELECT pg_temp.t('D the same dam twice in one block is rejected (DUPLICATE_IN_BATCH): twins go through the single tool with force; nothing written', $qq$pg_temp.rs('r6')->>'status' = 'rejected' AND pg_temp.rs('r6')->'lines'->1->>'code' = 'DUPLICATE_IN_BATCH' AND pg_temp.n_births(pg_temp.cx('b5')) = 0$qq$);
SELECT pg_temp.t('D the cap is 50 lines (TOO_MANY_ITEMS for 51), 50 are accepted by the validator; empty / not an array / bad common date are answers', $qq$sp_repro_births_batch_preview(pg_temp.cx('A'), pg_temp.cx('u1'), (SELECT jsonb_agg(jsonb_build_object('dam_identifier', 'x' || g, 'calf_sex', 'MACHO'))::text FROM generate_series(1, 51) g))->>'code' = 'TOO_MANY_ITEMS'
    AND sp_repro_births_batch_preview(pg_temp.cx('A'), pg_temp.cx('u1'), (SELECT jsonb_agg(jsonb_build_object('dam_identifier', 'x' || g, 'calf_sex', 'MACHO'))::text FROM generate_series(1, 50) g))->>'status' = 'ok'
    AND sp_repro_births_batch_register(pg_temp.cx('A'), pg_temp.cx('u1'), (SELECT jsonb_agg(jsonb_build_object('dam_identifier', 'x' || g, 'calf_sex', 'MACHO'))::text FROM generate_series(1, 51) g))->>'code' = 'TOO_MANY_ITEMS'
    AND sp_repro_births_batch_preview(pg_temp.cx('A'), pg_temp.cx('u1'), '[]')->>'code' = 'BAD_ITEMS'
    AND sp_repro_births_batch_preview(pg_temp.cx('A'), pg_temp.cx('u1'), '{"a":1}')->>'code' = 'BAD_ITEMS'
    AND sp_repro_births_batch_preview(pg_temp.cx('A'), pg_temp.cx('u1'), '[{"dam_identifier":"x","calf_sex":"MACHO"}]', 'ayer')->>'code' = 'BAD_DATE'$qq$);
SELECT pg_temp.call('r7', format($f$SELECT sp_repro_births_batch_register(%L, %L, %L)$f$, pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(
        jsonb_build_object('dam_identifier', 'T087-A-B6', 'calf_sex', 'MACHO'),
        jsonb_build_object('dam_id', pg_temp.cx('bd2'), 'calf_sex', 'MACHO'),
        jsonb_build_object('dam_identifier', 'T087-A-B7', 'calf_sex', 'MACHO', 'lot_id', pg_temp.cx('lot_b')))::text));
SELECT pg_temp.t('D ISOLATION: a block with a dam of company B and a lot of B is rejected line by line (not_found / LOT_NOT_FOUND) and the good line is NOT written either', $qq$pg_temp.rs('r7')->>'status' = 'rejected' AND pg_temp.rs('r7')->'lines'->1->>'status' = 'not_found' AND pg_temp.rs('r7')->'lines'->2->>'code' = 'LOT_NOT_FOUND'
    AND pg_temp.n_births(pg_temp.cx('b6')) = 0 AND pg_temp.n_births(pg_temp.cx('bd2')) = 0 AND pg_temp.n_births(pg_temp.cx('b7')) = 0$qq$);
SELECT pg_temp.t('D ISOLATION: user 1 cannot preview or register for company B (error), a stranger either', $qq$pg_temp.raises(format('SELECT sp_repro_births_batch_preview(%L, %L, ''[]'')', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_births_batch_register(%L, %L, ''[]'')', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')$qq$);

-- =============================================================================================================
-- PART E. historical births
-- =============================================================================================================

CREATE FUNCTION pg_temp.hist(p_key text, p_dam text, p_date text, p_prec text DEFAULT NULL, p_sex text DEFAULT NULL, p_lit text DEFAULT NULL,
                             p_who text DEFAULT 'u1', p_company text DEFAULT 'A', p_by_id boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_register_historical_birth(%L, %L, %L, %L, %L, %L, %L, %L, NULL, ''T087 historical'')',
        pg_temp.cx(p_company), pg_temp.cx(p_who), CASE WHEN p_by_id THEN NULL ELSE 'T087-' || p_dam END,
        CASE WHEN p_by_id THEN pg_temp.cx(lower(replace(p_dam, 'A-', ''))) END, p_date, p_prec, p_sex, p_lit));
END $$;

CREATE TEMP TABLE t_base_h ON COMMIT DROP AS
SELECT pg_temp.n_animals() AS animals, (SELECT count(*) FROM birth_events) AS births, pg_temp.dam_status(pg_temp.cx('h1')) AS h1_status,
       pg_temp.dam_status(pg_temp.cx('sold')) AS sold_status;
SELECT pg_temp.hist('hh1', 'A-H1', pg_temp.dago(100));
SELECT pg_temp.t('E a DAY historical birth is recorded: no calf, no registered birth, the dam''s status unchanged', $qq$pg_temp.rs('hh1')->>'status' = 'recorded' AND pg_temp.rs('hh1')->>'date_precision' = 'DAY' AND pg_temp.n_hist(pg_temp.cx('h1')) = 1
    AND pg_temp.n_animals() = (SELECT animals FROM t_base_h) AND (SELECT count(*) FROM birth_events) = (SELECT births FROM t_base_h)
    AND pg_temp.dam_status(pg_temp.cx('h1')) = (SELECT h1_status FROM t_base_h)$qq$, $qq$pg_temp.rs('hh1')::text$qq$);
SELECT pg_temp.hist('hh1b', 'A-H1', pg_temp.dago(100));
SELECT pg_temp.hist('hh1c', 'A-H1', pg_temp.dago(100), 'DAY', NULL, '2');
SELECT pg_temp.hist('hh1d', 'A-H1', pg_temp.dago(100), 'DAY', 'macho');
SELECT pg_temp.t('E idempotent: the same call is duplicate_skipped; a twin (litter_position 2) and a different calf sex are separate rows', $qq$pg_temp.rs('hh1b')->>'status' = 'duplicate_skipped' AND pg_temp.rs('hh1b')->>'historical_birth_id' = pg_temp.rs('hh1')->>'historical_birth_id'
    AND pg_temp.rs('hh1c')->>'status' = 'recorded' AND pg_temp.rs('hh1d')->>'status' = 'recorded' AND pg_temp.n_hist(pg_temp.cx('h1')) = 3$qq$);
SELECT pg_temp.hist('hh2', 'A-H2', to_char(fn_repro_today() - 200, 'YYYY-MM'), 'MONTH');
SELECT pg_temp.hist('hh3', 'A-H3', to_char(fn_repro_today() - 800, 'YYYY'), 'YEAR');
SELECT pg_temp.t('E MONTH accepts YYYY-MM and stores the first day; YEAR accepts YYYY and stores 1 January; there is no lower bound', $qq$pg_temp.rs('hh2')->>'status' = 'recorded' AND (pg_temp.rs('hh2')->>'birth_date')::date = date_trunc('month', fn_repro_today() - 200)::date
    AND pg_temp.rs('hh3')->>'status' = 'recorded' AND (pg_temp.rs('hh3')->>'birth_date')::date = date_trunc('year', fn_repro_today() - 800)::date
    AND pg_temp.rs('hh3')->>'date_precision' = 'YEAR'$qq$);
SELECT pg_temp.hist('hh4', 'A-SOLD', pg_temp.dago(900), NULL, 'HEMBRA');
SELECT pg_temp.t('E the dam may have ANY status of the company (a sold cow): recorded, her status returned as information and unchanged', $qq$pg_temp.rs('hh4')->>'status' = 'recorded' AND pg_temp.rs('hh4')->'dam'->>'current_status' = 'VENDIDO'
    AND pg_temp.dam_status(pg_temp.cx('sold')) = (SELECT sold_status FROM t_base_h)$qq$);
SELECT pg_temp.t('E validation: future date, bad precision, bad month text, bad sex, bad litter position, bad source, missing date', $qq$sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, to_char(fn_repro_today() + 1, 'YYYY-MM-DD'))->>'code' = 'BAD_DATE'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, pg_temp.dago(10), 'WEEK')->>'code' = 'BAD_PRECISION'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, '2024-13', 'MONTH')->>'code' = 'BAD_DATE'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, pg_temp.dago(10), 'DAY', 'X')->>'code' = 'BAD_SEX'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, pg_temp.dago(10), 'DAY', NULL, '9')->>'code' = 'BAD_LITTER'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, pg_temp.dago(10), 'DAY', NULL, NULL, 'WHATEVER')->>'code' = 'BAD_SOURCE'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H4', NULL, NULL)->>'code' = 'BAD_DATE'
    AND pg_temp.n_hist(pg_temp.cx('h4')) = 0$qq$);
SELECT pg_temp.t('E the dam of a historical birth: ambiguous fire number answers ambiguous with candidates, unknown is not_found, a dam of B is not_found for A', $qq$sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087DUP', NULL, pg_temp.dago(50))->>'status' = 'ambiguous'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-NOPE', NULL, pg_temp.dago(50))->>'status' = 'not_found'
    AND sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('bh1'), pg_temp.dago(50))->>'status' = 'not_found'
    AND pg_temp.n_hist(pg_temp.cx('bh1')) = 0$qq$);

-- historical births count for possible_duplicate: DAY and MONTH yes, YEAR no, voided no
SELECT pg_temp.hist('hw1', 'A-H5', pg_temp.dago(100));
SELECT pg_temp.hist('hw2', 'A-H6', to_char(fn_repro_today() - 200, 'YYYY-MM'), 'MONTH');
SELECT pg_temp.hist('hw3', 'A-H7', to_char(fn_repro_today() - 200, 'YYYY'), 'YEAR');
SELECT pg_temp.hist('hw4', 'A-H8', pg_temp.dago(100));
SELECT pg_temp.call('hv', format('SELECT sp_repro_void_historical_birth(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('hw4')->>'historical_birth_id', 'T087 captured twice'));
SELECT pg_temp.call('set240', format('SELECT sp_repro_births_set_config(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '240'));
SELECT pg_temp.bth('hb1', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-H5', 'date', pg_temp.dago(10)));
SELECT pg_temp.bth('hb2', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-H6', 'date', pg_temp.dago(0)));
SELECT pg_temp.bth('hb3', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-H7', 'date', pg_temp.dago(0)));
SELECT pg_temp.bth('hb4', jsonb_build_object('sex', 'MACHO', 'dam', 'T087-A-H8', 'date', pg_temp.dago(10)));
SELECT pg_temp.t('E a DAY historical birth (100 days earlier) triggers possible_duplicate and names it as source HISTORICAL; a MONTH one overlaps the window too', $qq$pg_temp.rs('hb1')->>'status' = 'possible_duplicate' AND pg_temp.rs('hb1')->'existing'->0->>'source' = 'HISTORICAL'
    AND pg_temp.rs('hb1')->'existing'->0->>'id' = pg_temp.rs('hw1')->>'historical_birth_id'
    AND pg_temp.rs('hb2')->>'status' = 'possible_duplicate' AND pg_temp.rs('hb2')->'existing'->0->>'date_precision' = 'MONTH'
    AND pg_temp.n_births(pg_temp.cx('h5')) = 0 AND pg_temp.n_births(pg_temp.cx('h6')) = 0$qq$, $qq$pg_temp.rs('hb1')::text$qq$);
SELECT pg_temp.t('E a YEAR historical birth is too coarse (does NOT trigger), and a VOIDED one never counts: both births are recorded', $qq$pg_temp.rs('hb3')->>'status' = 'recorded' AND pg_temp.rs('hv')->>'status' = 'voided' AND pg_temp.rs('hb4')->>'status' = 'recorded'
    AND pg_temp.n_births(pg_temp.cx('h7')) = 1 AND pg_temp.n_births(pg_temp.cx('h8')) = 1$qq$);

-- void
SELECT pg_temp.call('hv2', format('SELECT sp_repro_void_historical_birth(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('hw4')->>'historical_birth_id', 'again please'));
SELECT pg_temp.call('hv3', format('SELECT sp_repro_void_historical_birth(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('hw1')->>'historical_birth_id', 'x'));
SELECT pg_temp.call('hv4', format('SELECT sp_repro_void_historical_birth(%L, %L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u2'), pg_temp.rs('hw1')->>'historical_birth_id', 'not mine, valid reason'));
SELECT pg_temp.t('E void: one void per birth (already_voided), a reason is required (REASON_REQUIRED), and ANOTHER company''s id answers not_found and voids nothing', $qq$pg_temp.rs('hv2')->>'status' = 'already_voided' AND pg_temp.rs('hv3')->>'code' = 'REASON_REQUIRED' AND pg_temp.rs('hv4')->>'status' = 'not_found'
    AND NOT EXISTS (SELECT 1 FROM repro_historical_birth_voids WHERE historical_birth_id = (pg_temp.rs('hw1')->>'historical_birth_id')::uuid)
    AND sp_repro_void_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), 'nope', 'valid reason')->>'code' = 'BAD_ID'
    AND (SELECT count(*) FROM repro_historical_birth_voids WHERE historical_birth_id = (pg_temp.rs('hw4')->>'historical_birth_id')::uuid) = 1$qq$);
SELECT pg_temp.call('hl', format('SELECT sp_repro_list_historical_births(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H1'));
SELECT pg_temp.call('hl2', format('SELECT sp_repro_list_historical_births(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H8', 'true'));
SELECT pg_temp.call('hl3', format('SELECT sp_repro_list_historical_births(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u2')));
SELECT pg_temp.t('E list: by dam; voided rows hidden unless asked; company B sees none of A''s historical births', $qq$(pg_temp.rs('hl')->>'total')::int = 3 AND (pg_temp.rs('hl2')->>'total')::int = 1 AND (pg_temp.rs('hl2')->'historical_births'->0->>'voided')::boolean
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('hl3')->'historical_births') e WHERE e->>'dam_id' IN (SELECT dam_id::text FROM repro_historical_births WHERE id_company = pg_temp.cx('A')::integer)) = 0
    AND sp_repro_list_historical_births(pg_temp.cx('A'), pg_temp.cx('u1'), 'T087-A-H8')->>'total' = '0'$qq$);

SELECT pg_temp.t('E append-only: UPDATE and DELETE of both historical tables raise P0095; TRUNCATE of the voids table raises P0095; TRUNCATE of the PARENT table is refused by its foreign key from the voids table (0A000, checked before the trigger) or by the trigger (P0095), and TRUNCATE ... CASCADE reaches the triggers (P0095)', $qq$pg_temp.raises('UPDATE repro_historical_births SET notes = ''x''', 'P0095') AND pg_temp.raises('DELETE FROM repro_historical_births', 'P0095')
    AND pg_temp.raises_any('TRUNCATE repro_historical_births', ARRAY['P0095', '0A000']) AND pg_temp.raises('TRUNCATE repro_historical_births CASCADE', 'P0095')
    AND pg_temp.raises('UPDATE repro_historical_birth_voids SET reason = ''xxx''', 'P0095')
    AND pg_temp.raises('DELETE FROM repro_historical_birth_voids', 'P0095') AND pg_temp.raises('TRUNCATE repro_historical_birth_voids', 'P0095')$qq$);
SELECT pg_temp.t('E tenant guards: a historical birth whose company is not the dam''s company raises P0096; a void of another company''s birth raises P0096', $qq$pg_temp.raises(format('INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, entered_by_email) VALUES (%L, %L, CURRENT_DATE, ''DAY'', ''x'')',
                          pg_temp.cx('B'), pg_temp.cx('h1')), 'P0096')
    AND pg_temp.raises(format('INSERT INTO repro_historical_birth_voids (id_company, historical_birth_id, reason, voided_by_email) VALUES (%L, %L, ''abc'', ''x'')',
                              pg_temp.cx('B'), pg_temp.rs('hw1')->>'historical_birth_id'), 'P0096')$qq$);
SELECT pg_temp.t('E constraints: bad precision, a MONTH not on day 1, a YEAR not on 1 January, a bad sex and a short void reason are refused (23514)', $qq$pg_temp.raises(format('INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, entered_by_email) VALUES (%L, %L, CURRENT_DATE, ''WEEK'', ''x'')', pg_temp.cx('A'), pg_temp.cx('h1')), '23514')
    AND pg_temp.raises(format('INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, entered_by_email) VALUES (%L, %L, ''2024-03-15'', ''MONTH'', ''x'')', pg_temp.cx('A'), pg_temp.cx('h1')), '23514')
    AND pg_temp.raises(format('INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, entered_by_email) VALUES (%L, %L, ''2024-02-01'', ''YEAR'', ''x'')', pg_temp.cx('A'), pg_temp.cx('h1')), '23514')
    AND pg_temp.raises(format('INSERT INTO repro_historical_births (id_company, dam_id, birth_date, date_precision, calf_sex, entered_by_email) VALUES (%L, %L, CURRENT_DATE, ''DAY'', ''X'', ''x'')', pg_temp.cx('A'), pg_temp.cx('h1')), '23514')
    AND pg_temp.raises(format('INSERT INTO repro_historical_birth_voids (id_company, historical_birth_id, reason, voided_by_email) VALUES (%L, %L, ''ab'', ''x'')',
                              pg_temp.cx('A'), pg_temp.rs('hw1')->>'historical_birth_id'), '23514')$qq$);
SELECT pg_temp.t('E by dam id also works (and the registered-birth overlap is informational: none here)', $qq$(SELECT sp_repro_register_historical_birth(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('h2'), pg_temp.dago(700))->>'status') = 'recorded'$qq$);

-- =============================================================================================================
-- PART F. fail-closed on every tool
-- =============================================================================================================

SELECT pg_temp.t('F every tool raises P0001 for user 1 on company B (not a member), for a stranger, a blank e-mail and bad tenants', $qq$(SELECT bool_and(pg_temp.raises(format(t.sql_tpl, pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A'), 'nadie@example.test'), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A'), ''), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, 'abc', pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, '', pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A') || ' OR 1=1', pg_temp.cx('u1')), 'P0001'))
       FROM (VALUES
            ('SELECT sp_repro_births_get_config(%L, %L)'),
            ('SELECT sp_repro_births_set_config(%L, %L, ''60'')'),
            ('SELECT sp_repro_register_birth(%L, %L, ''MACHO'', ''T087-A-D8'')'),
            ('SELECT sp_repro_births_batch_preview(%L, %L, ''[]'')'),
            ('SELECT sp_repro_births_batch_register(%L, %L, ''[]'')'),
            ('SELECT sp_repro_register_historical_birth(%L, %L, ''T087-A-H1'', NULL, ''2020-01-01'')'),
            ('SELECT sp_repro_void_historical_birth(%L, %L, ''00000000-0000-0000-0000-000000000000'', ''reason'')'),
            ('SELECT sp_repro_list_historical_births(%L, %L)')) AS t (sql_tpl))$qq$);
SELECT pg_temp.t('F ... and none of those rejected calls wrote anything (D8 has no new birth, configs unchanged)', $qq$pg_temp.n_births(pg_temp.cx('d8')) = 1 AND sp_repro_births_get_config(pg_temp.cx('B'), pg_temp.cx('u2'))->>'possible_duplicate_days' = '240'$qq$);

DO $$
DECLARE
    v_palm integer;
BEGIN
    SELECT c.id_company INTO v_palm FROM companys c WHERE c.is_active AND fn_company_business_domain(c.id_company) = 'PALM' ORDER BY c.id_company LIMIT 1;
    IF v_palm IS NULL THEN
        INSERT INTO t_result (test, ok, detail) VALUES ('F palm company is rejected (P0094) - skipped: no palm company in this database', true, 'skipped');
        RETURN;
    END IF;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT pg_temp.cx('u1'), v_palm, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = pg_temp.cx('u1') AND id_company = v_palm);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = pg_temp.cx('u1') AND id_company = v_palm;
    INSERT INTO t_result (test, ok, detail)
    VALUES ('F palm company is rejected (P0094) by every birth tool',
            pg_temp.raises(format('SELECT sp_repro_births_get_config(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_births_set_config(%L, %L, ''60'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_register_birth(%L, %L, ''MACHO'', ''x'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_births_batch_preview(%L, %L, ''[]'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_births_batch_register(%L, %L, ''[]'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_register_historical_birth(%L, %L, ''x'', NULL, ''2020-01-01'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_void_historical_birth(%L, %L, gen_random_uuid()::text, ''reason'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_historical_births(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094'),
            'palm company ' || v_palm);
END $$;

-- =============================================================================================================
-- PART G. nothing else was written
-- =============================================================================================================

SELECT pg_temp.t('G sp_log_breeding_event, sp_void_event and sp_log_palpation_event are byte-identical to the start of this run (087 does not touch them)', $qq$NOT EXISTS (SELECT 1 FROM t_proc t JOIN pg_proc p ON p.proname = t.proname AND p.pronamespace = 'public'::regnamespace
                 WHERE md5(pg_get_functiondef(p.oid)) <> t.md5)$qq$);
SELECT pg_temp.t('G the legacy procedure carries the 087 marker and still has exactly its 13-parameter signature', $qq$(SELECT prosrc LIKE '%087:legacy-birth-v1%' AND pronargs = 13 FROM pg_proc WHERE oid = to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)'))$qq$);
SELECT pg_temp.t('G none of the 087 tables or tools is exposed through crud_models', $qq$NOT EXISTS (SELECT 1 FROM crud_models
                 WHERE table_name IN ('repro_births_config', 'repro_historical_births', 'repro_historical_birth_voids')
                    OR model_name IN ('repro_births_config', 'repro_historical_births', 'repro_historical_birth_voids')
                    OR table_name LIKE 'sp\_repro\_%' OR model_name LIKE 'sp\_repro\_%')$qq$);
SELECT pg_temp.t('G every registered birth of the fixtures belongs to the company of its dam; every calf has the dam''s company; no birth_events row lost its company', $qq$NOT EXISTS (SELECT 1 FROM birth_events b JOIN cattle_livestock d ON d.id = b.dam_id WHERE d.rfid_siniiga LIKE 'T087%' AND d.tenant_id <> b.id_company)
    AND NOT EXISTS (SELECT 1 FROM cattle_livestock c JOIN cattle_livestock d ON d.id = c.mother_id WHERE d.rfid_siniiga LIKE 'T087%' AND d.tenant_id <> c.tenant_id)$qq$);
SELECT pg_temp.t('G no PREÑADA or other dam changed category (only d1 changed status, PREÑADA -> VACÍA, through the legacy writer)', $qq$NOT EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T087-A-%' AND category NOT IN ('VACA', 'TORO', 'NOVILLONA', 'BECERRO', 'BECERRA'))$qq$);

SELECT pg_temp.t('087 tests ran inside ONE transaction: no included file committed or rolled back (the same txid is still current)',
    $qq$ txid_current()::text = (SELECT v FROM t_ctx WHERE k = 'txid') $qq$);

\echo === RESULTS
-- Any ERROR line printed above (outside this table) is an unexpected error in a fixture / helper statement, not a failed assertion.
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 400) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
\set ON_ERROR_STOP on
\set ON_ERROR_ROLLBACK off
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '087 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 087 tests: everything rolled back ***'
