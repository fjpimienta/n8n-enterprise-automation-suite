-- 080_tests.sql — functional checks for migration 080 (LOCAL only). EVERYTHING is rolled back at the end.
-- Loads 080_agri_structure.sql inside this transaction (embedded mode), so it runs the same way before
-- and after 080 is applied. Uses company 3 (test tenant) and company 6 (only inside this transaction:
-- the plantations created under 6 and a temporary ADMIN membership are rolled back).
--
-- Run (the migrations folder must be visible to psql because of \ir):
--   docker cp database/migrations n8n-enterprise-db:/tmp/m080
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1 -f /tmp/m080/080_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 080_agri_structure.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_id (k text PRIMARY KEY, v uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.id(p_key text) RETURNS uuid
LANGUAGE sql AS $$ SELECT v FROM t_id WHERE k = p_key $$;

-- Runs p_sql and records OK only if it fails with SQLSTATE p_state.
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

DO $$
DECLARE
    c_actor  constant text := 'fjpimienta@gmail.com';
    v_res    jsonb;
    v_n      integer;
    v_m      integer;
    v_tmp    integer;
    r        record;
BEGIN
    -- Test actor: ADMIN of 3 (already) and, only inside this transaction, ADMIN of 6.
    INSERT INTO user_companies (email, id_company, role, is_active) VALUES (c_actor, 3, 'ADMIN', true), (c_actor, 6, 'ADMIN', true)
    ON CONFLICT (email, id_company) DO UPDATE SET role = 'ADMIN', is_active = true;

    -- Independent of earlier QA data: plantations already registered for 3 / 6 are deactivated inside
    -- this transaction only (deactivation also clears their default flag), so the tests start clean.
    UPDATE agri_plantations SET is_active = false WHERE id_company IN (3, 6) AND is_active;

    -- T01 catalog seed
    SELECT count(*) INTO v_n FROM agri_variety_catalog WHERE variety_code IN ('TENERA','DURA','HIBRIDO_OXG','OTRA_SIN_ESPECIFICAR');
    PERFORM pg_temp.ok('T01 variety catalog seeded (4)', v_n = 4, v_n::text);

    -- T02 first plantation of the company becomes the default; the client cannot force is_default
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (3, 'QA-P3A', 'Plantación QA A', 100, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P3A', r.id);
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure, is_default)
    VALUES (3, 'QA-P3B', 'Plantación QA B', 50, 'RENTADA', true) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P3B', r.id);
    PERFORM pg_temp.ok('T02 first plantation is default, second is not (is_default from client ignored)',
        (SELECT is_default FROM agri_plantations WHERE id = pg_temp.id('P3A'))
        AND NOT (SELECT is_default FROM agri_plantations WHERE id = pg_temp.id('P3B')));

    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (6, 'QA-P6', 'Plantación QA empresa 6', 10, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P6', r.id);
END $$;

-- T03 unique plantation code per company among active rows, case-insensitive
SELECT pg_temp.expect_error('T03 duplicate plantation code (case/space-insensitive) rejected',
    $q$INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
       VALUES (3, ' qa-p3a ', 'Duplicada', 5, 'PROPIA')$q$, '23505');

-- T04 the same code is allowed in another company and after deactivating the original
DO $$
DECLARE r record;
BEGIN
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (6, 'QA-P3A', 'Mismo código en otra empresa', 5, 'PROPIA');
    UPDATE agri_plantations SET is_active = false WHERE id = pg_temp.id('P3B');
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (3, 'qa-p3b', 'Reemplazo de B', 60, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P3B2', r.id);
    PERFORM pg_temp.ok('T04 same code in other company / after deactivation allowed', true);
    PERFORM pg_temp.ok('T04b deactivating a plantation clears is_default and never errors',
        NOT (SELECT is_default FROM agri_plantations WHERE id = pg_temp.id('P3B')));
END $$;

-- T05..T07 CHECK constraints
SELECT pg_temp.expect_error('T05 lessor_name only when RENTADA',
    $q$INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure, lessor_name)
       VALUES (3, 'QA-CHK1', 'x', 5, 'PROPIA', 'Arrendador')$q$, '23514');
SELECT pg_temp.expect_error('T06 latitude without longitude rejected',
    $q$INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure, latitude)
       VALUES (3, 'QA-CHK2', 'x', 5, 'PROPIA', 17.5)$q$, '23514');
SELECT pg_temp.expect_error('T07 latitude out of range rejected',
    $q$INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure, latitude, longitude)
       VALUES (3, 'QA-CHK3', 'x', 5, 'PROPIA', 95, -92)$q$, '23514');
SELECT pg_temp.expect_error('T07b total_area_ha must be > 0',
    $q$INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
       VALUES (3, 'QA-CHK4', 'x', 0, 'PROPIA')$q$, '23514');

-- T08..T12 default plantation
DO $$
DECLARE v_res jsonb; v_n integer;
BEGIN
    v_res := sp_agri_set_default_plantation(3, pg_temp.id('P3B2'), 'fjpimienta@gmail.com');
    SELECT count(*) INTO v_n FROM agri_plantations WHERE id_company = 3 AND is_default AND is_active;
    PERFORM pg_temp.ok('T08 set default moves it in one call; exactly one active default',
        (v_res->>'changed')::boolean AND v_n = 1
        AND (SELECT is_default FROM agri_plantations WHERE id = pg_temp.id('P3B2'))
        AND v_res->>'previous_default_id' = pg_temp.id('P3A')::text, v_res::text);
    v_res := sp_agri_set_default_plantation(3, pg_temp.id('P3B2'), 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T08b setting the current default again is a no-op', NOT (v_res->>'changed')::boolean);

    UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
END $$;
SELECT pg_temp.expect_error('T09 EDITOR cannot change the default',
    $q$SELECT sp_agri_set_default_plantation(3, pg_temp.id('P3A'), 'fjpimienta@gmail.com')$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
SELECT pg_temp.expect_error('T10 an inactive plantation cannot be the default',
    $q$SELECT sp_agri_set_default_plantation(3, pg_temp.id('P3B'), 'fjpimienta@gmail.com')$q$, 'P0088');
SELECT pg_temp.expect_error('T11 is_default cannot be changed outside the procedure',
    $q$UPDATE agri_plantations SET is_default = true WHERE id = pg_temp.id('P3A')$q$, 'P0088');
SELECT pg_temp.expect_error('T12 another company''s plantation cannot become my default (no leak)',
    $q$SELECT sp_agri_set_default_plantation(3, pg_temp.id('P6'), 'fjpimienta@gmail.com')$q$, 'P0080');
SELECT pg_temp.expect_error('T12b a non-member cannot change the default',
    $q$SELECT sp_agri_set_default_plantation(7, pg_temp.id('P6'), 'fjpimienta@gmail.com')$q$, 'P0084');

-- T13..T16 lots
SELECT pg_temp.expect_error('T13 lot of company 3 under a plantation of company 6 rejected',
    $q$INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (3, pg_temp.id('P6'), 'QA-X', 1)$q$, 'P0080');
SELECT pg_temp.expect_error('T13b lot under an inactive plantation rejected',
    $q$INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (3, pg_temp.id('P3B'), 'QA-X', 1)$q$, 'P0081');
SELECT pg_temp.expect_error('T13c future planting date rejected',
    $q$INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha, planting_date)
       VALUES (3, pg_temp.id('P3A'), 'QA-X', 1, fn_agri_today_cdmx() + 1)$q$, 'P0083');
DO $$
DECLARE r record; v_tenera uuid := (SELECT id FROM agri_variety_catalog WHERE variety_code = 'TENERA');
BEGIN
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha, planting_date, variety_id,
                           planting_pattern, spacing_m, design_density_plants_ha, water_regime)
    VALUES (3, pg_temp.id('P3A'), 'L-01', 'Lote 1', 20, fn_agri_today_cdmx() - interval '10 years', v_tenera,
            'TRESBOLILLO', 9, 143, 'TEMPORAL') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L1', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha, planting_date)
    VALUES (3, pg_temp.id('P3A'), 'L-02', 90, fn_agri_today_cdmx() - interval '2 years') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L2', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha, planting_date)
    VALUES (3, pg_temp.id('P3B2'), 'L-26', 1, fn_agri_today_cdmx() - interval '26 years') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L26', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha, planting_date)
    VALUES (3, pg_temp.id('P3B2'), 'L-22', 1, fn_agri_today_cdmx() - interval '22 years') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L22', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha)
    VALUES (3, pg_temp.id('P3B2'), 'L-SF', 1) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LSF', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha)
    VALUES (6, pg_temp.id('P6'), 'L-01', 5) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L6', r.id);
    PERFORM pg_temp.ok('T14 lots created (same lot code allowed in another plantation / company)', true);

    -- Per-lot tenure: P3B2 is PROPIA without lessor; L-26 overrides with RENTADA + lessor, L-22 inherits.
    UPDATE agri_lots SET tenure = 'RENTADA', lessor_name = 'Ejido La Esperanza' WHERE id = pg_temp.id('L26');
    PERFORM pg_temp.ok('T14b lot tenure override and inheritance (effective_tenure / effective_lessor_name)',
        (SELECT effective_tenure = 'RENTADA' AND effective_lessor_name = 'Ejido La Esperanza'
           FROM vw_agri_lot_summary WHERE id = pg_temp.id('L26'))
        AND (SELECT tenure IS NULL AND effective_tenure = 'PROPIA' AND effective_lessor_name IS NULL
               FROM vw_agri_lot_summary WHERE id = pg_temp.id('L22')));
    UPDATE agri_plantations SET tenure = 'RENTADA', lessor_name = 'Arrendador de la plantación' WHERE id = pg_temp.id('P3B2');
    PERFORM pg_temp.ok('T14c an inheriting lot follows the plantation lessor; an overriding lot keeps its own',
        (SELECT effective_tenure = 'RENTADA' AND effective_lessor_name = 'Arrendador de la plantación'
           FROM vw_agri_lot_summary WHERE id = pg_temp.id('L22'))
        AND (SELECT effective_lessor_name = 'Ejido La Esperanza' FROM vw_agri_lot_summary WHERE id = pg_temp.id('L26')));
    UPDATE agri_plantations SET tenure = 'PROPIA', lessor_name = NULL WHERE id = pg_temp.id('P3B2');
END $$;
SELECT pg_temp.expect_error('T14d lot lessor only when the lot tenure is RENTADA',
    $q$UPDATE agri_lots SET tenure = 'PROPIA', lessor_name = 'X' WHERE id = pg_temp.id('L22')$q$, '23514');
SELECT pg_temp.expect_error('T14e a lessor on a lot that inherits its tenure is rejected (NULL-safe CHECK)',
    $q$UPDATE agri_lots SET tenure = NULL, lessor_name = 'X' WHERE id = pg_temp.id('L22')$q$, '23514');
SELECT pg_temp.expect_error('T14f invalid lot tenure rejected',
    $q$UPDATE agri_lots SET tenure = 'PRESTADA' WHERE id = pg_temp.id('L22')$q$, '23514');
SELECT pg_temp.expect_error('T15 duplicate lot code in the same plantation (case-insensitive) rejected',
    $q$INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (3, pg_temp.id('P3A'), 'l-01', 1)$q$, '23505');
SELECT pg_temp.expect_error('T16 a lot cannot move to another plantation',
    $q$UPDATE agri_lots SET plantation_id = pg_temp.id('P3B2') WHERE id = pg_temp.id('L1')$q$, 'P0082');
SELECT pg_temp.expect_error('T16b a lot cannot change company',
    $q$UPDATE agri_lots SET id_company = 6 WHERE id = pg_temp.id('L1')$q$, 'P0082');
SELECT pg_temp.expect_error('T16c an inactive variety cannot be assigned',
    $q$UPDATE agri_variety_catalog SET is_active = false WHERE variety_code = 'DURA';
       UPDATE agri_lots SET variety_id = (SELECT id FROM agri_variety_catalog WHERE variety_code = 'DURA') WHERE id = pg_temp.id('L2')$q$, 'P0080');

-- T17..T22 rows and bulk creation
DO $$
DECLARE v_res jsonb; v_n integer; v_h integer;
BEGIN
    v_res := sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 1, 50, 20, 'fjpimienta@gmail.com');
    SELECT count(*) INTO v_n FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND is_active AND alive_plants = 20 AND planting_positions = 20;
    SELECT count(*) INTO v_h FROM agri_row_census_history h JOIN agri_rows r ON r.id = h.row_id
     WHERE r.lot_id = pg_temp.id('L1') AND h.reason = 'ALTA' AND h.changed_by = 'fjpimienta@gmail.com';
    PERFORM pg_temp.ok('T17 bulk create 1..50 x 20: 50 rows alive=positions, 50 ALTA history rows with actor',
        (v_res->>'created')::int = 50 AND v_n = 50 AND v_h = 50, format('created=%s rows=%s history=%s', v_res->>'created', v_n, v_h));
END $$;
SELECT pg_temp.expect_error('T18 bulk range overlapping active rows rejected',
    $q$SELECT sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 45, 60, 20, 'fjpimienta@gmail.com')$q$, 'P0086');
SELECT pg_temp.ok('T18b nothing created by the rejected overlap',
    (SELECT count(*) FROM agri_rows WHERE lot_id = pg_temp.id('L1')) = 50);
SELECT pg_temp.expect_error('T19 more than 500 rows per call rejected',
    $q$SELECT sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 100, 600, 20, 'fjpimienta@gmail.com')$q$, 'P0085');
SELECT pg_temp.expect_error('T19b from_row > to_row rejected',
    $q$SELECT sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 80, 70, 20, 'fjpimienta@gmail.com')$q$, 'P0085');
SELECT pg_temp.expect_error('T19c bulk into a lot of another company rejected',
    $q$SELECT sp_agri_bulk_create_rows(3, pg_temp.id('L6'), 1, 5, 20, 'fjpimienta@gmail.com')$q$, 'P0080');
UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
SELECT pg_temp.expect_error('T20 EDITOR cannot bulk-create rows',
    $q$SELECT sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 51, 60, 20, 'fjpimienta@gmail.com')$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;

DO $$
DECLARE r record; v_res jsonb;
BEGIN
    -- Single row through the procedure (the gateway cannot write planting_positions any more).
    v_res := sp_agri_bulk_create_rows(3, pg_temp.id('L1'), 51, 51, 10, 'fjpimienta@gmail.com');
    SELECT id, alive_plants, planting_positions INTO STRICT r FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND row_number = 51;
    INSERT INTO t_id VALUES ('R51', r.id);
    PERFORM pg_temp.ok('T21 single row (from = to) via procedure: alive = positions, history note "Alta de fila 51"',
        (v_res->>'created')::int = 1 AND r.alive_plants = 10 AND r.planting_positions = 10
        AND (SELECT notes FROM agri_row_census_history WHERE row_id = r.id AND reason = 'ALTA') = 'Alta de fila 51');
    INSERT INTO t_id SELECT 'R1', id FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND row_number = 1;
    INSERT INTO t_id SELECT 'R2', id FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND row_number = 2;
    INSERT INTO t_id SELECT 'R5', id FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND row_number = 5;
END $$;
SELECT pg_temp.expect_error('T21b planting_positions cannot be changed outside the procedure',
    $q$UPDATE agri_rows SET planting_positions = 25 WHERE id = pg_temp.id('R2')$q$, 'P0087');
SELECT pg_temp.expect_error('T21c positions below the count rejected using FINAL values (ADMIN, positions 5, alive 20)',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R2'), 20, 'CORRECCION_CAPTURA', NULL, NULL, 'fjpimienta@gmail.com', 5)$q$, 'P0087');
SELECT pg_temp.expect_error('T21d the CHECK still guards the table (direct SQL with the procedure flag set)',
    $q$SELECT set_config('app.agri_census_reason', 'CORRECCION_CAPTURA', true);
       UPDATE agri_rows SET planting_positions = 5 WHERE id = pg_temp.id('R2')$q$, '23514');
SELECT pg_temp.expect_error('T22 duplicate active row number in a lot rejected',
    $q$INSERT INTO agri_rows (id_company, lot_id, row_number, planting_positions) VALUES (3, pg_temp.id('L1'), 5, 20)$q$, '23505');
DO $$
BEGIN
    UPDATE agri_rows SET is_active = false WHERE id = pg_temp.id('R5');
    INSERT INTO agri_rows (id_company, lot_id, row_number, planting_positions) VALUES (3, pg_temp.id('L1'), 5, 18);
    PERFORM pg_temp.ok('T22b row number reusable after deactivating the old row', true);
END $$;
SELECT pg_temp.expect_error('T22c row of company 3 under a lot of company 6 rejected',
    $q$INSERT INTO agri_rows (id_company, lot_id, row_number, planting_positions) VALUES (3, pg_temp.id('L6'), 1, 10)$q$, 'P0080');
SELECT pg_temp.expect_error('T22d a row cannot move to another lot',
    $q$UPDATE agri_rows SET lot_id = pg_temp.id('L2') WHERE id = pg_temp.id('R1')$q$, 'P0082');

-- T23..T27 census
DO $$
DECLARE v_res jsonb; h record;
BEGIN
    UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
    v_res := sp_agri_record_row_census(3, pg_temp.id('R1'), 18, 'perdida', fn_agri_today_cdmx() - 1, 'Dos palmas caídas', 'FJPimienta@gmail.com');
    -- now() is constant inside the transaction: select the census row by reason, not by changed_at.
    SELECT * INTO h FROM agri_row_census_history WHERE row_id = pg_temp.id('R1') AND reason <> 'ALTA';
    PERFORM pg_temp.ok('T23 EDITOR records a census: alive updated, history PERDIDA with actor and notes',
        (SELECT alive_plants FROM agri_rows WHERE id = pg_temp.id('R1')) = 18
        AND (SELECT last_census_date FROM agri_rows WHERE id = pg_temp.id('R1')) = fn_agri_today_cdmx() - 1
        AND h.reason = 'PERDIDA' AND h.previous_alive = 20 AND h.new_alive = 18
        AND h.changed_by = 'fjpimienta@gmail.com' AND h.notes = 'Dos palmas caídas', v_res::text);
    UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
    PERFORM pg_temp.ok('T23b procedure settings are reset after the call',
        fn_agri_setting('app.agri_census_reason') IS NULL AND fn_agri_setting('app.agri_census_user') IS NULL);
END $$;
DO $$
DECLARE v_res jsonb; v_before integer; v_after integer; h record;
BEGIN
    -- CENSO confirming the same count: one explicit history row with previous = new.
    SELECT count(*) INTO v_before FROM agri_row_census_history WHERE row_id = pg_temp.id('R1');
    v_res := sp_agri_record_row_census(3, pg_temp.id('R1'), 18, 'CENSO', NULL, 'Conteo de confirmación', 'fjpimienta@gmail.com');
    SELECT count(*) INTO v_after FROM agri_row_census_history WHERE row_id = pg_temp.id('R1');
    SELECT * INTO h FROM agri_row_census_history WHERE row_id = pg_temp.id('R1') AND reason = 'CENSO';
    PERFORM pg_temp.ok('T23c CENSO with an unchanged count still logs one row (previous = new) with actor',
        NOT (v_res->>'changed')::boolean AND v_after = v_before + 1
        AND h.previous_alive = 18 AND h.new_alive = 18 AND h.previous_positions = h.new_positions
        AND h.changed_by = 'fjpimienta@gmail.com' AND h.notes = 'Conteo de confirmación', v_res::text);

    -- CENSO with a change: exactly one row (the trigger's), never a duplicate from the procedure.
    v_before := v_after;
    v_res := sp_agri_record_row_census(3, pg_temp.id('R1'), 17, 'CENSO', NULL, NULL, 'fjpimienta@gmail.com');
    SELECT count(*) INTO v_after FROM agri_row_census_history WHERE row_id = pg_temp.id('R1');
    PERFORM pg_temp.ok('T23d CENSO with a change logs exactly one row (no duplicate)',
        (v_res->>'changed')::boolean AND v_after = v_before + 1
        AND EXISTS (SELECT 1 FROM agri_row_census_history WHERE row_id = pg_temp.id('R1')
                     AND reason = 'CENSO' AND previous_alive = 18 AND new_alive = 17));

    -- Other reasons with an unchanged count do not add a row.
    v_before := v_after;
    v_res := sp_agri_record_row_census(3, pg_temp.id('R1'), 17, 'RESIEMBRA', NULL, NULL, 'fjpimienta@gmail.com');
    SELECT count(*) INTO v_after FROM agri_row_census_history WHERE row_id = pg_temp.id('R1');
    PERFORM pg_temp.ok('T23e non-CENSO reason without changes adds no history row', v_after = v_before);
END $$;
SELECT pg_temp.expect_error('T24 census above planting positions rejected',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R1'), 21, 'CENSO', NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0087');
SELECT pg_temp.expect_error('T24b invalid reason rejected (ALTA is not a census reason)',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R1'), 10, 'ALTA', NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0087');
SELECT pg_temp.expect_error('T24c future census date rejected',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R1'), 10, 'CENSO', fn_agri_today_cdmx() + 1, NULL, 'fjpimienta@gmail.com')$q$, 'P0083');
SELECT pg_temp.expect_error('T24d census on a row of another company rejected (no leak)',
    $q$SELECT sp_agri_record_row_census(6, pg_temp.id('R1'), 10, 'CENSO', NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0080');
SELECT pg_temp.expect_error('T24e census on an inactive row rejected',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R5'), 10, 'CENSO', NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0081');
UPDATE user_companies SET role = 'CUSTOMER' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
SELECT pg_temp.expect_error('T25 CUSTOMER (read-only) cannot record a census',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R1'), 10, 'CENSO', NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
SELECT pg_temp.expect_error('T25b alive_plants cannot be changed outside the procedure',
    $q$UPDATE agri_rows SET alive_plants = 3 WHERE id = pg_temp.id('R2')$q$, 'P0087');
DO $$
DECLARE h record; v_res jsonb;
BEGIN
    v_res := sp_agri_record_row_census(3, pg_temp.id('R2'), 20, 'CORRECCION_CAPTURA', NULL, 'Recuento de puntos', 'fjpimienta@gmail.com', 25);
    SELECT * INTO h FROM agri_row_census_history WHERE row_id = pg_temp.id('R2') AND reason <> 'ALTA';
    PERFORM pg_temp.ok('T26 ADMIN changes planting positions via the procedure: history with reason and actor',
        h.reason = 'CORRECCION_CAPTURA' AND h.previous_positions = 20 AND h.new_positions = 25
        AND h.previous_alive = 20 AND h.new_alive = 20 AND h.changed_by = 'fjpimienta@gmail.com'
        AND (SELECT planting_positions FROM agri_rows WHERE id = pg_temp.id('R2')) = 25, v_res::text);

    UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
    v_res := sp_agri_record_row_census(3, pg_temp.id('R2'), 24, 'PERDIDA', NULL, NULL, 'fjpimienta@gmail.com', 25);
    PERFORM pg_temp.ok('T26b EDITOR may send the current positions unchanged and record the count',
        (v_res->>'alive_plants')::int = 24 AND (v_res->>'planting_positions')::int = 25, v_res::text);
END $$;
SELECT pg_temp.expect_error('T26c EDITOR cannot change planting positions',
    $q$SELECT sp_agri_record_row_census(3, pg_temp.id('R2'), 20, 'CORRECCION_CAPTURA', NULL, NULL, 'fjpimienta@gmail.com', 30)$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 3;
SELECT pg_temp.expect_error('T27 history is append-only (UPDATE)',
    $q$UPDATE agri_row_census_history SET reason = 'CENSO' WHERE row_id = pg_temp.id('R1')$q$, 'P0089');
SELECT pg_temp.expect_error('T27b history is append-only (DELETE)',
    $q$DELETE FROM agri_row_census_history WHERE row_id = pg_temp.id('R1')$q$, 'P0089');
SELECT pg_temp.expect_error('T27c history row must belong to the company of its row',
    $q$INSERT INTO agri_row_census_history (row_id, id_company, new_positions, new_alive, reason)
       VALUES (pg_temp.id('R1'), 6, 1, 1, 'CENSO')$q$, 'P0080');

-- T28..T31 views
DO $$
DECLARE s record; p record;
BEGIN
    SELECT * INTO s FROM vw_agri_lot_summary WHERE id = pg_temp.id('L1');
    PERFORM pg_temp.ok('T28 lot summary counts match the rows',
        s.active_rows = (SELECT count(*) FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND is_active)
        AND s.planting_positions = (SELECT sum(planting_positions) FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND is_active)
        AND s.alive_plants = (SELECT sum(alive_plants) FROM agri_rows WHERE lot_id = pg_temp.id('L1') AND is_active)
        AND s.missing_plants = s.planting_positions - s.alive_plants
        AND s.real_density_plants_ha = round(s.alive_plants / 20.0, 1)
        AND s.density_pct_of_design = round(100.0 * s.alive_plants / 20.0 / 143, 1)
        AND s.variety_code = 'TENERA',
        format('rows=%s positions=%s alive=%s missing=%s density=%s pct=%s',
               s.active_rows, s.planting_positions, s.alive_plants, s.missing_plants, s.real_density_plants_ha, s.density_pct_of_design));
    PERFORM pg_temp.ok('T29 productive stage by completed years (10, 2, 26, 22, no date)',
        (SELECT productive_stage FROM vw_agri_lot_summary WHERE id = pg_temp.id('L1'))  = 'PRODUCCION_PLENA'
        AND (SELECT productive_stage FROM vw_agri_lot_summary WHERE id = pg_temp.id('L2'))  = 'INMADURA'
        AND (SELECT productive_stage FROM vw_agri_lot_summary WHERE id = pg_temp.id('L26')) = 'RENOVACION'
        AND (SELECT productive_stage FROM vw_agri_lot_summary WHERE id = pg_temp.id('L22')) = 'PRODUCCION_DECLINANTE'
        AND (SELECT productive_stage FROM vw_agri_lot_summary WHERE id = pg_temp.id('LSF')) = 'SIN_FECHA');
    SELECT * INTO p FROM vw_agri_plantation_summary WHERE id = pg_temp.id('P3A');
    PERFORM pg_temp.ok('T30 plantation summary: planted area = sum of active lots, inconsistency flagged (110 > 100)',
        p.active_lots = 2 AND p.planted_area_ha = 110 AND p.has_area_inconsistency
        AND p.alive_plants = (SELECT alive_plants FROM vw_agri_lot_summary WHERE id = pg_temp.id('L1'))
                           + (SELECT alive_plants FROM vw_agri_lot_summary WHERE id = pg_temp.id('L2')),
        format('lots=%s planted=%s flag=%s', p.active_lots, p.planted_area_ha, p.has_area_inconsistency));
    PERFORM pg_temp.ok('T30b no inconsistency when lots fit (P3B2: 3 ha of 60)',
        NOT (SELECT has_area_inconsistency FROM vw_agri_plantation_summary WHERE id = pg_temp.id('P3B2')));
    PERFORM pg_temp.ok('T31 views filtered by id_company never mix companies',
        NOT EXISTS (SELECT 1 FROM vw_agri_lot_summary WHERE id_company = 3 AND id = pg_temp.id('L6'))
        AND NOT EXISTS (SELECT 1 FROM vw_agri_plantation_summary WHERE id_company = 3 AND id = pg_temp.id('P6'))
        AND (SELECT count(*) FROM vw_agri_lot_summary WHERE id_company = 6 AND lot_code LIKE 'L-%') = 1);
END $$;

-- T32..T33 parent activity
SELECT pg_temp.expect_error('T32 a lot cannot be reactivated while its plantation is inactive',
    $q$UPDATE agri_lots SET is_active = false WHERE id = pg_temp.id('L2');
       UPDATE agri_plantations SET is_active = false WHERE id = pg_temp.id('P3A');
       UPDATE agri_lots SET is_active = true WHERE id = pg_temp.id('L2')$q$, 'P0081');
SELECT pg_temp.expect_error('T32b a row cannot be created in a lot whose plantation is inactive',
    $q$UPDATE agri_plantations SET is_active = false WHERE id = pg_temp.id('P3A');
       INSERT INTO agri_rows (id_company, lot_id, row_number, planting_positions) VALUES (3, pg_temp.id('L1'), 99, 10)$q$, 'P0081');
-- Company 3 is the test tenant; its deactivation lives only inside this sub-transaction.
SELECT pg_temp.expect_error('T33 plantation in an inactive company rejected',
    $q$UPDATE companys SET is_active = false WHERE id_company = 3;
       INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
       VALUES (3, 'QA-IN', 'x', 1, 'PROPIA')$q$, 'P0081');
SELECT pg_temp.ok('T33b company 3 still active after the rejected sub-transaction',
    (SELECT is_active FROM companys WHERE id_company = 3));

-- T34..T35 crud_models
SELECT pg_temp.ok('T34 10 agri_* models registered, none with id in allowed_fields, none with DELETE',
    (SELECT count(*) FROM crud_models WHERE model_name = ANY (ARRAY['agri_variety_catalog', 'agri_plantations', 'agri_lots', 'agri_rows', 'agri_row_census_history',
                         'agri_lot_summary', 'agri_plantation_summary', 'agri_set_default_plantation',
                         'agri_bulk_create_rows', 'agri_record_row_census'])) = 10
    AND NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name LIKE 'agri\_%' AND (allowed_fields ? 'id' OR 'DELETE' = ANY (allowed_ops)))
    AND NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name IN ('agri_plantations','agri_lots','agri_rows')
                     AND (allowed_fields ? 'is_default' OR allowed_fields ? 'alive_plants' OR allowed_fields ? 'last_census_date'
                          OR allowed_fields ? 'planting_positions'))
    AND (SELECT allowed_fields ? 'tenure' AND allowed_fields ? 'lessor_name' FROM crud_models WHERE model_name = 'agri_lots')
    AND (SELECT allowed_fields ? 'planting_positions' FROM crud_models WHERE model_name = 'agri_record_row_census')
    AND (SELECT allowed_roles_insert FROM crud_models WHERE model_name = 'agri_record_row_census') = 'ADMIN,OWNER,EDITOR'
    AND (SELECT allowed_roles_insert FROM crud_models WHERE model_name = 'agri_bulk_create_rows') = 'ADMIN,OWNER');
SELECT pg_temp.ok('T34b agri_rows has no INSERT op (rows only via sp_agri_bulk_create_rows); UPDATE stays ADMIN/OWNER',
    (SELECT NOT ('INSERT' = ANY (allowed_ops)) AND 'UPDATE' = ANY (allowed_ops)
            AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'ADMIN,OWNER'
       FROM crud_models WHERE model_name = 'agri_rows'));
SELECT pg_temp.ok('T35 PalmTelemetry: no DELETE, UPDATE only ADMIN',
    (SELECT NOT ('DELETE' = ANY (allowed_ops)) AND allowed_roles_update = 'ADMIN' AND allowed_roles_delete = 'NONE'
       FROM crud_models WHERE model_name = 'PalmTelemetry'));

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '080 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 080 tests: everything rolled back ***'
