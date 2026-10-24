-- 083_tests.sql — functional checks for migration 083 (LOCAL only). EVERYTHING is rolled back at the end.
-- Loads 083_agri_chat_wrappers.sql inside this transaction (embedded mode), so it runs the same way before and
-- after 083 is applied. Company 10 (palm test tenant) is the main stage with its own QA plantations; company 6 is
-- turned into a palm company ONLY inside this transaction to prove isolation between two palm companies; company 3
-- (livestock) and 1 (unknown domain) check the domain gate; company 7 (real client) is never touched.
-- Test users (memberships added only inside this transaction):
--   ADMIN  fjpimienta@gmail.com            (ADMIN of 10 and, here, of 6)
--   EDITOR fjpimienta@yahoo.com            (EDITOR of 10)
--   OWNER  pistahielo.admin@hosting3m.com  (OWNER of 10)
--   CUSTOMER sanjose.recepcion@hosting3m.com (CUSTOMER of 10)
--   outsider n8n@hosting3m.com             (no membership in 10 nor 6)
--
-- Run (the migrations folder must be visible to psql because of \ir):
--   docker cp database/migrations n8n-enterprise-db:/tmp/m083
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1 -f /tmp/m083/083_tests.sql
-- Output: one line per test (OK / FAIL) and a final summary; it exits non-zero if any test fails.

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 083_agri_chat_wrappers.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_id (k text PRIMARY KEY, v uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;

CREATE FUNCTION pg_temp.id(p_key text) RETURNS uuid
LANGUAGE sql AS $$ SELECT v FROM t_id WHERE k = p_key $$;

-- First issue of an answer for a field (NULL when none).
CREATE FUNCTION pg_temp.iss(p_ans jsonb, p_field text) RETURNS jsonb
LANGUAGE sql AS $$ SELECT e FROM jsonb_array_elements(coalesce(p_ans->'issues', '[]'::jsonb)) e WHERE e->>'field' = p_field LIMIT 1 $$;

CREATE FUNCTION pg_temp.n_exp(p_company integer DEFAULT 10) RETURNS bigint
LANGUAGE sql AS $$ SELECT count(*) FROM agri_expenses WHERE id_company = p_company $$;

-- register_palm_expense shorthand (tenant 10, actor ADMIN, preview by default).
CREATE FUNCTION pg_temp.ex(p_cat text DEFAULT NULL, p_amount text DEFAULT NULL, p_date text DEFAULT NULL,
                           p_pl text DEFAULT NULL, p_lot text DEFAULT NULL, p_qty text DEFAULT NULL,
                           p_unit text DEFAULT NULL, p_sup text DEFAULT NULL, p_desc text DEFAULT NULL,
                           p_inv text DEFAULT NULL, p_folio text DEFAULT NULL, p_conf text DEFAULT 'false',
                           p_force text DEFAULT NULL, p_actor text DEFAULT 'fjpimienta@gmail.com',
                           p_tenant text DEFAULT '10') RETURNS jsonb
LANGUAGE sql AS $$
    SELECT sp_agri_chat_record_expense(p_tenant, p_actor, p_cat, p_amount, p_date, p_pl, p_lot, p_qty, p_unit, p_sup,
                                       p_desc, p_inv, p_folio, p_conf, p_force)
$$;

-- Census shorthand (tenant 10, actor ADMIN, preview by default).
CREATE FUNCTION pg_temp.cen(p_lot text DEFAULT NULL, p_pl text DEFAULT NULL, p_row text DEFAULT NULL, p_alive text DEFAULT NULL,
                            p_reason text DEFAULT NULL, p_date text DEFAULT NULL, p_notes text DEFAULT NULL,
                            p_conf text DEFAULT 'false', p_actor text DEFAULT 'fjpimienta@gmail.com',
                            p_tenant text DEFAULT '10') RETURNS jsonb
LANGUAGE sql AS $$
    SELECT sp_agri_chat_record_row_census(p_tenant, p_actor, p_lot, p_pl, p_row, p_alive, p_reason, p_date, p_notes, p_conf)
$$;

-- Setup ------------------------------------------------------------------------------------------------------

DO $$
DECLARE
    r record;
BEGIN
    INSERT INTO user_companies (email, id_company, role, is_active) VALUES
        ('fjpimienta@gmail.com', 10, 'ADMIN', true),
        ('fjpimienta@gmail.com', 6, 'ADMIN', true),
        ('fjpimienta@yahoo.com', 10, 'EDITOR', true),
        ('pistahielo.admin@hosting3m.com', 10, 'OWNER', true),
        ('sanjose.recepcion@hosting3m.com', 10, 'CUSTOMER', true)
    ON CONFLICT (email, id_company) DO UPDATE SET role = EXCLUDED.role, is_active = true;
    DELETE FROM user_companies WHERE email = 'n8n@hosting3m.com' AND id_company IN (10, 6);

    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (10, 'QA-CHAT-A', 'Plantación QA Chat Alfa', 100, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('PA', r.id);
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (10, 'QA-CHAT-B', 'Plantación QA Chat Beta', 50, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('PB', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha) VALUES (10, pg_temp.id('PA'), 'QA-L01', 'Lote Norte', 10) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LA1', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha) VALUES (10, pg_temp.id('PA'), 'QA-L010', 'Lote Norte Alto', 10) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LA10', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha) VALUES (10, pg_temp.id('PB'), 'QA-L01', 'Lote Sur', 10) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('LB1', r.id);
    PERFORM sp_agri_bulk_create_rows(10, pg_temp.id('LA1'), 1, 5, 22, 'fjpimienta@gmail.com');
    PERFORM sp_agri_bulk_create_rows(10, pg_temp.id('LB1'), 1, 2, 30, 'fjpimienta@gmail.com');
END $$;

-- T01 helpers
SELECT pg_temp.ok('T01a txt: NULL for empty, null and undefined; trims',
    fn_agri_chat_txt('') IS NULL AND fn_agri_chat_txt(' NULL ') IS NULL AND fn_agri_chat_txt('undefined') IS NULL
    AND fn_agri_chat_txt(NULL) IS NULL AND fn_agri_chat_txt('  hola ') = 'hola');
SELECT pg_temp.ok('T01b key: accents, case and punctuation do not matter',
    fn_agri_chat_key('L-01') = fn_agri_chat_key('l 01') AND fn_agri_chat_key('Plantación Ñandú') = 'plantacionnandu');
SELECT pg_temp.ok('T01c num: thousands commas and $ accepted; garbage rejected',
    fn_agri_chat_num('1,300') = 1300 AND fn_agri_chat_num('$1,300.50') = 1300.50 AND fn_agri_chat_num(' 12 ') = 12
    AND fn_agri_chat_num('abc') IS NULL AND fn_agri_chat_num('1e3') IS NULL AND fn_agri_chat_num('-5') IS NULL
    AND fn_agri_chat_num('1.2.3') IS NULL AND fn_agri_chat_num('') IS NULL AND fn_agri_chat_num('1234567890123') IS NULL);
SELECT pg_temp.ok('T01d date: ISO only; impossible dates and words are NULL',
    fn_agri_chat_date('2026-10-24') = DATE '2026-10-24' AND fn_agri_chat_date('2026-10-24T10:00:00Z') = DATE '2026-10-24'
    AND fn_agri_chat_date('2026-02-30') IS NULL AND fn_agri_chat_date('ayer') IS NULL AND fn_agri_chat_date('24/10/2026') IS NULL);

-- T02..T05 the session gate (any tool; the catalog and structure are used as probes)
SELECT pg_temp.ok('T02 garbage tenants are forbidden, never an error',
    (SELECT bool_and(sp_agri_chat_structure(t, 'fjpimienta@gmail.com')->>'status' = 'forbidden')
       FROM unnest(ARRAY['abc', '10; DROP TABLE x', '', '0x10', '-1', '99999999999', ' ', '1.0', 'null']) t)
    AND sp_agri_chat_structure(NULL, 'fjpimienta@gmail.com')->>'status' = 'forbidden',
    (SELECT string_agg(sp_agri_chat_structure(t, 'fjpimienta@gmail.com')->>'status', ',') FROM unnest(ARRAY['abc', '', '99999999999']) t));
SELECT pg_temp.ok('T02b a tenant with trailing spaces is the same tenant (10)',
    sp_agri_chat_structure(' 10 ', 'fjpimienta@gmail.com')->>'status' = 'ok');
SELECT pg_temp.ok('T03a outsider (no membership) is forbidden, also against livestock and palm companies',
    sp_agri_chat_structure('10', 'n8n@hosting3m.com')->>'status' = 'forbidden'
    AND sp_agri_chat_structure('6', 'n8n@hosting3m.com')->>'status' = 'forbidden'
    AND sp_agri_chat_structure('3', 'n8n@hosting3m.com')->>'status' = 'forbidden');
SELECT pg_temp.ok('T03b a member of a livestock / unknown-domain company gets not_palm (3, 1) and, before the flip, 6',
    sp_agri_chat_structure('3', 'fjpimienta@gmail.com')->>'status' = 'not_palm'
    AND sp_agri_chat_structure('1', 'fjpimienta@gmail.com')->>'status' = 'not_palm'
    AND sp_agri_chat_structure('6', 'fjpimienta@gmail.com')->>'status' = 'not_palm');
SELECT pg_temp.ok('T03c an unknown actor / NULL actor / e-mail with other case',
    sp_agri_chat_structure('10', 'nadie@example.test')->>'status' = 'forbidden'
    AND sp_agri_chat_structure('10', NULL)->>'status' = 'forbidden'
    AND sp_agri_chat_structure('10', '  FJPimienta@GMAIL.com ')->>'status' = 'ok');
UPDATE user_companies SET is_active = false WHERE email = 'fjpimienta@yahoo.com' AND id_company = 10;
SELECT pg_temp.ok('T04 an inactive membership is forbidden on every tool',
    sp_agri_chat_structure('10', 'fjpimienta@yahoo.com')->>'status' = 'forbidden'
    AND pg_temp.ex('MANO_OBRA', '100', p_actor => 'fjpimienta@yahoo.com')->>'status' = 'forbidden'
    AND pg_temp.cen('QA-L010', NULL, '1', '5', p_actor => 'fjpimienta@yahoo.com')->>'status' = 'forbidden');
UPDATE user_companies SET is_active = true WHERE email = 'fjpimienta@yahoo.com' AND id_company = 10;

-- T05 catalog
DO $$
DECLARE v jsonb;
BEGIN
    UPDATE agri_plantations SET plantation_name = E'Plantación QA\nChat Alfa\tx' WHERE id = pg_temp.id('PA');
    v := sp_agri_chat_catalog('10', 'fjpimienta@yahoo.com');
    PERFORM pg_temp.ok('T05a catalog: 13 categories, 9 units, QA plantations with lots',
        v->>'status' = 'ok' AND jsonb_array_length(v->'categories') = 13 AND jsonb_array_length(v->'units') = 9
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v->'plantations') p WHERE p->>'code' = 'QA-CHAT-A' AND jsonb_array_length(p->'lots') = 2),
        v->>'status');
    PERFORM pg_temp.ok('T05b catalog: newlines and tabs in names never reach the prompt',
        (v::text) !~ '\\n' AND (v::text) !~ '\\t' AND v::text LIKE '%Plantación QA Chat Alfa x%', left(v::text, 120));
    UPDATE agri_plantations SET plantation_name = 'Plantación QA Chat Alfa' WHERE id = pg_temp.id('PA');
    PERFORM pg_temp.ok('T05d catalog carries the company name and the REAL role of each actor (the prompt shows it)',
        sp_agri_chat_catalog('10', 'fjpimienta@yahoo.com')->>'role' = 'EDITOR' AND sp_agri_chat_catalog('10', 'fjpimienta@gmail.com')->>'role' = 'ADMIN'
        AND sp_agri_chat_catalog('10', 'fjpimienta@gmail.com')->>'company_name' = (SELECT company_name FROM companys WHERE id_company = 10));
    PERFORM pg_temp.ok('T05c catalog is open to every active member (CUSTOMER) and only to them',
        sp_agri_chat_catalog('10', 'sanjose.recepcion@hosting3m.com')->>'status' = 'ok'
        AND sp_agri_chat_catalog('10', 'n8n@hosting3m.com')->>'status' = 'forbidden'
        AND sp_agri_chat_catalog('3', 'fjpimienta@gmail.com')->>'status' = 'not_palm');
END $$;

-- T06 role matrix: tool x role -> gate result ('gate' = passed the gate, answers anything but forbidden / not_palm)
DO $$
DECLARE
    c_a constant text := 'fjpimienta@gmail.com';       c_e constant text := 'fjpimienta@yahoo.com';
    c_o constant text := 'pistahielo.admin@hosting3m.com'; c_c constant text := 'sanjose.recepcion@hosting3m.com';
    v_bad text := '';
    v_actor text;
    v_pass boolean;
BEGIN
    -- explicit matrix (clearer failure messages than a generic loop)
    FOR v_actor IN SELECT unnest(ARRAY[c_a, c_e, c_o, c_c]) LOOP
        v_pass := v_actor IN (c_a, c_e, c_o);
        IF (pg_temp.ex('MANO_OBRA', NULL, p_actor => v_actor)->>'status' <> 'forbidden') <> v_pass THEN v_bad := v_bad || 'register:' || v_actor || ' '; END IF;
        IF (pg_temp.cen(NULL, p_actor => v_actor)->>'status' <> 'forbidden') <> v_pass THEN v_bad := v_bad || 'census:' || v_actor || ' '; END IF;
        v_pass := v_actor IN (c_a, c_o);
        IF (sp_agri_chat_void_expense('10', v_actor, NULL, NULL, 'false')->>'status' <> 'forbidden') <> v_pass THEN v_bad := v_bad || 'void:' || v_actor || ' '; END IF;
        IF (sp_agri_chat_recent_expenses('10', v_actor)->>'status' <> 'forbidden') <> v_pass THEN v_bad := v_bad || 'recent:' || v_actor || ' '; END IF;
        IF (sp_agri_chat_expense_balance('10', v_actor)->>'status' <> 'forbidden') <> v_pass THEN v_bad := v_bad || 'balance:' || v_actor || ' '; END IF;
        IF sp_agri_chat_structure('10', v_actor)->>'status' <> 'ok' THEN v_bad := v_bad || 'structure:' || v_actor || ' '; END IF;
        IF sp_agri_chat_lot_summary('10', v_actor, NULL)->>'status' <> 'need_info' THEN v_bad := v_bad || 'lot_summary:' || v_actor || ' '; END IF;
    END LOOP;
    PERFORM pg_temp.ok('T06 role matrix: register/census ADMIN+OWNER+EDITOR; void/recent/balance ADMIN+OWNER; reads everyone',
        v_bad = '', coalesce(nullif(v_bad, ''), 'matrix ok'));
END $$;

-- T07..T13 register_palm_expense: validation (every case is a preview or need_info; nothing is written)
DO $$
DECLARE
    n0 bigint := pg_temp.n_exp();
    v jsonb;
BEGIN
    v := pg_temp.ex();
    PERFORM pg_temp.ok('T07 nothing given: ONE answer listing both missing fields',
        v->>'status' = 'need_info' AND pg_temp.iss(v, 'category_code')->>'type' = 'missing' AND pg_temp.iss(v, 'amount')->>'type' = 'missing'
        AND jsonb_array_length(v->'issues') = 2, v::text);
    v := pg_temp.ex('MANO_OBRA');
    PERFORM pg_temp.ok('T07b only the amount is missing', jsonb_array_length(v->'issues') = 1 AND pg_temp.iss(v, 'amount')->>'type' = 'missing');
    v := pg_temp.ex(p_amount => '1,300');
    PERFORM pg_temp.ok('T07c only the category is missing', jsonb_array_length(v->'issues') = 1 AND pg_temp.iss(v, 'category_code')->>'type' = 'missing');

    PERFORM pg_temp.ok('T08a amount "1,300" -> 1300', (pg_temp.ex('MANO_OBRA', '1,300')->'summary'->>'amount')::numeric = 1300);
    PERFORM pg_temp.ok('T08b amount "$1,300.50" -> 1300.5', (pg_temp.ex('MANO_OBRA', '$1,300.50')->'summary'->>'amount')::numeric = 1300.5);
    PERFORM pg_temp.ok('T08c bad amounts are invalid (0, -5, 3 decimals, text, 1e3, 99999999999.99)',
        (SELECT bool_and(pg_temp.iss(pg_temp.ex('MANO_OBRA', a), 'amount')->>'type' = 'invalid') FROM unnest(ARRAY['0', '-5', '1300.555', 'mil', '1e3', '99999999999.99']) a),
        (SELECT string_agg(coalesce(pg_temp.iss(pg_temp.ex('MANO_OBRA', a), 'amount')->>'type', pg_temp.ex('MANO_OBRA', a)->>'status'), ',') FROM unnest(ARRAY['0', '-5', '1300.555', 'mil', '1e3', '99999999999.99']) a));

    v := pg_temp.ex('MANO_OBRA', '100');
    PERFORM pg_temp.ok('T09a default date is today in Mexico City', (v->'summary'->>'expense_date')::date = fn_agri_today_cdmx(), v->'summary'->>'expense_date');
    PERFORM pg_temp.ok('T09b future date rejected', pg_temp.iss(pg_temp.ex('MANO_OBRA', '100', (fn_agri_today_cdmx() + 1)::text), 'expense_date')->>'type' = 'invalid');
    PERFORM pg_temp.ok('T09c impossible date and words rejected',
        pg_temp.iss(pg_temp.ex('MANO_OBRA', '100', '2026-02-30'), 'expense_date') IS NOT NULL AND pg_temp.iss(pg_temp.ex('MANO_OBRA', '100', 'ayer'), 'expense_date') IS NOT NULL);
    PERFORM pg_temp.ok('T09d a past date is accepted', pg_temp.ex('MANO_OBRA', '100', (fn_agri_today_cdmx() - 3)::text)->>'status' = 'preview');

    PERFORM pg_temp.ok('T10a category by code, by name and without accents',
        pg_temp.ex('mano_obra', '10')->'summary'->>'category_code' = 'MANO_OBRA'
        AND pg_temp.ex('Mano de obra', '10')->'summary'->>'category_code' = 'MANO_OBRA'
        AND pg_temp.ex('mantenimiento de MAQUINARIA', '10')->'summary'->>'category_code' = 'MANTENIMIENTO_MAQUINARIA'
        AND pg_temp.ex('Servicios (dron/aspersión)', '10')->'summary'->>'category_code' = 'SERVICIOS_DRON_ASPERSION');
    v := pg_temp.ex('BOMBA_DE_AGUA', '10');
    PERFORM pg_temp.ok('T10b unknown category: invalid with the 13 options, never guessed',
        pg_temp.iss(v, 'category_code')->>'type' = 'invalid' AND jsonb_array_length(pg_temp.iss(v, 'category_code')->'options') = 13, v::text);

    PERFORM pg_temp.ok('T11a quantity without unit / unit without quantity are missing',
        pg_temp.iss(pg_temp.ex('RIEGO', '10', p_qty => '3'), 'unit_code')->>'type' = 'missing'
        AND pg_temp.iss(pg_temp.ex('RIEGO', '10', p_unit => 'KG'), 'quantity')->>'type' = 'missing');
    v := pg_temp.ex('RIEGO', '10', p_qty => '3', p_unit => 'XYZ');
    PERFORM pg_temp.ok('T11b unknown unit: invalid with the 9 options', pg_temp.iss(v, 'unit_code')->>'type' = 'invalid' AND jsonb_array_length(pg_temp.iss(v, 'unit_code')->'options') = 9);
    v := pg_temp.ex('FERTILIZANTES', '10', p_qty => '2.5', p_unit => 'bultos');
    PERFORM pg_temp.ok('T11c unit by name resolves; quantity kept', v->'summary'->>'unit_code' = 'BULTO' AND (v->'summary'->>'quantity')::numeric = 2.5, v::text);
    PERFORM pg_temp.ok('T11d quantity 0, negative and 4 decimals are invalid',
        (SELECT bool_and(pg_temp.iss(pg_temp.ex('RIEGO', '10', p_qty => q, p_unit => 'KG'), 'quantity')->>'type' = 'invalid') FROM unnest(ARRAY['0', '-1', '1.2345', 'x']) q));

    PERFORM pg_temp.ok('T12a a folio implies invoiced', (pg_temp.ex('OTROS', '10', p_folio => 'F-123')->'summary'->>'is_invoiced')::boolean);
    PERFORM pg_temp.ok('T12b folio with invoiced = false is invalid', pg_temp.iss(pg_temp.ex('OTROS', '10', p_inv => 'false', p_folio => 'F-1'), 'invoice_folio')->>'type' = 'invalid');
    PERFORM pg_temp.ok('T12c default is not invoiced', NOT (pg_temp.ex('OTROS', '10')->'summary'->>'is_invoiced')::boolean);

    -- scope resolution
    v := pg_temp.ex('OTROS', '10');
    PERFORM pg_temp.ok('T13a no plantation, no lot -> GENERAL, said in the summary', v->'summary'->>'scope' = 'GENERAL' AND v->'summary'->>'scope_label' LIKE 'General%');
    v := pg_temp.ex('OTROS', '10', p_lot => 'QA-L01');
    PERFORM pg_temp.ok('T13b the same lot code in two plantations is ambiguous (2 candidates), never guessed',
        pg_temp.iss(v, 'lot')->>'type' = 'ambiguous' AND jsonb_array_length(pg_temp.iss(v, 'lot')->'candidates') = 2, v::text);
    v := pg_temp.ex('OTROS', '10', p_pl => 'qa chat alfa', p_lot => 'qa l01');
    PERFORM pg_temp.ok('T13c plantation by partial name + lot by code (punctuation-insensitive) -> LOT scope',
        v->'summary'->>'scope' = 'LOT' AND v->'summary'->>'scope_label' LIKE '%QA-L01%', v::text);
    PERFORM pg_temp.ok('T13d exact code wins over partial: QA-L010 is not ambiguous with QA-L01',
        pg_temp.ex('OTROS', '10', p_lot => 'QA-L010')->'summary'->>'scope_label' LIKE '%QA-L010%');
    PERFORM pg_temp.ok('T13e exact lot name resolves ("lote norte" is not "Lote Norte Alto")',
        pg_temp.ex('OTROS', '10', p_lot => 'LOTE NORTE')->'summary'->>'scope_label' LIKE '%QA-L01 —%');
    v := pg_temp.ex('OTROS', '10', p_lot => 'norte');
    PERFORM pg_temp.ok('T13f partial match with 2 lots is ambiguous', pg_temp.iss(v, 'lot')->>'type' = 'ambiguous');
    v := pg_temp.ex('OTROS', '10', p_lot => 'ZZZ-99');
    PERFORM pg_temp.ok('T13g unknown lot: not_found with options (lots of the company)', pg_temp.iss(v, 'lot')->>'type' = 'not_found' AND jsonb_array_length(pg_temp.iss(v, 'lot')->'options') >= 3);
    v := pg_temp.ex('OTROS', '10', p_pl => 'Inexistente');
    PERFORM pg_temp.ok('T13h unknown plantation: not_found with options', pg_temp.iss(v, 'plantation')->>'type' = 'not_found');
    v := pg_temp.ex('OTROS', '10', p_pl => 'QA Chat');
    PERFORM pg_temp.ok('T13i partial plantation name matching Alfa and Beta is ambiguous', pg_temp.iss(v, 'plantation')->>'type' = 'ambiguous');
    PERFORM pg_temp.ok('T13j plantation only -> PLANTATION scope', pg_temp.ex('OTROS', '10', p_pl => 'Beta')->'summary'->>'scope' = 'PLANTATION');
    PERFORM pg_temp.ok('T13k a lot of plantation A asked under plantation B is not_found', pg_temp.iss(pg_temp.ex('OTROS', '10', p_pl => 'Beta', p_lot => 'QA-L010'), 'lot')->>'type' = 'not_found');
    PERFORM pg_temp.ok('T13l punctuation-only names are invalid, not a match-all',
        pg_temp.iss(pg_temp.ex('OTROS', '10', p_lot => '---'), 'lot')->>'type' = 'invalid' AND pg_temp.iss(pg_temp.ex('OTROS', '10', p_pl => '%'), 'plantation')->>'type' = 'invalid');
    PERFORM pg_temp.ok('T13m several problems come back in ONE answer (category, unit, lot)',
        jsonb_array_length(pg_temp.ex('XX', '10', p_lot => 'ZZZ', p_qty => '1', p_unit => 'ZZ')->'issues') = 3);

    PERFORM pg_temp.ok('T14 no preview or rejected request wrote anything', pg_temp.n_exp() = n0, (pg_temp.n_exp() - n0)::text);
    PERFORM pg_temp.ok('T14b confirmed with a missing field writes nothing and says need_info',
        pg_temp.ex('MANO_OBRA', NULL, p_conf => 'true')->>'status' = 'need_info' AND pg_temp.n_exp() = n0);
    PERFORM pg_temp.ok('T14c only the exact word true confirms (TRUE yes 1 sí do not, except TRUE)',
        pg_temp.ex('MANO_OBRA', '11.11', p_desc => 'T14c-a', p_conf => 'yes')->>'status' = 'preview'
        AND pg_temp.ex('MANO_OBRA', '11.11', p_desc => 'T14c-b', p_conf => '1')->>'status' = 'preview'
        AND pg_temp.ex('MANO_OBRA', '11.11', p_desc => 'T14c-c', p_conf => 'sí')->>'status' = 'preview'
        AND pg_temp.ex('MANO_OBRA', '11.11', p_desc => 'T14c-d', p_conf => NULL)->>'status' = 'preview'
        AND pg_temp.n_exp() = n0);
END $$;

-- T15..T21 register_palm_expense: writes
DO $$
DECLARE
    v jsonb; r record; n0 bigint;
BEGIN
    v := pg_temp.ex('MANTENIMIENTO_MAQUINARIA', '1,300', NULL, 'Alfa', 'QA-L01', '2', 'PZA', 'Refaccionaria El Tornillo', 'Material para la bomba de agua, incluye mano de obra', NULL, NULL, 'true');
    SELECT * INTO r FROM agri_expenses WHERE id = (v->>'expense_id')::uuid;
    PERFORM pg_temp.ok('T15a ADMIN confirmed -> recorded in company 10, amount, scope, actor from the session',
        v->>'status' = 'recorded' AND r.id_company = 10 AND r.amount = 1300 AND r.plantation_id = pg_temp.id('PA') AND r.lot_id = pg_temp.id('LA1')
        AND r.reported_by_email = 'fjpimienta@gmail.com' AND r.quantity = 2 AND r.unit_code = 'PZA' AND NOT r.is_void
        AND r.description = 'Material para la bomba de agua, incluye mano de obra', v::text);
    PERFORM pg_temp.ok('T15b the recorded answer carries no amount at all', v::text !~* 'amount|1300', v::text);

    v := pg_temp.ex('RIEGO', '250.50', p_conf => 'TRUE', p_actor => 'fjpimienta@yahoo.com');
    SELECT * INTO r FROM agri_expenses WHERE id = (v->>'expense_id')::uuid;
    PERFORM pg_temp.ok('T16a EDITOR records a general expense; "TRUE" confirms; no amount in the answer; actor lower-cased',
        v->>'status' = 'recorded' AND r.plantation_id IS NULL AND r.lot_id IS NULL AND r.reported_by_email = 'fjpimienta@yahoo.com'
        AND r.id_company = 10 AND v::text !~* 'amount|250', v::text);
    v := pg_temp.ex('RIEGO', '77', p_conf => 'true', p_actor => 'FJPimienta@Yahoo.COM');
    SELECT * INTO r FROM agri_expenses WHERE id = (v->>'expense_id')::uuid;
    PERFORM pg_temp.ok('T16b the actor e-mail is stored in lower case whatever the case sent', r.reported_by_email = 'fjpimienta@yahoo.com');

    -- hostile text is stored literally (parameters, not SQL)
    v := pg_temp.ex('OTROS', '5', p_sup => repeat('Proveedor ', 40), p_desc => $d$tornillos, cables; DROP TABLE agri_expenses; -- ' " $x$ {}$d$, p_conf => 'true');
    SELECT * INTO r FROM agri_expenses WHERE id = (v->>'expense_id')::uuid;
    PERFORM pg_temp.ok('T17 commas, quotes and SQL in the description are data; a 400-char supplier is cut to 150',
        r.description = $d$tornillos, cables; DROP TABLE agri_expenses; -- ' " $x$ {}$d$ AND length(r.supplier_name) <= 150 AND to_regclass('public.agri_expenses') IS NOT NULL);

    -- duplicate guard (same actor, category, amount, date, scope; 2 minutes)
    n0 := pg_temp.n_exp();
    v := pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010', p_conf => 'true');
    PERFORM pg_temp.ok('T18a first expense recorded', v->>'status' = 'recorded');
    v := pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010');
    PERFORM pg_temp.ok('T18b an identical PREVIEW already says duplicate_recent and explains how to force',
        v->>'status' = 'duplicate_recent' AND v->>'message' LIKE '%force_duplicate = true%', v::text);
    v := pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010', p_conf => 'true');
    PERFORM pg_temp.ok('T18c an identical CONFIRMED call writes nothing', v->>'status' = 'duplicate_recent' AND pg_temp.n_exp() = n0 + 1, v->>'status');
    v := pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010', p_conf => 'true', p_force => 'true');
    PERFORM pg_temp.ok('T18d force_duplicate = true records the identical expense', v->>'status' = 'recorded' AND pg_temp.n_exp() = n0 + 2);
    PERFORM pg_temp.ok('T18e a different amount, scope, category, date or actor is not a duplicate',
        pg_temp.ex('COMBUSTIBLE', '901', p_lot => 'QA-L010')->>'status' = 'preview'
        AND pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L01', p_pl => 'Alfa')->>'status' = 'preview'
        AND pg_temp.ex('COMBUSTIBLE', '900')->>'status' = 'preview'
        AND pg_temp.ex('RIEGO', '900', p_lot => 'QA-L010')->>'status' = 'preview'
        AND pg_temp.ex('COMBUSTIBLE', '900', (fn_agri_today_cdmx() - 1)::text, p_lot => 'QA-L010')->>'status' = 'preview'
        AND pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010', p_actor => 'fjpimienta@yahoo.com')->>'status' = 'preview');
    PERFORM sp_agri_void_expense(10, (SELECT id FROM agri_expenses WHERE id_company = 10 AND amount = 900 AND category_id =
        (SELECT id FROM agri_expense_categories WHERE id_company = 10 AND category_code = 'COMBUSTIBLE') AND NOT is_void ORDER BY created_at, id LIMIT 1),
        'prueba T18f', 'fjpimienta@gmail.com');
    PERFORM sp_agri_void_expense(10, (SELECT id FROM agri_expenses WHERE id_company = 10 AND amount = 900 AND category_id =
        (SELECT id FROM agri_expense_categories WHERE id_company = 10 AND category_code = 'COMBUSTIBLE') AND NOT is_void ORDER BY created_at, id LIMIT 1),
        'prueba T18f', 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T18f once both are voided, the same expense is no longer a duplicate',
        pg_temp.ex('COMBUSTIBLE', '900', p_lot => 'QA-L010')->>'status' = 'preview');
END $$;

-- T19 recent expenses
DO $$
DECLARE v jsonb; n integer;
BEGIN
    PERFORM pg_temp.ex('COMBUSTIBLE', '321', p_lot => 'QA-L010', p_conf => 'true');
    PERFORM pg_temp.ex('OTROS', '123', p_conf => 'true');
    v := sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T19a ADMIN lists the last expenses with ref (8 chars), amount and date; voided ones are not listed',
        v->>'status' = 'ok' AND jsonb_array_length(v->'expenses') = 5
        AND (SELECT bool_and(length(e->>'ref') = 8 AND e ? 'amount' AND e ? 'expense_date') FROM jsonb_array_elements(v->'expenses') e)
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'expenses') e JOIN agri_expenses x ON left(x.id::text, 8) = e->>'ref' WHERE x.is_void),
        left(v::text, 200));
    PERFORM pg_temp.ok('T19b limit: 2 -> 2, 50 -> capped to 10, 0 -> 1, abc -> 5',
        jsonb_array_length(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '2')->'expenses') = 2
        AND jsonb_array_length(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '50')->'expenses') <= 10
        AND jsonb_array_length(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '0')->'expenses') = 1
        AND jsonb_array_length(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', 'abc')->'expenses') = 5);
    v := sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10', NULL, 'RIEGO');
    PERFORM pg_temp.ok('T19c filter by category', jsonb_array_length(v->'expenses') = 2 AND (SELECT bool_and(e->>'category_name' = 'Riego') FROM jsonb_array_elements(v->'expenses') e), v::text);
    v := sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10', NULL, NULL, 'QA-L010');
    PERFORM pg_temp.ok('T19d filter by lot', jsonb_array_length(v->'expenses') >= 1 AND (SELECT bool_and(e->>'lot_code' = 'QA-L010') FROM jsonb_array_elements(v->'expenses') e), v::text);
    PERFORM pg_temp.ok('T19e filter by date_from (tomorrow -> none); bad date and bad category -> need_info',
        jsonb_array_length(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10', (fn_agri_today_cdmx() + 1)::text)->'expenses') = 0
        AND sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10', 'hoy')->>'status' = 'need_info'
        AND sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10', NULL, 'NOPE')->>'status' = 'need_info');
    PERFORM pg_temp.ok('T19f the EDITOR gets no list and no figure',
        sp_agri_chat_recent_expenses('10', 'fjpimienta@yahoo.com')::text !~* 'amount|expenses'
        AND sp_agri_chat_recent_expenses('10', 'fjpimienta@yahoo.com')->>'status' = 'forbidden');
END $$;

-- T20 void
DO $$
DECLARE
    v jsonb; v_ref text; v_id uuid; r record; v_other uuid;
BEGIN
    SELECT id INTO v_id FROM agri_expenses WHERE id_company = 10 AND NOT is_void AND amount = 1300;
    v_ref := left(v_id::text, 8);
    PERFORM pg_temp.ok('T20a no ref / no reason -> need_info listing what is missing',
        pg_temp.iss(sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', NULL, NULL, 'false'), 'expense_ref')->>'type' = 'missing'
        AND pg_temp.iss(sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', NULL, NULL, 'false'), 'reason')->>'type' = 'missing');
    PERFORM pg_temp.ok('T20b a short or non-hex ref is invalid', pg_temp.iss(sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', 'abc', 'x', 'false'), 'expense_ref')->>'type' = 'invalid'
        AND pg_temp.iss(sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', 'zzzzzzzz%', 'x', 'false'), 'expense_ref')->>'type' = 'invalid');
    PERFORM pg_temp.ok('T20c ref that matches nothing -> not_found', sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', 'deadbeef', 'x', 'false')->>'status' = 'not_found');
    v := sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', upper(v_ref), 'Captura duplicada', 'false');
    PERFORM pg_temp.ok('T20d preview shows the expense WITH amount (ADMIN) and the reason; nothing voided',
        v->>'status' = 'preview' AND (v->'summary'->>'amount')::numeric = 1300 AND v->'summary'->>'reason' = 'Captura duplicada'
        AND NOT (SELECT is_void FROM agri_expenses WHERE id = v_id), v::text);
    v := sp_agri_chat_void_expense('10', 'fjpimienta@yahoo.com', v_ref, 'Captura duplicada', 'true');
    PERFORM pg_temp.ok('T20e the EDITOR cannot void (forbidden, expense intact, no amount in the answer)',
        v->>'status' = 'forbidden' AND v::text !~* 'amount|1300' AND NOT (SELECT is_void FROM agri_expenses WHERE id = v_id));
    v := sp_agri_chat_void_expense('10', 'pistahielo.admin@hosting3m.com', v_ref, 'Captura duplicada', 'true');
    SELECT * INTO r FROM agri_expenses WHERE id = v_id;
    PERFORM pg_temp.ok('T20f OWNER confirms -> voided with reason and actor', v->>'status' = 'voided' AND r.is_void AND r.void_reason = 'Captura duplicada'
        AND r.voided_by_email = 'pistahielo.admin@hosting3m.com', v::text);
    PERFORM pg_temp.ok('T20g voiding again -> already_void', sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', v_ref, 'otra vez', 'true')->>'status' = 'already_void');
END $$;

-- T21 company 6 as a SECOND palm company (inside this transaction only): isolation both ways
UPDATE companys SET industry = 'Agricultura de Precisión' WHERE id_company = 6;
DO $$
DECLARE
    v jsonb; r record; v_ref6 text; n10 bigint := pg_temp.n_exp(10); n6 bigint;
BEGIN
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (6, 'QA6-P', 'Plantación QA Seis', 10, 'PROPIA') RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('P6', r.id);
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha) VALUES (6, pg_temp.id('P6'), 'QA6-LOT', 'Lote Seis', 5) RETURNING id INTO STRICT r;
    INSERT INTO t_id VALUES ('L6', r.id);
    PERFORM sp_agri_bulk_create_rows(6, pg_temp.id('L6'), 1, 3, 20, 'fjpimienta@gmail.com');

    v := pg_temp.ex('RIEGO', '4444', p_lot => 'QA6-LOT', p_conf => 'true', p_tenant => '6');
    PERFORM pg_temp.ok('T21a ADMIN records an expense in company 6 (now palm) on its own lot', v->>'status' = 'recorded'
        AND (SELECT id_company FROM agri_expenses WHERE id = (v->>'expense_id')::uuid) = 6, v::text);
    v_ref6 := left(v->>'expense_id', 8);
    n6 := pg_temp.n_exp(6);

    PERFORM pg_temp.ok('T21b a lot of company 6 asked from company 10 is not_found and its name does not leak',
        pg_temp.iss(pg_temp.ex('OTROS', '10', p_lot => 'QA6-LOT'), 'lot')->>'type' = 'not_found'
        AND pg_temp.ex('OTROS', '10', p_lot => 'QA6-LOT')::text !~* 'QA6|Seis');
    PERFORM pg_temp.ok('T21c and the other way: a lot of company 10 asked from company 6 is not_found',
        pg_temp.iss(pg_temp.ex('OTROS', '10', p_lot => 'QA-L010', p_tenant => '6'), 'lot')->>'type' = 'not_found'
        AND pg_temp.ex('OTROS', '10', p_pl => 'Alfa', p_tenant => '6')::text !~* 'Alfa');
    PERFORM pg_temp.ok('T21d the EDITOR (member of 10 only) is forbidden in company 6 on every tool',
        pg_temp.ex('OTROS', '10', p_actor => 'fjpimienta@yahoo.com', p_tenant => '6')->>'status' = 'forbidden'
        AND pg_temp.cen('QA6-LOT', NULL, '1', '5', p_actor => 'fjpimienta@yahoo.com', p_tenant => '6')->>'status' = 'forbidden'
        AND sp_agri_chat_catalog('6', 'fjpimienta@yahoo.com')->>'status' = 'forbidden');
    v := sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', v_ref6, 'intento cruzado', 'true');
    PERFORM pg_temp.ok('T21e voiding an expense of company 6 from company 10 -> not_found and it stays valid',
        v->>'status' = 'not_found' AND NOT (SELECT is_void FROM agri_expenses WHERE left(id::text, 8) = v_ref6), v::text);
    PERFORM pg_temp.ok('T21f recent expenses never mix companies',
        NOT EXISTS (SELECT 1 FROM jsonb_array_elements(sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com', '10')->'expenses') e WHERE e->>'ref' = v_ref6)
        AND jsonb_array_length(sp_agri_chat_recent_expenses('6', 'fjpimienta@gmail.com', '10')->'expenses') = 1);
    v := pg_temp.cen('QA6-LOT', NULL, '1', '5', p_conf => 'true');
    PERFORM pg_temp.ok('T21g a census on a company-6 lot from company 10 is not_found and changes nothing',
        pg_temp.iss(v, 'lot')->>'type' = 'not_found' AND (SELECT alive_plants FROM agri_rows WHERE lot_id = pg_temp.id('L6') AND row_number = 1) = 20);
    PERFORM pg_temp.ok('T21h catalogs and structures are per company',
        sp_agri_chat_catalog('6', 'fjpimienta@gmail.com')::text !~ 'QA-CHAT' AND sp_agri_chat_catalog('10', 'fjpimienta@gmail.com')::text !~ 'QA6'
        AND sp_agri_chat_structure('6', 'fjpimienta@gmail.com')::text !~ 'QA-CHAT');
    PERFORM pg_temp.ok('T21i nothing of company 10 changed while working on 6', pg_temp.n_exp(10) = n10);
END $$;

-- T22 balance
DO $$
DECLARE
    v jsonb; v_total numeric; v_n bigint; v_from date := date_trunc('month', fn_agri_today_cdmx()::timestamp)::date;
BEGIN
    SELECT coalesce(sum(amount), 0), count(*) INTO v_total, v_n FROM agri_expenses
     WHERE id_company = 10 AND NOT is_void AND expense_date BETWEEN v_from AND fn_agri_today_cdmx();
    v := sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com');
    PERFORM pg_temp.ok('T22a default THIS_MONTH equals the direct SUM of the company (voided excluded) and says it is the whole company',
        v->>'status' = 'ok' AND (v->>'total_amount')::numeric = v_total AND (v->>'expense_count')::bigint = v_n AND v->>'scope' LIKE '%TODA la empresa%', v::text);
    PERFORM pg_temp.ok('T22b the voided 1300 is excluded and company 6 (4444) is not included', v_total < 4444 + 100000 AND NOT EXISTS (SELECT 1 FROM agri_expenses WHERE id_company = 10 AND amount = 4444));
    PERFORM pg_temp.ok('T22c company 6 balance is only company 6', (sp_agri_chat_expense_balance('6', 'fjpimienta@gmail.com')->>'total_amount')::numeric = 4444);
    v := sp_agri_chat_expense_balance('10', 'pistahielo.admin@hosting3m.com', 'TODAY');
    PERFORM pg_temp.ok('T22d OWNER reads TODAY', v->>'status' = 'ok' AND v->>'date_from' = fn_agri_today_cdmx()::text);
    PERFORM pg_temp.ok('T22e periods THIS_WEEK, LAST_MONTH, THIS_YEAR answer ok with sane ranges',
        sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'THIS_WEEK')->>'status' = 'ok'
        AND (sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'LAST_MONTH')->>'date_to')::date = v_from - 1
        AND (sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'THIS_YEAR')->>'date_from')::date = date_trunc('year', fn_agri_today_cdmx()::timestamp)::date);
    PERFORM pg_temp.ok('T22f CUSTOM needs both dates; bad period / reversed range are need_info',
        sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'CUSTOM')->>'status' = 'need_info'
        AND sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'CUSTOM', '2026-10-10', '2026-10-01')->>'status' = 'need_info'
        AND sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'FOREVER')->>'status' = 'need_info'
        AND sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'CUSTOM', '2020-01-01', fn_agri_today_cdmx()::text)->>'status' IN ('ok', 'invalid'));
    v := sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'THIS_MONTH', NULL, NULL, NULL, NULL, 'RIEGO');
    PERFORM pg_temp.ok('T22g category filter', (v->>'total_amount')::numeric = (SELECT coalesce(sum(amount), 0) FROM agri_expenses e JOIN agri_expense_categories c ON c.id = e.category_id
        WHERE e.id_company = 10 AND NOT e.is_void AND c.category_code = 'RIEGO' AND e.expense_date BETWEEN v_from AND fn_agri_today_cdmx()), v::text);
    v := sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com', 'THIS_MONTH', NULL, NULL, NULL, 'QA-L010');
    PERFORM pg_temp.ok('T22h lot filter', v->>'status' = 'ok' AND jsonb_array_length(v->'by_lot') <= 1 AND (v->>'total_amount')::numeric = (SELECT coalesce(sum(amount), 0) FROM agri_expenses
        WHERE id_company = 10 AND NOT is_void AND lot_id = pg_temp.id('LA10') AND expense_date BETWEEN v_from AND fn_agri_today_cdmx()), v::text);
    v := sp_agri_chat_expense_balance('10', 'fjpimienta@yahoo.com');
    PERFORM pg_temp.ok('T22i the EDITOR gets the polite refusal and NO figure', v->>'status' = 'forbidden' AND v::text !~* 'total|amount|[0-9]{3}', v::text);
    PERFORM pg_temp.ok('T22j by_category lists at most 5 entries', jsonb_array_length(sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com')->'by_category') <= 5);
END $$;

-- T23 row census
DO $$
DECLARE
    v jsonb; r record; h0 bigint; h1 bigint;
BEGIN
    SELECT count(*) INTO h0 FROM agri_row_census_history WHERE id_company = 10;
    v := pg_temp.cen();
    PERFORM pg_temp.ok('T23a nothing given: lot, row and alive plants all missing in ONE answer', jsonb_array_length(v->'issues') = 3, v::text);
    PERFORM pg_temp.ok('T23b non-integer row / alive / negative / reason / future date are invalid',
        pg_temp.iss(pg_temp.cen('QA-L010', NULL, 'tres', '5'), 'row_number')->>'type' = 'invalid'
        AND pg_temp.iss(pg_temp.cen('QA-L010', NULL, '1', '5.5'), 'alive_plants')->>'type' = 'invalid'
        AND pg_temp.iss(pg_temp.cen('QA-L010', NULL, '1', '-1'), 'alive_plants')->>'type' = 'invalid'
        AND pg_temp.iss(pg_temp.cen('QA-L010', NULL, '1', '5', 'VACACIONES'), 'reason')->>'type' = 'invalid'
        AND pg_temp.iss(pg_temp.cen('QA-L010', NULL, '1', '5', NULL, (fn_agri_today_cdmx() + 1)::text), 'census_date')->>'type' = 'invalid'
        AND pg_temp.iss(pg_temp.cen('QA-L010', NULL, '0', '5'), 'row_number')->>'type' = 'invalid');
    v := pg_temp.cen('QA-L01', NULL, '3', '18');
    PERFORM pg_temp.ok('T23c the same lot code in two plantations is ambiguous', pg_temp.iss(v, 'lot')->>'type' = 'ambiguous');
    v := pg_temp.cen('QA-L01', 'Alfa', '9', '18');
    PERFORM pg_temp.ok('T23d row 9 does not exist: not_found with the available range', pg_temp.iss(v, 'row_number')->>'type' = 'not_found'
        AND (pg_temp.iss(v, 'row_number')->'rows_available'->>'count')::int = 5 AND (pg_temp.iss(v, 'row_number')->'rows_available'->>'last')::int = 5, v::text);
    v := pg_temp.cen('QA-L01', 'Alfa', '3', '23');
    PERFORM pg_temp.ok('T23e more alive plants than planting positions is invalid and says the limit', pg_temp.iss(v, 'alive_plants')->>'type' = 'invalid'
        AND pg_temp.iss(v, 'alive_plants')->>'message' LIKE '%22 puntos%', v::text);
    v := pg_temp.cen('QA-L01', 'Alfa', '3', '18', NULL, NULL, 'conteo de campo');
    PERFORM pg_temp.ok('T23f preview: before -> after with positions; defaults CENSO and today',
        v->>'status' = 'preview' AND (v->'summary'->>'previous_alive_plants')::int = 22 AND (v->'summary'->>'new_alive_plants')::int = 18
        AND (v->'summary'->>'change')::int = -4 AND (v->'summary'->>'planting_positions')::int = 22 AND v->'summary'->>'reason' = 'CENSO'
        AND (v->'summary'->>'census_date')::date = fn_agri_today_cdmx(), v::text);
    SELECT count(*) INTO h1 FROM agri_row_census_history WHERE id_company = 10;
    PERFORM pg_temp.ok('T23g the preview wrote nothing (row and history unchanged)',
        (SELECT alive_plants FROM agri_rows WHERE lot_id = pg_temp.id('LA1') AND row_number = 3) = 22 AND h0 = h1);
    v := pg_temp.cen('QA-L01', 'Alfa', '3', '18', NULL, NULL, 'conteo de campo', 'true', 'fjpimienta@yahoo.com');
    SELECT * INTO r FROM agri_rows WHERE lot_id = pg_temp.id('LA1') AND row_number = 3;
    PERFORM pg_temp.ok('T23h the EDITOR confirms: row updated, positions untouched',
        v->>'status' = 'recorded' AND r.alive_plants = 18 AND r.planting_positions = 22 AND r.last_census_date = fn_agri_today_cdmx(), v::text);
    PERFORM pg_temp.ok('T23i history has the actor (lower case), reason and the change',
        EXISTS (SELECT 1 FROM agri_row_census_history h WHERE h.row_id = r.id AND h.changed_by = 'fjpimienta@yahoo.com' AND h.reason = 'CENSO'
                AND h.previous_alive = 22 AND h.new_alive = 18 AND h.notes = 'conteo de campo'));
    v := pg_temp.cen('QA-L01', 'Alfa', '3', '18', NULL, NULL, NULL, 'true');
    PERFORM pg_temp.ok('T23j a CENSO that confirms the same numbers still leaves a history row (changed = false)',
        v->>'status' = 'recorded' AND (v->>'changed')::boolean = false
        AND (SELECT count(*) FROM agri_row_census_history WHERE row_id = r.id AND reason = 'CENSO') = 2, v::text);
    v := pg_temp.cen('QA-L01', 'Alfa', '4', '20', 'PERDIDA', NULL, NULL, 'true', 'pistahielo.admin@hosting3m.com');
    PERFORM pg_temp.ok('T23k OWNER with another reason (PERDIDA, lower-case accepted too)',
        v->>'status' = 'recorded' AND pg_temp.cen('Qa-l01', 'alfa', '4', '21', 'resiembra', NULL, NULL, 'true')->>'status' = 'recorded');
    v := pg_temp.cen('QA-L01', 'Alfa', '5', '1', NULL, NULL, NULL, 'true', 'sanjose.recepcion@hosting3m.com');
    PERFORM pg_temp.ok('T23l a CUSTOMER is forbidden and the row is intact',
        v->>'status' = 'forbidden' AND (SELECT alive_plants FROM agri_rows WHERE lot_id = pg_temp.id('LA1') AND row_number = 5) = 22);
    v := pg_temp.cen('Lote Sur', 'Beta', '2', '29', NULL, NULL, NULL, 'true');
    PERFORM pg_temp.ok('T23m lot by name under another plantation', v->>'status' = 'recorded' AND (SELECT alive_plants FROM agri_rows WHERE lot_id = pg_temp.id('LB1') AND row_number = 2) = 29);
END $$;

-- T24 structure and lot summary
DO $$
DECLARE v jsonb;
BEGIN
    v := sp_agri_chat_structure('10', 'fjpimienta@yahoo.com');
    PERFORM pg_temp.ok('T24a the EDITOR lists plantations with their lots, no amounts anywhere',
        v->>'status' = 'ok' AND v::text !~* 'amount|monto' AND EXISTS (SELECT 1 FROM jsonb_array_elements(v->'plantations') p WHERE p->>'code' = 'QA-CHAT-A' AND jsonb_array_length(p->'lots') = 2), left(v::text, 200));
    v := sp_agri_chat_structure('10', 'fjpimienta@yahoo.com', 'QA Chat Alfa');
    PERFORM pg_temp.ok('T24b filter by plantation: only that one, with its row counts and alive plants',
        jsonb_array_length(v->'plantations') = 1 AND (v->'plantations'->0->>'active_rows')::int = 5
        AND (v->'plantations'->0->>'alive_plants')::int = (SELECT sum(alive_plants) FROM agri_rows WHERE lot_id IN (pg_temp.id('LA1'), pg_temp.id('LA10')) AND is_active), v::text);
    PERFORM pg_temp.ok('T24c unknown or ambiguous plantation -> need_info',
        sp_agri_chat_structure('10', 'fjpimienta@yahoo.com', 'Nope')->>'status' = 'need_info' AND sp_agri_chat_structure('10', 'fjpimienta@yahoo.com', 'QA Chat')->>'status' = 'need_info');
    v := sp_agri_chat_lot_summary('10', 'sanjose.recepcion@hosting3m.com', 'QA-L01', 'Alfa');
    PERFORM pg_temp.ok('T24d lot summary (CUSTOMER can read): live numbers from the view, no amounts',
        v->>'status' = 'ok' AND (v->>'active_rows')::int = 5 AND (v->>'planting_positions')::int = 110
        AND (v->>'alive_plants')::int = (SELECT sum(alive_plants) FROM agri_rows WHERE lot_id = pg_temp.id('LA1')) AND v::text !~* 'amount|monto', v::text);
    PERFORM pg_temp.ok('T24e lot summary: ambiguous and unknown lots -> need_info, missing lot -> need_info',
        sp_agri_chat_lot_summary('10', 'fjpimienta@gmail.com', 'QA-L01')->>'status' = 'need_info'
        AND sp_agri_chat_lot_summary('10', 'fjpimienta@gmail.com', 'ZZZ')->>'status' = 'need_info'
        AND sp_agri_chat_lot_summary('10', 'fjpimienta@gmail.com', NULL)->>'status' = 'need_info');
END $$;

-- T25 fail-closed on the DOMAIN at every call: company 10 stops being palm -> every tool says not_palm
UPDATE companys SET industry = 'Ganadería de Precisión' WHERE id_company = 10;
DO $$
DECLARE v_bad text := ''; v_n bigint := pg_temp.n_exp(); v_alive int;
BEGIN
    SELECT alive_plants INTO v_alive FROM agri_rows WHERE lot_id = pg_temp.id('LA1') AND row_number = 1;
    IF pg_temp.ex('RIEGO', '10', p_conf => 'true')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'register '; END IF;
    IF pg_temp.cen('QA-L010', NULL, '1', '5', p_conf => 'true')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'census '; END IF;
    IF sp_agri_chat_void_expense('10', 'fjpimienta@gmail.com', 'deadbeef', 'x', 'true')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'void '; END IF;
    IF sp_agri_chat_recent_expenses('10', 'fjpimienta@gmail.com')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'recent '; END IF;
    IF sp_agri_chat_expense_balance('10', 'fjpimienta@gmail.com')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'balance '; END IF;
    IF sp_agri_chat_structure('10', 'fjpimienta@gmail.com')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'structure '; END IF;
    IF sp_agri_chat_lot_summary('10', 'fjpimienta@gmail.com', 'QA-L010')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'lot_summary '; END IF;
    IF sp_agri_chat_catalog('10', 'fjpimienta@gmail.com')->>'status' <> 'not_palm' THEN v_bad := v_bad || 'catalog '; END IF;
    PERFORM pg_temp.ok('T25 a company that is no longer palm: all 8 tools answer not_palm and write nothing', v_bad = '' AND pg_temp.n_exp() = v_n, coalesce(nullif(v_bad, ''), 'ok'));
END $$;
UPDATE companys SET industry = 'Agricultura de Precisión' WHERE id_company = 10;
UPDATE companys SET is_active = false WHERE id_company = 10;
SELECT pg_temp.ok('T25b an inactive company is forbidden',
    sp_agri_chat_structure('10', 'fjpimienta@gmail.com')->>'status' = 'forbidden' AND pg_temp.ex('RIEGO', '10', p_conf => 'true')->>'status' = 'forbidden');
UPDATE companys SET is_active = true WHERE id_company = 10;

-- T26 shape of the functions
SELECT pg_temp.ok('T26a read tools are STABLE, write tools are VOLATILE',
    (SELECT bool_and(p.provolatile = 's') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('sp_agri_chat_catalog', 'sp_agri_chat_structure', 'sp_agri_chat_lot_summary', 'sp_agri_chat_recent_expenses', 'sp_agri_chat_expense_balance'))
    AND (SELECT bool_and(p.provolatile = 'v') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('sp_agri_chat_record_expense', 'sp_agri_chat_void_expense', 'sp_agri_chat_record_row_census')));
SELECT pg_temp.ok('T26b no tool takes a tenant as integer or an e-mail it could invent: first two parameters are text',
    (SELECT bool_and(p.proargtypes[0] = 'text'::regtype AND p.proargtypes[1] = 'text'::regtype)
       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'sp\_agri\_chat\_%'));
SELECT pg_temp.ok('T26c exactly 8 tool functions',
    (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'sp\_agri\_chat\_%') = 8);

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 300) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '083 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 083 tests: everything rolled back ***'
