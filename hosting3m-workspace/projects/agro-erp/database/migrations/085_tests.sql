-- 085_tests.sql — functional checks for migration 085 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It loads 084 and 085 inside this transaction (embedded mode), so it runs the same way whether or not they are
-- applied. It needs a database that has the real schema plus AT LEAST two ACTIVE non-palm companies and two users
-- (see 085_RUNBOOK.md, "Test database"). It picks the two companies (A, B) and two users, and arranges memberships INSIDE
-- the transaction (filtered UPDATE / INSERT, rolled back):
--     user 1: ACTIVE ADMIN of A, INACTIVE in B        user 2: ACTIVE ADMIN of B, INACTIVE in A
-- Fixture animals use identifiers prefixed T085 so existing data cannot interfere; assertions are about those fixtures
-- (found by id in the paged lists), never about counts of pre-existing data.
--
-- Snapshot rule used throughout: a statement never reads a row that a write tool created in the SAME statement
-- (the outer snapshot cannot see it). Every write goes through pg_temp.call(key, sql) in its own statement; the result is
-- kept in t_res and asserted in the NEXT statement.
--
-- Part A  per-company config (defaults, ADMIN only, validation, notify stays off, isolation)
-- Part B  list_heifers_eligible_for_empadre (EDAD / PESO / AMBAS, SIN_DATOS, exclusions, thresholds, isolation)
-- Part C  log_empadre_entry (warning, idempotency, validations, ambiguity, dates, roles, append-only, tenant guards)
-- Part D  log_empadre_entry_batch (all-or-nothing, idempotent retry, per-item overrides, cross-company items)
-- Part E  sp_void_empadre_entry (reason, one void per entry, isolation)
-- Part F  list_empadre_entries
-- Part G  list_open_cows (both palpation key sets, both spellings, voided services, N days, isolation)
-- Part H  fail-closed on every tool (stranger, other company, blank, bad tenant, palm)
-- Part I  nothing else was written (animals, events, sp_void_event untouched, no crud_models rows)
--
-- Run (the test files must be INSIDE the container; psql resolves \ir relative to this file):
--   docker exec n8n-enterprise-db rm -rf /tmp/m085
--   docker cp database/migrations n8n-enterprise-db:/tmp/m085
--   docker exec -w /tmp/m085 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m085/085_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE t_res (k text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.cx(p_key text) RETURNS text
LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;

-- run a statement that returns one jsonb value and keep it under a key (own statement => visible to the next one)
CREATE FUNCTION pg_temp.call(p_key text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    EXECUTE p_sql INTO v;
    INSERT INTO t_res (k, r) VALUES (p_key, v);
END $$;

CREATE FUNCTION pg_temp.rs(p_key text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT r FROM t_res WHERE k = p_key $$;

-- log_empadre_entry for company A as user 1 (or p_who)
CREATE FUNCTION pg_temp.log1(p_key text, p_ident text, p_bull text DEFAULT NULL, p_date text DEFAULT NULL,
                             p_method text DEFAULT NULL, p_notes text DEFAULT NULL, p_who text DEFAULT 'u1') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_log_empadre_entry(%L, %L, %L, %L, %L, %L, %L)',
                                       pg_temp.cx('A'), pg_temp.cx(p_who), p_ident, p_bull, p_date, p_method, p_notes));
END $$;

CREATE FUNCTION pg_temp.batch1(p_key text, p_items text, p_bull text DEFAULT NULL, p_method text DEFAULT NULL,
                               p_notes text DEFAULT NULL, p_date text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_log_empadre_entry_batch(%L, %L, %L, %L, %L, %L, %L)',
                                       pg_temp.cx('A'), pg_temp.cx('u1'), p_items, p_date, p_bull, p_method, p_notes));
END $$;

-- true when the statement raises exactly this SQLSTATE
CREATE FUNCTION pg_temp.raises(p_sql text, p_state text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE = p_state;
END $$;

CREATE FUNCTION pg_temp.raises_any(p_sql text, p_states text[]) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE = ANY (p_states);
END $$;

-- first element of a paged list (p_array = 'eligible' | 'sin_datos') whose livestock_id matches; walks up to 20 pages
CREATE FUNCTION pg_temp.find_elig(p_tenant text, p_email text, p_array text, p_id text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    o integer := 0; r jsonb; e jsonb;
BEGIN
    WHILE o < 2000 LOOP
        r := sp_repro_list_heifers_eligible_for_empadre(p_tenant, p_email, '100', o::text);
        SELECT x INTO e FROM jsonb_array_elements(r->p_array) x WHERE x->>'livestock_id' = p_id LIMIT 1;
        IF e IS NOT NULL THEN RETURN e; END IF;
        EXIT WHEN NOT (r->>'has_more')::boolean;
        o := o + 100;
    END LOOP;
    RETURN NULL;
END $$;

-- 1-based position and element of a cow in the paged open-cows list: {pos, cow}, or NULL when it is not listed
CREATE FUNCTION pg_temp.find_cow(p_tenant text, p_email text, p_days text, p_id text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    o integer := 0; r jsonb; e jsonb; p integer;
BEGIN
    WHILE o < 3000 LOOP
        r := sp_repro_list_open_cows(p_tenant, p_email, p_days, '100', o::text);
        SELECT x.ord::integer, x.val INTO p, e
          FROM jsonb_array_elements(r->'cows') WITH ORDINALITY AS x(val, ord) WHERE x.val->>'livestock_id' = p_id LIMIT 1;
        IF e IS NOT NULL THEN RETURN jsonb_build_object('pos', o + p, 'cow', e); END IF;
        EXIT WHEN NOT (r->>'has_more')::boolean;
        o := o + 100;
    END LOOP;
    RETURN NULL;
END $$;

CREATE FUNCTION pg_temp.n_entries(p_heifer text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM repro_empadre_entries WHERE heifer_id = p_heifer::uuid $$;

CREATE FUNCTION pg_temp.cfg_rows(p_company text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM repro_empadre_config WHERE id_company = p_company::integer $$;

CREATE FUNCTION pg_temp.n_voids() RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM repro_empadre_voids $$;

-- =============================================================================================================
-- Setup: two companies, two users, memberships (all inside this transaction)
-- =============================================================================================================

DO $$
DECLARE
    v_a  integer;
    v_b  integer;
    v_e1 text;
    v_e2 text;
BEGIN
    SELECT c.id_company INTO v_a FROM companys c
     WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM'
     ORDER BY c.id_company LIMIT 1;
    SELECT c.id_company INTO v_b FROM companys c
     WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM' AND c.id_company <> v_a
     ORDER BY c.id_company LIMIT 1;
    IF v_a IS NULL OR v_b IS NULL THEN
        RAISE EXCEPTION '085 tests need two active non-palm companies in the database (see 085_RUNBOOK.md, Test database).';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '085 tests need two users in the database (see 085_RUNBOOK.md, Test database).';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T085%') THEN
        RAISE EXCEPTION '085 tests: T085 fixtures already exist in this database; run the tests on a clean copy.';
    END IF;

    -- user 1: ADMIN of A, inactive in B.   user 2: ADMIN of B, inactive in A.
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e1, v_a, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e1 AND id_company = v_a);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e1 AND id_company = v_a;
    UPDATE user_companies SET is_active = false WHERE email = v_e1 AND id_company = v_b;

    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e2, v_b, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e2 AND id_company = v_b);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e2 AND id_company = v_b;
    UPDATE user_companies SET is_active = false WHERE email = v_e2 AND id_company = v_a;

    -- a clean slate for the two companies' config (filtered by company; rolled back with everything else)
    DELETE FROM repro_empadre_config WHERE id_company IN (v_a, v_b);

    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

CREATE FUNCTION pg_temp.setrole(p_email text, p_company text, p_role text) RETURNS void
LANGUAGE sql AS $$ UPDATE user_companies SET role = p_role WHERE email = p_email AND id_company = p_company::integer $$;

-- Fixtures ------------------------------------------------------------------------------------------------

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_key text, p_fuego text, p_cat text, p_status text, p_birth date DEFAULT NULL) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego, birth_date)
    VALUES (p_tenant, 'T085-' || p_key, 'CRIA', p_cat, p_status, p_fuego, p_birth)
    RETURNING id
$$;

-- weight logs fire update_current_weight (current_weight_kg = the inserted weight; log_date is ignored by the trigger)
CREATE FUNCTION pg_temp.wt(p_id uuid, p_kg numeric, p_days_ago integer) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
    VALUES (p_id, p_kg, now() - make_interval(days => p_days_ago), 'T085')
$$;

DO $$
DECLARE
    a integer := pg_temp.cx('A')::integer;
    b integer := pg_temp.cx('B')::integer;
    id uuid;
    k text;
BEGIN
    -- heifers (company A)
    id := pg_temp.mk(a, 'A-HAGE', '2097', 'NOVILLONA', 'ACTIVO');                       -- legacy number: year only (2020)
    INSERT INTO t_ctx VALUES ('h_age', id::text);
    id := pg_temp.mk(a, 'A-HWEIGHT', NULL, 'BECERRA', 'ACTIVO', current_date - 200);    -- young, heavy, stale weight
    PERFORM pg_temp.wt(id, 320, 100);
    INSERT INTO t_ctx VALUES ('h_weight', id::text);
    id := pg_temp.mk(a, 'A-HBOTH', NULL, 'NOVILLONA', 'ACTIVO', current_date - 600);    -- old and heavy, fresh weight
    PERFORM pg_temp.wt(id, 310, 0);
    INSERT INTO t_ctx VALUES ('h_both', id::text);
    id := pg_temp.mk(a, 'A-HBELOW', NULL, 'BECERRA', 'ACTIVO', current_date - 120);     -- below both
    PERFORM pg_temp.wt(id, 120, 0);
    INSERT INTO t_ctx VALUES ('h_below', id::text);
    id := pg_temp.mk(a, 'A-HBELOW2', NULL, 'BECERRA', 'ACTIVO', current_date - 100);    -- below both, no weight
    INSERT INTO t_ctx VALUES ('h_below2', id::text);
    id := pg_temp.mk(a, 'A-HNODATA', 'S/N', 'NOVILLONA', 'ACTIVO');                     -- no age, no weight
    INSERT INTO t_ctx VALUES ('h_nodata', id::text);
    id := pg_temp.mk(a, 'A-HPREG', '2097', 'NOVILLONA', 'PREÑADA');
    INSERT INTO t_ctx VALUES ('h_preg', id::text);
    id := pg_temp.mk(a, 'A-HSOLD', '2097', 'NOVILLONA', 'VENDIDO');
    INSERT INTO t_ctx VALUES ('h_sold', id::text);
    id := pg_temp.mk(a, 'A-HDUP1', 'T085DUP', 'BECERRA', 'ACTIVO', current_date - 500);
    INSERT INTO t_ctx VALUES ('h_dup1', id::text);
    id := pg_temp.mk(a, 'A-HDUP2', 'T085DUP', 'BECERRA', 'ACTIVO', current_date - 500);
    INSERT INTO t_ctx VALUES ('h_dup2', id::text);
    FOREACH k IN ARRAY ARRAY['e1', 'e2', 'e3', 'e4', 'e5'] LOOP
        id := pg_temp.mk(a, 'A-' || upper(k), NULL, 'NOVILLONA', 'ACTIVO', current_date - 600);
        INSERT INTO t_ctx VALUES (k, id::text);
    END LOOP;
    -- bulls and others (company A)
    id := pg_temp.mk(a, 'A-BULL1', 'T085BULL', 'TORO', 'ACTIVO');   INSERT INTO t_ctx VALUES ('bull_a', id::text);
    id := pg_temp.mk(a, 'A-BULLD1', 'T085BDUP', 'TORO', 'ACTIVO');  INSERT INTO t_ctx VALUES ('bull_d1', id::text);
    id := pg_temp.mk(a, 'A-BULLD2', 'T085BDUP', 'TORO', 'ACTIVO');  INSERT INTO t_ctx VALUES ('bull_d2', id::text);
    id := pg_temp.mk(a, 'A-BULLS', NULL, 'TORO', 'VENDIDO');        INSERT INTO t_ctx VALUES ('bull_sold', id::text);
    id := pg_temp.mk(a, 'A-STEER', NULL, 'NOVILLO', 'ACTIVO');      INSERT INTO t_ctx VALUES ('steer', id::text);
    id := pg_temp.mk(a, 'A-COW', NULL, 'VACA', 'ACTIVO');           INSERT INTO t_ctx VALUES ('cow_a', id::text);
    -- open-cow fixtures (company A)
    id := pg_temp.mk(a, 'A-OC1', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('oc1', id::text);   -- never served; English key, accent-less spelling
    id := pg_temp.mk(a, 'A-OC2', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('oc2', id::text);   -- served 30 days ago
    id := pg_temp.mk(a, 'A-OC3', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('oc3', id::text);   -- served 120 days ago
    id := pg_temp.mk(a, 'A-OC4', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('oc4', id::text);   -- service 30 days ago, VOIDED
    id := pg_temp.mk(a, 'A-OC5', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('oc5', id::text);   -- pregnant: not open
    id := pg_temp.mk(a, 'A-OC6', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('oc6', id::text);   -- Spanish key set
    -- company B
    id := pg_temp.mk(b, 'B-HB', '2097', 'BECERRA', 'ACTIVO', current_date - 600);  INSERT INTO t_ctx VALUES ('hb', id::text);
    id := pg_temp.mk(b, 'B-BULL', NULL, 'TORO', 'ACTIVO');                          INSERT INTO t_ctx VALUES ('bull_b', id::text);
    id := pg_temp.mk(b, 'B-OCB', NULL, 'VACA', 'VACÍA');                            INSERT INTO t_ctx VALUES ('oc_b', id::text);

    -- breeding events and palpations of the open-cow fixtures
    INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method) VALUES
        (pg_temp.cx('oc2')::uuid, a, current_date - 30,  'MONTA_NATURAL'),
        (pg_temp.cx('oc3')::uuid, a, current_date - 120, 'MONTA_NATURAL'),
        (pg_temp.cx('oc4')::uuid, a, current_date - 30,  'MONTA_NATURAL');
    INSERT INTO event_voids (tenant_id, event_table, event_id, voided_by_email, voided_reason)
    SELECT a, 'cattle_breeding_events', be.id, 'T085', 'T085 fixture'
      FROM cattle_breeding_events be WHERE be.livestock_id = pg_temp.cx('oc4')::uuid;
    INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date) VALUES
        (pg_temp.cx('oc1')::uuid,  'PALPACION', 'T085 old',    '{"result": "PREÑADA", "gestation_days": 60}',                         now() - interval '90 days'),
        (pg_temp.cx('oc1')::uuid,  'PALPACION', 'T085 latest', '{"result": "VACIA"}',                                                 now() - interval '40 days'),
        (pg_temp.cx('oc6')::uuid,  'PALPACION', 'T085 es',     '{"resultado": "VACÍA", "dias_gestacion": 0, "condicion_utero": "UNE"}', now() - interval '10 days'),
        (pg_temp.cx('oc_b')::uuid, 'PALPACION', 'T085 B',      '{"result": "VACÍA"}',                                                 now() - interval '5 days');
END $$;

-- Counts of everything the 085 tools must NOT write to (checked again in part I), taken after the fixtures.
CREATE TEMP TABLE t_counts ON COMMIT DROP AS
SELECT (SELECT count(*) FROM birth_events) AS births, (SELECT count(*) FROM cattle_livestock) AS animals,
       (SELECT count(*) FROM cattle_weight_logs) AS weights, (SELECT count(*) FROM event_voids) AS voids,
       (SELECT count(*) FROM cattle_breeding_events) AS services, (SELECT count(*) FROM cattle_health_logs) AS health,
       (SELECT md5(string_agg(concat_ws('|', id::text, category, current_status), ',' ORDER BY id))
          FROM cattle_livestock WHERE rfid_siniiga LIKE 'T085%') AS fixture_state;

-- =============================================================================================================
-- PART A. config
-- =============================================================================================================

SELECT pg_temp.ok('A defaults for a company without a row (15 months, 300 kg, 60, 90, notify off)',
    (SELECT c->>'status' = 'ok' AND (c->>'min_age_months')::int = 15 AND (c->>'min_weight_kg')::numeric = 300
            AND (c->>'weight_stale_days')::int = 60 AND (c->>'empadre_window_days')::int = 90
            AND (c->>'notify_enabled')::boolean = false AND (c->>'is_default')::boolean = true
       FROM (SELECT sp_repro_empadre_get_config(pg_temp.cx('A'), pg_temp.cx('u1')) AS c) x));

SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.ok('A a non-ADMIN member is refused (forbidden) and no row is created',
    sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '10', '200')->>'status' = 'forbidden'
    AND pg_temp.cfg_rows(pg_temp.cx('A')) = 0);
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');

SELECT pg_temp.call('a_set1', format('SELECT sp_repro_empadre_set_config(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '14', '280.5'));
SELECT pg_temp.ok('A ADMIN changes the thresholds; the new values are read back, with the author, in a row of company A',
    (SELECT c->>'status' = 'updated' AND (c->>'min_age_months')::int = 14 AND (c->>'min_weight_kg')::numeric = 280.5
            AND (c->>'is_default')::boolean = false AND c->>'updated_by_email' = lower(pg_temp.cx('u1'))
       FROM (SELECT pg_temp.rs('a_set1') AS c) x)
    AND pg_temp.cfg_rows(pg_temp.cx('A')) = 1);

SELECT pg_temp.call('a_set2', format('SELECT sp_repro_empadre_set_config(%L, %L, NULL, NULL, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '45'));
SELECT pg_temp.ok('A a partial update keeps the other values',
    (SELECT (c->>'min_age_months')::int = 14 AND (c->>'min_weight_kg')::numeric = 280.5 AND (c->>'weight_stale_days')::int = 45
            AND (c->>'empadre_window_days')::int = 90
       FROM (SELECT pg_temp.rs('a_set2') AS c) x));

SELECT pg_temp.ok('A out-of-range / malformed values and an empty call are rejected (invalid) and change nothing',
    sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '0')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), '121')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), 'abc')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, '-5')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, '12,5')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, '5000')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, NULL, '0')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, NULL, NULL, '366')->>'status' = 'invalid'
    AND sp_repro_empadre_set_config(pg_temp.cx('A'), pg_temp.cx('u1'))->>'status' = 'invalid');
SELECT pg_temp.ok('A ... and the stored values are unchanged',
    (SELECT min_age_months = 14 AND min_weight_kg = 280.5 AND weight_stale_days = 45 AND empadre_window_days = 90
       FROM repro_empadre_config WHERE id_company = pg_temp.cx('A')::integer));
SELECT pg_temp.ok('A notify_enabled cannot be turned on (check constraint) and no tool parameter exists for it',
    pg_temp.raises(format('UPDATE repro_empadre_config SET notify_enabled = true WHERE id_company = %s', pg_temp.cx('A')), '23514')
    AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'sp_repro_empadre_set_config' AND p.pronamespace = 'public'::regnamespace
                       AND pg_get_function_arguments(p.oid) ILIKE '%notify%'));
SELECT pg_temp.ok('A ISOLATION: user 1 (member of A only) gets an ERROR, not data, for B: get_config and set_config; no row for B',
    pg_temp.raises(format('SELECT sp_repro_empadre_get_config(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_empadre_set_config(%L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), '10'), 'P0001')
    AND pg_temp.cfg_rows(pg_temp.cx('B')) = 0);
SELECT pg_temp.ok('A company B keeps its own defaults, unaffected by the change in A',
    (SELECT (c->>'min_age_months')::int = 15 AND (c->>'is_default')::boolean
       FROM (SELECT sp_repro_empadre_get_config(pg_temp.cx('B'), pg_temp.cx('u2')) AS c) x));

SELECT pg_temp.call('a_restore', format('SELECT sp_repro_empadre_set_config(%L, %L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '15', '300', '60'));
SELECT pg_temp.ok('A thresholds restored to 15 months / 300 kg for the rest of the tests',
    (SELECT (c->>'min_age_months')::int = 15 AND (c->>'min_weight_kg')::numeric = 300 AND (c->>'weight_stale_days')::int = 60
       FROM (SELECT pg_temp.rs('a_restore') AS c) x));

-- =============================================================================================================
-- PART B. eligible heifers
-- =============================================================================================================

SELECT pg_temp.ok('B EDAD: a legacy year-only age counts with its minimum possible age and is shown as YEAR_ONLY',
    (SELECT e->>'eligibility_trigger' = 'EDAD' AND e->>'age_precision' = 'YEAR_ONLY' AND e->'age_months' = 'null'::jsonb
            AND (e->>'age_months_min')::int >= 15 AND e->>'age_source' = 'ESTIMADA_NUMERO_FUEGO' AND e->>'category' = 'NOVILLONA'
            AND (e->>'category_possibly_outdated')::boolean = false
       FROM (SELECT pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_age')) AS e) x));
SELECT pg_temp.ok('B PESO: a young heavy BECERRA is eligible by weight, with its weigh-in date, flagged stale and category_possibly_outdated',
    (SELECT e->>'eligibility_trigger' = 'PESO' AND (e->>'weight_kg')::numeric = 320 AND e->>'weight_date' IS NOT NULL
            AND (e->>'weight_stale')::boolean AND (e->>'category_possibly_outdated')::boolean AND e->>'age_precision' = 'MONTH'
            AND (e->>'age_months')::int < 15
       FROM (SELECT pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_weight')) AS e) x));
SELECT pg_temp.ok('B AMBAS: old and heavy with a fresh weight, not stale',
    (SELECT e->>'eligibility_trigger' = 'AMBAS' AND NOT (e->>'weight_stale')::boolean AND (e->>'age_months')::int >= 15
       FROM (SELECT pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_both')) AS e) x));
SELECT pg_temp.ok('B below both thresholds: in neither list',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_below')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'sin_datos', pg_temp.cx('h_below')) IS NULL);
SELECT pg_temp.ok('B SIN_DATOS: no usable age and no valid weight goes to sin_datos, not to eligible',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'sin_datos', pg_temp.cx('h_nodata')) IS NOT NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_nodata')) IS NULL);
SELECT pg_temp.ok('B PREÑADA and VENDIDO heifers are in no list',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_preg')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'sin_datos', pg_temp.cx('h_preg')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_sold')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'sin_datos', pg_temp.cx('h_sold')) IS NULL);
SELECT pg_temp.ok('B a VACA and a bull are never listed as heifers',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('cow_a')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'sin_datos', pg_temp.cx('cow_a')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('bull_a')) IS NULL);
SELECT pg_temp.ok('B the answer has the agreed shape (thresholds, totals, eligible, sin_datos) and no physical-review bucket',
    (SELECT r ? 'eligible' AND r ? 'sin_datos' AND r ? 'thresholds' AND r ? 'eligible_total' AND r ? 'no_data_total'
            AND r ? 'below_thresholds_total' AND NOT (r::text ILIKE '%REQUIERE_REVISION%')
            AND (r->>'eligible_total')::int >= 4 AND (r->>'no_data_total')::int >= 1
       FROM (SELECT sp_repro_list_heifers_eligible_for_empadre(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) x));
SELECT pg_temp.ok('B pagination: limit 1 returns one eligible heifer and has_more',
    (SELECT jsonb_array_length(r->'eligible') = 1 AND (r->>'has_more')::boolean AND (r->>'limit')::int = 1
       FROM (SELECT sp_repro_list_heifers_eligible_for_empadre(pg_temp.cx('A'), pg_temp.cx('u1'), '1') AS r) x));
SELECT pg_temp.ok('B ISOLATION: B sees its own heifer and none of A''s; A never sees B''s',
    pg_temp.find_elig(pg_temp.cx('B'), pg_temp.cx('u2'), 'eligible', pg_temp.cx('hb')) IS NOT NULL
    AND pg_temp.find_elig(pg_temp.cx('B'), pg_temp.cx('u2'), 'eligible', pg_temp.cx('h_both')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('B'), pg_temp.cx('u2'), 'sin_datos', pg_temp.cx('h_nodata')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('hb')) IS NULL);
SELECT pg_temp.ok('B ISOLATION: user 1 gets an ERROR for B',
    pg_temp.raises(format('SELECT sp_repro_list_heifers_eligible_for_empadre(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

-- the company thresholds drive the result: 30 months / 400 kg
SELECT pg_temp.call('b_cfg30', format('SELECT sp_repro_empadre_set_config(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '30', '400'));
SELECT pg_temp.ok('B thresholds drive eligibility (30 months / 400 kg): the 20-month 310 kg heifer and the 320 kg one drop out, the year-only one stays',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_both')) IS NULL
    AND pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_weight')) IS NULL
    AND (pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_age')))->>'eligibility_trigger' = 'EDAD'
    AND (SELECT (r->'thresholds'->>'min_age_months')::int = 30
           FROM (SELECT sp_repro_list_heifers_eligible_for_empadre(pg_temp.cx('A'), pg_temp.cx('u1'), '1') AS r) x));
SELECT pg_temp.call('b_cfg15', format('SELECT sp_repro_empadre_set_config(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '15', '300'));

-- =============================================================================================================
-- PART C. log_empadre_entry
-- =============================================================================================================

SELECT pg_temp.log1('c1', 'T085-A-HAGE', 'T085-A-BULL1', NULL, 'MONTA_NATURAL', 'first');
SELECT pg_temp.ok('C a heifer that meets the criteria is recorded: no warning, bull linked, company and author stored',
    (SELECT r->>'status' = 'recorded' AND r->>'eligibility_trigger' = 'EDAD' AND r->'warning' = 'null'::jsonb
            AND r->>'entry_date' = fn_repro_today()::text
            AND EXISTS (SELECT 1 FROM repro_empadre_entries e
                         WHERE e.id = (r->>'entry_id')::uuid AND e.id_company = pg_temp.cx('A')::integer
                           AND e.heifer_id = pg_temp.cx('h_age')::uuid AND e.bull_id = pg_temp.cx('bull_a')::uuid
                           AND e.method = 'MONTA_NATURAL' AND e.registered_by_email = lower(pg_temp.cx('u1'))
                           AND e.warning IS NULL AND e.notes = 'first' AND e.criteria ? 'min_age_months'
                           AND e.category_at_entry = 'NOVILLONA')
       FROM (SELECT pg_temp.rs('c1') AS r) x));

SELECT pg_temp.log1('c_retry', 'T085-A-HAGE', 'T085-A-BULL1', NULL, 'MONTA_NATURAL', 'other notes', 'u1');
SELECT pg_temp.ok('C idempotent retry (same heifer, date and bull): duplicate_skipped with the original entry, still one row',
    pg_temp.rs('c_retry')->>'status' = 'duplicate_skipped'
    AND pg_temp.rs('c_retry')->>'existing_entry_id' = pg_temp.rs('c1')->>'entry_id'
    AND pg_temp.n_entries(pg_temp.cx('h_age')) = 1);

SELECT pg_temp.log1('c_other_date', 'T085-A-HAGE', NULL, (fn_repro_today() - 5)::text);
SELECT pg_temp.ok('C the same heifer on another date or with another bull while an empadre is active: ALREADY_IN_EMPADRE, nothing written',
    pg_temp.rs('c_other_date')->>'status' = 'invalid' AND pg_temp.rs('c_other_date')->>'code' = 'ALREADY_IN_EMPADRE'
    AND pg_temp.n_entries(pg_temp.cx('h_age')) = 1);

SELECT pg_temp.ok('C a heifer in an active empadre leaves the eligible list and is counted as already in empadre',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_age')) IS NULL
    AND (SELECT (r->>'already_in_empadre_total')::int >= 1
           FROM (SELECT sp_repro_list_heifers_eligible_for_empadre(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) x));

SELECT pg_temp.log1('c_below', 'T085-A-HBELOW');
SELECT pg_temp.ok('C below both thresholds: RECORDED with a BELOW_THRESHOLDS warning, stored with the entry and returned (never blocks)',
    (SELECT r->>'status' = 'recorded' AND r->>'warning_code' = 'BELOW_THRESHOLDS' AND r->>'warning' ILIKE '%15 meses%300 kg%'
            AND EXISTS (SELECT 1 FROM repro_empadre_entries e
                         WHERE e.id = (r->>'entry_id')::uuid AND e.warning_code = 'BELOW_THRESHOLDS'
                           AND e.warning = r->>'warning' AND e.eligibility_trigger = 'NINGUNO')
       FROM (SELECT pg_temp.rs('c_below') AS r) x));

SELECT pg_temp.log1('c_nodata', 'T085-A-HNODATA');
SELECT pg_temp.ok('C no usable age or weight: RECORDED with a NO_DATA warning',
    pg_temp.rs('c_nodata')->>'status' = 'recorded' AND pg_temp.rs('c_nodata')->>'warning_code' = 'NO_DATA'
    AND pg_temp.rs('c_nodata')->>'eligibility_trigger' = 'SIN_DATOS');

SELECT pg_temp.log1('c_stale', 'T085-A-HWEIGHT');
SELECT pg_temp.ok('C eligible only by a stale weight: RECORDED with a WEIGHT_STALE warning',
    pg_temp.rs('c_stale')->>'status' = 'recorded' AND pg_temp.rs('c_stale')->>'warning_code' = 'WEIGHT_STALE'
    AND (pg_temp.rs('c_stale')->>'category_possibly_outdated')::boolean);

SELECT pg_temp.log1('c_cow', 'T085-A-OC1');
SELECT pg_temp.ok('C a VACA can be put in empadre; the heifer criteria do not apply (NO_APLICA, no warning)',
    pg_temp.rs('c_cow')->>'status' = 'recorded' AND pg_temp.rs('c_cow')->>'eligibility_trigger' = 'NO_APLICA'
    AND pg_temp.rs('c_cow')->'warning' = 'null'::jsonb);

SELECT pg_temp.ok('C PREÑADA heifer: refused (PREGNANT); sold heifer: refused (NOT_ACTIVE); nothing written',
    sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-HPREG')->>'code' = 'PREGNANT'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-HSOLD')->>'code' = 'NOT_ACTIVE'
    AND pg_temp.n_entries(pg_temp.cx('h_preg')) = 0 AND pg_temp.n_entries(pg_temp.cx('h_sold')) = 0);
SELECT pg_temp.ok('C unknown heifer: not_found; empty identifier: invalid; a bull or a steer as "heifer": NOT_FEMALE_BOVINE',
    sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'NO-SUCH-ANIMAL')->>'status' = 'not_found'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), '')->>'code' = 'HEIFER_MISSING'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-BULL1')->>'code' = 'NOT_FEMALE_BOVINE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-STEER')->>'code' = 'NOT_FEMALE_BOVINE');
SELECT pg_temp.ok('C duplicated numero_fuego: AMBIGUOUS with both candidates, nothing written (never guessed)',
    (SELECT r->>'status' = 'ambiguous' AND r->>'code' = 'HEIFER_AMBIGUOUS' AND jsonb_array_length(r->'candidates') = 2
       FROM (SELECT sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085DUP') AS r) x)
    AND pg_temp.n_entries(pg_temp.cx('h_dup1')) = 0 AND pg_temp.n_entries(pg_temp.cx('h_dup2')) = 0);
SELECT pg_temp.ok('C bull validation: a heifer, a steer, a sold bull and a bull of ANOTHER company are all refused; ambiguity and a bad method too',
    sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085-A-E2')->>'code' = 'BULL_NOT_MALE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085-A-STEER')->>'code' = 'BULL_NOT_MALE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085-A-BULLS')->>'code' = 'BULL_NOT_ACTIVE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085-B-BULL')->>'code' = 'BULL_NOT_FOUND'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085BDUP')->>'code' = 'BULL_AMBIGUOUS'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', 'T085-A-BULL1', NULL, 'NADA')->>'code' = 'BAD_METHOD'
    AND pg_temp.n_entries(pg_temp.cx('e1')) = 0);
SELECT pg_temp.ok('C ISOLATION: a heifer of B is not found from A; user 1 calling with tenant B gets an ERROR; nothing is written for B',
    sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-B-HB')->>'status' = 'not_found'
    AND pg_temp.raises(format('SELECT sp_repro_log_empadre_entry(%L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), 'T085-B-HB'), 'P0001')
    AND pg_temp.n_entries(pg_temp.cx('hb')) = 0);
SELECT pg_temp.ok('C dates: future, older than a year and malformed are refused (BAD_DATE)',
    sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', NULL, (fn_repro_today() + 1)::text)->>'code' = 'BAD_DATE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', NULL, (fn_repro_today() - 400)::text)->>'code' = 'BAD_DATE'
    AND sp_repro_log_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-E1', NULL, '3/2/2026')->>'code' = 'BAD_DATE'
    AND pg_temp.n_entries(pg_temp.cx('e1')) = 0);
SELECT pg_temp.log1('c_past', 'T085-A-E5', NULL, (fn_repro_today() - 10)::text);
SELECT pg_temp.ok('C an explicit past date is kept',
    pg_temp.rs('c_past')->>'status' = 'recorded' AND pg_temp.rs('c_past')->>'entry_date' = (fn_repro_today() - 10)::text);

SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.log1('c_editor', 'T085-A-E4');
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');
SELECT pg_temp.ok('C any active member may log (EDITOR): staff report through the chat',
    pg_temp.rs('c_editor')->>'status' = 'recorded');

SELECT pg_temp.ok('C append-only: UPDATE and DELETE on entries raise P0095; TRUNCATE is refused',
    pg_temp.raises('UPDATE repro_empadre_entries SET notes = ''x''', 'P0095')
    AND pg_temp.raises('DELETE FROM repro_empadre_entries', 'P0095')
    AND pg_temp.raises_any('TRUNCATE public.repro_empadre_entries', ARRAY['P0095', '0A000']));
SELECT pg_temp.ok('C company guard: an entry whose heifer or bull belongs to another company is refused by the table itself (P0096)',
    pg_temp.raises(format('INSERT INTO repro_empadre_entries (id_company, heifer_id, entry_date, category_at_entry, eligibility_trigger, registered_by_email) VALUES (%s, %L, current_date, %L, %L, %L)',
                          pg_temp.cx('B'), pg_temp.cx('h_age'), 'NOVILLONA', 'EDAD', 'x'), 'P0096')
    AND pg_temp.raises(format('INSERT INTO repro_empadre_entries (id_company, heifer_id, bull_id, entry_date, category_at_entry, eligibility_trigger, registered_by_email) VALUES (%s, %L, %L, current_date, %L, %L, %L)',
                          pg_temp.cx('A'), pg_temp.cx('e2'), pg_temp.cx('bull_b'), 'NOVILLONA', 'EDAD', 'x'), 'P0096'));

-- =============================================================================================================
-- PART D. batch
-- =============================================================================================================

SELECT pg_temp.batch1('d1', '["T085-A-E1","T085-A-E2","T085-A-E3"]', 'T085-A-BULL1', 'MONTA_NATURAL', 'batch one');
SELECT pg_temp.ok('D a batch records every heifer with the common bull / method / notes under one batch id',
    (SELECT r->>'status' = 'recorded' AND (r->>'recorded')::int = 3 AND (r->>'skipped_duplicates')::int = 0
            AND (SELECT count(*) FROM repro_empadre_entries e
                  WHERE e.batch_id = (r->>'batch_id')::uuid AND e.id_company = pg_temp.cx('A')::integer
                    AND e.bull_id = pg_temp.cx('bull_a')::uuid AND e.method = 'MONTA_NATURAL' AND e.notes = 'batch one') = 3
       FROM (SELECT pg_temp.rs('d1') AS r) x));

SELECT pg_temp.batch1('d_retry', '["T085-A-E1","T085-A-E2","T085-A-E3"]', 'T085-A-BULL1', 'MONTA_NATURAL');
SELECT pg_temp.ok('D idempotent retry of the whole batch: duplicate_skipped, nothing new',
    pg_temp.rs('d_retry')->>'status' = 'duplicate_skipped' AND (pg_temp.rs('d_retry')->>'recorded')::int = 0
    AND (pg_temp.rs('d_retry')->>'skipped_duplicates')::int = 3
    AND pg_temp.n_entries(pg_temp.cx('e1')) + pg_temp.n_entries(pg_temp.cx('e2')) + pg_temp.n_entries(pg_temp.cx('e3')) = 3);

SELECT pg_temp.batch1('d_nf', '["T085-A-HDUP2","NO-SUCH-ANIMAL"]');
SELECT pg_temp.batch1('d_preg', '["T085-A-HDUP2","T085-A-HPREG"]');
SELECT pg_temp.batch1('d_amb', '["T085-A-HDUP2","T085DUP"]');
SELECT pg_temp.batch1('d_bull', '["T085-A-HDUP2"]', 'T085-A-STEER');
SELECT pg_temp.batch1('d_twice', '["T085-A-HDUP2","T085-A-HDUP2"]');
SELECT pg_temp.ok('D ALL OR NOTHING: an unknown animal, a PREÑADA heifer, an ambiguous number, a bad bull or the same heifer twice reject the whole batch',
    pg_temp.rs('d_nf')->>'status' = 'rejected' AND pg_temp.rs('d_nf')->'issues'->0->>'code' = 'HEIFER_NOT_FOUND'
    AND pg_temp.rs('d_preg')->>'status' = 'rejected' AND pg_temp.rs('d_preg')->'issues'->0->>'code' = 'PREGNANT'
    AND pg_temp.rs('d_amb')->>'status' = 'rejected' AND pg_temp.rs('d_amb')->'issues'->0->>'code' = 'HEIFER_AMBIGUOUS'
    AND jsonb_array_length(pg_temp.rs('d_amb')->'issues'->0->'candidates') = 2
    AND pg_temp.rs('d_bull')->>'status' = 'rejected' AND pg_temp.rs('d_bull')->'issues'->0->>'code' = 'BULL_NOT_MALE'
    AND pg_temp.rs('d_twice')->>'status' = 'rejected' AND pg_temp.rs('d_twice')->'issues'->0->>'code' = 'DUPLICATE_IN_BATCH'
    AND (pg_temp.rs('d_nf')->>'recorded')::int = 0);
SELECT pg_temp.ok('D ... and the valid heifer of those batches (HDUP2) was NOT written',
    pg_temp.n_entries(pg_temp.cx('h_dup2')) = 0);

SELECT pg_temp.batch1('d_mixed', '["T085-A-E1","T085-A-HDUP2"]', 'T085-A-BULL1', 'MONTA_NATURAL');
SELECT pg_temp.ok('D a batch that mixes a retry and a new heifer records the new one and skips the old',
    pg_temp.rs('d_mixed')->>'status' = 'recorded' AND (pg_temp.rs('d_mixed')->>'recorded')::int = 1
    AND (pg_temp.rs('d_mixed')->>'skipped_duplicates')::int = 1
    AND pg_temp.n_entries(pg_temp.cx('h_dup2')) = 1 AND pg_temp.n_entries(pg_temp.cx('e1')) = 1);

SELECT pg_temp.batch1('d_warn', '["T085-A-HBELOW2"]');
SELECT pg_temp.ok('D a below-threshold heifer inside a batch is recorded and carries its warning in the results',
    pg_temp.rs('d_warn')->>'status' = 'recorded' AND (pg_temp.rs('d_warn')->>'with_warning')::int = 1
    AND pg_temp.rs('d_warn')->'results'->0->>'warning_code' = 'BELOW_THRESHOLDS');

SELECT pg_temp.batch1('d_obj', '[{"heifer":"T085-A-OC3","bull":"T085-A-BULL1","method":"INSEMINACION_ARTIFICIAL","notes":"item"}]', NULL, 'MONTA_NATURAL');
SELECT pg_temp.ok('D an object item uses its own bull / method / notes instead of the common ones',
    pg_temp.rs('d_obj')->>'status' = 'recorded'
    AND EXISTS (SELECT 1 FROM repro_empadre_entries e
                 WHERE e.heifer_id = pg_temp.cx('oc3')::uuid AND e.method = 'INSEMINACION_ARTIFICIAL'
                   AND e.bull_id = pg_temp.cx('bull_a')::uuid AND e.notes = 'item'));

SELECT pg_temp.ok('D invalid items: not JSON, empty array, not an array, NULL, more than 100',
    sp_repro_log_empadre_entry_batch(pg_temp.cx('A'), pg_temp.cx('u1'), 'not json')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_empadre_entry_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '[]')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_empadre_entry_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '{"a":1}')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_empadre_entry_batch(pg_temp.cx('A'), pg_temp.cx('u1'), NULL)->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_empadre_entry_batch(pg_temp.cx('A'), pg_temp.cx('u1'),
            (SELECT jsonb_agg('X' || g)::text FROM generate_series(1, 101) g))->>'code' = 'TOO_MANY_ITEMS');

SELECT pg_temp.batch1('d_cross', '["T085-B-HB","T085-A-E2"]');
SELECT pg_temp.ok('D ISOLATION: a heifer of B inside a batch from A is not found, the batch is rejected and nothing is written; tenant B raises',
    pg_temp.rs('d_cross')->>'status' = 'rejected' AND pg_temp.rs('d_cross')->'issues'->0->>'code' = 'HEIFER_NOT_FOUND'
    AND pg_temp.n_entries(pg_temp.cx('hb')) = 0
    AND pg_temp.raises(format('SELECT sp_repro_log_empadre_entry_batch(%L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), '["T085-B-HB"]'), 'P0001'));

-- =============================================================================================================
-- PART E. void
-- =============================================================================================================

SELECT pg_temp.ok('E a reason is required (empty and too short are refused); nothing is voided',
    sp_void_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('c1')->>'entry_id', '')->>'code' = 'REASON_REQUIRED'
    AND sp_void_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('c1')->>'entry_id', 'ab')->>'code' = 'REASON_REQUIRED'
    AND pg_temp.n_voids() = 0);
SELECT pg_temp.ok('E ISOLATION: the entry of A cannot be voided from B (not_found) nor by user 1 as tenant B (error)',
    sp_void_empadre_entry(pg_temp.cx('B'), pg_temp.cx('u2'), pg_temp.rs('c1')->>'entry_id', 'wrong company')->>'status' = 'not_found'
    AND pg_temp.raises(format('SELECT sp_void_empadre_entry(%L, %L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), pg_temp.rs('c1')->>'entry_id', 'nope'), 'P0001')
    AND pg_temp.n_voids() = 0);

SELECT pg_temp.call('e_void', format('SELECT sp_void_empadre_entry(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('c1')->>'entry_id', 'entered by mistake'));
SELECT pg_temp.ok('E voiding an entry: voided, with company, author and reason stored',
    pg_temp.rs('e_void')->>'status' = 'voided'
    AND EXISTS (SELECT 1 FROM repro_empadre_voids v
                 WHERE v.entry_id = (pg_temp.rs('c1')->>'entry_id')::uuid AND v.id_company = pg_temp.cx('A')::integer
                   AND v.voided_by_email = lower(pg_temp.cx('u1')) AND v.reason = 'entered by mistake'));

SELECT pg_temp.call('e_void2', format('SELECT sp_void_empadre_entry(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('c1')->>'entry_id', 'again'));
SELECT pg_temp.ok('E one void per entry: the second attempt answers already_voided and adds no row',
    pg_temp.rs('e_void2')->>'status' = 'already_voided' AND pg_temp.n_voids() = 1);
SELECT pg_temp.ok('E unknown id: not_found; malformed or empty id: invalid',
    sp_void_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), gen_random_uuid()::text, 'reason')->>'status' = 'not_found'
    AND sp_void_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), 'abc', 'reason')->>'code' = 'BAD_ENTRY_ID'
    AND sp_void_empadre_entry(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, 'reason')->>'code' = 'BAD_ENTRY_ID');

SELECT pg_temp.ok('E after the void the heifer is eligible again',
    pg_temp.find_elig(pg_temp.cx('A'), pg_temp.cx('u1'), 'eligible', pg_temp.cx('h_age')) IS NOT NULL);
SELECT pg_temp.log1('e_again', 'T085-A-HAGE', 'T085-A-BULL1', NULL, 'MONTA_NATURAL');
SELECT pg_temp.ok('E ... and can be re-entered the same day: a NEW entry (the voided one does not count as a duplicate)',
    pg_temp.rs('e_again')->>'status' = 'recorded' AND pg_temp.rs('e_again')->>'entry_id' <> pg_temp.rs('c1')->>'entry_id'
    AND pg_temp.n_entries(pg_temp.cx('h_age')) = 2);
SELECT pg_temp.ok('E voids are append-only (UPDATE / DELETE / TRUNCATE raise P0095) and the void table guards the company (P0096)',
    pg_temp.raises('UPDATE repro_empadre_voids SET reason = ''changed''', 'P0095')
    AND pg_temp.raises('DELETE FROM repro_empadre_voids', 'P0095')
    AND pg_temp.raises('TRUNCATE public.repro_empadre_voids', 'P0095')
    AND pg_temp.raises(format('INSERT INTO repro_empadre_voids (id_company, entry_id, reason, voided_by_email) VALUES (%s, %L, %L, %L)',
                              pg_temp.cx('B'), pg_temp.rs('e_again')->>'entry_id', 'cross company', 'x'), 'P0096'));
SELECT pg_temp.ok('E the generic event_voids table (sp_void_event) was not used: no new rows',
    (SELECT count(*) FROM event_voids) = (SELECT voids FROM t_counts));

-- =============================================================================================================
-- PART F. list_empadre_entries
-- =============================================================================================================

SELECT pg_temp.ok('F entries of one heifer: the voided one is hidden by default and shown with include_voided',
    (SELECT jsonb_array_length(a.r->'entries') = 1 AND (a.r->>'total')::int = 1
            AND jsonb_array_length(b.r->'entries') = 2 AND (b.r->>'total')::int = 2
            AND (SELECT count(*) FROM jsonb_array_elements(b.r->'entries') e
                  WHERE (e->>'voided')::boolean AND e->>'void_reason' = 'entered by mistake') = 1
       FROM (SELECT sp_repro_list_empadre_entries(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-HAGE') AS r) a,
            (SELECT sp_repro_list_empadre_entries(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085-A-HAGE', 'true') AS r) b));
SELECT pg_temp.ok('F an ambiguous or unknown heifer filter answers ambiguous / not_found',
    sp_repro_list_empadre_entries(pg_temp.cx('A'), pg_temp.cx('u1'), 'T085DUP')->>'status' = 'ambiguous'
    AND sp_repro_list_empadre_entries(pg_temp.cx('A'), pg_temp.cx('u1'), 'NO-SUCH-ANIMAL')->>'status' = 'not_found');
SELECT pg_temp.ok('F ISOLATION: B lists none of A''s entries; user 1 gets an ERROR for B',
    (SELECT (r->>'total')::int = 0 FROM (SELECT sp_repro_list_empadre_entries(pg_temp.cx('B'), pg_temp.cx('u2')) AS r) x)
    AND pg_temp.raises(format('SELECT sp_repro_list_empadre_entries(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));
SELECT pg_temp.ok('F pagination: limit 1 returns one entry and has_more',
    (SELECT jsonb_array_length(r->'entries') = 1 AND (r->>'has_more')::boolean
       FROM (SELECT sp_repro_list_empadre_entries(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, NULL, '1') AS r) x));

-- =============================================================================================================
-- PART G. open cows
-- =============================================================================================================

SELECT pg_temp.ok('G a never-served VACÍA cow is listed; the English key + accent-less spelling is read as VACÍA from the LATEST palpation',
    (SELECT (c->'cow'->>'last_palpation_result') = 'VACÍA' AND (c->'cow'->>'last_palpation_date')::date = (current_date - 40)
            AND c->'cow'->'last_service_date' = 'null'::jsonb
       FROM (SELECT pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc1')) AS c) x));
SELECT pg_temp.ok('G the Spanish key set (resultado) is read too',
    (SELECT (c->'cow'->>'last_palpation_result') = 'VACÍA' AND (c->'cow'->>'last_palpation_date')::date = (current_date - 10)
       FROM (SELECT pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc6')) AS c) x));
SELECT pg_temp.ok('G default 90 days: served 30 days ago is NOT open; served 120 days ago is open with days_since_last_service; a VOIDED service does not count',
    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc2')) IS NULL
    AND (SELECT (c->'cow'->>'days_since_last_service')::int BETWEEN 119 AND 121
           FROM (SELECT pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc3')) AS c) x)
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc4')) IS NOT NULL);
SELECT pg_temp.ok('G a PREÑADA cow and a bull are not open cows',
    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc5')) IS NULL
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('bull_a')) IS NULL);
SELECT pg_temp.ok('G the days parameter moves the cut: 150 days hides the 120-day service, 100 days shows it, 20 days shows the 30-day one',
    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), '150', pg_temp.cx('oc3')) IS NULL
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), '100', pg_temp.cx('oc3')) IS NOT NULL
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), '20', pg_temp.cx('oc2')) IS NOT NULL
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), '150', pg_temp.cx('oc4')) IS NOT NULL);
SELECT pg_temp.ok('G order: never-served cows come before older services',
    (SELECT (a->>'pos')::int < (b->>'pos')::int
       FROM (SELECT pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc1')) AS a,
                    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc3')) AS b) x));
SELECT pg_temp.ok('G in_active_empadre is true for the cows put in empadre in parts C / D, false for the others',
    (SELECT (a->'cow'->>'in_active_empadre')::boolean AND (b->'cow'->>'in_active_empadre')::boolean
            AND NOT (c->'cow'->>'in_active_empadre')::boolean
       FROM (SELECT pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc1')) AS a,
                    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc3')) AS b,
                    pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc6')) AS c) x));
SELECT pg_temp.ok('G invalid days are refused',
    sp_repro_list_open_cows(pg_temp.cx('A'), pg_temp.cx('u1'), '0')->>'status' = 'invalid'
    AND sp_repro_list_open_cows(pg_temp.cx('A'), pg_temp.cx('u1'), 'abc')->>'status' = 'invalid'
    AND sp_repro_list_open_cows(pg_temp.cx('A'), pg_temp.cx('u1'), '731')->>'status' = 'invalid');
SELECT pg_temp.ok('G ISOLATION: B lists its own open cow (its palpation joined through the company) and none of A''s; user 1 gets an ERROR for B',
    (SELECT (c->'cow'->>'last_palpation_result') = 'VACÍA'
       FROM (SELECT pg_temp.find_cow(pg_temp.cx('B'), pg_temp.cx('u2'), NULL, pg_temp.cx('oc_b')) AS c) x)
    AND pg_temp.find_cow(pg_temp.cx('B'), pg_temp.cx('u2'), NULL, pg_temp.cx('oc1')) IS NULL
    AND pg_temp.find_cow(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('oc_b')) IS NULL
    AND pg_temp.raises(format('SELECT sp_repro_list_open_cows(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

-- =============================================================================================================
-- PART H. fail-closed on every tool
-- =============================================================================================================

SELECT pg_temp.ok('H every tool raises P0001 for user 1 on company B (not a member), for a stranger, a blank e-mail and bad tenants',
    (SELECT bool_and(pg_temp.raises(format(t.sql_tpl, pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A'), 'nadie@example.test'), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A'), ''), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, 'abc', pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, '', pg_temp.cx('u1')), 'P0001')
                 AND pg_temp.raises(format(t.sql_tpl, pg_temp.cx('A') || ' OR 1=1', pg_temp.cx('u1')), 'P0001'))
       FROM (VALUES
            ('SELECT sp_repro_empadre_get_config(%L, %L)'),
            ('SELECT sp_repro_empadre_set_config(%L, %L, ''10'')'),
            ('SELECT sp_repro_list_heifers_eligible_for_empadre(%L, %L)'),
            ('SELECT sp_repro_log_empadre_entry(%L, %L, ''T085-A-E3'')'),
            ('SELECT sp_repro_log_empadre_entry_batch(%L, %L, ''["T085-A-E3"]'')'),
            ('SELECT sp_void_empadre_entry(%L, %L, ''00000000-0000-0000-0000-000000000000'', ''reason'')'),
            ('SELECT sp_repro_list_empadre_entries(%L, %L)'),
            ('SELECT sp_repro_list_open_cows(%L, %L)')) AS t (sql_tpl)));
SELECT pg_temp.ok('H ... and none of those rejected calls wrote anything',
    pg_temp.n_entries(pg_temp.cx('e3')) = 1 AND pg_temp.n_voids() = 1 AND pg_temp.cfg_rows(pg_temp.cx('B')) = 0);
SELECT pg_temp.ok('H the e-mail comparison ignores case but the membership must be active',
    sp_repro_list_open_cows(pg_temp.cx('A'), upper(pg_temp.cx('u1')), '90', '1')->>'status' = 'ok'
    AND pg_temp.raises(format('SELECT sp_repro_list_open_cows(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

DO $$
DECLARE
    v_palm  integer;
BEGIN
    SELECT c.id_company INTO v_palm FROM companys c WHERE c.is_active AND fn_company_business_domain(c.id_company) = 'PALM' ORDER BY c.id_company LIMIT 1;
    IF v_palm IS NULL THEN
        INSERT INTO t_result (test, ok, detail) VALUES ('H palm company is rejected (P0094) - skipped: no palm company in this database', true, 'skipped');
        RETURN;
    END IF;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT pg_temp.cx('u1'), v_palm, 'ADMIN', true
     WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = pg_temp.cx('u1') AND id_company = v_palm);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = pg_temp.cx('u1') AND id_company = v_palm;
    INSERT INTO t_result (test, ok, detail)
    VALUES ('H palm company is rejected (P0094) by every empadre tool',
            pg_temp.raises(format('SELECT sp_repro_empadre_get_config(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_empadre_set_config(%L, %L, ''10'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_heifers_eligible_for_empadre(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_log_empadre_entry(%L, %L, ''x'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_log_empadre_entry_batch(%L, %L, ''["x"]'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_void_empadre_entry(%L, %L, %L, ''reason'')', v_palm::text, pg_temp.cx('u1'), gen_random_uuid()::text), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_empadre_entries(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_open_cows(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.cfg_rows(v_palm::text) = 0,
            'palm company ' || v_palm);
END $$;

-- =============================================================================================================
-- PART I. nothing else was written
-- =============================================================================================================

SELECT pg_temp.ok('I the tools wrote nothing outside the empadre tables (births, animals, weights, voids, services, health logs)',
    (SELECT (SELECT count(*) FROM birth_events) = c.births AND (SELECT count(*) FROM cattle_livestock) = c.animals
        AND (SELECT count(*) FROM cattle_weight_logs) = c.weights AND (SELECT count(*) FROM event_voids) = c.voids
        AND (SELECT count(*) FROM cattle_breeding_events) = c.services AND (SELECT count(*) FROM cattle_health_logs) = c.health
       FROM t_counts c));
SELECT pg_temp.ok('I no animal changed category or status (the category is never changed automatically)',
    (SELECT md5(string_agg(concat_ws('|', l.id::text, l.category, l.current_status), ',' ORDER BY l.id)) = (SELECT fixture_state FROM t_counts)
       FROM cattle_livestock l WHERE l.rfid_siniiga LIKE 'T085%'));
SELECT pg_temp.ok('I sp_void_event and the other pre-existing reproduction procedures do not mention the empadre objects (not modified by 085)',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
        AND proname IN ('sp_void_event', 'sp_register_birth_event', 'sp_log_breeding_event', 'sp_log_palpation_event')
        AND (prosrc ILIKE '%empadre%' OR prosrc LIKE '%fn_repro_%')) = 0);
SELECT pg_temp.ok('I none of the empadre tables or tools is exposed through crud_models',
    NOT EXISTS (SELECT 1 FROM crud_models
                 WHERE table_name LIKE 'repro\_empadre\_%' OR model_name LIKE 'repro\_empadre\_%'
                    OR table_name LIKE 'sp\_repro\_%' OR table_name = 'sp_void_empadre_entry' OR model_name = 'sp_void_empadre_entry'));
SELECT pg_temp.ok('I every entry''s heifer and bull belong to the entry''s company, and every void to its entry''s company',
    NOT EXISTS (SELECT 1 FROM repro_empadre_entries e
                 LEFT JOIN cattle_livestock h ON h.id = e.heifer_id AND h.tenant_id = e.id_company
                WHERE h.id IS NULL)
    AND NOT EXISTS (SELECT 1 FROM repro_empadre_entries e
                     JOIN cattle_livestock b ON b.id = e.bull_id WHERE b.tenant_id <> e.id_company)
    AND NOT EXISTS (SELECT 1 FROM repro_empadre_voids v
                     JOIN repro_empadre_entries e ON e.id = v.entry_id WHERE e.id_company <> v.id_company));

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 300) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '085 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 085 tests: everything rolled back ***'
