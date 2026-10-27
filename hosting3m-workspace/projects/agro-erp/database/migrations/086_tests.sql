-- 086_tests.sql — functional checks for migration 086 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It loads 084, 085 and 086 inside this transaction (embedded mode), so it runs the same way whether or not they are
-- applied. It needs a database that has the real schema plus AT LEAST two ACTIVE non-palm companies and two users
-- (see 086_RUNBOOK.md, "Test database"), and NO palpations in those two companies (a schema-only copy). It picks the two
-- companies (A, B) and two users and arranges memberships INSIDE the transaction (filtered UPDATE / INSERT, rolled back):
--     user 1: ACTIVE ADMIN of A, INACTIVE in B        user 2: ACTIVE ADMIN of B, INACTIVE in A
-- Fixture animals use identifiers prefixed T086 so existing data cannot interfere; assertions are about those fixtures
-- (found by id in the paged lists), never about counts of pre-existing data.
--
-- Snapshot rule used throughout: a statement never reads a row that a write tool created in the SAME statement.
-- Every write goes through pg_temp.call(key, sql) in its own statement; the result is kept in t_res and asserted in
-- the NEXT statement.
--
-- Part A  parser unit tests (UNE, UNE/NR, UTCL2/OI, 'VACIA UNE', 'No apto', N/A, empty, explicit words, never raises)
-- Part B  sp_repro_condition_code_set (ADMIN only, validation, normalisation, isolation)
-- Part C  log_palpation_with_condition (details, mapping, all-or-nothing, idempotency, dates, roles, cross-company)
-- Part D  side table: append-only, tenant guard, CHECK constraints; the existing tools are untouched
-- Part E  list_palpation_due (both key sets, both spellings, empadre, stale_import_date, days, order, isolation)
-- Part F  list_upcoming_calvings (palpation / service estimate, buckets, stale_data, isolation)
-- Part G  list_unmapped_uterine_codes (tokens, bulk-loaded + logged, isolation)
-- Part H  fail-closed on every tool (stranger, other company, blank, bad tenant, palm)
-- Part I  nothing else was written
--
-- Run (the test files must be INSIDE the container; psql resolves \ir relative to this file):
--   docker exec n8n-enterprise-db rm -rf /tmp/m086
--   docker cp database/migrations n8n-enterprise-db:/tmp/m086
--   docker exec -w /tmp/m086 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m086/086_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql
\ir 086_repro_palpation.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE t_res (k text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.cx(p_key text) RETURNS text
LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;

CREATE FUNCTION pg_temp.call(p_key text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    EXECUTE p_sql INTO v;
    INSERT INTO t_res (k, r) VALUES (p_key, v);
END $$;

CREATE FUNCTION pg_temp.rs(p_key text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT r FROM t_res WHERE k = p_key $$;

-- log_palpation_with_condition (company A as user 1 by default)
CREATE FUNCTION pg_temp.plog(p_key text, p_items text, p_date text DEFAULT NULL, p_tech text DEFAULT NULL,
                             p_who text DEFAULT 'u1', p_company text DEFAULT 'A') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.call(p_key, format('SELECT sp_repro_log_palpation_batch(%L, %L, %L, %L, %L)',
                                       pg_temp.cx(p_company), pg_temp.cx(p_who), p_items, p_date, p_tech));
END $$;

CREATE FUNCTION pg_temp.raises(p_sql text, p_state text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE = p_state;
END $$;

CREATE FUNCTION pg_temp.no_error(p_sql text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END $$;

-- parser result as 'raw|side|condition|status' (empty string for NULL)
CREATE FUNCTION pg_temp.pc(p_text text, p_tenant text DEFAULT NULL) RETURNS text
LANGUAGE sql AS $$
    SELECT concat_ws('|', coalesce(raw_code, ''), coalesce(ovary_side, ''), coalesce(repro_condition, ''), mapping_status)
      FROM fn_parse_uterine_code(p_text, p_tenant::integer)
$$;

-- a fixture animal's details row as jsonb (the latest one)
CREATE FUNCTION pg_temp.det(p_key text) RETURNS jsonb
LANGUAGE sql AS $$
    SELECT to_jsonb(d) FROM palpation_repro_details d JOIN cattle_livestock l ON l.id = d.livestock_id
     WHERE l.rfid_siniiga = 'T086-' || p_key ORDER BY d.created_at DESC, d.id LIMIT 1
$$;

CREATE FUNCTION pg_temp.n_det() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM palpation_repro_details $$;
CREATE FUNCTION pg_temp.n_logs() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::integer FROM cattle_health_logs $$;
CREATE FUNCTION pg_temp.n_codes(p_company text) RETURNS integer
LANGUAGE sql AS $$ SELECT count(*)::integer FROM repro_condition_codes WHERE id_company = p_company::integer $$;

-- the fixture's health log (latest PALPACION)
CREATE FUNCTION pg_temp.hl(p_key text) RETURNS jsonb
LANGUAGE sql AS $$
    SELECT to_jsonb(h) FROM cattle_health_logs h JOIN cattle_livestock l ON l.id = h.livestock_id
     WHERE l.rfid_siniiga = 'T086-' || p_key AND h.event_type = 'PALPACION' ORDER BY h.created_at DESC, h.id LIMIT 1
$$;

CREATE FUNCTION pg_temp.status_of(p_key text) RETURNS text
LANGUAGE sql AS $$ SELECT current_status FROM cattle_livestock WHERE rfid_siniiga = 'T086-' || p_key $$;

-- element and 1-based position of an animal in a paged list array of a tool: {pos, row}, or NULL when not listed
CREATE FUNCTION pg_temp.find_in(p_fn text, p_tenant text, p_email text, p_days text, p_array text, p_id text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    o integer := 0; r jsonb; e jsonb; p integer;
BEGIN
    WHILE o < 3000 LOOP
        EXECUTE format('SELECT %I(%L, %L, %L, %L, %L)', p_fn, p_tenant, p_email, p_days, '100', o::text) INTO r;
        SELECT x.ord::integer, x.val INTO p, e
          FROM jsonb_array_elements(r->p_array) WITH ORDINALITY AS x(val, ord) WHERE x.val->>'livestock_id' = p_id LIMIT 1;
        IF e IS NOT NULL THEN RETURN jsonb_build_object('pos', o + p, 'row', e); END IF;
        EXIT WHEN jsonb_array_length(r->p_array) < 100;
        o := o + 100;
    END LOOP;
    RETURN NULL;
END $$;

CREATE FUNCTION pg_temp.due(p_key text, p_days text DEFAULT NULL, p_company text DEFAULT 'A', p_who text DEFAULT 'u1') RETURNS jsonb
LANGUAGE sql AS $$
    SELECT pg_temp.find_in('sp_repro_list_palpation_due', pg_temp.cx(p_company), pg_temp.cx(p_who), p_days, 'cows', pg_temp.cx(p_key))
$$;

CREATE FUNCTION pg_temp.cal(p_arr text, p_key text, p_days text DEFAULT NULL, p_company text DEFAULT 'A', p_who text DEFAULT 'u1') RETURNS jsonb
LANGUAGE sql AS $$
    SELECT pg_temp.find_in('sp_repro_list_upcoming_calvings', pg_temp.cx(p_company), pg_temp.cx(p_who), p_days, p_arr, pg_temp.cx(p_key))
$$;

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
        RAISE EXCEPTION '086 tests need two active non-palm companies in the database (see 086_RUNBOOK.md, Test database).';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '086 tests need two users in the database (see 086_RUNBOOK.md, Test database).';
    END IF;
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T086%') THEN
        RAISE EXCEPTION '086 tests: T086 fixtures already exist in this database; run the tests on a clean copy.';
    END IF;
    IF EXISTS (SELECT 1 FROM fn_repro_palpations(v_a)) OR EXISTS (SELECT 1 FROM fn_repro_palpations(v_b)) THEN
        RAISE EXCEPTION '086 tests need companies A and B WITHOUT palpations (the import-date test counts them): use the schema-only copy.';
    END IF;

    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e1, v_a, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e1 AND id_company = v_a);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e1 AND id_company = v_a;
    UPDATE user_companies SET is_active = false WHERE email = v_e1 AND id_company = v_b;

    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e2, v_b, 'ADMIN', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e2 AND id_company = v_b);
    UPDATE user_companies SET is_active = true, role = 'ADMIN' WHERE email = v_e2 AND id_company = v_b;
    UPDATE user_companies SET is_active = false WHERE email = v_e2 AND id_company = v_a;

    -- a clean slate for the two companies' mapping and empadre config (filtered by company; rolled back with the rest)
    DELETE FROM repro_condition_codes WHERE id_company IN (v_a, v_b);
    DELETE FROM repro_empadre_config WHERE id_company IN (v_a, v_b);

    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

CREATE FUNCTION pg_temp.setrole(p_email text, p_company text, p_role text) RETURNS void
LANGUAGE sql AS $$ UPDATE user_companies SET role = p_role WHERE email = p_email AND id_company = p_company::integer $$;

-- Fixtures ------------------------------------------------------------------------------------------------

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_key text, p_fuego text, p_cat text, p_status text) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego)
    VALUES (p_tenant, 'T086-' || p_key, 'CRIA', p_cat, p_status, p_fuego)
    RETURNING id
$$;

-- a palpation written directly (a fixture of a palpation that exists already); p_style = 'en' | 'es'
CREATE FUNCTION pg_temp.pal(p_id uuid, p_days_ago integer, p_style text, p_result text, p_gest text DEFAULT NULL, p_cond text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
    VALUES (p_id, 'PALPACION', 'T086 fixture',
            CASE WHEN p_style = 'en'
                 THEN jsonb_strip_nulls(jsonb_build_object('result', p_result, 'gestation_days', p_gest))
                 ELSE jsonb_strip_nulls(jsonb_build_object('resultado', p_result, 'dias_gestacion', p_gest, 'condicion_utero', p_cond)) END,
            fn_repro_today()::timestamp - make_interval(days => p_days_ago))
$$;

DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_b integer := pg_temp.cx('B')::integer;
    v_id uuid;
    v_k text;
BEGIN
    -- company A: animals the wrapper will palpate
    FOREACH v_k IN ARRAY ARRAY['V1', 'V2', 'V3', 'V4', 'V5', 'V6', 'V7', 'V8', 'V9', 'V10', 'P1', 'P2', 'P3', 'P4', 'P5'] LOOP
        v_id := pg_temp.mk(v_a, 'A-' || v_k, NULL, 'VACA', 'ACTIVO');
        INSERT INTO t_ctx VALUES (v_k, v_id::text);
    END LOOP;
    v_id := pg_temp.mk(v_a, 'A-DUP1', 'T086DUP', 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('dup1', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-DUP2', 'T086DUP', 'VACA', 'ACTIVO');  INSERT INTO t_ctx VALUES ('dup2', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-SOLD', NULL, 'VACA', 'VENDIDO');       INSERT INTO t_ctx VALUES ('sold', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-ED', NULL, 'VACA', 'ACTIVO');          INSERT INTO t_ctx VALUES ('ed', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-RET', NULL, 'VACA', 'ACTIVO');         INSERT INTO t_ctx VALUES ('ret', v_id::text);
    v_id := pg_temp.mk(v_a, 'A-OLD', NULL, 'VACA', 'ACTIVO');         INSERT INTO t_ctx VALUES ('old', v_id::text);
    -- a health log that is NOT a palpation (for the tenant-guard test)
    v_id := pg_temp.mk(v_a, 'A-VAX', NULL, 'VACA', 'ACTIVO');         INSERT INTO t_ctx VALUES ('vax', v_id::text);
    -- company B
    v_id := pg_temp.mk(v_b, 'B-V1', NULL, 'VACA', 'ACTIVO');          INSERT INTO t_ctx VALUES ('bv1', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-V2', NULL, 'VACA', 'ACTIVO');          INSERT INTO t_ctx VALUES ('bv2', v_id::text);
    v_id := pg_temp.mk(v_b, 'B-P1', NULL, 'VACA', 'PREÑADA');         INSERT INTO t_ctx VALUES ('bp1', v_id::text);
END $$;

-- =============================================================================================================
-- PART A. parser unit tests
-- =============================================================================================================

-- the confirmed mapping of company 5, replicated for company A inside the transaction
INSERT INTO repro_condition_codes (id_company, code, repro_condition, source, confirmed_by, confirmed_at) VALUES
    (pg_temp.cx('A')::integer, 'UNE',   'ESTATICA', 'T086', 'T086', now()),
    (pg_temp.cx('A')::integer, 'UTCL1', 'CICLANDO', 'T086', 'T086', now()),
    (pg_temp.cx('A')::integer, 'UTCL2', 'CICLANDO', 'T086', 'T086', now()),
    (pg_temp.cx('A')::integer, 'UTCL3', 'CICLANDO', 'T086', 'T086', now());

SELECT pg_temp.ok('A UNE -> ESTATICA (MAPPED)',            pg_temp.pc('UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED', pg_temp.pc('UNE', pg_temp.cx('A')));
SELECT pg_temp.ok('A UTCL1 / UTCL2 / UTCL3 -> CICLANDO (MAPPED)',
    pg_temp.pc('UTCL1', pg_temp.cx('A')) = 'UTCL1||CICLANDO|MAPPED' AND pg_temp.pc('UTCL2', pg_temp.cx('A')) = 'UTCL2||CICLANDO|MAPPED'
    AND pg_temp.pc('UTCL3', pg_temp.cx('A')) = 'UTCL3||CICLANDO|MAPPED');
SELECT pg_temp.ok('A UNE/NR -> condition NULL, UNMAPPED, raw kept (NR is not confirmed)',
    pg_temp.pc('UNE/NR', pg_temp.cx('A')) = 'UNE/NR|||UNMAPPED', pg_temp.pc('UNE/NR', pg_temp.cx('A')));
SELECT pg_temp.ok('A UTCL2/OI -> CICLANDO with ovary_side OI, raw UTCL2/OI',
    pg_temp.pc('UTCL2/OI', pg_temp.cx('A')) = 'UTCL2/OI|OI|CICLANDO|MAPPED', pg_temp.pc('UTCL2/OI', pg_temp.cx('A')));
SELECT pg_temp.ok('A UNE/OD and OI/UNE: the ovary token may come first or last',
    pg_temp.pc('UNE/OD', pg_temp.cx('A')) = 'UNE/OD|OD|ESTATICA|MAPPED' AND pg_temp.pc('OI/UNE', pg_temp.cx('A')) = 'OI/UNE|OI|ESTATICA|MAPPED');
SELECT pg_temp.ok('A leading result word is skipped, any accent / case / separator: VACIA UNE, VACÍA UTCL2/OI, vacía/une, PREÑADA UNE',
    pg_temp.pc('VACIA UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED'
    AND pg_temp.pc('VACÍA UTCL2/OI', pg_temp.cx('A')) = 'UTCL2/OI|OI|CICLANDO|MAPPED'
    AND pg_temp.pc('vacía/une', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED'
    AND pg_temp.pc('  Vacia   /  UNE ', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED'
    AND pg_temp.pc('PREÑADA UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED');
SELECT pg_temp.ok('A the leading word is only skipped as a WORD: VACIAS is a code, not VACIA + S',
    pg_temp.pc('VACIAS', pg_temp.cx('A')) = 'VACIAS|||UNMAPPED');
SELECT pg_temp.ok('A unconfirmed codes stay UNMAPPED with the raw value normalised: No apto, Matriz ocupada, RP, UTC2, NR',
    pg_temp.pc('No apto', pg_temp.cx('A')) = 'NO APTO|||UNMAPPED' AND pg_temp.pc('Matriz ocupada', pg_temp.cx('A')) = 'MATRIZ OCUPADA|||UNMAPPED'
    AND pg_temp.pc('RP', pg_temp.cx('A')) = 'RP|||UNMAPPED' AND pg_temp.pc('UTC2', pg_temp.cx('A')) = 'UTC2|||UNMAPPED'
    AND pg_temp.pc('NR', pg_temp.cx('A')) = 'NR|||UNMAPPED' AND pg_temp.pc('VACÍA No apto', pg_temp.cx('A')) = 'NO APTO|||UNMAPPED');
SELECT pg_temp.ok('A N/A, empty, blank, NULL and a lone result word -> NOT_APPLICABLE with no raw code',
    pg_temp.pc('N/A', pg_temp.cx('A')) = '|||NOT_APPLICABLE' AND pg_temp.pc('n/a', pg_temp.cx('A')) = '|||NOT_APPLICABLE'
    AND pg_temp.pc('VACIA N/A', pg_temp.cx('A')) = '|||NOT_APPLICABLE'
    AND pg_temp.pc('', pg_temp.cx('A')) = '|||NOT_APPLICABLE' AND pg_temp.pc('   ', pg_temp.cx('A')) = '|||NOT_APPLICABLE'
    AND pg_temp.pc(NULL, pg_temp.cx('A')) = '|||NOT_APPLICABLE'
    AND pg_temp.pc('VACIA', pg_temp.cx('A')) = '|||NOT_APPLICABLE' AND pg_temp.pc('VACÍA /', pg_temp.cx('A')) = '|||NOT_APPLICABLE');
SELECT pg_temp.ok('A explicit free words map directly (EXPLICIT) in any case / accent: ciclando, CICLANDO, estática, estatica, ESTÁTICA',
    pg_temp.pc('ciclando', pg_temp.cx('A')) = 'CICLANDO||CICLANDO|EXPLICIT' AND pg_temp.pc('CICLANDO', pg_temp.cx('A')) = 'CICLANDO||CICLANDO|EXPLICIT'
    AND pg_temp.pc('estática', pg_temp.cx('A')) = 'ESTATICA||ESTATICA|EXPLICIT' AND pg_temp.pc('estatica', pg_temp.cx('A')) = 'ESTATICA||ESTATICA|EXPLICIT'
    AND pg_temp.pc('ESTÁTICA', pg_temp.cx('A')) = 'ESTATICA||ESTATICA|EXPLICIT');
SELECT pg_temp.ok('A explicit words after a result word and with an ovary side: VACÍA CICLANDO, VACIA ESTÁTICA, ciclando/OD',
    pg_temp.pc('VACÍA CICLANDO', pg_temp.cx('A')) = 'CICLANDO||CICLANDO|EXPLICIT'
    AND pg_temp.pc('VACIA ESTÁTICA', pg_temp.cx('A')) = 'ESTATICA||ESTATICA|EXPLICIT'
    AND pg_temp.pc('ciclando/OD', pg_temp.cx('A')) = 'CICLANDO/OD|OD|CICLANDO|EXPLICIT');
SELECT pg_temp.ok('A an explicit word next to an unknown token makes the whole value UNMAPPED (ciclando/NR)',
    pg_temp.pc('ciclando/NR', pg_temp.cx('A')) = 'CICLANDO/NR|||UNMAPPED');
SELECT pg_temp.ok('A the ovary side may be written with a blank: UTCL1 OD, OI UNE',
    pg_temp.pc('UTCL1 OD', pg_temp.cx('A')) = 'UTCL1/OD|OD|CICLANDO|MAPPED' AND pg_temp.pc('OI UNE', pg_temp.cx('A')) = 'UNE/OI|OI|ESTATICA|MAPPED');
SELECT pg_temp.ok('A several known tokens with ONE condition map (UTCL1/UTCL2); with conflicting conditions the value is UNMAPPED (UNE/UTCL1)',
    pg_temp.pc('UTCL1/UTCL2', pg_temp.cx('A')) = 'UTCL1/UTCL2||CICLANDO|MAPPED' AND pg_temp.pc('UNE/UTCL1', pg_temp.cx('A')) = 'UNE/UTCL1|||UNMAPPED');
SELECT pg_temp.ok('A both ovaries -> ovary_side NULL; only an ovary -> NOT_APPLICABLE with the side',
    pg_temp.pc('UNE/OI/OD', pg_temp.cx('A')) = 'UNE/OI/OD||ESTATICA|MAPPED' AND pg_temp.pc('OI', pg_temp.cx('A')) = 'OI|OI||NOT_APPLICABLE');
SELECT pg_temp.ok('A without a company there is no lookup (UNE UNMAPPED) but explicit words still work',
    pg_temp.pc('UNE', NULL) = 'UNE|||UNMAPPED' AND pg_temp.pc('estatica', NULL) = 'ESTATICA||ESTATICA|EXPLICIT');
SELECT pg_temp.ok('A ISOLATION of the mapping: company B has no mapping for UNE, and B''s own mapping does not change A',
    pg_temp.pc('UNE', pg_temp.cx('B')) = 'UNE|||UNMAPPED' AND pg_temp.pc('UTCL2/OI', pg_temp.cx('B')) = 'UTCL2/OI|OI||UNMAPPED'
    AND pg_temp.pc('UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED');
INSERT INTO repro_condition_codes (id_company, code, repro_condition, source, confirmed_by, confirmed_at)
VALUES (pg_temp.cx('B')::integer, 'UNE', 'OTRO', 'T086', 'T086', now());
SELECT pg_temp.ok('A the same code means different things in different companies (B: UNE -> OTRO, A: UNE -> ESTATICA)',
    pg_temp.pc('UNE', pg_temp.cx('B')) = 'UNE||OTRO|MAPPED' AND pg_temp.pc('UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED');
DELETE FROM repro_condition_codes WHERE id_company = pg_temp.cx('B')::integer;
SELECT pg_temp.ok('A the parser never raises: huge, binary, odd and empty-token inputs',
    pg_temp.no_error(format('SELECT * FROM fn_parse_uterine_code(%L, %L)', repeat('/', 5000), pg_temp.cx('A')))
    AND pg_temp.no_error(format('SELECT * FROM fn_parse_uterine_code(%L, %L)', repeat('UNE/', 3000), pg_temp.cx('A')))
    AND pg_temp.no_error(format('SELECT * FROM fn_parse_uterine_code(%L, %L)', E'ç\u0001  \t\n/ // /OI', pg_temp.cx('A')))
    AND pg_temp.no_error('SELECT * FROM fn_parse_uterine_code(NULL, NULL)')
    AND pg_temp.no_error('SELECT * FROM fn_parse_uterine_code(''a/b/c/'', 999999)')
    AND pg_temp.pc('/', pg_temp.cx('A')) = '|||NOT_APPLICABLE');
SELECT pg_temp.ok('A the normaliser is accent- and case-insensitive without extensions',
    fn_repro_norm_code(' ñandú  Áéíóú ') = 'NANDU AEIOU' AND fn_repro_norm_code('') IS NULL AND fn_repro_norm_code(NULL) IS NULL);

-- =============================================================================================================
-- PART B. sp_repro_condition_code_set
-- =============================================================================================================

SELECT pg_temp.call('b1', format('SELECT sp_repro_condition_code_set(%L, %L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), '  utcl9 ', 'otro', 'vet visit'));
SELECT pg_temp.ok('B an ADMIN creates a mapping; the code is normalised (UTCL9) and the condition upper-cased',
    pg_temp.rs('b1')->>'status' = 'created' AND pg_temp.rs('b1')->>'code' = 'UTCL9' AND pg_temp.rs('b1')->>'repro_condition' = 'OTRO'
    AND (SELECT confirmed_by = lower(pg_temp.cx('u1')) AND source = 'vet visit' FROM repro_condition_codes
          WHERE id_company = pg_temp.cx('A')::integer AND code = 'UTCL9'));
SELECT pg_temp.call('b2', format('SELECT sp_repro_condition_code_set(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'UTCL9', 'CICLANDO'));
SELECT pg_temp.ok('B re-confirming updates in place and reports the previous condition',
    pg_temp.rs('b2')->>'status' = 'updated' AND pg_temp.rs('b2')->>'previous_condition' = 'OTRO'
    AND pg_temp.n_codes(pg_temp.cx('A')) = 5
    AND pg_temp.pc('UTCL9', pg_temp.cx('A')) = 'UTCL9||CICLANDO|MAPPED');
SELECT pg_temp.ok('B validation: bad condition, empty code, slash, 41 characters and reserved words are refused with nothing written',
    sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'X1', 'MAYBE')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), '  ', 'OTRO')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'A/B', 'OTRO')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), repeat('X', 41), 'OTRO')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'OI', 'OTRO')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'vacía', 'OTRO')->>'status' = 'invalid'
    AND sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'Estática', 'OTRO')->>'status' = 'invalid'
    AND pg_temp.n_codes(pg_temp.cx('A')) = 5);
SELECT pg_temp.ok('B the table rejects a code that is not normalised (direct INSERT)',
    pg_temp.raises(format('INSERT INTO repro_condition_codes (id_company, code, repro_condition, source, confirmed_by) VALUES (%L, ''utcl7'', ''OTRO'', ''x'', ''x'')', pg_temp.cx('A')), '23514')
    AND pg_temp.raises(format('INSERT INTO repro_condition_codes (id_company, code, repro_condition, source, confirmed_by) VALUES (%L, ''UTCL7'', ''MAYBE'', ''x'', ''x'')', pg_temp.cx('A')), '23514'));

SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.ok('B a non-ADMIN member (EDITOR) is forbidden and nothing is written',
    sp_repro_condition_code_set(pg_temp.cx('A'), pg_temp.cx('u1'), 'UTCL8', 'OTRO')->>'status' = 'forbidden'
    AND pg_temp.n_codes(pg_temp.cx('A')) = 5);
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');

SELECT pg_temp.ok('B ISOLATION: user 1 (not a member of B) gets an ERROR for B and a stranger an ERROR for A; B has no rows',
    pg_temp.raises(format('SELECT sp_repro_condition_code_set(%L, %L, ''ZZ'', ''OTRO'')', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_condition_code_set(%L, %L, ''ZZ'', ''OTRO'')', pg_temp.cx('A'), 'nadie@example.test'), 'P0001')
    AND pg_temp.n_codes(pg_temp.cx('B')) = 0);
SELECT pg_temp.call('b3', format('SELECT sp_repro_condition_code_set(%L, %L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u2'), 'UNE', 'OTRO'));
SELECT pg_temp.ok('B company B''s ADMIN writes only company B''s row; A''s UNE is unchanged',
    pg_temp.rs('b3')->>'status' = 'created' AND pg_temp.n_codes(pg_temp.cx('B')) = 1
    AND pg_temp.pc('UNE', pg_temp.cx('A')) = 'UNE||ESTATICA|MAPPED' AND pg_temp.pc('UNE', pg_temp.cx('B')) = 'UNE||OTRO|MAPPED');
DELETE FROM repro_condition_codes WHERE id_company = pg_temp.cx('B')::integer;

-- =============================================================================================================
-- PART C. log_palpation_with_condition
-- =============================================================================================================

CREATE TEMP TABLE t_base ON COMMIT DROP AS
SELECT pg_temp.n_logs() AS logs, pg_temp.n_det() AS dets;
CREATE TEMP TABLE t_counts ON COMMIT DROP AS
SELECT (SELECT count(*) FROM birth_events) AS births, (SELECT count(*) FROM cattle_weight_logs) AS weights,
       (SELECT count(*) FROM repro_empadre_entries) AS entries;

SELECT pg_temp.plog('c1', $j$[
  {"identifier":"T086-A-V1","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-V2","raw_diagnosis":"VACIA UTCL2/OI"},
  {"identifier":"T086-A-V3","raw_diagnosis":"VACÍA UNE/NR"},
  {"identifier":"T086-A-P1","raw_diagnosis":"PREÑADA 02 MESES"},
  {"identifier":"T086-A-V4","raw_diagnosis":"ciclando"},
  {"identifier":"T086-A-V5","raw_diagnosis":"VACÍA RP"},
  {"identifier":"T086-A-P2","raw_diagnosis":"prenada 3 meses"},
  {"identifier":"T086-A-P3","raw_diagnosis":"PREÑADA 120 dias"},
  {"identifier":"T086-A-P4","raw_diagnosis":"PREÑADA 11 MESES"},
  {"identifier":"T086-A-V6","raw_diagnosis":"VACÍA N/A"}
]$j$, NULL, 'Dr. Prueba');

SELECT pg_temp.ok('C a batch is recorded: status, counts (4 pregnant, 6 empty), 3 with a condition, 2 UNMAPPED, unmapped codes returned',
    pg_temp.rs('c1')->>'status' = 'recorded' AND (pg_temp.rs('c1')->>'written')::int = 10
    AND (pg_temp.rs('c1')->>'pregnant')::int = 4 AND (pg_temp.rs('c1')->>'empty')::int = 6
    AND (pg_temp.rs('c1')->>'with_condition')::int = 3 AND (pg_temp.rs('c1')->>'unmapped')::int = 2
    AND (pg_temp.rs('c1')->'unmapped_codes') @> '["UNE/NR", "RP"]'::jsonb
    AND jsonb_array_length(pg_temp.rs('c1')->'results') = 10, pg_temp.rs('c1')::text);
SELECT pg_temp.ok('C the existing procedure ran for every item: PALPACION health logs with the English keys, status, description and notes unchanged in shape',
    (SELECT count(*) FROM cattle_health_logs) = (SELECT logs FROM t_base) + 10
    AND pg_temp.hl('A-V1')->'medicines_json'->>'result' = 'VACÍA'
    AND pg_temp.hl('A-V1')->>'description' LIKE 'Palpación: VACÍA%Dr. Prueba%Notas: VACÍA UNE'
    AND pg_temp.hl('A-P1')->'medicines_json'->>'gestation_days' = '60'
    AND pg_temp.status_of('A-V1') = 'VACÍA' AND pg_temp.status_of('A-P1') = 'PREÑADA',
    pg_temp.hl('A-V1')::text);
SELECT pg_temp.ok('C gestation: "02 MESES" = 60, "3 meses" lower case = 90, "120 dias" = 120, "11 MESES" out of range = NULL with a note but still PREÑADA',
    pg_temp.hl('A-P1')->'medicines_json'->>'gestation_days' = '60'
    AND pg_temp.hl('A-P2')->'medicines_json'->>'gestation_days' = '90'
    AND pg_temp.hl('A-P3')->'medicines_json'->>'gestation_days' = '120'
    AND pg_temp.hl('A-P4')->'medicines_json'->>'gestation_days' IS NULL
    AND pg_temp.status_of('A-P4') = 'PREÑADA'
    AND (SELECT e->>'gestation_note' FROM jsonb_array_elements(pg_temp.rs('c1')->'results') e WHERE e->>'identifier' = 'T086-A-P4') = 'MONTHS_OUT_OF_RANGE');
SELECT pg_temp.ok('C details written in the same call: one row per palpation, linked to the log the existing procedure returned, id_company = A',
    (SELECT count(*) FROM palpation_repro_details) = (SELECT dets FROM t_base) + 10
    AND NOT EXISTS (SELECT 1 FROM palpation_repro_details d
                     LEFT JOIN cattle_health_logs h ON h.id = d.health_log_id
                    WHERE d.id_company = pg_temp.cx('A')::integer AND h.id IS NULL)
    AND (SELECT bool_and(pg_temp.det(replace(e->>'identifier', 'T086-', ''))->>'health_log_id' = e->>'log_id'
                         AND pg_temp.det(replace(e->>'identifier', 'T086-', ''))->>'id_company' = pg_temp.cx('A'))
           FROM jsonb_array_elements(pg_temp.rs('c1')->'results') e));
SELECT pg_temp.ok('C VACÍA UNE -> raw UNE, ESTATICA, MAPPED;  VACIA UTCL2/OI -> raw UTCL2/OI, CICLANDO, side OI, MAPPED',
    pg_temp.det('A-V1')->>'raw_code' = 'UNE' AND pg_temp.det('A-V1')->>'repro_condition' = 'ESTATICA' AND pg_temp.det('A-V1')->>'mapping_status' = 'MAPPED'
    AND pg_temp.det('A-V2')->>'raw_code' = 'UTCL2/OI' AND pg_temp.det('A-V2')->>'repro_condition' = 'CICLANDO'
    AND pg_temp.det('A-V2')->>'ovary_side' = 'OI' AND pg_temp.det('A-V2')->>'mapping_status' = 'MAPPED');
SELECT pg_temp.ok('C VACÍA UNE/NR -> condition NULL, UNMAPPED;  VACÍA RP -> UNMAPPED;  ciclando -> EXPLICIT CICLANDO;  VACÍA N/A -> NOT_APPLICABLE',
    pg_temp.det('A-V3')->>'repro_condition' IS NULL AND pg_temp.det('A-V3')->>'mapping_status' = 'UNMAPPED' AND pg_temp.det('A-V3')->>'raw_code' = 'UNE/NR'
    AND pg_temp.det('A-V5')->>'repro_condition' IS NULL AND pg_temp.det('A-V5')->>'mapping_status' = 'UNMAPPED'
    AND pg_temp.det('A-V4')->>'repro_condition' = 'CICLANDO' AND pg_temp.det('A-V4')->>'mapping_status' = 'EXPLICIT'
    AND pg_temp.det('A-V6')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.det('A-V6')->>'raw_code' IS NULL);
SELECT pg_temp.ok('C a PREÑADA palpation has a details row with NO condition and mapping_status NOT_APPLICABLE',
    pg_temp.det('A-P1')->>'result' = 'PREÑADA' AND pg_temp.det('A-P1')->>'repro_condition' IS NULL
    AND pg_temp.det('A-P1')->>'mapping_status' = 'NOT_APPLICABLE' AND pg_temp.det('A-P1')->>'raw_code' IS NULL);

-- idempotent retry: the existing procedure answers duplicate_skipped for an identical palpation inside 5 minutes
CREATE TEMP TABLE t_base2 ON COMMIT DROP AS SELECT pg_temp.n_logs() AS logs, pg_temp.n_det() AS dets;
SELECT pg_temp.plog('c2', $j$[
  {"identifier":"T086-A-V1","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-P1","raw_diagnosis":"PREÑADA 02 MESES"}
]$j$, NULL, 'Dr. Prueba');
SELECT pg_temp.ok('C an identical retry is idempotent: duplicate_skipped for both, no new health log and no new details row',
    pg_temp.rs('c2')->>'status' = 'recorded' AND (pg_temp.rs('c2')->>'duplicate_skipped')::int = 2
    AND pg_temp.n_logs() = (SELECT logs FROM t_base2) AND pg_temp.n_det() = (SELECT dets FROM t_base2),
    pg_temp.rs('c2')::text);

-- all-or-nothing: one bad item rejects the whole batch with nothing written
CREATE TEMP TABLE t_base3 ON COMMIT DROP AS
SELECT pg_temp.n_logs() AS logs, pg_temp.n_det() AS dets, pg_temp.status_of('A-V7') AS v7, pg_temp.status_of('A-V8') AS v8;
SELECT pg_temp.plog('c3', $j$[
  {"identifier":"T086-A-V7","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-NO-EXISTE","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-V8","raw_diagnosis":"PREÑADA 2 MESES"}
]$j$);
SELECT pg_temp.ok('C ALL-OR-NOTHING: an unknown animal rejects the whole batch (written 0, issue ANIMAL_NOT_FOUND at index 2); nothing changed',
    pg_temp.rs('c3')->>'status' = 'rejected' AND (pg_temp.rs('c3')->>'written')::int = 0
    AND pg_temp.rs('c3')->'issues'->0->>'code' = 'ANIMAL_NOT_FOUND' AND (pg_temp.rs('c3')->'issues'->0->>'index')::int = 2
    AND pg_temp.n_logs() = (SELECT logs FROM t_base3) AND pg_temp.n_det() = (SELECT dets FROM t_base3)
    AND pg_temp.status_of('A-V7') = (SELECT v7 FROM t_base3) AND pg_temp.status_of('A-V8') = (SELECT v8 FROM t_base3),
    pg_temp.rs('c3')::text);
SELECT pg_temp.plog('c4', $j$[
  {"identifier":"T086DUP","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-SOLD","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-V7","raw_diagnosis":"VACÍA UNE"},
  {"identifier":"T086-A-V7","raw_diagnosis":"VACÍA UTCL1"},
  {"identifier":"T086-A-V8"},
  {"identifier":"","raw_diagnosis":"VACÍA UNE"},
  "T086-A-V9"
]$j$);
SELECT pg_temp.ok('C every problem is reported at once: ANIMAL_AMBIGUOUS with candidates, NOT_ACTIVE, DUPLICATE_IN_BATCH, ITEM_INCOMPLETE (x3); nothing written',
    pg_temp.rs('c4')->>'status' = 'rejected'
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('c4')->'issues') e WHERE e->>'code' = 'ANIMAL_AMBIGUOUS' AND jsonb_array_length(e->'candidates') = 2) = 1
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('c4')->'issues') e WHERE e->>'code' = 'NOT_ACTIVE') = 1
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('c4')->'issues') e WHERE e->>'code' = 'DUPLICATE_IN_BATCH') = 1
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('c4')->'issues') e WHERE e->>'code' = 'ITEM_INCOMPLETE') = 3
    AND pg_temp.n_logs() = (SELECT logs FROM t_base3) AND pg_temp.n_det() = (SELECT dets FROM t_base3),
    pg_temp.rs('c4')::text);
SELECT pg_temp.ok('C bad input is an answer, not an error: not JSON, not an array, empty array, 101 items, bad / future / too-old dates',
    sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), 'no json')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '{"a":1}')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '[]')->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), NULL)->>'code' = 'BAD_ITEMS'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'),
            (SELECT jsonb_agg(jsonb_build_object('identifier', 'x' || g, 'raw_diagnosis', 'VACÍA'))::text FROM generate_series(1, 101) g))->>'code' = 'TOO_MANY_ITEMS'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '[{"identifier":"T086-A-V7","raw_diagnosis":"VACÍA"}]', 'ayer')->>'code' = 'BAD_DATE'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '[{"identifier":"T086-A-V7","raw_diagnosis":"VACÍA"}]', to_char(fn_repro_today() + 1, 'YYYY-MM-DD'))->>'code' = 'BAD_DATE'
    AND sp_repro_log_palpation_batch(pg_temp.cx('A'), pg_temp.cx('u1'), '[{"identifier":"T086-A-V7","raw_diagnosis":"VACÍA"}]', to_char(fn_repro_today() - 400, 'YYYY-MM-DD'))->>'code' = 'BAD_DATE'
    AND pg_temp.n_logs() = (SELECT logs FROM t_base3) AND pg_temp.n_det() = (SELECT dets FROM t_base3));

SELECT pg_temp.plog('c5', '[{"identifier":"T086-A-V7","raw_diagnosis":"VACÍA UTCL1/OD"},{"identifier":"T086-A-V8","raw_diagnosis":"VACÍA UNE"}]',
                    to_char(fn_repro_today() - 3, 'YYYY-MM-DD'), 'Dr. Fecha');
SELECT pg_temp.ok('C a past date is the event_date of the palpation (and the technician is passed through)',
    pg_temp.rs('c5')->>'status' = 'recorded'
    AND (pg_temp.hl('A-V7')->>'event_date')::date = fn_repro_today() - 3
    AND pg_temp.hl('A-V7')->'medicines_json'->>'technician_name' = 'Dr. Fecha'
    AND pg_temp.det('A-V7')->>'repro_condition' = 'CICLANDO' AND pg_temp.det('A-V7')->>'ovary_side' = 'OD');

SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'EDITOR');
SELECT pg_temp.plog('c6', '[{"identifier":"T086-A-ED","raw_diagnosis":"VACÍA UNE"}]');
SELECT pg_temp.ok('C any active member may log (EDITOR), same as the existing palpation tools',
    pg_temp.rs('c6')->>'status' = 'recorded' AND pg_temp.det('A-ED')->>'repro_condition' = 'ESTATICA');
SELECT pg_temp.setrole(pg_temp.cx('u1'), pg_temp.cx('A'), 'ADMIN');

-- cross-company: user 1 (company A) tries to palpate company B's animals; user 2 logs for B
CREATE TEMP TABLE t_base4 ON COMMIT DROP AS
SELECT pg_temp.n_logs() AS logs, pg_temp.n_det() AS dets, pg_temp.status_of('B-V1') AS bv1;
SELECT pg_temp.plog('c7', '[{"identifier":"T086-B-V1","raw_diagnosis":"PREÑADA 2 MESES"}]');
SELECT pg_temp.ok('C ISOLATION: company A cannot palpate a company B animal by its identifier (ANIMAL_NOT_FOUND, nothing written, B''s status unchanged)',
    pg_temp.rs('c7')->>'status' = 'rejected' AND pg_temp.rs('c7')->'issues'->0->>'code' = 'ANIMAL_NOT_FOUND'
    AND pg_temp.n_logs() = (SELECT logs FROM t_base4) AND pg_temp.n_det() = (SELECT dets FROM t_base4)
    AND pg_temp.status_of('B-V1') = (SELECT bv1 FROM t_base4));
SELECT pg_temp.ok('C ISOLATION: user 1 calling with company B''s number gets an ERROR (not a member) and a stranger an ERROR',
    pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, ''[{"identifier":"T086-B-V1","raw_diagnosis":"VACÍA"}]'')', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, ''[{"identifier":"T086-B-V1","raw_diagnosis":"VACÍA"}]'')', pg_temp.cx('B'), 'nadie@example.test'), 'P0001')
    AND pg_temp.n_det() = (SELECT dets FROM t_base4));
SELECT pg_temp.plog('c8', '[{"identifier":"T086-B-V1","raw_diagnosis":"VACÍA UNE"},{"identifier":"T086-B-V2","raw_diagnosis":"VACÍA UTCL2"}]', NULL, NULL, 'u2', 'B');
SELECT pg_temp.ok('C ISOLATION of the mapping: company B logs the same codes and gets UNMAPPED (A''s mapping does not leak); the rows carry id_company B',
    pg_temp.rs('c8')->>'status' = 'recorded'
    AND pg_temp.det('B-V1')->>'mapping_status' = 'UNMAPPED' AND pg_temp.det('B-V1')->>'repro_condition' IS NULL
    AND pg_temp.det('B-V2')->>'mapping_status' = 'UNMAPPED'
    AND pg_temp.det('B-V1')->>'id_company' = pg_temp.cx('B') AND pg_temp.det('B-V2')->>'id_company' = pg_temp.cx('B')
    AND pg_temp.det('A-V1')->>'repro_condition' = 'ESTATICA');
SELECT pg_temp.ok('C the stored e-mail is the caller''s and the details never name another company',
    (SELECT bool_and(lower(d.registered_by_email) = lower(pg_temp.cx('u1'))) FROM palpation_repro_details d WHERE d.id_company = pg_temp.cx('A')::integer)
    AND (SELECT bool_and(lower(d.registered_by_email) = lower(pg_temp.cx('u2'))) FROM palpation_repro_details d WHERE d.id_company = pg_temp.cx('B')::integer));

-- =============================================================================================================
-- PART D. the side table: append-only, tenant guard, constraints; the existing procedure and tools are untouched
-- =============================================================================================================

SELECT pg_temp.ok('D append-only: UPDATE, DELETE and TRUNCATE of palpation_repro_details raise P0095',
    pg_temp.raises('UPDATE palpation_repro_details SET raw_code = ''X''', 'P0095')
    AND pg_temp.raises('DELETE FROM palpation_repro_details', 'P0095')
    AND pg_temp.raises('TRUNCATE palpation_repro_details', 'P0095'));
INSERT INTO cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
VALUES (pg_temp.cx('vax')::uuid, 'VACUNACION', 'T086 fixture', '{}'::jsonb, now()),
       (pg_temp.cx('V9')::uuid, 'PALPACION', 'T086 fixture guard', '{"result":"VACÍA"}'::jsonb, now());
SELECT pg_temp.ok('D tenant guard: company B cannot attach a details row to company A''s palpation (P0096); a non-palpation log cannot have details (P0096); the animal must match the log (P0096)',
    pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, mapping_status, registered_by_email)
                           SELECT %L, h.id, h.livestock_id, ''VACÍA'', ''NOT_APPLICABLE'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('B')), 'P0096')
    AND pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, mapping_status, registered_by_email)
                               SELECT %L, h.id, h.livestock_id, ''VACÍA'', ''NOT_APPLICABLE'', ''x'' FROM cattle_health_logs h WHERE h.event_type = ''VACUNACION'' AND h.description = ''T086 fixture''', pg_temp.cx('A')), 'P0096')
    AND pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, mapping_status, registered_by_email)
                               SELECT %L, h.id, %L, ''VACÍA'', ''NOT_APPLICABLE'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('A'), pg_temp.cx('V1')::uuid), 'P0096'));
SELECT pg_temp.ok('D a condition is only allowed on a VACÍA result (CHECK): PREÑADA + CICLANDO is refused',
    pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, repro_condition, mapping_status, registered_by_email)
                           SELECT %L, h.id, h.livestock_id, ''PREÑADA'', ''CICLANDO'', ''MAPPED'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('A')), '23514'));
SELECT pg_temp.ok('D mapping_status and condition must agree (CHECK): MAPPED without a condition and UNMAPPED with one are refused; so are bad values',
    pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, mapping_status, registered_by_email)
                           SELECT %L, h.id, h.livestock_id, ''VACÍA'', ''MAPPED'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('A')), '23514')
    AND pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, repro_condition, mapping_status, registered_by_email)
                              SELECT %L, h.id, h.livestock_id, ''VACÍA'', ''OTRO'', ''UNMAPPED'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('A')), '23514')
    AND pg_temp.raises(format('INSERT INTO palpation_repro_details (id_company, health_log_id, livestock_id, result, ovary_side, mapping_status, registered_by_email)
                              SELECT %L, h.id, h.livestock_id, ''VACÍA'', ''XX'', ''NOT_APPLICABLE'', ''x'' FROM cattle_health_logs h WHERE h.description = ''T086 fixture guard''', pg_temp.cx('A')), '23514'));
SELECT pg_temp.ok('D the existing procedure still works on its own and writes NO details (the old tools are unchanged)',
    (SELECT count(*) FROM palpation_repro_details) = (SELECT dets FROM t_base4) + 2
    AND (sp_log_palpation_event(pg_temp.cx('A')::integer, pg_temp.cx('u1'), 'T086-A-RET', 'VACÍA', NULL, NULL, 'VACÍA UNE', NULL)->>'success')::boolean
    AND pg_temp.n_det() = (SELECT dets FROM t_base4) + 2);
SELECT pg_temp.ok('D sp_log_palpation_event does not mention the new objects (it was not modified)',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_log_palpation_event'
        AND (prosrc ILIKE '%palpation_repro%' OR prosrc ILIKE '%uterine%' OR prosrc ILIKE '%repro_condition%')) = 0);

-- =============================================================================================================
-- PART E. list_palpation_due
-- =============================================================================================================

DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_b integer := pg_temp.cx('B')::integer;
    v_id uuid;
BEGIN
    v_id := pg_temp.mk(v_a, 'A-D1', NULL, 'VACA', 'PREÑADA');     INSERT INTO t_ctx VALUES ('d1', v_id::text);    -- 120 days, English keys
    PERFORM pg_temp.pal(v_id, 120, 'en', 'PREÑADA', '100');
    v_id := pg_temp.mk(v_a, 'A-D2', NULL, 'VACA', 'PREÑADA');     INSERT INTO t_ctx VALUES ('d2', v_id::text);    -- 30 days: not due
    PERFORM pg_temp.pal(v_id, 30, 'en', 'PREÑADA', '100');
    v_id := pg_temp.mk(v_a, 'A-D3', NULL, 'NOVILLONA', 'ACTIVO'); INSERT INTO t_ctx VALUES ('d3', v_id::text);    -- empadre, never palpated
    v_id := pg_temp.mk(v_a, 'A-D4', NULL, 'VACA', 'PREÑADA');     INSERT INTO t_ctx VALUES ('d4', v_id::text);    -- 200 days, Spanish keys, no accent
    PERFORM pg_temp.pal(v_id, 200, 'es', 'PRENADA', '90');
    v_id := pg_temp.mk(v_a, 'A-D5', NULL, 'NOVILLONA', 'ACTIVO'); INSERT INTO t_ctx VALUES ('d5', v_id::text);    -- empadre, palpated 100 days ago (VACIA)
    PERFORM pg_temp.pal(v_id, 100, 'en', 'VACIA');
    v_id := pg_temp.mk(v_a, 'A-D6', NULL, 'VACA', 'VACÍA');       INSERT INTO t_ctx VALUES ('d6', v_id::text);    -- open cow, old palpation, NOT in empadre
    PERFORM pg_temp.pal(v_id, 300, 'es', 'VACIA');
    v_id := pg_temp.mk(v_a, 'A-D7', NULL, 'VACA', 'VENDIDO');     INSERT INTO t_ctx VALUES ('d7', v_id::text);    -- sold
    PERFORM pg_temp.pal(v_id, 300, 'en', 'PREÑADA', '100');
    v_id := pg_temp.mk(v_a, 'A-D8', NULL, 'NOVILLONA', 'ACTIVO'); INSERT INTO t_ctx VALUES ('d8', v_id::text);    -- empadre entry that gets VOIDED
    v_id := pg_temp.mk(v_a, 'A-D9', NULL, 'NOVILLONA', 'ACTIVO'); INSERT INTO t_ctx VALUES ('d9', v_id::text);    -- empadre first, PREÑADA afterwards; palpated before the entry
    PERFORM pg_temp.pal(v_id, 150, 'en', 'PREÑADA', '100');
    v_id := pg_temp.mk(v_b, 'B-D1', NULL, 'VACA', 'PREÑADA');     INSERT INTO t_ctx VALUES ('bd1', v_id::text);   -- company B
    PERFORM pg_temp.pal(v_id, 150, 'en', 'PREÑADA', '100');
END $$;

SELECT pg_temp.call('e1', format('SELECT sp_repro_log_empadre_entry(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T086-A-D3'));
SELECT pg_temp.call('e2', format('SELECT sp_repro_log_empadre_entry(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T086-A-D5'));
SELECT pg_temp.call('e3', format('SELECT sp_repro_log_empadre_entry(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T086-A-D8'));
SELECT pg_temp.call('e4', format('SELECT sp_repro_log_empadre_entry(%L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'T086-A-D9'));
UPDATE cattle_livestock SET current_status = 'PREÑADA' WHERE id = pg_temp.cx('d9')::uuid;
SELECT pg_temp.call('e5', format('SELECT sp_void_empadre_entry(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), pg_temp.rs('e3')->>'entry_id', 'T086 void'));
SELECT pg_temp.ok('E fixtures: four empadre entries recorded and one voided',
    pg_temp.rs('e1')->>'status' = 'recorded' AND pg_temp.rs('e2')->>'status' = 'recorded' AND pg_temp.rs('e4')->>'status' = 'recorded'
    AND pg_temp.rs('e5')->>'status' = 'voided', pg_temp.rs('e5')::text);

SELECT pg_temp.ok('E default 90 days: lists a PREÑADA cow palpated 120 days ago (English keys) with days_since_last_palpation',
    (SELECT (c->'row'->>'days_since_last_palpation')::int = 120 AND c->'row'->>'last_palpation_result' = 'PREÑADA'
            AND c->'row'->>'reason' = 'PREÑADA' AND (c->'row'->>'gestation_days_at_palpation')::int = 100
       FROM (SELECT pg_temp.due('d1') AS c) x));
SELECT pg_temp.ok('E a palpation 30 days ago is not due',
    pg_temp.due('d2') IS NULL);
SELECT pg_temp.ok('E the Spanish key set and the accent-less spelling are read: resultado PRENADA + dias_gestacion 90, 200 days ago',
    (SELECT (c->'row'->>'days_since_last_palpation')::int = 200 AND c->'row'->>'last_palpation_result' = 'PREÑADA'
            AND (c->'row'->>'gestation_days_at_palpation')::int = 90
       FROM (SELECT pg_temp.due('d4') AS c) x));
SELECT pg_temp.ok('E a heifer in empadre that was never palpated is due (never_palpated, empadre_entry_date shown)',
    (SELECT (c->'row'->>'never_palpated')::boolean AND c->'row'->>'reason' = 'EMPADRE' AND c->'row'->>'last_palpation_date' IS NULL
            AND c->'row'->>'empadre_entry_date' IS NOT NULL
       FROM (SELECT pg_temp.due('d3') AS c) x));
SELECT pg_temp.ok('E a heifer in empadre palpated 100 days ago (VACIA, English key) is due; a PREÑADA cow in empadre says PREÑADA_Y_EMPADRE and palpated_after_empadre_entry = false',
    (SELECT (c->'row'->>'days_since_last_palpation')::int = 100 AND c->'row'->>'last_palpation_result' = 'VACÍA' AND c->'row'->>'reason' = 'EMPADRE'
       FROM (SELECT pg_temp.due('d5') AS c) x)
    AND (SELECT c->'row'->>'reason' = 'PREÑADA_Y_EMPADRE' AND NOT (c->'row'->>'palpated_after_empadre_entry')::boolean
       FROM (SELECT pg_temp.due('d9') AS c) x));
SELECT pg_temp.ok('E NOT listed: an open cow outside empadre, a sold PREÑADA cow, a VOIDED empadre entry, and company B''s PREÑADA cow',
    pg_temp.due('d6') IS NULL AND pg_temp.due('d7') IS NULL AND pg_temp.due('d8') IS NULL AND pg_temp.due('bd1') IS NULL);
SELECT pg_temp.ok('E order: never palpated first, then the oldest palpation first (d3 < d4 (200) < d9 (150) < d1 (120) < d5 (100))',
    (SELECT (pg_temp.due('d3')->>'pos')::int < (pg_temp.due('d4')->>'pos')::int
        AND (pg_temp.due('d4')->>'pos')::int < (pg_temp.due('d9')->>'pos')::int
        AND (pg_temp.due('d9')->>'pos')::int < (pg_temp.due('d1')->>'pos')::int
        AND (pg_temp.due('d1')->>'pos')::int < (pg_temp.due('d5')->>'pos')::int));
SELECT pg_temp.ok('E days is configurable between 90 and 120: 110 hides the 100-day palpation and keeps the 120-day one; 89 / 121 / abc are refused',
    pg_temp.due('d5', '110') IS NULL AND pg_temp.due('d1', '110') IS NOT NULL AND pg_temp.due('d1', '120') IS NULL AND pg_temp.due('d9', '120') IS NOT NULL
    AND sp_repro_list_palpation_due(pg_temp.cx('A'), pg_temp.cx('u1'), '89')->>'status' = 'invalid'
    AND sp_repro_list_palpation_due(pg_temp.cx('A'), pg_temp.cx('u1'), '121')->>'status' = 'invalid'
    AND sp_repro_list_palpation_due(pg_temp.cx('A'), pg_temp.cx('u1'), 'abc')->>'status' = 'invalid');

-- stale_import_date: B has few palpations (flag false); A gets 40 palpations that share one date (flag true)
SELECT pg_temp.ok('E stale_import_date is false for a company with few palpations (B), even if two share a date',
    sp_repro_list_palpation_due(pg_temp.cx('B'), pg_temp.cx('u2'))->'stale_import_date'->>'flag' = 'false');
DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_id uuid;
    v_g integer;
BEGIN
    FOR v_g IN 1..40 LOOP
        v_id := pg_temp.mk(v_a, 'A-IMP' || v_g, NULL, 'VACA', 'PREÑADA');
        PERFORM pg_temp.pal(v_id, 300, 'es', 'PREÑADA', '100', CASE WHEN v_g % 2 = 0 THEN 'UNE/NR' ELSE 'UTCL1' END);
        IF v_g = 1 THEN INSERT INTO t_ctx VALUES ('imp1', v_id::text); END IF;
    END LOOP;
END $$;
SELECT pg_temp.ok('E stale_import_date: the most common date covers more than 50% of A''s palpations -> flag true with the date, share and total; the rows carry date_is_stale_import',
    (SELECT r->'stale_import_date'->>'flag' = 'true' AND (r->'stale_import_date'->>'date')::date = fn_repro_today() - 300
            AND (r->'stale_import_date'->>'share_pct')::numeric > 50 AND (r->'stale_import_date'->>'palpations_total')::int >= 40
       FROM (SELECT sp_repro_list_palpation_due(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) x)
    AND (pg_temp.due('imp1')->'row'->>'date_is_stale_import')::boolean
    AND NOT (pg_temp.due('d1')->'row'->>'date_is_stale_import')::boolean);
SELECT pg_temp.ok('E ISOLATION: B lists its own PREÑADA cow only; user 1 gets an ERROR for B; the import-date flag of A does not leak to B',
    (SELECT c->'row'->>'last_palpation_result' = 'PREÑADA' FROM (SELECT pg_temp.due('bd1', NULL, 'B', 'u2') AS c) x)
    AND pg_temp.due('d1', NULL, 'B', 'u2') IS NULL AND pg_temp.due('imp1', NULL, 'B', 'u2') IS NULL
    AND sp_repro_list_palpation_due(pg_temp.cx('B'), pg_temp.cx('u2'))->'stale_import_date'->>'flag' = 'false'
    AND pg_temp.raises(format('SELECT sp_repro_list_palpation_due(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));
SELECT pg_temp.ok('E fn_repro_palpations is scoped by company: A''s function never returns B''s palpations and vice versa',
    NOT EXISTS (SELECT 1 FROM fn_repro_palpations(pg_temp.cx('A')::integer) p WHERE p.livestock_id = pg_temp.cx('bd1')::uuid)
    AND NOT EXISTS (SELECT 1 FROM fn_repro_palpations(pg_temp.cx('B')::integer) p WHERE p.livestock_id = pg_temp.cx('d1')::uuid)
    AND EXISTS (SELECT 1 FROM fn_repro_palpations(pg_temp.cx('B')::integer) p WHERE p.livestock_id = pg_temp.cx('bd1')::uuid));

-- =============================================================================================================
-- PART F. list_upcoming_calvings
-- =============================================================================================================

DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_b integer := pg_temp.cx('B')::integer;
    v_id uuid;
BEGIN
    v_id := pg_temp.mk(v_a, 'A-C1', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_up', v_id::text);       -- est = today + 20 (palpation)
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '163');
    v_id := pg_temp.mk(v_a, 'A-C2', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_far', v_id::text);      -- est = today + 120
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '63');
    v_id := pg_temp.mk(v_a, 'A-C3', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_over', v_id::text);     -- est = today - 10 (overdue)
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '193');
    v_id := pg_temp.mk(v_a, 'A-C4', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_stale', v_id::text);    -- est = today - 100 (stale data)
    PERFORM pg_temp.pal(v_id, 300, 'en', 'PREÑADA', '83');
    v_id := pg_temp.mk(v_a, 'A-C5', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_svc', v_id::text);      -- no palpation: service 263 days ago => today + 20
    INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method) VALUES (v_id, v_a, fn_repro_today() - 263, 'MONTA_NATURAL');
    v_id := pg_temp.mk(v_a, 'A-C6', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_span', v_id::text);     -- Spanish keys, no accent, gestation as text
    PERFORM pg_temp.pal(v_id, 100, 'es', 'PRENADA', '163');
    v_id := pg_temp.mk(v_a, 'A-C7', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_conf', v_id::text);     -- PREÑADA then a newer VACÍA: status conflict
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '163');
    PERFORM pg_temp.pal(v_id, 10, 'en', 'VACÍA');
    v_id := pg_temp.mk(v_a, 'A-C8', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_none', v_id::text);     -- nothing to estimate from
    v_id := pg_temp.mk(v_a, 'A-C9', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_void', v_id::text);     -- only a VOIDED service
    INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method) VALUES (v_id, v_a, fn_repro_today() - 263, 'MONTA_NATURAL');
    INSERT INTO event_voids (tenant_id, event_table, event_id, voided_by_email, voided_reason)
    SELECT v_a, 'cattle_breeding_events', be.id, 'T086', 'T086 fixture' FROM cattle_breeding_events be WHERE be.livestock_id = v_id;
    v_id := pg_temp.mk(v_a, 'A-C10', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_nogest', v_id::text);  -- palpation without gestation days + service => SERVICIO
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA');
    INSERT INTO cattle_breeding_events (livestock_id, tenant_id, breeding_date, method) VALUES (v_id, v_a, fn_repro_today() - 263, 'MONTA_NATURAL');
    v_id := pg_temp.mk(v_a, 'A-C11', NULL, 'VACA', 'PREÑADA'); INSERT INTO t_ctx VALUES ('c_300', v_id::text);     -- gestation 300 > 283: unusable
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '300');
    v_id := pg_temp.mk(v_a, 'A-C12', NULL, 'VACA', 'VENDIDO'); INSERT INTO t_ctx VALUES ('c_sold', v_id::text);    -- sold: never listed
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '163');
    v_id := pg_temp.mk(v_a, 'A-C13', NULL, 'VACA', 'VACÍA');   INSERT INTO t_ctx VALUES ('c_open', v_id::text);    -- not PREÑADA: never listed
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '163');
    v_id := pg_temp.mk(v_b, 'B-C1', NULL, 'VACA', 'PREÑADA');  INSERT INTO t_ctx VALUES ('bc1', v_id::text);      -- company B, est = today + 20
    PERFORM pg_temp.pal(v_id, 100, 'en', 'PREÑADA', '163');
END $$;

SELECT pg_temp.ok('F palpation estimate: last PREÑADA palpation + (283 - gestation days) = today + 20 -> upcoming, source PALPACION, days_to_calving 20',
    (SELECT (c->'row'->>'estimated_calving_date')::date = fn_repro_today() + 20 AND c->'row'->>'estimate_source' = 'PALPACION'
            AND (c->'row'->>'days_to_calving')::int = 20 AND (c->'row'->>'gestation_days_at_palpation')::int = 163
       FROM (SELECT pg_temp.cal('upcoming', 'c_up') AS c) x));
SELECT pg_temp.ok('F service estimate: service date + 283 when there is no palpation (source SERVICIO); a palpation without usable gestation days (none, or 300 > 283) falls back to the service',
    (SELECT (c->'row'->>'estimated_calving_date')::date = fn_repro_today() + 20 AND c->'row'->>'estimate_source' = 'SERVICIO'
       FROM (SELECT pg_temp.cal('upcoming', 'c_svc') AS c) x)
    AND (SELECT c->'row'->>'estimate_source' = 'SERVICIO' FROM (SELECT pg_temp.cal('upcoming', 'c_nogest') AS c) x)
    AND pg_temp.cal('no_estimate', 'c_300') IS NOT NULL);
SELECT pg_temp.ok('F the Spanish key set (resultado PRENADA, dias_gestacion as text) is read like the English one',
    (SELECT (c->'row'->>'estimated_calving_date')::date = fn_repro_today() + 20 AND c->'row'->>'estimate_source' = 'PALPACION'
       FROM (SELECT pg_temp.cal('upcoming', 'c_span') AS c) x));
SELECT pg_temp.ok('F default window is 60 days: +120 is not upcoming, and with days = 150 it is; a past estimate is overdue (-10) with negative days_to_calving',
    pg_temp.cal('upcoming', 'c_far') IS NULL AND pg_temp.cal('upcoming', 'c_far', '150') IS NOT NULL
    AND (SELECT (c->'row'->>'days_to_calving')::int = -10 FROM (SELECT pg_temp.cal('overdue', 'c_over') AS c) x)
    AND pg_temp.cal('upcoming', 'c_over') IS NULL);
SELECT pg_temp.ok('F STALE DATA: an estimate more than 60 days in the past is in stale_data and NEVER in upcoming or overdue',
    pg_temp.cal('stale_data', 'c_stale') IS NOT NULL
    AND pg_temp.cal('upcoming', 'c_stale', '300') IS NULL AND pg_temp.cal('overdue', 'c_stale') IS NULL
    AND (SELECT (c->'row'->>'days_to_calving')::int = -100 FROM (SELECT pg_temp.cal('stale_data', 'c_stale') AS c) x));
SELECT pg_temp.ok('F the 40 import-dated PREÑADA cows (palpation 300 days ago, gestation 100 -> estimate ~117 days ago) all land in stale_data, none upcoming / overdue',
    (SELECT (r->>'stale_data_total')::int >= 41 FROM (SELECT sp_repro_list_upcoming_calvings(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) x)
    AND pg_temp.cal('stale_data', 'imp1') IS NOT NULL AND pg_temp.cal('upcoming', 'imp1', '300') IS NULL AND pg_temp.cal('overdue', 'imp1') IS NULL
    AND (SELECT (c->'row'->>'date_is_stale_import')::boolean FROM (SELECT pg_temp.cal('stale_data', 'imp1') AS c) x)
    AND (SELECT r->'stale_import_date'->>'flag' = 'true' FROM (SELECT sp_repro_list_upcoming_calvings(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) x));
SELECT pg_temp.ok('F no estimate: a PREÑADA cow with nothing to estimate from, with only a VOIDED service, and with an unusable gestation are listed apart',
    pg_temp.cal('no_estimate', 'c_none') IS NOT NULL AND pg_temp.cal('no_estimate', 'c_void') IS NOT NULL
    AND pg_temp.cal('upcoming', 'c_none', '300') IS NULL AND pg_temp.cal('stale_data', 'c_none') IS NULL);
SELECT pg_temp.ok('F a PREÑADA status with a NEWER VACÍA palpation is flagged status_conflict (still estimated from the last PREÑADA palpation)',
    (SELECT (c->'row'->>'status_conflict')::boolean AND c->'row'->>'last_palpation_result' = 'VACÍA'
       FROM (SELECT pg_temp.cal('upcoming', 'c_conf') AS c) x)
    AND NOT (SELECT (c->'row'->>'status_conflict')::boolean FROM (SELECT pg_temp.cal('upcoming', 'c_up') AS c) x));
SELECT pg_temp.ok('F only PREÑADA, active animals are listed anywhere: not the sold cow, not the VACÍA cow',
    (SELECT bool_and(pg_temp.cal(s, k, '300') IS NULL) FROM unnest(ARRAY['upcoming', 'overdue', 'stale_data', 'no_estimate']) s, unnest(ARRAY['c_sold', 'c_open']) k));
SELECT pg_temp.ok('F days must be between 1 and 300',
    sp_repro_list_upcoming_calvings(pg_temp.cx('A'), pg_temp.cx('u1'), '0')->>'status' = 'invalid'
    AND sp_repro_list_upcoming_calvings(pg_temp.cx('A'), pg_temp.cx('u1'), '301')->>'status' = 'invalid'
    AND sp_repro_list_upcoming_calvings(pg_temp.cx('A'), pg_temp.cx('u1'), 'x')->>'status' = 'invalid');
SELECT pg_temp.ok('F ISOLATION: B lists its own cow (+20) and none of A''s; A never lists B''s; user 1 gets an ERROR for B',
    (SELECT (c->'row'->>'estimated_calving_date')::date = fn_repro_today() + 20 FROM (SELECT pg_temp.cal('upcoming', 'bc1', NULL, 'B', 'u2') AS c) x)
    AND pg_temp.cal('upcoming', 'c_up', NULL, 'B', 'u2') IS NULL AND pg_temp.cal('stale_data', 'imp1', NULL, 'B', 'u2') IS NULL
    AND pg_temp.cal('upcoming', 'bc1') IS NULL
    AND (SELECT (r->>'pregnant_total')::int = 3 FROM (SELECT sp_repro_list_upcoming_calvings(pg_temp.cx('B'), pg_temp.cx('u2')) AS r) x)
    AND pg_temp.raises(format('SELECT sp_repro_list_upcoming_calvings(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

-- =============================================================================================================
-- PART G. list_unmapped_uterine_codes
-- =============================================================================================================

-- bulk-loaded style values (Spanish key condicion_utero) on top of what Part C logged: 'No apto' x2, UNE/NR once more, VACIA/UNE (mapped)
DO $$
DECLARE
    v_a integer := pg_temp.cx('A')::integer;
    v_id uuid;
BEGIN
    v_id := pg_temp.mk(v_a, 'A-G1', NULL, 'VACA', 'VACÍA'); PERFORM pg_temp.pal(v_id, 400, 'es', 'VACIA', NULL, 'No apto');
    v_id := pg_temp.mk(v_a, 'A-G2', NULL, 'VACA', 'VACÍA'); PERFORM pg_temp.pal(v_id, 400, 'es', 'VACIA', NULL, 'NO APTO');
    v_id := pg_temp.mk(v_a, 'A-G3', NULL, 'VACA', 'VACÍA'); PERFORM pg_temp.pal(v_id, 400, 'es', 'VACIA', NULL, 'UNE/NR');
    v_id := pg_temp.mk(v_a, 'A-G4', NULL, 'VACA', 'VACÍA'); PERFORM pg_temp.pal(v_id, 400, 'es', 'VACIA', NULL, 'VACIA/UNE');
    v_id := pg_temp.mk(v_a, 'A-G5', NULL, 'VACA', 'VACÍA'); PERFORM pg_temp.pal(v_id, 400, 'es', 'VACIA', NULL, 'ciclando');
END $$;

SELECT pg_temp.call('g1', format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.ok('G the list is by TOKEN, not by whole value: NR (from UNE/NR), RP and NO APTO are listed; UNE, UTCL1, ciclando are not',
    pg_temp.rs('g1')->>'status' = 'ok'
    AND (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('g1')->'unmapped') e WHERE e->>'code' IN ('NR', 'RP', 'NO APTO')) = 3
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.rs('g1')->'unmapped') e WHERE e->>'code' IN ('UNE', 'UTCL1', 'UTCL2', 'CICLANDO', 'ESTATICA')),
    pg_temp.rs('g1')::text);
SELECT pg_temp.ok('G counts split by origin: NO APTO 2 from the bulk load (case-insensitive); NR 1 logged (C: V3) + 1 bulk load (G3) + 20 import rows (UNE/NR)',
    (SELECT (e->>'palpations')::int = 2 AND (e->>'from_bulk_load')::int = 2 AND (e->>'from_logged')::int = 0
       FROM jsonb_array_elements(pg_temp.rs('g1')->'unmapped') e WHERE e->>'code' = 'NO APTO')
    AND (SELECT (e->>'from_logged')::int = 1 AND (e->>'from_bulk_load')::int = 21 AND (e->>'palpations')::int = 22
       FROM jsonb_array_elements(pg_temp.rs('g1')->'unmapped') e WHERE e->>'code' = 'NR')
    AND (SELECT (e->>'palpations')::int = 1 FROM jsonb_array_elements(pg_temp.rs('g1')->'unmapped') e WHERE e->>'code' = 'RP'));
SELECT pg_temp.ok('G the confirmed mappings of the company are returned for the vets (UNE, UTCL1..3, UTCL9) with who confirmed them',
    (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('g1')->'confirmed') e WHERE e->>'code' IN ('UNE', 'UTCL1', 'UTCL2', 'UTCL3', 'UTCL9')) = 5
    AND jsonb_array_length(pg_temp.rs('g1')->'confirmed') = 5);
SELECT pg_temp.call('g2', format('SELECT sp_repro_condition_code_set(%L, %L, %L, %L)', pg_temp.cx('A'), pg_temp.cx('u1'), 'rp', 'OTRO'));
SELECT pg_temp.call('g3', format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u1')));
SELECT pg_temp.ok('G once an ADMIN confirms RP it leaves the list, and the next palpation of RP is MAPPED (as OTRO)',
    pg_temp.rs('g2')->>'status' = 'created'
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.rs('g3')->'unmapped') e WHERE e->>'code' = 'RP')
    AND pg_temp.pc('VACÍA RP', pg_temp.cx('A')) = 'RP||OTRO|MAPPED'
    AND pg_temp.det('A-V5')->>'mapping_status' = 'UNMAPPED');
SELECT pg_temp.ok('G the snapshot rule: re-mapping does not rewrite a stored palpation (A-V5 stays UNMAPPED with a NULL condition)',
    pg_temp.det('A-V5')->>'repro_condition' IS NULL AND pg_temp.det('A-V5')->>'raw_code' = 'RP');
SELECT pg_temp.call('g4', format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u2')));
SELECT pg_temp.ok('G ISOLATION: B sees only its own unmapped tokens (UNE and UTCL2 logged by B in C) and none of A''s; B''s confirmed list is empty; user 1 gets an ERROR for B',
    (SELECT count(*) FROM jsonb_array_elements(pg_temp.rs('g4')->'unmapped') e WHERE e->>'code' IN ('UNE', 'UTCL2')) = 2
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.rs('g4')->'unmapped') e WHERE e->>'code' IN ('NR', 'RP', 'NO APTO'))
    AND jsonb_array_length(pg_temp.rs('g4')->'confirmed') = 0
    AND pg_temp.raises(format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'),
    pg_temp.rs('g4')::text);

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
            ('SELECT sp_repro_log_palpation_batch(%L, %L, ''[{"identifier":"T086-A-V9","raw_diagnosis":"VACÍA"}]'')'),
            ('SELECT sp_repro_list_palpation_due(%L, %L)'),
            ('SELECT sp_repro_list_upcoming_calvings(%L, %L)'),
            ('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)'),
            ('SELECT sp_repro_condition_code_set(%L, %L, ''ZZTOOL'', ''OTRO'')')) AS t (sql_tpl)));
SELECT pg_temp.ok('H ... and none of those rejected calls wrote anything (V9 unpalpated, no ZZTOOL code)',
    pg_temp.status_of('A-V9') = 'ACTIVO' AND NOT EXISTS (SELECT 1 FROM repro_condition_codes WHERE code = 'ZZTOOL')
    AND NOT EXISTS (SELECT 1 FROM palpation_repro_details d JOIN cattle_livestock l ON l.id = d.livestock_id WHERE l.rfid_siniiga = 'T086-A-V9'));
SELECT pg_temp.ok('H the e-mail comparison ignores case but the membership must be active (upper-cased e-mail works for A, still fails for B)',
    sp_repro_list_palpation_due(pg_temp.cx('A'), upper(pg_temp.cx('u1')), '90', '1')->>'status' = 'ok'
    AND (sp_repro_log_palpation_batch(pg_temp.cx('A'), upper(pg_temp.cx('u1')), '[{"identifier":"T086-A-V9","raw_diagnosis":"VACÍA UNE"}]')->>'status') = 'recorded'
    AND pg_temp.raises(format('SELECT sp_repro_list_palpation_due(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

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
    VALUES ('H palm company is rejected (P0094) by every palpation tool',
            pg_temp.raises(format('SELECT sp_repro_log_palpation_batch(%L, %L, ''[{"identifier":"x","raw_diagnosis":"VACÍA"}]'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_palpation_due(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_upcoming_calvings(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_list_unmapped_uterine_codes(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_condition_code_set(%L, %L, ''ZZ'', ''OTRO'')', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.n_codes(v_palm::text) = 0,
            'palm company ' || v_palm);
END $$;

-- =============================================================================================================
-- PART I. nothing else was written
-- =============================================================================================================

SELECT pg_temp.ok('I the tools wrote nothing outside the phase-3 tables and the health logs: births and weights unchanged, empadre entries only the 4 fixture entries of Part E',
    (SELECT (SELECT count(*) FROM birth_events) = c.births AND (SELECT count(*) FROM cattle_weight_logs) = c.weights
            AND (SELECT count(*) FROM repro_empadre_entries) = c.entries + 4
       FROM t_counts c));
SELECT pg_temp.ok('I every palpation_repro_details row belongs to the company of its animal and of its health log, and every condition is on a VACÍA row',
    NOT EXISTS (SELECT 1 FROM palpation_repro_details d
                  JOIN cattle_health_logs h ON h.id = d.health_log_id
                  JOIN cattle_livestock l ON l.id = h.livestock_id
                 WHERE l.tenant_id <> d.id_company OR h.livestock_id <> d.livestock_id)
    AND NOT EXISTS (SELECT 1 FROM palpation_repro_details WHERE repro_condition IS NOT NULL AND result <> 'VACÍA'));
SELECT pg_temp.ok('I every mapping row belongs to one company and is normalised',
    NOT EXISTS (SELECT 1 FROM repro_condition_codes WHERE code <> fn_repro_norm_code(code))
    AND pg_temp.n_codes(pg_temp.cx('B')) = 0);
SELECT pg_temp.ok('I no animal changed category (only the palpated ones changed status, through the existing procedure)',
    NOT EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T086%' AND category NOT IN ('VACA', 'NOVILLONA')));
SELECT pg_temp.ok('I sp_void_event, sp_register_birth_event, sp_log_breeding_event and sp_log_palpation_event do not mention the phase-3 objects',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
        AND proname IN ('sp_void_event', 'sp_register_birth_event', 'sp_log_breeding_event', 'sp_log_palpation_event')
        AND (prosrc ILIKE '%palpation_repro%' OR prosrc ILIKE '%repro_condition%' OR prosrc LIKE '%fn_repro_%' OR prosrc ILIKE '%uterine%')) = 0);
SELECT pg_temp.ok('I none of the phase-3 tables or tools is exposed through crud_models',
    NOT EXISTS (SELECT 1 FROM crud_models
                 WHERE table_name IN ('repro_condition_codes', 'palpation_repro_details') OR model_name IN ('repro_condition_codes', 'palpation_repro_details')
                    OR table_name LIKE 'sp\_repro\_%' OR model_name LIKE 'sp\_repro\_%'));
SELECT pg_temp.ok('I the phase-3 tools are STABLE (reads) / VOLATILE (writes) and take text parameters',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND provolatile = 's'
        AND proname IN ('sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings', 'sp_repro_list_unmapped_uterine_codes')) = 3
    AND (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND provolatile = 'v'
        AND proname IN ('sp_repro_log_palpation_batch', 'sp_repro_condition_code_set')) = 2);

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 300) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '086 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 086 tests: everything rolled back ***'
