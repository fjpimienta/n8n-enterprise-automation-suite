-- 084_tests.sql — functional checks for migration 084 (LOCAL / throwaway database only). EVERYTHING is rolled back.
-- Loads 084_repro_births_age.sql inside this transaction (embedded mode), so it runs the same way before and after 084
-- is applied. It does not assume any particular data: it picks two existing active non-palm companies (A and B) and two
-- existing users, and arranges memberships INSIDE the transaction (filtered UPDATE / INSERT, rolled back):
--   user 1: ACTIVE member of A, INACTIVE in B        user 2: ACTIVE member of B, INACTIVE in A
-- Fixture animals / births use identifiers prefixed T084 and birth dates in 2001, so pre-existing data does not
-- interfere; assertions about counts of existing data are deltas against a baseline taken before the fixtures.
--
-- Part A  numero_fuego parser (pure unit tests; no data needed)
-- Part B  effective birth (placeholder date, real date, estimate, unknown)
-- Part C  tools: results, pagination, ambiguity, report-only, quality report
-- Part D  isolation: a user of A gets an error (never rows) for B, strangers / bad input / palm fail closed
-- Part E  nothing was written
--
-- Run (the migrations folder must be visible to psql because of \ir):
--   docker cp database/migrations n8n-enterprise-db:/tmp/m084
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_OR_LOCAL_DB> -v ON_ERROR_STOP=1 -f /tmp/m084/084_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.cx(p_key text) RETURNS text
LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;

-- true when the statement raises exactly this SQLSTATE
CREATE FUNCTION pg_temp.raises(p_sql text, p_state text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE = p_state;
END $$;

-- =============================================================================================================
-- PART A. numero_fuego parser
-- =============================================================================================================

DO $$
DECLARE
    r        record;
    v_shape  text;
    v_est    public.fire_number_estimate;
    v_ok     boolean;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            -- input,             shape,                 year,  month, precision
            ('26-45-4',           'CURRENT',             2026,  4,     'MONTH'),
            ('25-1-1',            'CURRENT',             2025,  1,     'MONTH'),
            ('25-9-12',           'CURRENT',             2025,  12,    'MONTH'),
            ('2097',              'LEGACY',              2020,  NULL,  'YEAR'),
            ('1342',              'LEGACY',              2013,  NULL,  'YEAR'),
            ('0512',              'LEGACY',              2005,  NULL,  'YEAR'),
            ('2412',              'LEGACY',              2024,  NULL,  'YEAR'),
            ('0499',              'FOUR_DIGITS_REJECTED',NULL,  NULL,  NULL),
            ('26-45-0',           'INVALID_MONTH',       NULL,  NULL,  NULL),
            ('26-45-13',          'INVALID_MONTH',       NULL,  NULL,  NULL),
            ('08-4 P',            'OTHER',               NULL,  NULL,  NULL),
            ('2011-1 P',          'OTHER',               NULL,  NULL,  NULL),
            ('24-10-2',           'DASHED_REJECTED',     NULL,  NULL,  NULL),
            ('99-1-1',            'CURRENT',             NULL,  NULL,  NULL),   -- year 2099: valid shape, future => no estimate
            ('2534',              'UNCONFIRMED_SHAPE',   NULL,  NULL,  NULL),
            ('2553',              'UNCONFIRMED_SHAPE',   NULL,  NULL,  NULL),
            ('2963',              'UNCONFIRMED_SHAPE',   NULL,  NULL,  NULL),
            ('19102',             'UNCONFIRMED_SHAPE',   NULL,  NULL,  NULL),
            ('21116',             'UNCONFIRMED_SHAPE',   NULL,  NULL,  NULL),
            ('375',               'NO_YEAR_ENCODING',    NULL,  NULL,  NULL),
            ('',                  'EMPTY',               NULL,  NULL,  NULL),
            ('   ',               'EMPTY',               NULL,  NULL,  NULL),
            (NULL,                'EMPTY',               NULL,  NULL,  NULL),
            ('S/N',               'OTHER',               NULL,  NULL,  NULL),
            ('20199-84',          'OTHER',               NULL,  NULL,  NULL),
            ('26-45-4-1',         'OTHER',               NULL,  NULL,  NULL),
            (' 26-45-4',          'OTHER',               NULL,  NULL,  NULL),   -- no trimming, no guessing
            ('26-45-4 ',          'OTHER',               NULL,  NULL,  NULL),
            ('26-45-4' || E'\n',  'OTHER',               NULL,  NULL,  NULL),
            ('26-45-',            'OTHER',               NULL,  NULL,  NULL),
            ('26--4',             'OTHER',               NULL,  NULL,  NULL),
            ('8',                 'OTHER',               NULL,  NULL,  NULL),
            ('12',                'OTHER',               NULL,  NULL,  NULL),
            ('26-45-4A',          'OTHER',               NULL,  NULL,  NULL),
            (E'２６-45-4','OTHER',               NULL,  NULL,  NULL)    -- full-width digits are not digits here
        ) AS t(input, exp_shape, exp_year, exp_month, exp_prec)
    LOOP
        v_shape := public.fn_fire_number_shape(r.input);
        v_est   := public.fn_estimate_birth_from_fire_number(r.input);
        v_ok := v_shape = r.exp_shape
            AND (v_est).birth_year      IS NOT DISTINCT FROM r.exp_year
            AND (v_est).birth_month     IS NOT DISTINCT FROM r.exp_month
            AND (v_est).birth_precision IS NOT DISTINCT FROM r.exp_prec;
        INSERT INTO t_result (test, ok, detail)
        VALUES ('A parser [' || coalesce(replace(r.input, E'\n', '\n'), 'NULL') || ']', v_ok,
                format('shape=%s year=%s month=%s prec=%s', v_shape, (v_est).birth_year, (v_est).birth_month, (v_est).birth_precision));
    END LOOP;
END $$;

SELECT pg_temp.ok('A month_reliable is true for the current format and false for legacy',
    (public.fn_estimate_birth_from_fire_number('26-45-4')).month_reliable IS TRUE
    AND (public.fn_estimate_birth_from_fire_number('2097')).month_reliable IS FALSE);
SELECT pg_temp.ok('A a legacy number never yields a month (never inferred)',
    (SELECT bool_and((public.fn_estimate_birth_from_fire_number(lpad(g::text, 4, '0'))).birth_month IS NULL)
       FROM generate_series(500, 2499) g WHERE public.fn_fire_number_shape(lpad(g::text, 4, '0')) = 'LEGACY'));
SELECT pg_temp.ok('A the parser never raises: odd inputs answer NULL',
    (SELECT bool_and((public.fn_estimate_birth_from_fire_number(x)).birth_year IS NULL)
       FROM unnest(ARRAY[repeat('9', 5000), '--', '-', '26-4-4-4', '０', E'\t', 'null', 'NULL', '26-45-4;DROP']) x));
SELECT pg_temp.ok('A the shape function is IMMUTABLE, the estimate is STABLE (it depends on today)',
    (SELECT provolatile FROM pg_proc WHERE proname = 'fn_fire_number_shape' AND pronamespace = 'public'::regnamespace) = 'i'
    AND (SELECT provolatile FROM pg_proc WHERE proname = 'fn_estimate_birth_from_fire_number' AND pronamespace = 'public'::regnamespace) = 's');
SELECT pg_temp.ok('A placeholder date is exactly 2020-01-01',
    public.fn_is_placeholder_birth_date(DATE '2020-01-01') AND NOT public.fn_is_placeholder_birth_date(DATE '2020-01-02')
    AND NOT public.fn_is_placeholder_birth_date(DATE '2026-05-09') AND public.fn_is_placeholder_birth_date(NULL) IS NULL);
SELECT pg_temp.ok('A text helpers',
    public.fn_repro_txt('  null ') IS NULL AND public.fn_repro_txt('undefined') IS NULL AND public.fn_repro_txt(' x ') = 'x'
    AND public.fn_repro_int('12') = 12 AND public.fn_repro_int('1.5') IS NULL AND public.fn_repro_int('-1') IS NULL
    AND public.fn_repro_date('2001-02-30') IS NULL AND public.fn_repro_date('2001-02-03') = DATE '2001-02-03'
    AND public.fn_repro_date('3/2/2001') IS NULL);

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
        RAISE EXCEPTION '084 tests need two active non-palm companies in the database.';
    END IF;
    SELECT u.email INTO v_e1 FROM users u ORDER BY u.email LIMIT 1;
    SELECT u.email INTO v_e2 FROM users u WHERE u.email <> v_e1 ORDER BY u.email LIMIT 1;
    IF v_e1 IS NULL OR v_e2 IS NULL THEN
        RAISE EXCEPTION '084 tests need two users in the database.';
    END IF;

    UPDATE user_companies SET is_active = true  WHERE email = v_e1 AND id_company = v_a;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e1, v_a, 'EDITOR', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e1 AND id_company = v_a);
    UPDATE user_companies SET is_active = false WHERE email = v_e1 AND id_company = v_b;

    UPDATE user_companies SET is_active = true  WHERE email = v_e2 AND id_company = v_b;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT v_e2, v_b, 'EDITOR', true WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = v_e2 AND id_company = v_b);
    UPDATE user_companies SET is_active = false WHERE email = v_e2 AND id_company = v_a;

    INSERT INTO t_ctx VALUES ('A', v_a::text), ('B', v_b::text), ('u1', v_e1), ('u2', v_e2);
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cattle_livestock WHERE electronic_rfid = '') OR EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga LIKE 'T084%') THEN
        RAISE EXCEPTION '084 tests: this database already has electronic_rfid = '''' or T084 fixtures; run the tests on a clean copy.';
    END IF;
END $$;

-- Baseline of the quality report for A, BEFORE the fixtures (so the assertions are deltas).
CREATE TEMP TABLE t_base ON COMMIT DROP AS
SELECT sp_repro_identifier_quality_report(pg_temp.cx('A'), pg_temp.cx('u1')) AS q;

-- Fixtures ------------------------------------------------------------------------------------------------

CREATE FUNCTION pg_temp.mk(p_tenant integer, p_rfid text, p_fuego text, p_cat text, p_status text,
                           p_birth date DEFAULT NULL, p_mother uuid DEFAULT NULL, p_eid text DEFAULT NULL) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego,
                                  birth_date, mother_id, electronic_rfid)
    VALUES (p_tenant, p_rfid, 'CRIA', p_cat, p_status, p_fuego, p_birth, p_mother, p_eid)
    RETURNING id
$$;

DO $$
DECLARE
    a integer := pg_temp.cx('A')::integer;
    b integer := pg_temp.cx('B')::integer;
    dam_a1 uuid; calf_a1 uuid; calf_a2 uuid; dam_b1 uuid; calf_b1 uuid;
BEGIN
    dam_a1  := pg_temp.mk(a, 'T084-A-DAM1', '0507',    'VACA',    'ACTIVO', DATE '2020-01-01');   -- placeholder date, legacy number (2005)
    PERFORM    pg_temp.mk(a, 'T084-A-DAM2', 'T084DUP', 'VACA',    'ACTIVO', NULL, NULL, '');      -- duplicate fuego + '' electronic_rfid
    PERFORM    pg_temp.mk(a, 'T084-A-DAM3', 'T084DUP', 'VACA',    'ACTIVO');                       -- duplicate fuego
    PERFORM    pg_temp.mk(a, 'T084-A-SOLD', 'T084DUP', 'VACA',    'VENDIDO');                      -- sold: outside the report scope
    PERFORM    pg_temp.mk(a, 'T084-A-UNK',  'S/N',     'VACA',    'ACTIVO');                       -- unknown age
    calf_a1 := pg_temp.mk(a, 'T084-A-CALF1', '26-8888-4', 'BECERRA', 'ACTIVO', NULL, dam_a1);     -- mother, no birth_events row
    calf_a2 := pg_temp.mk(a, 'T084-A-CALF2', NULL,      'BECERRA', 'ACTIVO', current_date - 100, dam_a1);
    dam_b1  := pg_temp.mk(b, 'T084-B-DAM1', 'T084DUP', 'VACA',    'ACTIVO');
    calf_b1 := pg_temp.mk(b, 'T084-B-CALF1', NULL,     'BECERRO', 'ACTIVO', NULL, dam_b1);        -- B's unregistered calf

    INSERT INTO birth_events (id_company, dam_id, calf_sex, calf_id, birth_date, source) VALUES
        (a, dam_a1, 'HEMBRA', calf_a2, DATE '2001-03-10', 'MANUAL'),
        (a, dam_a1, 'MACHO',  NULL,    DATE '2001-03-20', 'MANUAL'),
        (a, dam_a1, 'MACHO',  NULL,    DATE '2001-04-02', 'MANUAL'),
        (b, dam_b1, 'HEMBRA', NULL,    DATE '2001-03-11', 'MANUAL');
    INSERT INTO cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
    VALUES (calf_a2, 12.5, now(), 'BIRTH_EVENT');

    INSERT INTO t_ctx VALUES ('dam_a1', dam_a1::text), ('calf_a1', calf_a1::text), ('calf_a2', calf_a2::text),
                             ('dam_b1', dam_b1::text), ('calf_b1', calf_b1::text);
END $$;

-- Counts of everything the tools could possibly write to (checked again in part E).
CREATE TEMP TABLE t_counts ON COMMIT DROP AS
SELECT (SELECT count(*) FROM birth_events) AS births, (SELECT count(*) FROM cattle_livestock) AS animals,
       (SELECT count(*) FROM cattle_weight_logs) AS weights, (SELECT count(*) FROM event_voids) AS voids,
       (SELECT count(*) FROM cattle_breeding_events) AS services, (SELECT count(*) FROM cattle_health_logs) AS health;

-- =============================================================================================================
-- PART B. effective birth
-- =============================================================================================================

SELECT pg_temp.ok('B placeholder date is ignored and the legacy number is used (year only, no month)',
    (SELECT eb.age_source = 'ESTIMADA_NUMERO_FUEGO' AND eb.age_precision = 'YEAR_ONLY' AND eb.effective_birth_year = 2005
            AND eb.effective_birth_month IS NULL AND eb.age_months IS NULL AND eb.registered_birth_date IS NULL
            AND eb.date_quality = 'PLACEHOLDER_DATE_IGNORED' AND eb.month_reliable IS FALSE
            AND eb.age_months_min = (extract(year FROM current_date)::int * 12 + extract(month FROM current_date)::int) - (2005 * 12 + 12)
       FROM vw_animal_effective_birth eb WHERE eb.livestock_id = pg_temp.cx('dam_a1')::uuid AND eb.tenant_id = pg_temp.cx('A')::integer));
SELECT pg_temp.ok('B current-format number gives a month-precision estimate and an age in months',
    (SELECT eb.age_source = 'ESTIMADA_NUMERO_FUEGO' AND eb.age_precision = 'MONTH' AND eb.effective_birth_month = 4
            AND eb.month_reliable IS TRUE AND eb.date_quality IS NULL
            AND eb.age_months = (extract(year FROM current_date)::int * 12 + extract(month FROM current_date)::int) - (2026 * 12 + 4)
            AND eb.age_months = eb.age_months_min
       FROM vw_animal_effective_birth eb WHERE eb.livestock_id = pg_temp.cx('calf_a1')::uuid));
SELECT pg_temp.ok('B a real birth_date wins, month precision (the day is never used)',
    (SELECT eb.age_source = 'REGISTRADA' AND eb.age_precision = 'MONTH' AND eb.registered_birth_date = current_date - 100
            AND eb.effective_birth_year = extract(year FROM current_date - 100)::int
            AND eb.effective_birth_month = extract(month FROM current_date - 100)::int
            AND eb.age_months = (extract(year FROM current_date)::int * 12 + extract(month FROM current_date)::int)
                                - (extract(year FROM current_date - 100)::int * 12 + extract(month FROM current_date - 100)::int)
       FROM vw_animal_effective_birth eb WHERE eb.livestock_id = pg_temp.cx('calf_a2')::uuid));
SELECT pg_temp.ok('B no usable number and no date: unknown, nothing invented',
    (SELECT eb.age_source = 'DESCONOCIDA' AND eb.age_precision IS NULL AND eb.age_months IS NULL AND eb.age_months_min IS NULL
            AND eb.effective_birth_year IS NULL
       FROM vw_animal_effective_birth eb WHERE eb.livestock_id = (SELECT id FROM cattle_livestock WHERE rfid_siniiga = 'T084-A-UNK')));
SELECT pg_temp.ok('B the estimate is never written into cattle_livestock.birth_date',
    (SELECT birth_date IS NOT DISTINCT FROM DATE '2020-01-01' FROM cattle_livestock WHERE id = pg_temp.cx('dam_a1')::uuid)
    AND (SELECT birth_date IS NULL FROM cattle_livestock WHERE id = pg_temp.cx('calf_a1')::uuid));
SELECT pg_temp.ok('B one row per animal',
    (SELECT count(*) FROM vw_animal_effective_birth) = (SELECT count(*) FROM cattle_livestock));

-- =============================================================================================================
-- PART C. tools
-- =============================================================================================================

-- list_births
SELECT pg_temp.ok('C list_births: A sees exactly its 3 births of 2001, none of B',
    (SELECT (r->>'total')::int = 3 AND jsonb_array_length(r->'births') = 3
            AND NOT (r::text LIKE '%' || pg_temp.cx('dam_b1') || '%')
       FROM (SELECT sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31') AS r) s));
SELECT pg_temp.ok('C list_births: newest first, dam identifiers, calf, birth weight',
    (SELECT r->'births'->0->>'birth_date' = '2001-04-02' AND r->'births'->2->>'birth_date' = '2001-03-10'
            AND r->'births'->2->'dam'->>'rfid_siniiga' = 'T084-A-DAM1' AND (r->'births'->2->'dam'->>'linked')::boolean
            AND r->'births'->2->'calf'->>'rfid_siniiga' = 'T084-A-CALF2' AND (r->'births'->2->>'birth_weight_kg')::numeric = 12.5
       FROM (SELECT sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31') AS r) s));
SELECT pg_temp.ok('C list_births: pagination (limit 1: has_more true, true, false)',
    (SELECT (sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31', '1', '0')->>'has_more')::boolean
        AND (sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31', '1', '1')->>'has_more')::boolean
        AND NOT (sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31', '1', '2')->>'has_more')::boolean));
SELECT pg_temp.ok('C list_births: default window is the last 30 days; limit is capped at 100',
    (SELECT (r->>'date_from')::date = current_date - 30 AND (r->>'date_to')::date = current_date AND r->>'status' = 'ok'
       FROM (SELECT sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1')) AS r) s)
    AND (sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), NULL, NULL, '1000')->>'limit')::int = 100);
SELECT pg_temp.ok('C list_births: bad dates / reversed range are answered, not raised',
    sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), 'xx', NULL)->>'status' = 'invalid'
    AND sp_repro_list_births(pg_temp.cx('A'), pg_temp.cx('u1'), '2001-12-31', '2001-01-01')->>'status' = 'invalid');

-- get_dam_birth_history
SELECT pg_temp.ok('C dam history: resolved by arete, both linked and unlinked births, calf and weight',
    (SELECT r->>'status' = 'ok' AND (r->>'total_births')::int = 3 AND jsonb_array_length(r->'births') = 3
            AND r->'dam'->>'rfid_siniiga' = 'T084-A-DAM1' AND r->'dam'->>'age_precision' = 'YEAR_ONLY'
            AND r->'births'->2->'calf'->>'rfid_siniiga' = 'T084-A-CALF2' AND (r->'births'->2->>'birth_weight_kg')::numeric = 12.5
       FROM (SELECT sp_repro_dam_birth_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T084-A-DAM1') AS r) s));
SELECT pg_temp.ok('C dam history: a duplicated numero_fuego is an ambiguity, never a guess, and lists only this tenant',
    (SELECT r->>'status' = 'ambiguous' AND jsonb_array_length(r->'candidates') = 3
            AND NOT (r::text LIKE '%' || pg_temp.cx('dam_b1') || '%') AND NOT (r::text LIKE '%T084-B-DAM1%') AND r->'births' IS NULL
       FROM (SELECT sp_repro_dam_birth_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T084DUP') AS r) s));
SELECT pg_temp.ok('C dam history: not found / empty identifier / another tenant''s animal is not found',
    sp_repro_dam_birth_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T084-NOPE')->>'status' = 'not_found'
    AND sp_repro_dam_birth_history(pg_temp.cx('A'), pg_temp.cx('u1'), '  ')->>'status' = 'invalid'
    AND sp_repro_dam_birth_history(pg_temp.cx('A'), pg_temp.cx('u1'), 'T084-B-DAM1')->>'status' = 'not_found');

-- get_births_summary
SELECT pg_temp.ok('C summary by month (A: 2001-03 = 2, 2001-04 = 1; B''s birth not counted)',
    (SELECT r->>'status' = 'ok' AND (r->>'total_births')::int = 3
            AND r->'periods'->0->>'period' = '2001-03' AND (r->'periods'->0->>'births')::int = 2
            AND (r->'periods'->0->>'male')::int = 1 AND (r->'periods'->0->>'female')::int = 1
            AND r->'periods'->1->>'period' = '2001-04' AND (r->'periods'->1->>'births')::int = 1
       FROM (SELECT sp_repro_births_summary(pg_temp.cx('A'), pg_temp.cx('u1'), 'month', '2001-01-01', '2001-12-31') AS r) s));
SELECT pg_temp.ok('C summary by day',
    (SELECT jsonb_array_length(r->'periods') = 3 AND r->'periods'->0->>'period' = '2001-03-10'
       FROM (SELECT sp_repro_births_summary(pg_temp.cx('A'), pg_temp.cx('u1'), 'day', '2001-03-01', '2001-04-30') AS r) s));
SELECT pg_temp.ok('C summary: invalid group_by / range answered',
    sp_repro_births_summary(pg_temp.cx('A'), pg_temp.cx('u1'), 'week')->>'status' = 'invalid'
    AND sp_repro_births_summary(pg_temp.cx('A'), pg_temp.cx('u1'), 'day', '2000-01-01', '2002-12-31')->>'status' = 'invalid');

-- list_unregistered_historical_births (report only)
SELECT pg_temp.ok('C unregistered: the calf with a mother and no birth_events row is reported, with dam and estimate',
    (SELECT r->>'status' = 'ok' AND (r->>'report_only')::boolean
            AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'calves') c
                         WHERE c->'calf'->>'rfid_siniiga' = 'T084-A-CALF1'
                           AND c->'dam'->>'rfid_siniiga' = 'T084-A-DAM1' AND (c->'dam'->>'found')::boolean
                           AND (c->'estimated_birth'->>'year')::int = 2026 AND (c->'estimated_birth'->>'month')::int = 4
                           AND c->'estimated_birth'->>'age_source' = 'ESTIMADA_NUMERO_FUEGO')
       FROM (SELECT sp_repro_list_unregistered_historical_births(pg_temp.cx('A'), pg_temp.cx('u1'), '100') AS r) s));
SELECT pg_temp.ok('C unregistered: a calf that has a birth_events row is not reported; B''s calf never appears in A',
    (SELECT NOT (r::text LIKE '%T084-A-CALF2%') AND NOT (r::text LIKE '%T084-B-CALF1%')
       FROM (SELECT sp_repro_list_unregistered_historical_births(pg_temp.cx('A'), pg_temp.cx('u1'), '100') AS r) s));
SELECT pg_temp.ok('C unregistered: B sees its own calf only',
    (SELECT r::text LIKE '%T084-B-CALF1%' AND NOT (r::text LIKE '%T084-A-CALF1%')
       FROM (SELECT sp_repro_list_unregistered_historical_births(pg_temp.cx('B'), pg_temp.cx('u2'), '100') AS r) s));

-- identifier_quality_report (deltas against the baseline taken before the fixtures)
SELECT pg_temp.ok('C quality report: scope grew by the 6 active fixtures (the sold one is out of scope)',
    (SELECT (n.q->>'animals_in_scope')::int - (b.q->>'animals_in_scope')::int = 6
       FROM t_base b, (SELECT sp_repro_identifier_quality_report(pg_temp.cx('A'), pg_temp.cx('u1')) AS q) n));
SELECT pg_temp.ok('C quality report: duplicated fuego (T084DUP x2 in scope), empty-string RFID, non 10-digit arete',
    (SELECT (n.q->'duplicate_numero_fuego'->>'distinct_values')::int - (b.q->'duplicate_numero_fuego'->>'distinct_values')::int = 1
        AND (n.q->'duplicate_numero_fuego'->>'animals_involved')::int - (b.q->'duplicate_numero_fuego'->>'animals_involved')::int = 2
        AND (n.q->>'electronic_rfid_empty_string')::int - (b.q->>'electronic_rfid_empty_string')::int = 1
        AND (n.q->'siniiga_not_10_digits'->>'count')::int - (b.q->'siniiga_not_10_digits'->>'count')::int = 6
        AND (n.q->>'missing_electronic_rfid')::int - (b.q->>'missing_electronic_rfid')::int = 6
       FROM t_base b, (SELECT sp_repro_identifier_quality_report(pg_temp.cx('A'), pg_temp.cx('u1')) AS q) n));
SELECT pg_temp.ok('C quality report: unparsable numbers are counted by shape (T084DUP x2, S/N, NULL fuego), parsable ones are not',
    (SELECT (n.q->>'numero_fuego_not_parsable')::int - (b.q->>'numero_fuego_not_parsable')::int = 4
        AND (n.q->'numero_fuego_by_shape'->'CURRENT'->>'animals')::int - coalesce((b.q->'numero_fuego_by_shape'->'CURRENT'->>'animals')::int, 0) = 1
        AND (n.q->'numero_fuego_by_shape'->'LEGACY'->>'animals')::int - coalesce((b.q->'numero_fuego_by_shape'->'LEGACY'->>'animals')::int, 0) = 1
       FROM t_base b, (SELECT sp_repro_identifier_quality_report(pg_temp.cx('A'), pg_temp.cx('u1')) AS q) n));

-- =============================================================================================================
-- PART D. isolation and fail-closed behaviour
-- =============================================================================================================

SELECT pg_temp.ok('D user 1 (member of A only) gets an ERROR, not rows, for B: list_births',
    pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), '2001-01-01', '2001-12-31'), 'P0001'));
SELECT pg_temp.ok('D ... dam history',
    pg_temp.raises(format('SELECT sp_repro_dam_birth_history(%L, %L, %L)', pg_temp.cx('B'), pg_temp.cx('u1'), 'T084-B-DAM1'), 'P0001'));
SELECT pg_temp.ok('D ... births summary',
    pg_temp.raises(format('SELECT sp_repro_births_summary(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));
SELECT pg_temp.ok('D ... unregistered historical births',
    pg_temp.raises(format('SELECT sp_repro_list_unregistered_historical_births(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));
SELECT pg_temp.ok('D ... identifier quality report',
    pg_temp.raises(format('SELECT sp_repro_identifier_quality_report(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));
SELECT pg_temp.ok('D user 2 (member of B only) gets an error for A, and sees B''s birth for B',
    pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', pg_temp.cx('A'), pg_temp.cx('u2')), 'P0001')
    AND (sp_repro_list_births(pg_temp.cx('B'), pg_temp.cx('u2'), '2001-01-01', '2001-12-31')->>'total')::int = 1);
SELECT pg_temp.ok('D a stranger, a blank e-mail, a non-numeric / empty / injected tenant all fail closed',
    pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', pg_temp.cx('A'), 'nadie@example.test'), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', pg_temp.cx('A'), ''), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', 'abc', pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', '', pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', pg_temp.cx('A') || ' OR 1=1', pg_temp.cx('u1')), 'P0001')
    AND pg_temp.raises('SELECT sp_repro_list_births(NULL, NULL)', 'P0001'));
SELECT pg_temp.ok('D the e-mail comparison ignores case but the membership must be active',
    sp_repro_list_births(pg_temp.cx('A'), upper(pg_temp.cx('u1')), '2001-01-01', '2001-12-31')->>'status' = 'ok'
    AND pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', pg_temp.cx('B'), pg_temp.cx('u1')), 'P0001'));

DO $$
DECLARE
    v_palm  integer;
BEGIN
    SELECT c.id_company INTO v_palm FROM companys c WHERE c.is_active AND fn_company_business_domain(c.id_company) = 'PALM' ORDER BY c.id_company LIMIT 1;
    IF v_palm IS NULL THEN
        INSERT INTO t_result (test, ok, detail) VALUES ('D palm company is rejected (P0094) - skipped: no palm company in this database', true, 'skipped');
        RETURN;
    END IF;
    INSERT INTO user_companies (email, id_company, role, is_active)
    SELECT pg_temp.cx('u1'), v_palm, 'ADMIN', true
     WHERE NOT EXISTS (SELECT 1 FROM user_companies WHERE email = pg_temp.cx('u1') AND id_company = v_palm);
    UPDATE user_companies SET is_active = true WHERE email = pg_temp.cx('u1') AND id_company = v_palm;
    INSERT INTO t_result (test, ok, detail)
    VALUES ('D palm company is rejected (P0094) by every tool',
            pg_temp.raises(format('SELECT sp_repro_list_births(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094')
            AND pg_temp.raises(format('SELECT sp_repro_identifier_quality_report(%L, %L)', v_palm::text, pg_temp.cx('u1')), 'P0094'),
            'palm company ' || v_palm);
END $$;

SELECT pg_temp.ok('D the internal view is not exposed through crud_models',
    NOT EXISTS (SELECT 1 FROM crud_models WHERE table_name = 'vw_animal_effective_birth' OR model_name = 'vw_animal_effective_birth'));
SELECT pg_temp.ok('D tools take text parameters and are STABLE (read-only)',
    (SELECT bool_and(p.proargtypes[0] = 'text'::regtype AND p.proargtypes[1] = 'text'::regtype AND p.provolatile = 's')
       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'sp\_repro\_%')
    AND (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'sp\_repro\_%') = 5);

-- =============================================================================================================
-- PART E. nothing was written by the tools
-- =============================================================================================================

SELECT pg_temp.ok('E no tool wrote anything (births, animals, weights, voids, services, health logs unchanged)',
    (SELECT (SELECT count(*) FROM birth_events) = c.births AND (SELECT count(*) FROM cattle_livestock) = c.animals
        AND (SELECT count(*) FROM cattle_weight_logs) = c.weights AND (SELECT count(*) FROM event_voids) = c.voids
        AND (SELECT count(*) FROM cattle_breeding_events) = c.services AND (SELECT count(*) FROM cattle_health_logs) = c.health
       FROM t_counts c));
SELECT pg_temp.ok('E the pre-existing reproduction procedures were not touched by 084',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
        AND proname IN ('sp_register_birth_event', 'sp_log_breeding_event', 'sp_log_palpation_event', 'sp_void_event')
        AND prosrc LIKE '%fn_repro_ctx%') = 0);

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 300) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '084 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 084 tests: everything rolled back ***'
