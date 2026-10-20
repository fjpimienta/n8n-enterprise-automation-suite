-- 081_tests.sql — functional checks for migration 081 (LOCAL only). EVERYTHING is rolled back at the end.
-- Loads 081_agri_expenses.sql inside this transaction (embedded mode), so it runs the same way before and
-- after 081 is applied. Uses company 10 (palm test tenant), company 3 (livestock test tenant, for the domain
-- check) and company 6 (only inside this transaction: its plantation, categories, expense and a temporary
-- ADMIN membership are rolled back). Company 7 (real client) is only read.
--
-- Run (the migrations folder must be visible to psql because of \ir):
--   docker cp database/migrations n8n-enterprise-db:/tmp/m081
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1 -f /tmp/m081/081_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 081_agri_expenses.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_id (k text PRIMARY KEY, v uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.id(p_key text) RETURNS uuid
LANGUAGE sql AS $$ SELECT v FROM t_id WHERE k = p_key $$;

-- Category id of a company by code (active row).
CREATE FUNCTION pg_temp.cat(p_company integer, p_code text) RETURNS uuid
LANGUAGE sql AS $$ SELECT id FROM agri_expense_categories WHERE id_company = p_company AND category_code = p_code AND is_active $$;

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

-- Shorthand: record an expense of company p_company as the test actor.
CREATE FUNCTION pg_temp.rec(p_company integer, p_plantation uuid, p_lot uuid, p_category uuid, p_date date,
                            p_amount numeric, p_quantity numeric DEFAULT NULL, p_unit text DEFAULT NULL,
                            p_invoiced boolean DEFAULT false, p_folio text DEFAULT NULL) RETURNS jsonb
LANGUAGE sql AS $$
    SELECT sp_agri_record_expense(p_company, p_plantation, p_lot, p_category, p_date, p_amount, p_quantity, p_unit,
                                  'Proveedor QA', 'Gasto de prueba', p_invoiced, p_folio, 'fjpimienta@gmail.com')
$$;

DO $$
DECLARE
    c_actor constant text := 'fjpimienta@gmail.com';
    r record;
BEGIN
    -- Test actor: ADMIN of 10 and 3 (already) and, only inside this transaction, ADMIN of 6.
    INSERT INTO user_companies (email, id_company, role, is_active) VALUES (c_actor, 10, 'ADMIN', true), (c_actor, 6, 'ADMIN', true)
    ON CONFLICT (email, id_company) DO UPDATE SET role = 'ADMIN', is_active = true;

    -- Own plantations and lots for the tests (company 10 keeps its QA data untouched).
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (10, 'QA-EXP-A', 'Plantación gastos A', 100, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('PA', r.id);
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (10, 'QA-EXP-B', 'Plantación gastos B', 50, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('PB', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (10, pg_temp.id('PA'), 'QA-LA1', 10)
    RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LA1', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (10, pg_temp.id('PA'), 'QA-LA2', 10)
    RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LA2', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (10, pg_temp.id('PB'), 'QA-LB1', 10)
    RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LB1', r.id);
END $$;

-- T01..T05 domain, catalogs and seeding
SELECT pg_temp.ok('T01 business domain: 10 and 7 PALM, 3/5/6 LIVESTOCK, 1 NULL',
    fn_company_business_domain(10) = 'PALM' AND fn_company_business_domain(7) = 'PALM'
    AND fn_company_business_domain(3) = 'LIVESTOCK' AND fn_company_business_domain(5) = 'LIVESTOCK'
    AND fn_company_business_domain(6) = 'LIVESTOCK' AND fn_company_business_domain(1) IS NULL
    AND fn_company_business_domain(-1) IS NULL);
SELECT pg_temp.ok('T02 unit catalog seeded (9)',
    (SELECT count(*) FROM agri_unit_catalog WHERE unit_code IN ('KG','TON','L','PZA','BULTO','JORNAL','HA','VIAJE','SERVICIO')) = 9);
SELECT pg_temp.ok('T03 company 10 has the 13 initial categories; company 7 (no plantation) has none',
    (SELECT count(*) FROM agri_expense_categories WHERE id_company = 10 AND is_active) = 13
    AND NOT EXISTS (SELECT 1 FROM agri_expense_categories WHERE id_company = 7)
    AND NOT EXISTS (SELECT 1 FROM agri_plantations WHERE id_company = 7),
    (SELECT count(*)::text FROM agri_expense_categories WHERE id_company = 10));
DO $$
DECLARE r record; v_n1 integer; v_n2 integer;
BEGIN
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (6, 'QA-EXP-6', 'Plantación gastos empresa 6', 10, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P6', r.id);
    SELECT count(*) INTO v_n1 FROM agri_expense_categories WHERE id_company = 6;
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (6, 'QA-EXP-6B', 'Segunda plantación empresa 6', 10, 'PROPIA');
    SELECT count(*) INTO v_n2 FROM agri_expense_categories WHERE id_company = 6;
    PERFORM pg_temp.ok('T04 first plantation of a company seeds 13 categories; a second one does not duplicate them',
        v_n1 = 13 AND v_n2 = 13, format('first=%s second=%s', v_n1, v_n2));
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, area_ha) VALUES (6, pg_temp.id('P6'), 'QA-L6', 5)
    RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L6', r.id);
    PERFORM pg_temp.ok('T05 seeding is idempotent (0 when the company already has categories)',
        fn_agri_seed_expense_categories(10) = 0 AND fn_agri_seed_expense_categories(6) = 0);
END $$;
SELECT pg_temp.expect_error('T05b a company that retired every category does not get them back with a new plantation',
    $q$UPDATE agri_expense_categories SET is_active = false WHERE id_company = 6;
       INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
       VALUES (6, 'QA-EXP-6C', 'x', 1, 'PROPIA');
       DO $d$ BEGIN
           IF (SELECT count(*) FROM agri_expense_categories WHERE id_company = 6 AND is_active) = 0 THEN
               RAISE EXCEPTION 'not reseeded' USING ERRCODE = 'P0999';
           END IF;
       END $d$$q$, 'P0999');

-- T06..T09 category catalog
SELECT pg_temp.expect_error('T06 duplicate active category code in the company rejected (code normalized to upper case)',
    $q$INSERT INTO agri_expense_categories (id_company, category_code, category_name) VALUES (10, ' riego ', 'Riego 2')$q$, '23505');
SELECT pg_temp.expect_error('T06b duplicate active category name (case/space-insensitive) rejected',
    $q$INSERT INTO agri_expense_categories (id_company, category_code, category_name) VALUES (10, 'RIEGO_2', ' riego ')$q$, '23505');
DO $$
DECLARE r record;
BEGIN
    INSERT INTO agri_expense_categories (id_company, category_code, category_name) VALUES (3, 'RIEGO', 'Riego');
    UPDATE agri_expense_categories SET is_active = false WHERE id_company = 10 AND category_code = 'OTROS';
    INSERT INTO agri_expense_categories (id_company, category_code, category_name, sort_order)
    VALUES (10, 'otros', 'Otros', 140) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('C_OTROS2', r.id);
    PERFORM pg_temp.ok('T07 same code in another company and after deactivation allowed (code stored upper case)',
        (SELECT category_code FROM agri_expense_categories WHERE id = r.id) = 'OTROS');
    UPDATE agri_expense_categories SET category_name = 'Otros gastos' WHERE id = r.id;
    PERFORM pg_temp.ok('T07b the name can be edited',
        (SELECT category_name FROM agri_expense_categories WHERE id = r.id) = 'Otros gastos');
END $$;
SELECT pg_temp.expect_error('T08 category code is immutable',
    $q$UPDATE agri_expense_categories SET category_code = 'OTROS_GASTOS' WHERE id = pg_temp.id('C_OTROS2')$q$, 'P0082');
SELECT pg_temp.expect_error('T08b category company is immutable',
    $q$UPDATE agri_expense_categories SET id_company = 6 WHERE id = pg_temp.id('C_OTROS2')$q$, 'P0082');
SELECT pg_temp.expect_error('T09 invalid category code format rejected',
    $q$INSERT INTO agri_expense_categories (id_company, category_code, category_name) VALUES (10, 'CON ESPACIO-Y', 'x')$q$, '23514');

-- T10..T13 recording
DO $$
DECLARE v_res jsonb; e record;
BEGIN
    v_res := sp_agri_record_expense(10, NULL, NULL, pg_temp.cat(10, 'GASTOS_ADMINISTRATIVOS'), NULL, 1500.50, NULL, NULL,
                                    '  ', ' Papelería ', NULL, NULL, '  FJPimienta@Gmail.com ');
    SELECT * INTO e FROM agri_expenses WHERE id = (v_res->>'expense_id')::uuid;
    INSERT INTO t_id VALUES ('E_GEN', e.id);
    PERFORM pg_temp.ok('T10 ADMIN records a general expense: today CDMX by default, actor normalized, blanks to NULL, no amount in the answer',
        e.plantation_id IS NULL AND e.lot_id IS NULL AND e.expense_date = fn_agri_today_cdmx() AND e.amount = 1500.50
        AND e.reported_by_email = 'fjpimienta@gmail.com' AND e.supplier_name IS NULL AND e.description = 'Papelería'
        AND NOT e.is_invoiced AND NOT e.is_void AND NOT (v_res ? 'amount') AND (v_res->>'success')::boolean,
        v_res::text);

    -- Only the lot: the plantation is taken from the lot.
    v_res := pg_temp.rec(10, NULL, pg_temp.id('LA1'), pg_temp.cat(10, 'FERTILIZANTES'), fn_agri_today_cdmx() - 3,
                         10000, 1, 'ton', true, ' F-123 ');
    SELECT * INTO e FROM agri_expenses WHERE id = (v_res->>'expense_id')::uuid;
    INSERT INTO t_id VALUES ('E_LA1', e.id);
    PERFORM pg_temp.ok('T11 lot without plantation: plantation taken from the lot; unit upper-cased; folio trimmed',
        e.plantation_id = pg_temp.id('PA') AND e.lot_id = pg_temp.id('LA1') AND e.unit_code = 'TON' AND e.quantity = 1
        AND e.is_invoiced AND e.invoice_folio = 'F-123', v_res::text);

    UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
    v_res := pg_temp.rec(10, pg_temp.id('PA'), NULL, pg_temp.cat(10, 'MANO_OBRA'), fn_agri_today_cdmx(), 800, 2, 'JORNAL');
    INSERT INTO t_id VALUES ('E_PA', (v_res->>'expense_id')::uuid);
    PERFORM pg_temp.ok('T12 EDITOR records a plantation-level expense', (v_res->>'success')::boolean, v_res::text);
    UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
END $$;
UPDATE user_companies SET role = 'CUSTOMER' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T13 CUSTOMER (read-only) cannot record an expense',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T13b a non-member cannot record an expense (company 7)',
    $q$SELECT pg_temp.rec(7, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0084');
SELECT pg_temp.expect_error('T13c a livestock company is rejected (company 3, ADMIN)',
    $q$SELECT sp_agri_record_expense(3, NULL, NULL, (SELECT id FROM agri_expense_categories WHERE id_company = 3 AND category_code = 'RIEGO'),
                                     NULL, 10, NULL, NULL, NULL, NULL, false, NULL, 'fjpimienta@gmail.com')$q$, 'P0093');

-- T14..T17 isolation and parents
SELECT pg_temp.expect_error('T14 plantation of another company rejected',
    $q$SELECT pg_temp.rec(10, pg_temp.id('P6'), NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0080');
SELECT pg_temp.expect_error('T14b lot of another company rejected (lot only)',
    $q$SELECT pg_temp.rec(10, NULL, pg_temp.id('L6'), pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0080');
SELECT pg_temp.expect_error('T14c category of another company rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, (SELECT id FROM agri_expense_categories WHERE id_company = 6 LIMIT 1), NULL, 10)$q$, 'P0080');
SELECT pg_temp.expect_error('T15 lot outside the given plantation rejected',
    $q$SELECT pg_temp.rec(10, pg_temp.id('PB'), pg_temp.id('LA1'), pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0080');
SELECT pg_temp.expect_error('T16 inactive lot rejected',
    $q$UPDATE agri_lots SET is_active = false WHERE id = pg_temp.id('LA2');
       SELECT pg_temp.rec(10, NULL, pg_temp.id('LA2'), pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0081');
SELECT pg_temp.expect_error('T16b inactive plantation rejected',
    $q$UPDATE agri_plantations SET is_active = false WHERE id = pg_temp.id('PB');
       SELECT pg_temp.rec(10, pg_temp.id('PB'), NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10)$q$, 'P0081');
SELECT pg_temp.expect_error('T17 inactive category rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, (SELECT id FROM agri_expense_categories WHERE id_company = 10 AND category_code = 'OTROS' AND NOT is_active), NULL, 10)$q$, 'P0092');
SELECT pg_temp.expect_error('T17b missing category rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, NULL, NULL, 10)$q$, 'P0092');

-- T18..T21 data validation
SELECT pg_temp.expect_error('T18 future date (CDMX) rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), fn_agri_today_cdmx() + 1, 10)$q$, 'P0083');
SELECT pg_temp.expect_error('T18b future date rejected by the table guard too (direct SQL)',
    $q$INSERT INTO agri_expenses (id_company, category_id, expense_date, amount, reported_by_email)
       VALUES (10, pg_temp.cat(10, 'RIEGO'), fn_agri_today_cdmx() + 1, 10, 'qa@example.test')$q$, 'P0083');
SELECT pg_temp.expect_error('T19 amount 0 rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 0)$q$, 'P0092');
SELECT pg_temp.expect_error('T19b amount with 3 decimals rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10.555)$q$, 'P0092');
SELECT pg_temp.expect_error('T19c amount above numeric(12,2) rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10000000000)$q$, 'P0092');
SELECT pg_temp.expect_error('T20 quantity without unit rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, 5, NULL)$q$, 'P0092');
SELECT pg_temp.expect_error('T20b unit without quantity rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, NULL, 'KG')$q$, 'P0092');
SELECT pg_temp.expect_error('T20c unknown unit rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, 5, 'GALON')$q$, 'P0092');
SELECT pg_temp.expect_error('T20d inactive unit rejected',
    $q$UPDATE agri_unit_catalog SET is_active = false WHERE unit_code = 'VIAJE';
       SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, 1, 'VIAJE')$q$, 'P0092');
SELECT pg_temp.expect_error('T20e zero quantity rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, 0, 'KG')$q$, 'P0092');
SELECT pg_temp.expect_error('T21 invoice folio without "invoiced" rejected',
    $q$SELECT pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'RIEGO'), NULL, 10, NULL, NULL, false, 'F-1')$q$, 'P0092');

-- T22..T24 immutability and direct SQL
SELECT pg_temp.expect_error('T22 an expense cannot be updated',
    $q$UPDATE agri_expenses SET amount = 1 WHERE id = pg_temp.id('E_GEN')$q$, 'P0090');
SELECT pg_temp.expect_error('T22b an expense cannot be voided by direct UPDATE (without the procedure)',
    $q$UPDATE agri_expenses SET is_void = true, void_reason = 'x', voided_by_email = 'x', voided_at = now() WHERE id = pg_temp.id('E_GEN')$q$, 'P0090');
SELECT pg_temp.expect_error('T22c the void flag does not allow changing other columns',
    $q$SELECT set_config('app.agri_expense_void', 'on', true);
       UPDATE agri_expenses SET is_void = true, void_reason = 'x', voided_by_email = 'x', voided_at = now(), amount = 1
        WHERE id = pg_temp.id('E_GEN')$q$, 'P0090');
SELECT pg_temp.expect_error('T23 an expense cannot be deleted',
    $q$DELETE FROM agri_expenses WHERE id = pg_temp.id('E_GEN')$q$, 'P0090');
SELECT pg_temp.expect_error('T23b agri_expenses cannot be truncated',
    $q$TRUNCATE agri_expenses$q$, 'P0090');
SELECT pg_temp.expect_error('T24 direct insert: plantation of another company rejected',
    $q$INSERT INTO agri_expenses (id_company, plantation_id, category_id, expense_date, amount, reported_by_email)
       VALUES (10, pg_temp.id('P6'), pg_temp.cat(10, 'RIEGO'), fn_agri_today_cdmx(), 10, 'qa@example.test')$q$, 'P0080');
SELECT pg_temp.expect_error('T24b direct insert: lot without plantation rejected',
    $q$INSERT INTO agri_expenses (id_company, lot_id, category_id, expense_date, amount, reported_by_email)
       VALUES (10, pg_temp.id('LA1'), pg_temp.cat(10, 'RIEGO'), fn_agri_today_cdmx(), 10, 'qa@example.test')$q$, 'P0092');
SELECT pg_temp.expect_error('T24c direct insert: already voided rejected',
    $q$INSERT INTO agri_expenses (id_company, category_id, expense_date, amount, reported_by_email, is_void, void_reason, voided_by_email, voided_at)
       VALUES (10, pg_temp.cat(10, 'RIEGO'), fn_agri_today_cdmx(), 10, 'qa@example.test', true, 'x', 'x', now())$q$, 'P0092');

-- T25..T27 void
UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T25 EDITOR cannot void',
    $q$SELECT sp_agri_void_expense(10, pg_temp.id('E_GEN'), 'Error de captura', 'fjpimienta@gmail.com')$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T25b void without reason rejected',
    $q$SELECT sp_agri_void_expense(10, pg_temp.id('E_GEN'), '   ', 'fjpimienta@gmail.com')$q$, 'P0091');
SELECT pg_temp.expect_error('T25c void of another company''s expense rejected (no leak)',
    $q$SELECT sp_agri_void_expense(6, pg_temp.id('E_GEN'), 'x', 'fjpimienta@gmail.com')$q$, 'P0080');
DO $$
DECLARE v_res jsonb; e record;
BEGIN
    v_res := sp_agri_void_expense(10, pg_temp.id('E_GEN'), ' Error de captura ', 'FJPimienta@gmail.com');
    SELECT * INTO e FROM agri_expenses WHERE id = pg_temp.id('E_GEN');
    PERFORM pg_temp.ok('T26 ADMIN voids: reason, actor and time recorded; other columns unchanged; flag reset',
        e.is_void AND e.void_reason = 'Error de captura' AND e.voided_by_email = 'fjpimienta@gmail.com'
        AND e.voided_at IS NOT NULL AND e.amount = 1500.50 AND fn_agri_setting('app.agri_expense_void') IS NULL,
        v_res::text);
END $$;
SELECT pg_temp.expect_error('T27 voiding twice rejected',
    $q$SELECT sp_agri_void_expense(10, pg_temp.id('E_GEN'), 'otra vez', 'fjpimienta@gmail.com')$q$, 'P0091');

-- T28..T33 balance and views. Fixed dates in the past so the periods are deterministic.
DO $$
DECLARE v_res jsonb;
BEGIN
    -- 2026-01-05 is a Monday (ISO week 2); 2026-01-11 is the Sunday of that week.
    PERFORM pg_temp.rec(10, NULL, pg_temp.id('LB1'), pg_temp.cat(10, 'RIEGO'), DATE '2026-01-05', 100);
    PERFORM pg_temp.rec(10, NULL, pg_temp.id('LB1'), pg_temp.cat(10, 'RIEGO'), DATE '2026-01-11', 50.25);
    PERFORM pg_temp.rec(10, pg_temp.id('PB'), NULL, pg_temp.cat(10, 'COMBUSTIBLE'), DATE '2026-01-12', 30);
    PERFORM pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'GASTOS_ADMINISTRATIVOS'), DATE '2026-02-01', 20);
    v_res := pg_temp.rec(10, NULL, NULL, pg_temp.cat(10, 'GASTOS_ADMINISTRATIVOS'), DATE '2026-02-02', 999);
    PERFORM sp_agri_void_expense(10, (v_res->>'expense_id')::uuid, 'Duplicado', 'fjpimienta@gmail.com');
END $$;
-- Another company on the same dates: must never appear in company 10. Company 6 is LIVESTOCK (the capture
-- procedure rejects it with P0093), so it is inserted directly: the table guard does not check the domain.
INSERT INTO agri_expenses (id_company, plantation_id, category_id, expense_date, amount, reported_by_email)
VALUES (6, pg_temp.id('P6'), (SELECT id FROM agri_expense_categories WHERE id_company = 6 AND category_code = 'RIEGO'),
        DATE '2026-01-05', 7777, 'qa@example.test');
DO $$
DECLARE v_res jsonb; v_n integer;
BEGIN
    SELECT count(*) INTO v_n FROM agri_expenses WHERE id_company = 10 AND expense_date BETWEEN '2026-01-01' AND '2026-02-28';
    PERFORM pg_temp.ok('T28 balance data in place (5 expenses of company 10 in Jan-Feb 2026, one voided)', v_n = 5, v_n::text);

    v_res := sp_agri_expense_balance(10, DATE '2026-01-01', DATE '2026-02-28', 'month', NULL, NULL, NULL, 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T29 MONTH balance: totals exclude voided and other companies; general amount; periods with zeros',
        (v_res->>'total_amount')::numeric = 200.25 AND (v_res->>'expense_count')::int = 4
        AND (v_res->>'general_amount')::numeric = 20 AND v_res->>'grain' = 'MONTH'
        AND jsonb_array_length(v_res->'by_period') = 2
        AND (v_res->'by_period'->0->>'period_start') = '2026-01-01' AND (v_res->'by_period'->0->>'total_amount')::numeric = 180.25
        AND (v_res->'by_period'->0->>'period_end') = '2026-01-31'
        AND (v_res->'by_period'->1->>'total_amount')::numeric = 20,
        v_res::text);
    PERFORM pg_temp.ok('T29b MONTH balance breakdowns: category, plantation (general as null) and lot',
        (SELECT (x->>'total_amount')::numeric FROM jsonb_array_elements(v_res->'by_category') x WHERE x->>'category_code' = 'RIEGO') = 150.25
        AND (SELECT (x->>'total_amount')::numeric FROM jsonb_array_elements(v_res->'by_plantation') x WHERE x->>'plantation_id' IS NULL) = 20
        AND (SELECT (x->>'total_amount')::numeric FROM jsonb_array_elements(v_res->'by_plantation') x
              WHERE x->>'plantation_id' = pg_temp.id('PB')::text) = 180.25
        AND jsonb_array_length(v_res->'by_lot') = 1
        AND (v_res->'by_lot'->0->>'lot_code') = 'QA-LB1' AND (v_res->'by_lot'->0->>'total_amount')::numeric = 150.25);

    v_res := sp_agri_expense_balance(10, DATE '2026-01-05', DATE '2026-01-18', 'WEEK', NULL, NULL, NULL, 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T30 WEEK balance: ISO weeks start Monday (5 and 11 Jan together, 12 Jan in the next week)',
        jsonb_array_length(v_res->'by_period') = 2
        AND (v_res->'by_period'->0->>'period_start') = '2026-01-05' AND (v_res->'by_period'->0->>'period_end') = '2026-01-11'
        AND (v_res->'by_period'->0->>'total_amount')::numeric = 150.25
        AND (v_res->'by_period'->1->>'total_amount')::numeric = 30, v_res::text);

    v_res := sp_agri_expense_balance(10, DATE '2026-01-01', DATE '2026-01-31', 'DAY', pg_temp.id('PB'), pg_temp.id('LB1'),
                                     pg_temp.cat(10, 'RIEGO'), 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T31 DAY balance with plantation + lot + category filters: 31 days, zeros included',
        jsonb_array_length(v_res->'by_period') = 31 AND (v_res->>'total_amount')::numeric = 150.25
        AND (SELECT count(*) FROM jsonb_array_elements(v_res->'by_period') x WHERE (x->>'total_amount')::numeric > 0) = 2,
        left(v_res::text, 200));

    v_res := sp_agri_expense_balance(10, DATE '2026-01-01', DATE '2026-12-31', 'YEAR', NULL, pg_temp.id('LB1'), NULL, 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T31b YEAR balance filtered by lot only',
        jsonb_array_length(v_res->'by_period') = 1 AND (v_res->>'total_amount')::numeric = 150.25);

    v_res := sp_agri_expense_balance(10, NULL, NULL, NULL, NULL, NULL, NULL, 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T31c defaults: current month (CDMX) up to today, grain MONTH',
        v_res->>'grain' = 'MONTH' AND (v_res->>'date_from')::date = date_trunc('month', fn_agri_today_cdmx()::timestamp)::date
        AND (v_res->>'date_to')::date = fn_agri_today_cdmx(), v_res::text);
END $$;
UPDATE user_companies SET role = 'EDITOR' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T32 EDITOR cannot read the balance',
    $q$SELECT sp_agri_expense_balance(10, NULL, NULL, NULL, NULL, NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0084');
UPDATE user_companies SET role = 'ADMIN' WHERE email = 'fjpimienta@gmail.com' AND id_company = 10;
SELECT pg_temp.expect_error('T32b invalid grain rejected',
    $q$SELECT sp_agri_expense_balance(10, NULL, NULL, 'QUARTER', NULL, NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0092');
SELECT pg_temp.expect_error('T32c reversed range rejected',
    $q$SELECT sp_agri_expense_balance(10, DATE '2026-02-01', DATE '2026-01-01', 'DAY', NULL, NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0092');
SELECT pg_temp.expect_error('T32d DAY range above 366 days rejected',
    $q$SELECT sp_agri_expense_balance(10, DATE '2025-01-01', DATE '2026-01-02', 'DAY', NULL, NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0092');
SELECT pg_temp.expect_error('T32e range of 10 years or more rejected',
    $q$SELECT sp_agri_expense_balance(10, DATE '2016-01-01', DATE '2026-01-01', 'YEAR', NULL, NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0092');
SELECT pg_temp.expect_error('T32f filter by another company''s plantation rejected (no leak)',
    $q$SELECT sp_agri_expense_balance(10, NULL, NULL, NULL, pg_temp.id('P6'), NULL, NULL, 'fjpimienta@gmail.com')$q$, 'P0080');
SELECT pg_temp.expect_error('T32g filter by a lot outside the selected plantation rejected',
    $q$SELECT sp_agri_expense_balance(10, NULL, NULL, NULL, pg_temp.id('PA'), pg_temp.id('LB1'), NULL, 'fjpimienta@gmail.com')$q$, 'P0080');
SELECT pg_temp.expect_error('T32h filter by another company''s category rejected',
    $q$SELECT sp_agri_expense_balance(10, NULL, NULL, NULL, NULL, NULL, (SELECT id FROM agri_expense_categories WHERE id_company = 6 LIMIT 1), 'fjpimienta@gmail.com')$q$, 'P0080');
DO $$
BEGIN
    PERFORM pg_temp.ok('T33 summary view MONTH matches the balance and excludes voided / other companies',
        (SELECT sum(total_amount) FROM vw_agri_expense_summary
          WHERE id_company = 10 AND grain = 'MONTH' AND period_start IN ('2026-01-01', '2026-02-01')) = 200.25
        AND (SELECT sum(expense_count) FROM vw_agri_expense_summary
              WHERE id_company = 10 AND grain = 'MONTH' AND period_start IN ('2026-01-01', '2026-02-01')) = 4
        AND NOT EXISTS (SELECT 1 FROM vw_agri_expense_summary WHERE id_company = 10 AND total_amount = 7777));
    PERFORM pg_temp.ok('T33b summary view: the four grains agree, ISO week, one row per plantation x lot x category',
        (SELECT count(DISTINCT grain) FROM vw_agri_expense_summary WHERE id_company = 10) = 4
        AND (SELECT total_amount FROM vw_agri_expense_summary
              WHERE id_company = 10 AND grain = 'WEEK' AND period_start = '2026-01-05' AND lot_id = pg_temp.id('LB1')) = 150.25
        AND (SELECT period_end FROM vw_agri_expense_summary
              WHERE id_company = 10 AND grain = 'WEEK' AND period_start = '2026-01-05' AND lot_id = pg_temp.id('LB1')) = '2026-01-11'
        AND (SELECT total_amount FROM vw_agri_expense_summary
              WHERE id_company = 10 AND grain = 'YEAR' AND period_start = '2026-01-01' AND category_code = 'RIEGO') = 150.25
        AND (SELECT count(*) FROM vw_agri_expense_summary WHERE id_company = 10 AND grain = 'DAY'
              AND period_start BETWEEN '2026-01-01' AND '2026-02-28') = 4
        AND NOT EXISTS (SELECT 1 FROM vw_agri_expense_summary GROUP BY id HAVING count(*) > 1));
    PERFORM pg_temp.ok('T33c list view shows voided rows flagged, with names, and never mixes companies',
        (SELECT is_void AND void_reason = 'Duplicado' FROM vw_agri_expense_list WHERE id_company = 10 AND amount = 999)
        AND (SELECT lot_code = 'QA-LB1' AND plantation_code = 'QA-EXP-B' AND category_code = 'RIEGO'
               FROM vw_agri_expense_list WHERE id_company = 10 AND expense_date = '2026-01-05')
        AND (SELECT unit_name FROM vw_agri_expense_list WHERE id = pg_temp.id('E_LA1')) = 'Toneladas'
        AND NOT EXISTS (SELECT 1 FROM vw_agri_expense_list WHERE id_company = 10 AND amount = 7777));
END $$;

-- T34..T35 crud_models
SELECT pg_temp.ok('T34 7 models registered: no id in allowed_fields, no DELETE, amounts ADMIN/OWNER read-only',
    (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_unit_catalog','agri_expense_categories','agri_expenses',
        'agri_expense_summary','agri_record_expense','agri_void_expense','agri_expense_balance') AND cardinality(allowed_ops) > 0) = 7
    AND NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name IN ('agri_unit_catalog','agri_expense_categories','agri_expenses',
        'agri_expense_summary','agri_record_expense','agri_void_expense','agri_expense_balance')
        AND (allowed_fields ? 'id' OR 'DELETE' = ANY (allowed_ops)))
    AND (SELECT allowed_roles_select = 'ADMIN,OWNER' AND NOT ('INSERT' = ANY (allowed_ops)) AND NOT ('UPDATE' = ANY (allowed_ops))
           AND table_name = 'vw_agri_expense_list' FROM crud_models WHERE model_name = 'agri_expenses')
    AND (SELECT allowed_roles_select = 'ADMIN,OWNER' FROM crud_models WHERE model_name = 'agri_expense_summary')
    AND (SELECT allowed_roles_insert = 'ADMIN,OWNER,EDITOR' FROM crud_models WHERE model_name = 'agri_record_expense')
    AND (SELECT allowed_roles_insert = 'ADMIN,OWNER' FROM crud_models WHERE model_name = 'agri_void_expense')
    AND (SELECT allowed_roles_insert = 'ADMIN,OWNER' FROM crud_models WHERE model_name = 'agri_expense_balance')
    AND (SELECT allowed_roles_select = 'ADMIN,OWNER,EDITOR' AND allowed_roles_insert = 'ADMIN,OWNER' AND allowed_roles_update = 'ADMIN,OWNER'
           FROM crud_models WHERE model_name = 'agri_expense_categories'));
SELECT pg_temp.ok('T34b unit catalog is read-only through the gateway',
    (SELECT allowed_ops = '{SELECT,GETONE,GETALL}' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE'
       FROM crud_models WHERE model_name = 'agri_unit_catalog'));
SELECT pg_temp.ok('T35 procedure models list exactly the procedure parameters (paramOrder of v6) plus actor_email',
    (SELECT allowed_fields = '["plantation_id","lot_id","category_id","expense_date","amount","quantity","unit_code","supplier_name","description","is_invoiced","invoice_folio","actor_email"]'::jsonb
       FROM crud_models WHERE model_name = 'agri_record_expense')
    AND (SELECT allowed_fields = '["expense_id","reason","actor_email"]'::jsonb FROM crud_models WHERE model_name = 'agri_void_expense')
    AND (SELECT allowed_fields = '["date_from","date_to","grain","plantation_id","lot_id","category_id","actor_email"]'::jsonb
           FROM crud_models WHERE model_name = 'agri_expense_balance'));

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '081 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 081 tests: everything rolled back ***'
