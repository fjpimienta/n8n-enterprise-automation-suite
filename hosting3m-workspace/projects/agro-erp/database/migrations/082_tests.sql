-- 082_tests.sql — functional checks for migration 082 (LOCAL only). EVERYTHING is rolled back at the end.
-- Loads 082 inside this transaction (embedded). Company 10 is palm (test tenant), 7 is palm (real client: only
-- read here), 3 is livestock (test tenant), 1 has an unknown domain.
--
-- Run (the migrations folder must be visible to psql because of \ir):
--   docker cp database/migrations n8n-enterprise-db:/tmp/m082
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1 -f /tmp/m082/082_tests.sql

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 082_reject_palm_in_livestock_tools.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.expect_error(p_test text, p_sql text, p_state text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.ok(p_test, SQLSTATE = p_state, SQLSTATE || ': ' || left(SQLERRM, 140));
        RETURN;
    END;
    PERFORM pg_temp.ok(p_test, false, 'no error raised (expected ' || p_state || ')');
END;
$$;

CREATE FUNCTION pg_temp.plan(p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r record; v text := '';
BEGIN
    FOR r IN EXECUTE 'EXPLAIN ' || p_sql LOOP v := v || r."QUERY PLAN" || E'\n'; END LOOP;
    RETURN v;
END;
$$;

-- T01..T04 the function
SELECT pg_temp.expect_error('T01 palm test company (10) rejected with P0094',
    $q$SELECT fn_reject_palm_company(10)$q$, 'P0094');
SELECT pg_temp.expect_error('T01b palm client company (7) rejected with P0094',
    $q$SELECT fn_reject_palm_company(7)$q$, 'P0094');
SELECT pg_temp.ok('T02 livestock companies pass (3, 5, 6)',
    fn_reject_palm_company(3) AND fn_reject_palm_company(5) AND fn_reject_palm_company(6));
SELECT pg_temp.ok('T03 unknown domain (1), NULL and a missing company pass',
    fn_reject_palm_company(1) AND fn_reject_palm_company(NULL) AND fn_reject_palm_company(-1));
DO $$
BEGIN
    PERFORM fn_reject_palm_company(10);
EXCEPTION WHEN SQLSTATE 'P0094' THEN
    PERFORM pg_temp.ok('T04 the message is clear and in Spanish', SQLERRM LIKE 'Esta empresa es de palma; usa el registro de palma.%', SQLERRM);
END $$;

-- T05..T08 the planner: the guard runs before any row, even when the query finds none (the palm case)
SELECT pg_temp.expect_error('T05 SELECT with no rows for a palm company still raises',
    $q$SELECT l.id FROM cattle_livestock l WHERE fn_reject_palm_company(10) AND l.tenant_id = 10$q$, 'P0094');
SELECT pg_temp.expect_error('T06 INSERT ... SELECT guarded: raises and inserts nothing',
    $q$INSERT INTO cattle_expenses (tenant_id, category, amount, description, expense_date)
       SELECT 10, 'QA', 1, 'QA 082', CURRENT_DATE
       WHERE fn_reject_palm_company(10) AND EXISTS (SELECT 1 FROM user_companies WHERE id_company = 10)$q$, 'P0094');
SELECT pg_temp.ok('T06b nothing was written to cattle_expenses for company 10 by T06',
    NOT EXISTS (SELECT 1 FROM cattle_expenses WHERE tenant_id = 10 AND description = 'QA 082'));
SELECT pg_temp.expect_error('T07 a procedure in FROM is never reached (one-time filter first)',
    $q$SELECT sp.* FROM generate_series(1, 0) AS sp WHERE fn_reject_palm_company(10)$q$, 'P0094');
SELECT pg_temp.ok('T08 EXPLAIN shows a One-Time Filter for the guard',
    pg_temp.plan($q$SELECT l.id FROM cattle_livestock l WHERE fn_reject_palm_company(10) AND l.tenant_id = 10$q$) LIKE '%One-Time Filter: fn_reject_palm_company(10)%',
    pg_temp.plan($q$SELECT l.id FROM cattle_livestock l WHERE fn_reject_palm_company(10) AND l.tenant_id = 10$q$));
SELECT pg_temp.ok('T09 a livestock company keeps its normal answer (rows of company 3)',
    (SELECT count(*) FROM cattle_livestock l WHERE fn_reject_palm_company(3) AND l.tenant_id = 3)
    = (SELECT count(*) FROM cattle_livestock WHERE tenant_id = 3));

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '082 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 082 tests: everything rolled back ***'
