-- 098_tests.sql
-- Tests for 098 (grazing loans). LOCAL / throw-away schema ONLY: run it from this folder, because it applies 098 and its
-- rollback with \i. Everything happens inside ONE transaction that ends in ROLLBACK; nothing is kept.
-- Usage: psql -v ON_ERROR_STOP=1 -f 098_tests.sql
-- A failed assertion raises 'FAIL [label]' and stops the run (the open transaction is discarded with the connection).
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------------------------
-- Helpers (session-local)
-- ---------------------------------------------------------------------------------------------
CREATE TEMP TABLE t098_ids (k text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t098_res (label text);

CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM t098_ids WHERE k = p_k $$;

CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL [%]', p_label;
    END IF;
    INSERT INTO t098_res VALUES (p_label);
    RAISE NOTICE 'PASS [%]', p_label;
END $$;

-- Runs p_sql and requires it to fail with p_state (and, if given, a message matching p_like).
CREATE FUNCTION pg_temp.expect(p_sql text, p_state text, p_label text, p_like text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    s text;
    m text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE, m = MESSAGE_TEXT;
        IF s <> p_state OR (p_like IS NOT NULL AND m NOT LIKE p_like) THEN
            RAISE EXCEPTION 'FAIL [%]: expected % (like %), got %: %', p_label, p_state, coalesce(p_like, '-'), s, m;
        END IF;
        INSERT INTO t098_res VALUES (p_label);
        RAISE NOTICE 'PASS [%] -> % %', p_label, s, left(m, 100);
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL [%]: no error raised (expected %)', p_label, p_state;
END $$;

-- Fingerprint of the location columns that a return or a death must never touch.
CREATE FUNCTION pg_temp.loc(p_id uuid) RETURNS text LANGUAGE sql AS $$
    SELECT concat_ws('|', production_unit_id, lot_id, upp_origen) FROM cattle_livestock WHERE id = p_id
$$;

SELECT md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) AS md5_before_098 \gset
\echo md5 before 098 :md5_before_098

-- ---------------------------------------------------------------------------------------------
-- Apply 098 inside the test transaction
-- ---------------------------------------------------------------------------------------------
\set embedded 1
\i 098_repasto_return_movements.sql

SELECT md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) AS md5_patched \gset
SELECT pg_temp.ok(:'md5_before_098' <> :'md5_patched', 'T00 migration patched sp_solicitar_venta_orden');

-- Mutation hook: with -v mutation=M1..M6 one protection is broken here and the matching test must fail (098_mutation_check.sh).
\if :{?mutation}
\i 098_mutate.sql
\endif

-- ---------------------------------------------------------------------------------------------
-- Fixtures: two companies, three users, units, lot, third-party destination, animals, events
-- ---------------------------------------------------------------------------------------------
INSERT INTO companys (id_company, company_name) VALUES (9801, 'T098 Company A'), (9802, 'T098 Company B');
INSERT INTO users (email, names, password, role) VALUES
    ('t098-admin@example.test',  'T098 Admin',  'x', 'ADMIN'),
    ('t098-editor@example.test', 'T098 Editor', 'x', 'EDITOR'),
    ('t098-other@example.test',  'T098 Other',  'x', 'ADMIN');
INSERT INTO user_companies (email, id_company, role) VALUES
    ('t098-admin@example.test',  9801, 'ADMIN'),
    ('t098-editor@example.test', 9801, 'EDITOR'),
    ('t098-other@example.test',  9802, 'ADMIN');

WITH a AS (INSERT INTO production_units (id_company, upp_code, ranch_name) VALUES (9801, '99-998-0001-001', 'T098 Origin') RETURNING id),
     b AS (INSERT INTO production_units (id_company, upp_code, ranch_name) VALUES (9801, '99-998-0001-002', 'T098 Other unit') RETURNING id),
     c AS (INSERT INTO production_units (id_company, upp_code, ranch_name) VALUES (9802, '99-998-0002-001', 'T098 Company B unit') RETURNING id)
INSERT INTO t098_ids SELECT 'puA', id FROM a UNION ALL SELECT 'puB', id FROM b UNION ALL SELECT 'puC', id FROM c;

WITH x AS (
    INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type)
    VALUES (9801, pg_temp.id('puA'), 'T098 LOTE', 'PROPIO') RETURNING id)
INSERT INTO t098_ids SELECT 'lot', id FROM x;

WITH x AS (
    INSERT INTO external_destinations (id_company, name, destination_type, normative_type)
    VALUES (9801, 'T098 Third party', 'THIRD_PARTY_RANCH', 'UPP') RETURNING id)
INSERT INTO t098_ids SELECT 'dest', id FROM x;

-- Bovine animals: valid 10-digit tag, TB/BR of today, so that sp_procesar_salida_ganado reaches the sale update.
CREATE FUNCTION pg_temp.animal(p_key text, p_company int, p_unit text, p_status text, p_tag text, p_species text DEFAULT 'BOVINO',
                               p_category text DEFAULT 'BECERRA', p_lot boolean DEFAULT false, p_age interval DEFAULT interval '0')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga, production_unit_id,
                                  lot_id, tb_test_date, br_test_date, created_at)
    VALUES (p_company, 'CRIA', p_category, p_status, p_species, p_tag, pg_temp.id(p_unit),
            CASE WHEN p_lot THEN pg_temp.id('lot') END,
            CASE WHEN p_species = 'BOVINO' THEN CURRENT_DATE END, CASE WHEN p_species = 'BOVINO' THEN CURRENT_DATE END,
            now() - p_age)
    RETURNING id INTO v_id;
    INSERT INTO t098_ids VALUES (p_key, v_id);
END $$;

SELECT pg_temp.animal('a1', 9801, 'puA', 'ACTIVO', '9801000001');
SELECT pg_temp.animal('a2', 9801, 'puA', 'ACTIVO', '9801000002');
SELECT pg_temp.animal('a3', 9801, 'puA', 'ACTIVO', '9801000003');           -- never on loan: control for sales
SELECT pg_temp.animal('a5', 9801, 'puA', 'ACTIVO', '9801000005');
SELECT pg_temp.animal('a6', 9801, 'puA', 'ACTIVO', '9801000006');
SELECT pg_temp.animal('a9', 9801, 'puA', 'ACTIVO', '9801000009');
SELECT pg_temp.animal('ahist', 9801, 'puA', 'ACTIVO', '9801000010');         -- historical row with return_status NULL
SELECT pg_temp.animal('asold', 9801, 'puA', 'VENDIDO', '9801000011');
SELECT pg_temp.animal('adead', 9801, 'puA', 'BAJA_MORTANDAD', '9801000012');
SELECT pg_temp.animal('adep',  9801, 'puA', 'BAJA_DEPURACION_DATOS', '9801000013');
SELECT pg_temp.animal('afin',  9801, 'puA', 'FINALIZADO', '9801000014');
SELECT pg_temp.animal('aotherunit', 9801, 'puB', 'ACTIVO', '9801000015');   -- same company, not in the origin unit
SELECT pg_temp.animal('acompb', 9802, 'puC', 'ACTIVO', '9802000001');       -- other company
-- Non-bovine lot for the FIFO fixture (species and category BORREGO): no identifiers at all, oldest first.
SELECT pg_temp.animal('f1', 9801, 'puA', 'ACTIVO', NULL, 'BORREGO', 'BORREGO', true, interval '3 days');
SELECT pg_temp.animal('f2', 9801, 'puA', 'ACTIVO', NULL, 'BORREGO', 'BORREGO', true, interval '2 days');
SELECT pg_temp.animal('f3', 9801, 'puA', 'ACTIVO', NULL, 'BORREGO', 'BORREGO', true, interval '1 day');
UPDATE cattle_livestock SET electronic_rfid = '980100000000001' WHERE id = pg_temp.id('a1');

CREATE FUNCTION pg_temp.event(p_key text, p_folio text, p_purpose text, p_expected date) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO cattle_movement_events (id_company, production_unit_origin_id, external_destination_id, reemo_folio, movement_date,
                                        purpose, expected_return_date)
    VALUES (9801, pg_temp.id('puA'), pg_temp.id('dest'), p_folio, CURRENT_DATE - 10, p_purpose, p_expected)
    RETURNING id INTO v_id;
    INSERT INTO t098_ids VALUES (p_key, v_id);
END $$;

SELECT pg_temp.event('evA', '7139728-T098', 'REPASTO', CURRENT_DATE + 30);
SELECT pg_temp.event('evB', '7139729-T098', 'REPASTO', CURRENT_DATE + 30);
SELECT pg_temp.event('evD', '7139730-T098', 'REPASTO', CURRENT_DATE + 30);
SELECT pg_temp.event('evE', 'PRUEBA-T098',  'REPASTO', CURRENT_DATE + 30);
SELECT pg_temp.event('evO', 'ORD-T098',     NULL,      NULL);

CREATE FUNCTION pg_temp.loan(p_event text, p_animal text, p_status text DEFAULT 'OPEN') RETURNS void LANGUAGE sql AS $$
    INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status, returned_at)
    VALUES (pg_temp.id(p_event), pg_temp.id(p_animal), p_status,
            CASE WHEN p_status = 'OPEN' THEN NULL WHEN p_status = 'RETURNED' THEN now() END)
$$;

-- ---------------------------------------------------------------------------------------------
-- A. Table constraints
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.expect($q$INSERT INTO cattle_movement_events (id_company, production_unit_origin_id, external_destination_id, movement_date, purpose)
   VALUES (9801, pg_temp.id('puA'), pg_temp.id('dest'), CURRENT_DATE, 'REPASTO')$q$,
   '23514', 'A1 REPASTO without expected_return_date is rejected');
SELECT pg_temp.expect($q$INSERT INTO cattle_movement_events (id_company, production_unit_origin_id, external_destination_id, movement_date, purpose, expected_return_date)
   VALUES (9801, pg_temp.id('puA'), pg_temp.id('dest'), CURRENT_DATE, 'VENTA', CURRENT_DATE)$q$,
   '23514', 'A2 unknown purpose is rejected');
SELECT pg_temp.expect($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status)
   VALUES (pg_temp.id('evA'), pg_temp.id('a3'), 'GONE')$q$, '23514', 'A3 unknown return_status is rejected');
SELECT pg_temp.expect($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status)
   VALUES (pg_temp.id('evA'), pg_temp.id('a3'), 'RETURNED')$q$, '23514', 'A4 RETURNED without returned_at is rejected');
SELECT pg_temp.expect($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status, returned_at)
   VALUES (pg_temp.id('evA'), pg_temp.id('a3'), 'OPEN', now())$q$, '23514', 'A5 OPEN with returned_at is rejected');

-- ---------------------------------------------------------------------------------------------
-- B. Opening a loan row: guard trigger (P0100), tenant trigger, unique index
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.loan('evA', 'a1');
SELECT pg_temp.loan('evA', 'a2');
SELECT pg_temp.ok((SELECT count(*) FROM vw_livestock_out_on_loan WHERE event_id = pg_temp.id('evA') AND is_out_on_loan) = 2,
                  'B1 two animals open in the view');
SELECT pg_temp.ok((SELECT DISTINCT event_state FROM vw_livestock_out_on_loan WHERE event_id = pg_temp.id('evA')) = 'OPEN',
                  'B2 event_state OPEN while any row is OPEN');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('a1')),
                      '23505', 'B3 an animal cannot be OPEN in two movements (partial unique index)');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('asold')), 'P0100', 'B4 VENDIDO animal cannot go out', '%status VENDIDO%');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('adead')), 'P0100', 'B5 BAJA_MORTANDAD animal cannot go out', '%BAJA_MORTANDAD%');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('adep')), 'P0100', 'B6 BAJA_DEPURACION_DATOS animal cannot go out', '%BAJA_DEPURACION_DATOS%');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('afin')), 'P0100', 'B7 FINALIZADO animal cannot go out', '%FINALIZADO%');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('aotherunit')), 'P0100', 'B8 animal outside the origin production unit is rejected',
                      '%not in the origin production unit%');
SELECT pg_temp.expect(format($q$INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES (%L, %L, 'OPEN')$q$,
                             pg_temp.id('evB'), pg_temp.id('acompb')), 'P0001', 'B9 cross-tenant animal is rejected (tenant trigger)',
                      '%different tenant%');
-- Closing never blocked, even for sold / dead animals; historical rows (NULL) are not tracked.
SELECT pg_temp.loan('evE', 'asold', 'CANCELLED');
SELECT pg_temp.loan('evE', 'adead', 'CANCELLED');
SELECT pg_temp.ok(true, 'B10 closed rows can be written for sold and dead animals');
INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id) VALUES (pg_temp.id('evO'), pg_temp.id('ahist'));
SELECT pg_temp.ok((SELECT return_status IS NULL FROM cattle_movement_event_animals WHERE cattle_livestock_id = pg_temp.id('ahist')),
                  'B11 historical rows keep return_status NULL');
SELECT pg_temp.ok((SELECT count(*) FROM vw_livestock_out_on_loan WHERE cattle_livestock_id = pg_temp.id('ahist')) = 0,
                  'B12 historical rows are not in the loan view');
SELECT pg_temp.ok((SELECT count(*) FROM vw_livestock_out_on_loan WHERE id_company = 9802) = 0, 'B13 the view has no rows for the other company');

-- ---------------------------------------------------------------------------------------------
-- C. Status block on cattle_livestock (P0098) and the sale procedures
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.expect(format($q$UPDATE cattle_livestock SET current_status = 'VENDIDO' WHERE id = %L$q$, pg_temp.id('a1')),
                      'P0098', 'C1 direct UPDATE to VENDIDO is blocked', '%7139728-T098%');
SELECT pg_temp.expect(format($q$UPDATE cattle_livestock SET current_status = 'FINALIZADO' WHERE id = %L$q$, pg_temp.id('a1')),
                      'P0098', 'C2 direct UPDATE to FINALIZADO is blocked');
SELECT pg_temp.expect(format($q$UPDATE cattle_livestock SET current_status = 'BAJA_DEPURACION_DATOS' WHERE id = %L$q$, pg_temp.id('a1')),
                      'P0098', 'C3 direct UPDATE to BAJA_DEPURACION_DATOS is blocked');
UPDATE cattle_livestock SET current_status = 'PREÑADA' WHERE id = pg_temp.id('a1');
UPDATE cattle_livestock SET current_status = 'ACTIVO' WHERE id = pg_temp.id('a1');
SELECT pg_temp.ok(true, 'C4 non-terminal status changes are not blocked');

SELECT pg_temp.expect(format($q$SELECT sp_procesar_salida_ganado(NULL::varchar, 9801, NULL::varchar, NULL::varchar, %L::uuid)$q$, pg_temp.id('a1')),
                      'P0098', 'C5 sp_procesar_salida_ganado (5 parameters, by uuid) is blocked');
-- A 4-argument call is ambiguous between the 4- and 5-parameter overloads (42725, known); the gateway always sends 5.
SELECT pg_temp.expect($q$SELECT sp_procesar_salida_ganado(NULL::varchar, 9801, '9801000001'::varchar, NULL::varchar, NULL::uuid)$q$,
                      'P0098', 'C6 sp_procesar_salida_ganado (5 parameters, by SINIIGA tag, as the gateway calls it) is blocked');
-- The 1-parameter legacy overload and the 4-parameter one cannot be called by name either (42725: ambiguous with the
-- 5-parameter overload), so they are unreachable by a plain call; the guard sits on the table, so any path is blocked.
SELECT pg_temp.expect($q$SELECT sp_procesar_salida_ganado('980100000000001'::varchar, 9801, NULL::varchar, NULL::varchar, NULL::uuid)$q$,
                      'P0098', 'C7 sp_procesar_salida_ganado (5 parameters, by chip) is blocked');
SELECT pg_temp.ok((SELECT current_status FROM cattle_livestock WHERE id = pg_temp.id('a1')) = 'ACTIVO'
                  AND (SELECT production_unit_id FROM cattle_livestock WHERE id = pg_temp.id('a1')) IS NOT NULL,
                  'C8 the blocked sale left status and production unit untouched');
SELECT pg_temp.ok((sp_procesar_salida_ganado(NULL::varchar, 9801, '9801000003'::varchar, NULL::varchar, NULL::uuid)->>'success')::boolean,
                  'C9 control: an animal that is NOT on loan is still sold normally');

-- sp_solicitar_venta_orden: preview and creation
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"identificador":"9801000001","guia_transito":"G-T098"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST')
        -> 'errores' -> 0 ->> 'error')
    = 'Animal fuera en repasto (guía 7139728-T098, retorno esperado ' || (CURRENT_DATE + 30)::text || '): no se puede vender',
    'C10 order preview rejects an animal on loan with guide and expected return');
SELECT pg_temp.expect($q$SELECT sp_solicitar_venta_orden('[{"identificador":"9801000001","guia_transito":"G-T098"}]'::jsonb, 't098-admin@example.test', NULL, false, 'TEST')$q$,
                      'P0034', 'C11 order creation rejects an animal on loan', '%Animal fuera en repasto (guía 7139728-T098%');
SELECT pg_temp.ok((SELECT count(*) FROM sale_orders) = 0 AND (SELECT count(*) FROM pending_authorizations) = 0,
                  'C12 the rejected order wrote nothing');
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"identificador":"9801000010","guia_transito":"G-T098"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST') ->> 'success')::boolean,
    'C13 control: order preview is valid for an animal with a historical (untracked) row');

-- ---------------------------------------------------------------------------------------------
-- D. FIFO: the oldest animal of the lot is on loan, so the next one must be selected
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(NOT fn_species_requires_bovine_compliance('BORREGO'), 'D0 fixture check: species BORREGO is outside the bovine regime');
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"lote":"T098 LOTE","categoria":"BORREGO","cantidad":1,"seleccion":"FIFO"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST')
        -> 'seleccionados' -> 0 ->> 'livestock_id')::uuid = pg_temp.id('f1'),
    'D1 fixture check: without a loan FIFO selects the oldest animal');
SELECT pg_temp.loan('evB', 'f1');
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"lote":"T098 LOTE","categoria":"BORREGO","cantidad":1,"seleccion":"FIFO"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST')
        -> 'seleccionados' -> 0 ->> 'livestock_id')::uuid = pg_temp.id('f2'),
    'D2 with the oldest on loan FIFO selects the next one');
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"lote":"T098 LOTE","categoria":"BORREGO","cantidad":3,"seleccion":"FIFO"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST') ->> 'success')::boolean IS FALSE,
    'D3 FIFO does not count the animal on loan as available (3 requested, 2 eligible)');
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"lote":"T098 LOTE","categoria":"BORREGO","cantidad":2,"seleccion":"FIFO"}]'::jsonb, 't098-admin@example.test', NULL, true, 'TEST') ->> 'success')::boolean,
    'D4 FIFO still sells the two animals that are not on loan');

-- ---------------------------------------------------------------------------------------------
-- E. sp_return_movement
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.loan('evD', 'a5');
SELECT pg_temp.loan('evD', 'a6');
CREATE TEMP TABLE t098_loc AS SELECT 'a1' AS k, pg_temp.loc(pg_temp.id('a1')) AS l UNION ALL SELECT 'a5', pg_temp.loc(pg_temp.id('a5'));

SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, '{}'::uuid[], CURRENT_DATE, 't098-admin@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E1 empty animal list is rejected', '%empty animal list%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE, 't098-editor@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E2 an EDITOR cannot register a return', '%ADMIN or OWNER%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE, 't098-other@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E3 an ADMIN of another company cannot register a return', '%ADMIN or OWNER%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE, 'nobody@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E4 an unknown user cannot register a return');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE, NULL)$q$, pg_temp.id('evD')),
                      'P0099', 'E5 a missing actor email is rejected', '%actor email is required%');
SELECT pg_temp.expect($q$SELECT sp_return_movement('00000000-0000-0000-0000-000000000000', NULL, CURRENT_DATE, 't098-admin@example.test')$q$,
                      'P0099', 'E6 unknown movement is rejected', '%movement not found%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE, 't098-admin@example.test')$q$, pg_temp.id('evO')),
                      'P0099', 'E7 an ordinary (non-grazing) movement cannot be returned', '%not a grazing loan%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE + 1, 't098-admin@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E8 a future return date is rejected', '%future%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, NULL, CURRENT_DATE - 11, 't098-admin@example.test')$q$, pg_temp.id('evD')),
                      'P0099', 'E9 a return date before the departure is rejected', '%before the departure%');
SELECT pg_temp.expect(format($q$SELECT sp_return_movement(%L, ARRAY[%L]::uuid[], CURRENT_DATE, 't098-admin@example.test')$q$, pg_temp.id('evD'), pg_temp.id('a3')),
                      'P0099', 'E10 an animal that is not in the movement is rejected', '%do not belong%');

-- Partial return, then the same return again
CREATE TEMP TABLE t098_r AS
SELECT sp_return_movement(pg_temp.id('evD'), ARRAY[pg_temp.id('a5')], CURRENT_DATE - 1, 't098-admin@example.test') AS j;
SELECT pg_temp.ok((SELECT j->>'returned' = '1' AND j->>'still_open' = '1' AND j->>'event_state' = 'OPEN' FROM t098_r),
                  'E11 partial return: 1 returned, 1 still open, event stays OPEN');
SELECT pg_temp.ok((SELECT event_state FROM vw_livestock_out_on_loan WHERE cattle_livestock_id = pg_temp.id('a6')) = 'OPEN',
                  'E12 the view agrees: event OPEN');
DELETE FROM t098_r;
INSERT INTO t098_r SELECT sp_return_movement(pg_temp.id('evD'), ARRAY[pg_temp.id('a5')], CURRENT_DATE - 1, 't098-admin@example.test');
SELECT pg_temp.ok((SELECT j->>'returned' = '0' AND j->>'already_closed' = '1' AND j->>'still_open' = '1' FROM t098_r),
                  'E13 repeating the same return: returned=0, already_closed=1');
SELECT pg_temp.ok((SELECT returned_at IS NOT NULL AND return_status = 'RETURNED' FROM cattle_movement_event_animals
                    WHERE event_id = pg_temp.id('evD') AND cattle_livestock_id = pg_temp.id('a5')),
                  'E14 the closed row keeps its history (status and returned_at)');
-- Close the rest with NULL (= every OPEN animal)
DELETE FROM t098_r;
INSERT INTO t098_r SELECT sp_return_movement(pg_temp.id('evD'), NULL, CURRENT_DATE, 't098-admin@example.test');
SELECT pg_temp.ok((SELECT j->>'returned' = '1' AND j->>'still_open' = '0' AND j->>'event_state' = 'RETURNED' FROM t098_r),
                  'E15 closing the rest: event_state RETURNED');
DELETE FROM t098_r;
INSERT INTO t098_r SELECT sp_return_movement(pg_temp.id('evD'), NULL, CURRENT_DATE, 't098-admin@example.test');
SELECT pg_temp.ok((SELECT j->>'returned' = '0' AND j->>'already_closed' = '0' AND j->>'event_state' = 'RETURNED' FROM t098_r),
                  'E16 repeating the NULL return is a no-op');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_movement_event_animals WHERE event_id = pg_temp.id('evD')) = 2,
                  'E17 no loan row was deleted');
SELECT pg_temp.ok(pg_temp.loc(pg_temp.id('a5')) = (SELECT l FROM t098_loc WHERE k = 'a5')
                  AND (SELECT production_unit_id IS NOT NULL FROM cattle_livestock WHERE id = pg_temp.id('a5')),
                  'E18 the return left production_unit_id, lot_id and upp_origen untouched (no NULL, tenant trigger happy)');
SELECT pg_temp.ok((SELECT current_status FROM cattle_livestock WHERE id = pg_temp.id('a5')) = 'ACTIVO',
                  'E19 the return did not change the animal status');
-- After the return the animal can be sold again
SELECT pg_temp.ok((sp_procesar_salida_ganado(NULL::varchar, 9801, '9801000005'::varchar, NULL::varchar, NULL::uuid)->>'success')::boolean,
                  'E20 after the return the animal can be sold');

-- ---------------------------------------------------------------------------------------------
-- F. Death while out: DIED_AWAY, and closing rows of sold / dead animals
-- ---------------------------------------------------------------------------------------------
UPDATE cattle_livestock SET current_status = 'BAJA_MORTANDAD' WHERE id = pg_temp.id('a2');
SELECT pg_temp.ok((SELECT return_status = 'DIED_AWAY' AND returned_at IS NOT NULL FROM cattle_movement_event_animals
                    WHERE event_id = pg_temp.id('evA') AND cattle_livestock_id = pg_temp.id('a2')),
                  'F1 a death while out closes the row as DIED_AWAY');
SELECT pg_temp.ok((SELECT production_unit_id IS NOT NULL FROM cattle_livestock WHERE id = pg_temp.id('a2')),
                  'F2 the DIED_AWAY close did not null production_unit_id (no clash with the tenant trigger)');
SELECT pg_temp.ok((SELECT event_state FROM vw_livestock_out_on_loan WHERE cattle_livestock_id = pg_temp.id('a1')) = 'OPEN',
                  'F3 the other animal of the event is still OPEN, so the event is OPEN');
-- An OPEN row whose animal was sold by a path that bypassed the guard: closing must still work.
SELECT pg_temp.loan('evE', 'a9');
ALTER TABLE cattle_livestock DISABLE TRIGGER trg_block_out_on_loan_status;
UPDATE cattle_livestock SET current_status = 'VENDIDO' WHERE id = pg_temp.id('a9');
ALTER TABLE cattle_livestock ENABLE TRIGGER trg_block_out_on_loan_status;
SELECT pg_temp.ok((SELECT j->>'returned' = '1' FROM (SELECT sp_return_movement(pg_temp.id('evE'), ARRAY[pg_temp.id('a9')], CURRENT_DATE, 't098-admin@example.test') AS j) x),
                  'F4 a row of a sold animal can still be closed with sp_return_movement');
SELECT pg_temp.expect(format($q$UPDATE cattle_movement_event_animals SET return_status = 'OPEN', returned_at = NULL WHERE event_id = %L AND cattle_livestock_id = %L$q$,
                             pg_temp.id('evE'), pg_temp.id('a9')),
                      'P0100', 'F5 re-opening the row of a sold animal is rejected (guard fires on the OPEN transition)');
SELECT pg_temp.ok((SELECT event_state FROM vw_livestock_out_on_loan WHERE event_id = pg_temp.id('evE') LIMIT 1) = 'RETURNED',
                  'F6 event_state RETURNED when nothing is open and at least one RETURNED');
UPDATE cattle_movement_event_animals SET return_status = 'CANCELLED', returned_at = NULL
 WHERE event_id = pg_temp.id('evE') AND cattle_livestock_id = pg_temp.id('a9');
SELECT pg_temp.ok((SELECT DISTINCT event_state FROM vw_livestock_out_on_loan WHERE event_id = pg_temp.id('evE')) = 'CLOSED',
                  'F7 event_state CLOSED when every row is CANCELLED or DIED_AWAY');

-- ---------------------------------------------------------------------------------------------
-- I. A sale already PENDING when the animal goes out: approving it must fail with P0098 and leave the request PENDING.
--    The approval path is sp_resolver_autorizacion -> sp_procesar_venta_autorizada (not sp_procesar_salida_ganado).
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.animal('p1', 9801, 'puA', 'ACTIVO', '9801000030');   -- will go out after its sale request
SELECT pg_temp.animal('p2', 9801, 'puA', 'ACTIVO', '9801000031');   -- control: same flow, never goes out
SELECT pg_temp.ok(
    (sp_solicitar_venta_orden('[{"identificador":"9801000030","guia_transito":"G-P"},{"identificador":"9801000031","guia_transito":"G-P"}]'::jsonb,
                              't098-admin@example.test', NULL, false, 'TEST') ->> 'solicitudes')::int = 2,
    'I1 two sale requests are PENDING (order created before any loan)');
SELECT pg_temp.loan('evA', 'p1');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_movement_event_animals WHERE cattle_livestock_id = pg_temp.id('p1') AND return_status = 'OPEN') = 1,
                  'I2 the animal with a pending sale request can still go out on loan (decision: the approval is what fails)');
SELECT pg_temp.expect(format($q$SELECT sp_resolver_autorizacion(%L, 'APROBADO', 't098-admin@example.test', NULL,
        '{"modo_venta":"POR_PIEZA","precio_venta":"1000","comprador":"T098 Buyer","forma_pago":"EFECTIVO"}'::jsonb)$q$,
        (SELECT id FROM pending_authorizations WHERE livestock_id = pg_temp.id('p1'))),
    'P0098', 'I3 approving a pending sale of an animal now on loan fails with P0098', '%7139728-T098%');
SELECT pg_temp.ok((SELECT estado FROM pending_authorizations WHERE livestock_id = pg_temp.id('p1')) = 'PENDIENTE'
                  AND (SELECT current_status FROM cattle_livestock WHERE id = pg_temp.id('p1')) = 'ACTIVO'
                  AND (SELECT count(*) FROM cattle_sale_income WHERE livestock_id = pg_temp.id('p1')) = 0,
                  'I4 the failed approval left the request PENDIENTE, the animal ACTIVO and no sale income');
SELECT pg_temp.ok(
    (sp_resolver_autorizacion((SELECT id FROM pending_authorizations WHERE livestock_id = pg_temp.id('p2')), 'APROBADO', 't098-admin@example.test', NULL,
        '{"modo_venta":"POR_PIEZA","precio_venta":"1000","comprador":"T098 Buyer","forma_pago":"EFECTIVO"}'::jsonb) ->> 'estado') = 'APROBADO',
    'I5 control: the same approval for an animal that is NOT on loan succeeds');
-- Rejecting the stuck request is still possible (this is how an admin clears it).
SELECT pg_temp.ok(
    (sp_resolver_autorizacion((SELECT id FROM pending_authorizations WHERE livestock_id = pg_temp.id('p1')), 'RECHAZADO', 't098-admin@example.test',
        'Animal out on loan', NULL) ->> 'estado') = 'RECHAZADO',
    'I6 the stuck request can be rejected by an admin');

-- ---------------------------------------------------------------------------------------------
-- G. Re-apply is idempotent
-- ---------------------------------------------------------------------------------------------
\i 098_repasto_return_movements.sql
SELECT pg_temp.ok(md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) = :'md5_patched',
                  'G1 applying 098 twice leaves sp_solicitar_venta_orden unchanged');

-- ---------------------------------------------------------------------------------------------
-- H. Rollback with cancel_open=true, including an OPEN row whose animal has no production unit
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.animal('r1', 9801, 'puA', 'ACTIVO', '9801000020');
SELECT pg_temp.animal('r2', 9801, 'puA', 'ACTIVO', '9801000021');
SELECT pg_temp.loan('evE', 'r1');
SELECT pg_temp.loan('evE', 'r2');
UPDATE cattle_livestock SET production_unit_id = NULL, lot_id = NULL WHERE id = pg_temp.id('r2');
SELECT pg_temp.expect(format($q$UPDATE cattle_movement_event_animals SET return_status = 'CANCELLED' WHERE cattle_livestock_id = %L$q$, pg_temp.id('r2')),
                      'P0001', 'H1 precondition: updating a row whose animal has no production unit hits the tenant trigger', '%no resolvable tenant%');
SELECT count(*) AS open_before FROM cattle_movement_event_animals WHERE return_status = 'OPEN' \gset
\set cancel_open true
\i 098_rollback.sql
SELECT pg_temp.ok((SELECT return_status FROM cattle_movement_event_animals WHERE cattle_livestock_id = pg_temp.id('r1')) = 'CANCELLED',
                  'H2 rollback with cancel_open cancels the rows it can');
SELECT pg_temp.ok((SELECT return_status FROM cattle_movement_event_animals WHERE cattle_livestock_id = pg_temp.id('r2')) = 'OPEN',
                  'H3 the row whose animal has no production unit is skipped, not an error, and stays OPEN');
SELECT pg_temp.ok(md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) = :'md5_before_098',
                  'H4 rollback restores sp_solicitar_venta_orden to the exact pre-098 definition (md5)');
SELECT pg_temp.ok((SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_block_out_on_loan_status', 'trg_close_loan_on_death', 'trg_guard_movement_animal_open')
                      AND tgenabled = 'D') = 3,
                  'H5 the three guard triggers are disabled');
SELECT pg_temp.ok((SELECT sp_return_movement(pg_temp.id('evA'), NULL, CURRENT_DATE, 't098-admin@example.test') ->> 'status') = 'disabled',
                  'H6 sp_return_movement is a stub that answers disabled');
SELECT pg_temp.ok((SELECT count(*) FROM vw_livestock_out_on_loan) = 0, 'H7 the loan view is empty after the rollback');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_movement_event_animals WHERE return_status IS NOT NULL) > 0,
                  'H8 no loan row was deleted by the rollback (history kept)');
-- While rolled back, an OPEN animal is NOT protected (documented in the runbook)
UPDATE cattle_livestock SET current_status = 'FINALIZADO' WHERE id = pg_temp.id('r2');
SELECT pg_temp.ok(true, 'H9 while rolled back, an animal with an OPEN row is no longer protected (expected, documented)');
\i 098_rollback.sql
SELECT pg_temp.ok(true, 'H10 running the rollback twice is harmless');

-- Re-apply after a rollback: protection is back
\i 098_repasto_return_movements.sql
SELECT pg_temp.ok(md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) = :'md5_patched',
                  'H11 re-applying after a rollback gives the same patched md5');
SELECT pg_temp.ok((SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_block_out_on_loan_status', 'trg_close_loan_on_death', 'trg_guard_movement_animal_open')
                      AND tgenabled = 'O') = 3,
                  'H12 the three guard triggers are enabled again');

-- ---------------------------------------------------------------------------------------------
SELECT count(*) AS passed FROM t098_res \gset
\echo
\echo *** 098 TESTS: :passed assertions passed; rolling back, nothing is kept ***
ROLLBACK;
