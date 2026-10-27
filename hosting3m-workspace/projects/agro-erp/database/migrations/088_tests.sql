-- 088_tests.sql — functional checks for migration 088 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It loads 084 - 088 inside this transaction (embedded mode). It needs a database with the real schema (so the three production
-- procedures have their verified bodies: 087 / 088 abort otherwise), AT LEAST two ACTIVE non-palm companies and two users (see
-- 088_RUNBOOK.md, "Test database"). Memberships are arranged INSIDE the transaction:
--     user 1: ACTIVE ADMIN of A, INACTIVE in B        user 2: ACTIVE ADMIN of B, INACTIVE in A
-- Fixture animals use identifiers prefixed T088. Every write goes through pg_temp.call(key, sql) in its own statement and is asserted
-- in the NEXT statement (a statement never sees rows its own write functions created).
--
-- Part A  service <-> birth link (exactly one candidate, window edges, voided / used services, species names, isolation)
-- Part B  the guard trigger of cattle_breeding_events (the only allowed UPDATE is NULL -> value, once)
-- Part C  sp_log_breeding_event (membership, sire rules, warnings, duplicate skip, unchanged errors)
-- Part D  sp_void_event (membership, linked service refused, one void per event, whitelist, no side effects)
-- Part E  get_dam_reproductive_history (sections, ambiguity, flags, expected calving, isolation)
-- Part F  fail-closed (stranger, other company, blank, bad tenant, palm)
-- Part G  nothing else was written
--
-- Run (the test files must be INSIDE the container):
--   docker exec n8n-enterprise-db rm -rf /tmp/m088
--   docker cp database/migrations n8n-enterprise-db:/tmp/m088
--   docker exec -w /tmp/m088 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m088/088_tests.sql

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql
\ir 086_repro_palpation.sql
\ir 087_repro_births.sql
\ir 088_repro_services.sql

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
CREATE FUNCTION pg_temp.no_error(p_sql text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN true;
EXCEPTION WHEN assert_failure THEN
    RETURN false;
WHEN OTHERS THEN
    RETURN false;
END $$;
CREATE FUNCTION pg_temp.dd(p_days integer) RETURNS date
LANGUAGE sql AS $$ SELECT fn_repro_today() - p_days $$;
CREATE FUNCTION pg_temp.dago(p_days integer) RETURNS text
LANGUAGE sql AS $$ SELECT to_char(fn_repro_today() - p_days, 'YYYY-MM-DD') $$;

CREATE FUNCTION pg_temp.bth(p_key text, p_spec jsonb, p_who text DEFAULT 'u1', p_company text DEFAULT 'A') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_register_birth(%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.cx(p_company), pg_temp.cx(p_who), p_spec->>'sex', p_spec->>'dam', p_spec->>'dam_id', p_spec->>'date', p_spec->>'w',
        p_spec->>'lot', p_spec->>'pu', p_spec->>'pad', p_spec->>'sp', p_spec->>'notes', p_spec->>'force'));
END $$;

-- sp_log_breeding_event(identifier, tenant, date, method, sire, semen, email, notes)
CREATE FUNCTION pg_temp.brd(p_key text, p_ident text, p_date date, p_method text DEFAULT 'MONTA_NATURAL', p_sire text DEFAULT NULL,
                            p_semen text DEFAULT NULL, p_who text DEFAULT 'u1', p_company text DEFAULT 'A') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_log_breeding_event(%L, %L::int, %L::date, %L, %L, %L, %L, %L)',
        p_ident, pg_temp.cx(p_company), p_date, p_method, p_sire, p_semen, pg_temp.cx(p_who), 'T088'));
END $$;

CREATE FUNCTION pg_temp.n_svc(p_dam text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_breeding_events WHERE livestock_id = p_dam::uuid $$;
CREATE FUNCTION pg_temp.n_voids() RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM event_voids $$;
CREATE FUNCTION pg_temp.svc_link(p_svc text) RETURNS uuid
LANGUAGE sql AS $$ SELECT birth_event_id FROM cattle_breeding_events WHERE id = p_svc::uuid $$;

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
        RAISE EXCEPTION '088 tests need two active non-palm companies in the database (see 088_RUNBOOK.md, Test database).';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '088 tests need two users in the database (see 088_RUNBOOK.md, Test database).';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T088%') THEN
        RAISE EXCEPTION '088 tests: T088 fixtures already exist in this database; run the tests on a clean copy.';
    END IF;
    IF EXISTS (SELECT 1 FROM fn_repro_palpations(v_a)) OR EXISTS (SELECT 1 FROM fn_repro_palpations(v_b)) THEN
        RAISE EXCEPTION '088 tests need companies A and B WITHOUT palpations (the import-date flag counts them): use the schema-only copy.';
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
    DELETE FROM repro_births_config WHERE id_company IN (v_a, v_b);
    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_key text, p_fuego text, p_cat text, p_status text, p_species text DEFAULT 'BOVINO') RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego, species)
    VALUES (p_tenant, 'T088-' || p_key, 'CRIA', p_cat, p_status, p_fuego, p_species)
    RETURNING id
$$;

-- a service written directly (a fixture of a service that exists already): returns its id
CREATE FUNCTION pg_temp.svc(p_tenant integer, p_dam uuid, p_date date, p_method text DEFAULT 'MONTA_NATURAL') RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method, registered_by_email)
    VALUES (p_dam, p_tenant, p_date, p_method, 'T088') RETURNING id
$$;

CREATE FUNCTION pg_temp.void_svc(p_tenant integer, p_svc uuid) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO event_voids (tenant_id, event_table, event_id, voided_by_email, voided_reason)
    VALUES (p_tenant, 'cattle_breeding_events', p_svc, 'T088', 'T088 fixture')
$$;

DO $$
DECLARE
    v_a  integer := pg_temp.cx('A')::integer;
    v_b  integer := pg_temp.cx('B')::integer;
    v_id uuid;
    v_k  text;
BEGIN
    -- dams of company A for the link tests
    FOREACH v_k IN ARRAY ARRAY['s1','s2','s3','s4','s5','s6','s7','s8','e1','e2','e3','e4','s9'] LOOP
        v_id := pg_temp.mk(v_a, 'A-' || upper(v_k), NULL, 'VACA', 'ACTIVO');
        INSERT INTO t_ctx VALUES (v_k, v_id::text);
    END LOOP;
    v_id := pg_temp.mk(v_a, 'A-SHEEP', NULL, 'BORREGA', 'ACTIVO', 'BORREGO');  INSERT INTO t_ctx VALUES ('sheep', v_id::text);
    -- breeding fixtures
    FOREACH v_k IN ARRAY ARRAY['f1','f2','f3','f4','f5','f6','f7','f8','f9'] LOOP
        v_id := pg_temp.mk(v_a, 'A-' || upper(v_k), NULL, 'VACA', 'ACTIVO');
        INSERT INTO t_ctx VALUES (v_k, v_id::text);
    END LOOP;
    v_id := pg_temp.mk(v_a, 'A-BULL1', 'T088BULL', 'TORO', 'ACTIVO');            INSERT INTO t_ctx VALUES ('bull1', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-TORETE', NULL, 'BECERRO_TORETE', 'ACTIVO');       INSERT INTO t_ctx VALUES ('torete', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-BULLD1', 'T088BDUP', 'TORO', 'ACTIVO');           INSERT INTO t_ctx VALUES ('bulld1', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-BULLD2', 'T088BDUP', 'TORO', 'ACTIVO');           INSERT INTO t_ctx VALUES ('bulld2', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-COWSIRE', NULL, 'VACA', 'ACTIVO');                INSERT INTO t_ctx VALUES ('cowsire', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-FDUP1', 'T088FDUP', 'VACA', 'ACTIVO');            INSERT INTO t_ctx VALUES ('fdup1', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-FDUP2', 'T088FDUP', 'VACA', 'ACTIVO');            INSERT INTO t_ctx VALUES ('fdup2', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-FSOLD', NULL, 'VACA', 'VENDIDO');                  INSERT INTO t_ctx VALUES ('fsold', v_id::text);
    -- history fixtures
    FOREACH v_k IN ARRAY ARRAY['hd1','hd2','hd3','hd4'] LOOP
        v_id := pg_temp.mk(v_a, 'A-' || upper(v_k), NULL, 'VACA', 'ACTIVO');
        INSERT INTO t_ctx VALUES (v_k, v_id::text);
    END LOOP;
    -- company B
    v_id := pg_temp.mk(v_b, 'B-S1', NULL, 'VACA', 'ACTIVO');                       INSERT INTO t_ctx VALUES ('bs1', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-F1', NULL, 'VACA', 'ACTIVO');                       INSERT INTO t_ctx VALUES ('bf1', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-BULL', 'T088BULL', 'TORO', 'ACTIVO');               INSERT INTO t_ctx VALUES ('bbull', v_id::text);
END $$;

CREATE FUNCTION pg_temp.setrole(p_email text, p_company text, p_role text) RETURNS void
LANGUAGE sql AS $$ UPDATE user_companies SET role = p_role WHERE email = p_email AND id_company = p_company::integer $$;

CREATE TEMP TABLE t_proc ON COMMIT DROP AS
SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('sp_log_palpation_event', 'sp_register_birth_event');

-- From here on an unexpected error in a statement does not stop the run: psql rolls back to a savepoint of that statement only
-- (ON_ERROR_ROLLBACK) and goes on, and every assertion runs inside pg_temp.t(), which records errors as FAILs.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

-- =============================================================================================================
-- PART A. service <-> birth link
-- =============================================================================================================

SELECT pg_temp.t('A plausible windows by species (both name sets mapped): BOVINO 283 [238,328]; OVINO = BORREGO 152 [132,172]; EQUINO = EQUIDO 340 [295,385]; BUFALO 310 [280,340]; unknown = NULL', $qq$(SELECT days = 283 AND lo = 238 AND hi = 328 FROM fn_repro_gestation_bounds('BOVINO'))
    AND (SELECT days = 152 AND lo = 132 AND hi = 172 FROM fn_repro_gestation_bounds('ovino')) AND (SELECT days = 152 AND lo = 132 AND hi = 172 FROM fn_repro_gestation_bounds('BORREGO'))
    AND (SELECT days = 340 AND lo = 295 AND hi = 385 FROM fn_repro_gestation_bounds('EQUINO')) AND (SELECT days = 340 AND lo = 295 AND hi = 385 FROM fn_repro_gestation_bounds('EQUIDO'))
    AND (SELECT days = 310 AND lo = 280 AND hi = 340 FROM fn_repro_gestation_bounds('BUFALO'))
    AND (SELECT days IS NULL FROM fn_repro_gestation_bounds('DRAGON')) AND (SELECT days IS NULL FROM fn_repro_gestation_bounds(NULL))$qq$);

-- 1. exactly one candidate: linked
SELECT pg_temp.call('sv1', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 283)))', pg_temp.cx('A'), pg_temp.cx('s1')));
SELECT pg_temp.bth('lk1', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S1', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A exactly one service 283 days before the birth is LINKED by the new tool; the answer carries service_link = linked', $qq$pg_temp.rs('lk1')->>'status' = 'recorded' AND pg_temp.rs('lk1')->'service_link'->>'status' = 'linked'
    AND pg_temp.rs('lk1')->'service_link'->>'breeding_event_id' = trim(both '"' from pg_temp.rs('sv1')::text)
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv1')::text)) = (pg_temp.rs('lk1')->>'birth_event_id')::uuid$qq$, $qq$pg_temp.rs('lk1')::text$qq$);
-- 2. no service at all
SELECT pg_temp.bth('lk2', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S2', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A a birth whose dam has no service is registered and says no_candidate (nothing linked)', $qq$pg_temp.rs('lk2')->>'status' = 'recorded' AND pg_temp.rs('lk2')->'service_link'->>'status' = 'no_candidate'$qq$);
-- 3. two candidates: never guessed
SELECT pg_temp.call('sv3a', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 270)))', pg_temp.cx('A'), pg_temp.cx('s3')));
SELECT pg_temp.call('sv3b', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 290)))', pg_temp.cx('A'), pg_temp.cx('s3')));
SELECT pg_temp.bth('lk3', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T088-A-S3', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A two services inside the window: status ambiguous with both candidates, NEITHER is linked', $qq$pg_temp.rs('lk3')->'service_link'->>'status' = 'ambiguous' AND jsonb_array_length(pg_temp.rs('lk3')->'service_link'->'candidates') = 2
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv3a')::text)) IS NULL AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv3b')::text)) IS NULL
    AND pg_temp.rs('lk3')->>'status' = 'recorded'$qq$, $qq$pg_temp.rs('lk3')::text$qq$);
-- 4. outside the window
SELECT pg_temp.call('sv4', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 100)))', pg_temp.cx('A'), pg_temp.cx('s4')));
SELECT pg_temp.bth('lk4', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S4', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A a service only 100 days before the birth is outside the window: not linked', $qq$pg_temp.rs('lk4')->'service_link'->>'status' = 'no_candidate'
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv4')::text)) IS NULL$qq$);
-- 5. voided candidate excluded
SELECT pg_temp.call('sv5', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 283)))', pg_temp.cx('A'), pg_temp.cx('s5')));
SELECT pg_temp.void_svc(pg_temp.cx('A')::integer, trim(both '"' from pg_temp.rs('sv5')::text)::uuid);
SELECT pg_temp.bth('lk5', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S5', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A a VOIDED service is not a candidate', $qq$pg_temp.rs('lk5')->'service_link'->>'status' = 'no_candidate'
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv5')::text)) IS NULL$qq$);
-- 6. twins: the service is used once
SELECT pg_temp.call('sv6', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(2 + 283)))', pg_temp.cx('A'), pg_temp.cx('s6')));
SELECT pg_temp.bth('lk6a', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S6', 'date', pg_temp.dago(2), 'w', '31'));
SELECT pg_temp.bth('lk6b', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T088-A-S6', 'date', pg_temp.dago(2), 'w', '29', 'force', 'true'));
SELECT pg_temp.t('A twins: the first calf takes the service, the second finds no candidate and the service stays linked to the first birth', $qq$pg_temp.rs('lk6a')->'service_link'->>'status' = 'linked' AND pg_temp.rs('lk6b')->'service_link'->>'status' = 'no_candidate'
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv6')::text)) = (pg_temp.rs('lk6a')->>'birth_event_id')::uuid$qq$);
-- 7. edges of the window (238 and 328 days are inside; 237 and 329 outside)
SELECT pg_temp.call('sve1', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 238)))', pg_temp.cx('A'), pg_temp.cx('e1')));
SELECT pg_temp.call('sve2', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 328)))', pg_temp.cx('A'), pg_temp.cx('e2')));
SELECT pg_temp.call('sve3', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 237)))', pg_temp.cx('A'), pg_temp.cx('e3')));
SELECT pg_temp.call('sve4', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 329)))', pg_temp.cx('A'), pg_temp.cx('e4')));
SELECT pg_temp.bth('le1', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-E1', 'date', pg_temp.dago(1)));
SELECT pg_temp.bth('le2', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-E2', 'date', pg_temp.dago(1)));
SELECT pg_temp.bth('le3', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-E3', 'date', pg_temp.dago(1)));
SELECT pg_temp.bth('le4', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-E4', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('A window edges: 238 and 328 days are linked, 237 and 329 are not', $qq$pg_temp.rs('le1')->'service_link'->>'status' = 'linked' AND pg_temp.rs('le2')->'service_link'->>'status' = 'linked'
    AND pg_temp.rs('le3')->'service_link'->>'status' = 'no_candidate' AND pg_temp.rs('le4')->'service_link'->>'status' = 'no_candidate'$qq$);
-- 8. the legacy NULL e-mail path links too
SELECT pg_temp.call('sv7', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, CURRENT_DATE - 1 - 283))', pg_temp.cx('A'), pg_temp.cx('s7')));
SELECT pg_temp.call('lk7', format('SELECT sp_register_birth_event(%L::int, ''MACHO'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE - 1)', pg_temp.cx('A'), pg_temp.cx('s7')));
SELECT pg_temp.t('A the legacy procedure (NULL e-mail, as the gateway calls it) also links the single plausible service', $qq$(pg_temp.rs('lk7')->>'success')::boolean AND pg_temp.rs('lk7')->'service_link'->>'status' = 'linked'
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv7')::text)) = (pg_temp.rs('lk7')->>'birth_event_id')::uuid$qq$);
-- 9. sheep (BORREGO names) and no dam
SELECT pg_temp.call('sv8', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 152)))', pg_temp.cx('A'), pg_temp.cx('sheep')));
SELECT pg_temp.bth('lk8', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T088-A-SHEEP', 'date', pg_temp.dago(1), 'sp', 'BORREGO'));
SELECT pg_temp.call('lk9', format('SELECT sp_register_birth_event(%L::int, ''HEMBRA'', ''BORREGO'', NULL, NULL, NULL, CURRENT_DATE - 1)', pg_temp.cx('A')));
SELECT pg_temp.t('A a BORREGO birth links with the BORREGO window (152 days); a flock birth without dam links nothing (service_link null)', $qq$pg_temp.rs('lk8')->>'status' = 'recorded' AND pg_temp.rs('lk8')->'service_link'->>'status' = 'linked'
    AND (pg_temp.rs('lk9')->>'success')::boolean AND pg_temp.rs('lk9')->'service_link' = 'null'::jsonb$qq$, $qq$pg_temp.rs('lk8')::text$qq$);
-- 10. isolation of the linker
SELECT pg_temp.call('sv9', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(1 + 283)))', pg_temp.cx('B'), pg_temp.cx('bs1')));
SELECT pg_temp.call('lkiso', format('SELECT fn_repro_link_birth_service(%L::uuid, %L::int)', pg_temp.rs('lk1')->>'birth_event_id', pg_temp.cx('B')));
SELECT pg_temp.t('A ISOLATION: the linker of company B cannot see or touch a birth of company A (not_found), and company B''s service stays unlinked', $qq$pg_temp.rs('lkiso')->>'status' = 'not_found' AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv9')::text)) IS NULL$qq$);
SELECT pg_temp.call('lkagain', format('SELECT fn_repro_link_birth_service(%L::uuid, %L::int)', pg_temp.rs('lk1')->>'birth_event_id', pg_temp.cx('A')));
SELECT pg_temp.t('A calling the linker again is harmless: already_linked, no change', $qq$pg_temp.rs('lkagain')->>'status' = 'already_linked'$qq$);

-- =============================================================================================================
-- PART B. the guard trigger
-- =============================================================================================================

SELECT pg_temp.t('B any other change of a service row raises P0097 (notes, date, sire, method, dam) - also on a linked and on an unlinked row', $qq$pg_temp.raises(format('UPDATE cattle_breeding_events SET notes = ''x'' WHERE id = %L', trim(both '"' from pg_temp.rs('sv1')::text)), 'P0097')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET breeding_date = breeding_date + 1 WHERE id = %L', trim(both '"' from pg_temp.rs('sv4')::text)), 'P0097')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET sire_identifier = ''x'' WHERE id = %L', trim(both '"' from pg_temp.rs('sv4')::text)), 'P0097')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET method = ''INSEMINACION_ARTIFICIAL'' WHERE id = %L', trim(both '"' from pg_temp.rs('sv4')::text)), 'P0097')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET livestock_id = %L WHERE id = %L', pg_temp.cx('s2'), trim(both '"' from pg_temp.rs('sv4')::text)), 'P0097')$qq$);
SELECT pg_temp.t('B a linked service can never be re-linked, cleared or moved (P0097)', $qq$pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = NULL WHERE id = %L', trim(both '"' from pg_temp.rs('sv1')::text)), 'P0097')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = %L WHERE id = %L', pg_temp.rs('lk2')->>'birth_event_id', trim(both '"' from pg_temp.rs('sv1')::text)), 'P0097')$qq$);
SELECT pg_temp.t('B an UPDATE that changes nothing passes (the trigger only rejects real changes)', $qq$pg_temp.no_error(format('UPDATE cattle_breeding_events SET notes = notes WHERE id = %L', trim(both '"' from pg_temp.rs('sv4')::text)))
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv4')::text)) IS NULL$qq$);
SELECT pg_temp.t('B a service cannot be linked to a birth of ANOTHER dam or ANOTHER company (P0096)', $qq$pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = %L WHERE id = %L', pg_temp.rs('lk2')->>'birth_event_id', trim(both '"' from pg_temp.rs('sv4')::text)), 'P0096')
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = %L WHERE id = %L', pg_temp.rs('lk1')->>'birth_event_id', trim(both '"' from pg_temp.rs('sv9')::text)), 'P0096')$qq$);
SELECT pg_temp.t('B a VOIDED service cannot be linked (P0097); an INSERT cannot carry a link (P0097)', $qq$pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = %L WHERE id = %L', pg_temp.rs('lk5')->>'birth_event_id', trim(both '"' from pg_temp.rs('sv5')::text)), 'P0097')
    AND pg_temp.raises(format('INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method, birth_event_id) VALUES (%L, %L, CURRENT_DATE, ''MONTA_NATURAL'', %L)',
                              pg_temp.cx('s1'), pg_temp.cx('A'), pg_temp.rs('lk1')->>'birth_event_id'), 'P0097')$qq$);
SELECT pg_temp.call('manual', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(400)))', pg_temp.cx('A'), pg_temp.cx('s9')));
SELECT pg_temp.bth('lk10', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-S9', 'date', pg_temp.dago(1)));
SELECT pg_temp.t('B an old service outside the window stays unlinked automatically (no_candidate) ...', $qq$pg_temp.rs('lk10')->'service_link'->>'status' = 'no_candidate' AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('manual')::text)) IS NULL$qq$);
SELECT pg_temp.t('B ... and the one allowed update works: NULL -> a birth of the SAME dam and company (a person''s decision), exactly once', $qq$pg_temp.no_error(format('UPDATE cattle_breeding_events SET birth_event_id = %L WHERE id = %L', pg_temp.rs('lk10')->>'birth_event_id', trim(both '"' from pg_temp.rs('manual')::text)))
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('manual')::text)) = (pg_temp.rs('lk10')->>'birth_event_id')::uuid
    AND pg_temp.raises(format('UPDATE cattle_breeding_events SET birth_event_id = NULL WHERE id = %L', trim(both '"' from pg_temp.rs('manual')::text)), 'P0097')$qq$);

-- =============================================================================================================
-- PART C. sp_log_breeding_event
-- =============================================================================================================

CREATE TEMP TABLE t_base_c ON COMMIT DROP AS SELECT (SELECT count(*) FROM cattle_breeding_events) AS svcs;
SELECT pg_temp.t('C a NON-member e-mail, a NULL e-mail, a blank e-mail and an INACTIVE membership are refused with P0001 and nothing is written', $qq$pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, ''nadie@example.test'', NULL)', 'T088-A-F1', pg_temp.cx('A')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, NULL, NULL)', 'T088-A-F1', pg_temp.cx('A')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, ''  '', NULL)', 'T088-A-F1', pg_temp.cx('A')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088-B-F1', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
    AND (SELECT count(*) FROM cattle_breeding_events) = (SELECT svcs FROM t_base_c)$qq$);

SELECT pg_temp.brd('c1', 'T088-A-F1', pg_temp.dd(10), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.t('C natural service with a sire that is a bull of the company: success, sire_livestock_id returned, no warnings, BOVINO due date +283, stored sire text kept', $qq$(pg_temp.rs('c1')->>'success')::boolean AND pg_temp.rs('c1')->>'sire_livestock_id' = pg_temp.cx('bull1') AND pg_temp.rs('c1')->'warnings' = '[]'::jsonb
    AND (pg_temp.rs('c1')->>'estimated_due_date')::date = pg_temp.dd(10) + 283 AND pg_temp.rs('c1')->>'duplicate_skipped' = 'false'
    AND (SELECT e.sire_identifier = 'T088-A-BULL1' AND lower(e.registered_by_email) = lower(pg_temp.cx('u1')) FROM cattle_breeding_events e WHERE e.id = (pg_temp.rs('c1')->>'breeding_event_id')::uuid)$qq$, $qq$pg_temp.rs('c1')::text$qq$);
SELECT pg_temp.brd('c2', 'T088-A-F2', pg_temp.dd(10), 'MONTA_NATURAL', 'T088-A-TORETE');
SELECT pg_temp.t('C a BECERRO_TORETE is an accepted sire', $qq$(pg_temp.rs('c2')->>'success')::boolean AND pg_temp.rs('c2')->>'sire_livestock_id' = pg_temp.cx('torete')$qq$);
CREATE TEMP TABLE t_base_c2 ON COMMIT DROP AS SELECT (SELECT count(*) FROM cattle_breeding_events) AS svcs;
SELECT pg_temp.brd('c3', 'T088-A-F3', pg_temp.dd(10), 'MONTA_NATURAL', 'T088-A-COWSIRE');
SELECT pg_temp.brd('c4', 'T088-A-F3', pg_temp.dd(10), 'MONTA_NATURAL', 'T088BDUP');
SELECT pg_temp.brd('c5', 'T088-A-F3', pg_temp.dd(10), 'MONTA_NATURAL', 'T088-A-F3');
SELECT pg_temp.t('C a sire that resolves but is a cow is REJECTED (SIRE_NOT_BULL, an answer not an error); several matches are AMBIGUOUS with candidates; the female herself is rejected; nothing written', $qq$NOT (pg_temp.rs('c3')->>'success')::boolean AND pg_temp.rs('c3')->>'status' = 'rejected' AND pg_temp.rs('c3')->>'code' = 'SIRE_NOT_BULL'
    AND NOT (pg_temp.rs('c4')->>'success')::boolean AND pg_temp.rs('c4')->>'status' = 'ambiguous' AND jsonb_array_length(pg_temp.rs('c4')->'candidates') = 2
    AND pg_temp.rs('c5')->>'code' = 'SIRE_IS_THE_FEMALE'
    AND (SELECT count(*) FROM cattle_breeding_events) = (SELECT svcs FROM t_base_c2)$qq$, $qq$pg_temp.rs('c3')::text$qq$);
SELECT pg_temp.brd('c6', 'T088-A-F4', pg_temp.dd(10), 'MONTA_NATURAL', 'Toro de la vecina');
SELECT pg_temp.brd('c7', 'T088-A-F5', pg_temp.dd(10), 'MONTA_NATURAL', 'T088-B-BULL');
SELECT pg_temp.t('C a sire that does not resolve stays free text with the warning sire_not_resolved (never blocks); a bull of ANOTHER company is indistinguishable from an unknown name: same warning, no leak', $qq$(pg_temp.rs('c6')->>'success')::boolean AND pg_temp.rs('c6')->'warnings' = '["sire_not_resolved"]'::jsonb AND pg_temp.rs('c6')->>'sire_livestock_id' IS NULL
    AND (SELECT e.sire_identifier = 'Toro de la vecina' FROM cattle_breeding_events e WHERE e.id = (pg_temp.rs('c6')->>'breeding_event_id')::uuid)
    AND (pg_temp.rs('c7')->>'success')::boolean AND pg_temp.rs('c7')->'warnings' = '["sire_not_resolved"]'::jsonb AND pg_temp.rs('c7')->>'sire_livestock_id' IS NULL
    AND pg_temp.rs('c7')::text NOT LIKE '%' || pg_temp.cx('bbull') || '%'$qq$);
SELECT pg_temp.brd('c8', 'T088-A-F6', pg_temp.dd(10), 'INSEMINACION_ARTIFICIAL', 'Semen Brahman X');
SELECT pg_temp.brd('c9', 'T088-A-F7', pg_temp.dd(10), 'INSEMINACION_ARTIFICIAL', 'Semen Brahman X', 'LOTE-77');
SELECT pg_temp.brd('c10', 'T088-A-F8', pg_temp.dd(10), 'INSEMINACION_ARTIFICIAL', 'T088-A-COWSIRE', 'LOTE-78');
SELECT pg_temp.t('C artificial insemination: no semen batch = warning semen_batch_missing (never blocks); with a batch and an external (unresolved) sire the only warning is sire_not_resolved; a sire that resolves to a cow is rejected here too', $qq$(pg_temp.rs('c8')->>'success')::boolean AND pg_temp.rs('c8')->'warnings' @> '["semen_batch_missing", "sire_not_resolved"]'::jsonb
    AND (pg_temp.rs('c9')->>'success')::boolean AND pg_temp.rs('c9')->'warnings' = '["sire_not_resolved"]'::jsonb
    AND pg_temp.rs('c10')->>'code' = 'SIRE_NOT_BULL'$qq$);
SELECT pg_temp.brd('d1', 'T088-A-F9', pg_temp.dd(5), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.brd('d2', 'T088-A-F9', pg_temp.dd(5), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.brd('d3', 'T088-A-F9', pg_temp.dd(6), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.t('C exact retry (same female, date, method and sire within 5 minutes) is duplicate_skipped with the existing id; another date is a new service', $qq$(pg_temp.rs('d2')->>'duplicate_skipped')::boolean AND pg_temp.rs('d2')->>'breeding_event_id' = pg_temp.rs('d1')->>'breeding_event_id'
    AND NOT (pg_temp.rs('d3')->>'duplicate_skipped')::boolean AND pg_temp.rs('d3')->>'breeding_event_id' <> pg_temp.rs('d1')->>'breeding_event_id'
    AND pg_temp.n_svc(pg_temp.cx('f9')) = 2$qq$);
SELECT pg_temp.void_svc(pg_temp.cx('A')::integer, (pg_temp.rs('d1')->>'breeding_event_id')::uuid);
SELECT pg_temp.brd('d4', 'T088-A-F9', pg_temp.dd(5), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.t('C a VOIDED service does not block a new identical one', $qq$NOT (pg_temp.rs('d4')->>'duplicate_skipped')::boolean AND (pg_temp.rs('d4')->>'success')::boolean$qq$);
SELECT pg_temp.t('C the pre-existing errors are unchanged: bad method P0009, unknown female P0002, ambiguous female P0004, sold female P0001', $qq$pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MAGIA'', NULL, NULL, %L, NULL)', 'T088-A-F1', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0009')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088-NOPE', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0002')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088FDUP', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0004')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088-A-FSOLD', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0001')$qq$);
SELECT pg_temp.t('C ISOLATION: company A cannot register a service for an animal of company B (P0002); company B''s user cannot act in A (P0001)', $qq$pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088-B-F1', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0002')
    AND pg_temp.raises(format('SELECT sp_log_breeding_event(%L, %L::int, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', 'T088-A-F1', pg_temp.cx('A'), pg_temp.cx('u2')), 'P0001')
    AND pg_temp.n_svc(pg_temp.cx('bf1')) = 0$qq$);
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.brd('ed', 'T088-A-F1', pg_temp.dd(20), 'MONTA_NATURAL', 'T088-A-BULL1');
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');
SELECT pg_temp.t('C any active member may register a service (EDITOR)', $qq$(pg_temp.rs('ed')->>'success')::boolean$qq$);

-- =============================================================================================================
-- PART D. sp_void_event
-- =============================================================================================================

SELECT pg_temp.t('D a NON-member, a NULL and a blank e-mail are refused with P0001 and nothing is voided', $qq$pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, ''nadie@example.test'', ''x'')', pg_temp.rs('c1')->>'breeding_event_id', pg_temp.cx('A')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, NULL, ''x'')', pg_temp.rs('c1')->>'breeding_event_id', pg_temp.cx('A')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, '' '', ''x'')', pg_temp.rs('c1')->>'breeding_event_id', pg_temp.cx('A')), 'P0001')
    AND NOT EXISTS (SELECT 1 FROM event_voids WHERE event_id = (pg_temp.rs('c1')->>'breeding_event_id')::uuid)$qq$);
SELECT pg_temp.call('v1', format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, %L, ''T088 captured twice'')', pg_temp.rs('c2')->>'breeding_event_id', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('D a member voids an UNLINKED service: success, one event_voids row', $qq$(pg_temp.rs('v1')->>'success')::boolean AND (SELECT count(*) FROM event_voids WHERE event_id = (pg_temp.rs('c2')->>'breeding_event_id')::uuid) = 1$qq$, $qq$pg_temp.rs('v1')::text$qq$);
SELECT pg_temp.t('D one void per event stays: voiding it again raises P0017', $qq$pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, %L, ''again'')', pg_temp.rs('c2')->>'breeding_event_id', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0017')$qq$);
CREATE TEMP TABLE t_base_d2 ON COMMIT DROP AS SELECT pg_temp.n_voids() AS voids;
SELECT pg_temp.call('v2', format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, %L, ''wrong service'')', trim(both '"' from pg_temp.rs('sv1')::text), pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.t('D a service LINKED to a birth is refused with an ANSWER (rejected / LINKED_TO_BIRTH + the birth); no void row; the link is intact', $qq$NOT (pg_temp.rs('v2')->>'success')::boolean AND pg_temp.rs('v2')->>'status' = 'rejected' AND pg_temp.rs('v2')->>'code' = 'LINKED_TO_BIRTH'
    AND pg_temp.rs('v2')->>'birth_event_id' = pg_temp.rs('lk1')->>'birth_event_id' AND pg_temp.n_voids() = (SELECT voids FROM t_base_d2)
    AND pg_temp.svc_link(trim(both '"' from pg_temp.rs('sv1')::text)) = (pg_temp.rs('lk1')->>'birth_event_id')::uuid$qq$, $qq$pg_temp.rs('v2')::text$qq$);
SELECT pg_temp.t('D the whitelist stays (P0016 for another table), an event of another company or unknown is P0002, and B cannot void A''s service', $qq$pg_temp.raises(format('SELECT sp_void_event(''cattle_livestock'', %L::uuid, %L::int, %L, ''x'')', pg_temp.cx('s1'), pg_temp.cx('A'), pg_temp.cx('u1')), 'P0016')
    AND pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', gen_random_uuid(), %L::int, %L, ''x'')', pg_temp.cx('A'), pg_temp.cx('u1')), 'P0002')
    AND pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, %L, ''x'')', pg_temp.rs('c9')->>'breeding_event_id', pg_temp.cx('B'), pg_temp.cx('u2')), 'P0002')
    AND pg_temp.raises(format('SELECT sp_void_event(''cattle_breeding_events'', %L::uuid, %L::int, %L, ''x'')', pg_temp.rs('c9')->>'breeding_event_id', pg_temp.cx('A'), pg_temp.cx('u2')), 'P0001')$qq$);
SELECT pg_temp.t('D voiding does not reverse side effects (the female keeps her status)', $qq$(SELECT current_status FROM cattle_livestock WHERE id = pg_temp.cx('f2')::uuid) = 'ACTIVO'$qq$);

-- =============================================================================================================
-- PART E. get_dam_reproductive_history
-- =============================================================================================================

-- hd1: PREÑADA, 1 registered birth (linked service), 1 historical birth, 1 voided service, 2 palpations
INSERT INTO repro_condition_codes (id_company, code, repro_condition, source, confirmed_by, confirmed_at)
VALUES (pg_temp.cx('A')::integer, 'UNE', 'ESTATICA', 'T088', 'T088', now());
SELECT pg_temp.call('hs1', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(2 + 283)))', pg_temp.cx('A'), pg_temp.cx('hd1')));
SELECT pg_temp.call('hs2', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(60)))', pg_temp.cx('A'), pg_temp.cx('hd1')));
SELECT pg_temp.void_svc(pg_temp.cx('A')::integer, trim(both '"' from pg_temp.rs('hs2')::text)::uuid);
SELECT pg_temp.bth('hb', jsonb_build_object('sex', 'MACHO', 'dam', 'T088-A-HD1', 'date', pg_temp.dago(2), 'w', '35'));
SELECT pg_temp.call('hh', format('SELECT sp_repro_register_historical_birth(%L, %L, %L, NULL, %L, ''YEAR'')', pg_temp.cx('A'), pg_temp.cx('u1'), 'T088-A-HD1', to_char(fn_repro_today() - 900, 'YYYY')));
SELECT pg_temp.call('hp', format('SELECT sp_repro_log_palpation_batch(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'),
    jsonb_build_array(jsonb_build_object('identifier', 'T088-A-HD1', 'raw_diagnosis', 'VACÍA UNE/OI'))::text));
UPDATE cattle_livestock SET current_status = 'PREÑADA' WHERE id = pg_temp.cx('hd1')::uuid;
INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
VALUES (pg_temp.cx('hd1')::uuid, 'PALPACION', 'T088 fixture', jsonb_build_object('resultado', 'PREÑADA', 'dias_gestacion', '120', 'condicion_utero', 'UNE/NR'),
        fn_repro_today()::timestamp - interval '30 days');
SELECT pg_temp.call('h1', format('SELECT sp_repro_get_dam_history(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T088-A-HD1'));
SELECT pg_temp.t('E the history answers ok with the dam, her status and every section', $qq$pg_temp.rs('h1')->>'status' = 'ok' AND pg_temp.rs('h1')->'dam'->>'livestock_id' = pg_temp.cx('hd1') AND pg_temp.rs('h1')->>'current_status' = 'PREÑADA'
    AND pg_temp.rs('h1') ?& ARRAY['births', 'historical_births', 'services', 'palpations', 'empadre_entries', 'expected_calving', 'quality_flags']$qq$, $qq$pg_temp.rs('h1')::text$qq$);
SELECT pg_temp.t('E births: the registered birth with its calf and the LINKED service; historical births: the YEAR one without calf', $qq$jsonb_array_length(pg_temp.rs('h1')->'births') = 1 AND pg_temp.rs('h1')->'births'->0->>'calf_id' IS NOT NULL
    AND pg_temp.rs('h1')->'births'->0->>'linked_service_id' = trim(both '"' from pg_temp.rs('hs1')::text)
    AND lower(pg_temp.rs('h1')->'births'->0->>'reported_by_email') = lower(pg_temp.cx('u1'))
    AND jsonb_array_length(pg_temp.rs('h1')->'historical_births') = 1 AND pg_temp.rs('h1')->'historical_births'->0->>'date_precision' = 'YEAR'
    AND NOT (pg_temp.rs('h1')->'historical_births'->0->>'voided')::boolean$qq$);
SELECT pg_temp.t('E services: both listed, the linked one with its birth and the voided one flagged voided', $qq$jsonb_array_length(pg_temp.rs('h1')->'services') = 2
    AND (SELECT (e->>'linked_to_birth')::boolean AND NOT (e->>'voided')::boolean FROM jsonb_array_elements(pg_temp.rs('h1')->'services') e WHERE e->>'breeding_event_id' = trim(both '"' from pg_temp.rs('hs1')::text))
    AND (SELECT (e->>'voided')::boolean FROM jsonb_array_elements(pg_temp.rs('h1')->'services') e WHERE e->>'breeding_event_id' = trim(both '"' from pg_temp.rs('hs2')::text))$qq$);
SELECT pg_temp.t('E palpations: both key sets, the repro_condition of the logged one (UNE/OI -> ESTATICA, side OI) and the legacy condicion_utero of the bulk-loaded one', $qq$jsonb_array_length(pg_temp.rs('h1')->'palpations') = 2
    AND (SELECT e->>'repro_condition' = 'ESTATICA' AND e->>'ovary_side' = 'OI' AND e->>'mapping_status' = 'MAPPED' FROM jsonb_array_elements(pg_temp.rs('h1')->'palpations') e WHERE e->>'raw_uterine_code' = 'UNE/OI')
    AND (SELECT e->>'result' = 'PREÑADA' AND e->>'legacy_condicion_utero' = 'UNE/NR' AND (e->>'gestation_days')::int = 120 FROM jsonb_array_elements(pg_temp.rs('h1')->'palpations') e WHERE e->>'legacy_condicion_utero' IS NOT NULL)$qq$);
SELECT pg_temp.t('E expected calving for a PREÑADA cow: last PREÑADA palpation (30 days ago, 120 gestation days) + (283 - 120) = 133 days from today, source PALPACION, bucket upcoming', $qq$(pg_temp.rs('h1')->'expected_calving'->>'applies')::boolean AND pg_temp.rs('h1')->'expected_calving'->>'estimate_source' = 'PALPACION'
    AND (pg_temp.rs('h1')->'expected_calving'->>'estimated_calving_date')::date = pg_temp.dd(30) + (283 - 120)
    AND (pg_temp.rs('h1')->'expected_calving'->>'days_to_calving')::int = 133 AND pg_temp.rs('h1')->'expected_calving'->>'bucket' = 'upcoming'$qq$, $qq$pg_temp.rs('h1')->>'expected_calving'$qq$);
SELECT pg_temp.t('E quality flags: the birth has its linked service (0 births without one), no old unlinked service, and the PREÑADA status against the NEWEST palpation (VACÍA, logged today) is reported as a mismatch', $qq$(pg_temp.rs('h1')->'quality_flags'->>'births_without_linked_service')::int = 0
    AND (pg_temp.rs('h1')->'quality_flags'->>'services_older_than_gestation_still_unlinked')::int = 0
    AND (pg_temp.rs('h1')->'quality_flags'->>'status_vs_last_palpation_mismatch')::boolean$qq$, $qq$pg_temp.rs('h1')->>'quality_flags'$qq$);
-- hd2: not PREÑADA, an old service never linked, a birth without a service
SELECT pg_temp.call('hs3', format('SELECT to_jsonb(pg_temp.svc(%L::int, %L::uuid, pg_temp.dd(500)))', pg_temp.cx('A'), pg_temp.cx('hd2')));
SELECT pg_temp.bth('hb2', jsonb_build_object('sex', 'HEMBRA', 'dam', 'T088-A-HD2', 'date', pg_temp.dago(3)));
SELECT pg_temp.call('h2', format('SELECT sp_repro_get_dam_history(%L, %L, NULL, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.cx('hd2')));
SELECT pg_temp.t('E flags: an old service still unlinked and a birth without a linked service are reported; a non-PREÑADA cow has no expected calving', $qq$(pg_temp.rs('h2')->'quality_flags'->>'services_older_than_gestation_still_unlinked')::int = 1
    AND (pg_temp.rs('h2')->'quality_flags'->>'births_without_linked_service')::int = 1
    AND NOT (pg_temp.rs('h2')->'expected_calving'->>'applies')::boolean$qq$, $qq$pg_temp.rs('h2')::text$qq$);
-- hd3: stale import date + status mismatch
DO $$
DECLARE
    v_a  integer := pg_temp.cx('A')::integer;
    v_id uuid;
    g    integer;
BEGIN
    FOR g IN 1..14 LOOP
        v_id := pg_temp.mk(v_a, 'A-IMP' || g, NULL, 'VACA', 'PREÑADA');
        INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
        VALUES (v_id, 'PALPACION', 'T088 import', jsonb_build_object('resultado', 'PREÑADA', 'dias_gestacion', '90'), fn_repro_today()::timestamp - interval '400 days');
    END LOOP;
    INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
    VALUES (pg_temp.cx('hd3')::uuid, 'PALPACION', 'T088 import', jsonb_build_object('resultado', 'VACIA'), fn_repro_today()::timestamp - interval '400 days');
    UPDATE cattle_livestock SET current_status = 'PREÑADA' WHERE id = pg_temp.cx('hd3')::uuid;
END $$;
SELECT pg_temp.call('h3', format('SELECT sp_repro_get_dam_history(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T088-A-HD3'));
SELECT pg_temp.t('E flags: a palpation on the company''s import date is marked on_stale_import_date, the company flag names the date, and a PREÑADA status against a VACÍA palpation is a mismatch; a PREÑADA cow with no usable estimate says so', $qq$(pg_temp.rs('h3')->'quality_flags'->'stale_import_date_company'->>'flag')::boolean
    AND (pg_temp.rs('h3')->'quality_flags'->'stale_import_date_company'->>'date')::date = pg_temp.dd(400)
    AND (pg_temp.rs('h3')->'quality_flags'->>'palpations_on_stale_import_date')::int = 1
    AND (pg_temp.rs('h3')->'quality_flags'->>'status_vs_last_palpation_mismatch')::boolean
    AND pg_temp.rs('h3')->'expected_calving'->>'bucket' = 'no_estimate'$qq$, $qq$pg_temp.rs('h3')::text$qq$);
SELECT pg_temp.t('E the dam by fire number that is not unique answers ambiguous with candidates; unknown is not_found; a missing dam is DAM_MISSING; no dam is picked', $qq$sp_repro_get_dam_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T088FDUP')->>'status' = 'ambiguous'
    AND jsonb_array_length(sp_repro_get_dam_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T088FDUP')->'candidates') = 2
    AND sp_repro_get_dam_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T088-NOPE')->>'status' = 'not_found'
    AND sp_repro_get_dam_history(pg_temp.cx('A'), pg_temp.cx('u1'))->>'code' = 'DAM_MISSING'$qq$);
SELECT pg_temp.t('E ISOLATION: company A''s dam is not_found for B (by id and by identifier), B''s history shows none of A''s rows, and user 1 gets an ERROR for B', $qq$sp_repro_get_dam_history(pg_temp.cx('B'), pg_temp.cx('u2'), NULL, pg_temp.cx('hd1'))->>'status' = 'not_found'
    AND sp_repro_get_dam_history(pg_temp.cx('B'), pg_temp.cx('u2'), 'T088-A-HD1')->>'status' = 'not_found'
    AND sp_repro_get_dam_history(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, pg_temp.cx('bs1'))->>'status' = 'not_found'
    AND jsonb_array_length(sp_repro_get_dam_history(pg_temp.cx('B'), pg_temp.cx('u2'), 'T088-B-S1')->'services') = 1
    AND (SELECT count(*) FROM jsonb_array_elements(sp_repro_get_dam_history(pg_temp.cx('B'), pg_temp.cx('u2'), 'T088-B-S1')->'births')) = 0
    AND pg_temp.raises(format('SELECT sp_repro_get_dam_history(%L, %L, ''T088-B-S1'')', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')$qq$);

-- =============================================================================================================
-- PART F. fail-closed
-- =============================================================================================================

SELECT pg_temp.t('F get_dam_reproductive_history raises P0001 for user 1 on B, a stranger, a blank e-mail and bad tenants', $qq$(SELECT bool_and(pg_temp.raises(format('SELECT sp_repro_get_dam_history(%L, %L, ''T088-A-HD1'')', t.tn, t.em), 'P0001'))
       FROM (VALUES (pg_temp.cx('B'), pg_temp.cx('u1')), (pg_temp.cx('A'), 'nadie@example.test'), (pg_temp.cx('A'), ''), ('abc', pg_temp.cx('u1')),
                    ('', pg_temp.cx('u1')), (pg_temp.cx('A') || ' OR 1=1', pg_temp.cx('u1'))) AS t (tn, em))$qq$);
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
    VALUES ('F palm company is rejected (P0094) by the history tool',
            pg_temp.raises(format('SELECT sp_repro_get_dam_history(%L, %L, ''x'')', v_palm::text, pg_temp.cx('u1')), 'P0094'), 'palm company ' || v_palm);
END $$;

-- =============================================================================================================
-- PART G. nothing else was written
-- =============================================================================================================

SELECT pg_temp.t('G sp_log_palpation_event and sp_register_birth_event are byte-identical to the start of this run (088 does not touch them)', $qq$NOT EXISTS (SELECT 1 FROM t_proc t JOIN pg_proc p ON p.proname = t.proname AND p.pronamespace = 'public'::regnamespace WHERE md5(pg_get_functiondef(p.oid)) <> t.md5)$qq$);
SELECT pg_temp.t('G both hardened procedures carry the 088 marker and keep exactly their production signatures', $qq$(SELECT prosrc LIKE '%088:legacy-breeding-v1%' AND pronargs = 8 FROM pg_proc WHERE oid = to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)'))
    AND (SELECT prosrc LIKE '%088:legacy-void-v1%' AND pronargs = 5 FROM pg_proc WHERE oid = to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)'))$qq$);
SELECT pg_temp.t('G every link is consistent: the birth belongs to the service''s company and dam; no birth has two services; none of the tools or helpers is in crud_models', $qq$NOT EXISTS (SELECT 1 FROM cattle_breeding_events e LEFT JOIN birth_events b ON b.id = e.birth_event_id AND b.id_company = e.tenant_id AND b.dam_id = e.livestock_id
                 WHERE e.birth_event_id IS NOT NULL AND b.id IS NULL)
    AND NOT EXISTS (SELECT 1 FROM cattle_breeding_events WHERE birth_event_id IS NOT NULL GROUP BY birth_event_id HAVING count(*) > 1)
    AND NOT EXISTS (SELECT 1 FROM crud_models WHERE table_name = 'sp_repro_get_dam_history' OR model_name = 'sp_repro_get_dam_history')$qq$);
SELECT pg_temp.t('G company B''s service was never linked by company A''s births, and no voided service carries a link', $qq$NOT EXISTS (SELECT 1 FROM cattle_breeding_events e WHERE e.tenant_id = pg_temp.cx('B')::integer AND e.birth_event_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM cattle_breeding_events e JOIN event_voids v ON v.event_table = 'cattle_breeding_events' AND v.event_id = e.id
                     WHERE e.birth_event_id IS NOT NULL AND e.registered_by_email = 'T088')$qq$);

SELECT pg_temp.t('088 tests ran inside ONE transaction: no included file committed or rolled back (the same txid is still current)',
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
        RAISE EXCEPTION '088 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 088 tests: everything rolled back ***'
