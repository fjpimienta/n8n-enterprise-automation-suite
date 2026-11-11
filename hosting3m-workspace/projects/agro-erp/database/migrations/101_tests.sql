-- 101_tests.sql
-- Tests for 101 (REGULARIZACION branch in vw_cattle_event_log). LOCAL / throw-away database ONLY: it needs the schema with
-- migrations 060-067 applied (the view in its 067 state) and cattle_livestock. Everything happens inside ONE transaction that
-- ends in ROLLBACK; nothing is kept. Usage: psql -X -v ON_ERROR_STOP=1 -f 101_tests.sql
-- A failed assertion raises 'FAIL [label]' and stops the run.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL [%]', p_label; END IF;
    RAISE NOTICE 'PASS [%]', p_label;
END $$;

CREATE FUNCTION pg_temp.cols() RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
      FROM pg_attribute a WHERE a.attrelid = 'public.vw_cattle_event_log'::regclass AND a.attnum > 0 AND NOT a.attisdropped
$$;
CREATE FUNCTION pg_temp.defmd5() RETURNS text LANGUAGE sql AS $$
    SELECT md5(regexp_replace(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true), '\s+', ' ', 'g'))
$$;

-- ---------------------------------------------------------------------------------------------
-- Fixtures: two synthetic companies. The metadata of the regularization animals mirrors what 099 writes (including the keys the
-- view must NOT show: preview_hash and registered_by).
-- ---------------------------------------------------------------------------------------------
INSERT INTO companys (id_company, company_name, industry, is_active) VALUES
    (9831, 'T101 Uno', 'ganaderia', true), (9832, 'T101 Otra', 'ganaderia', true);
INSERT INTO cattle_livestock (id, tenant_id, species, category, business_model, current_status, rfid_siniiga, metadata) VALUES
    ('00000000-0000-4101-8000-000000000001', 9831, 'BOVINO', 'BECERRO', 'CRIA', 'ACTIVO', '9983100001',
     '{"source":"REGULARIZACION_PADRON","guide_folio":"G-0001","origin_upp_code":"07-123-4567-890","reported_age_months":8,
       "category_reported":"BECERRO","registered_by":"secret-actor@example.test","channel":"CHAT_WEB","notes":"nota de prueba",
       "preview_hash":"deadbeefdeadbeefdeadbeefdeadbeef","tool":"sp_register_livestock_regularization","migration":"099"}'),
    ('00000000-0000-4101-8000-000000000002', 9832, 'BOVINO', 'BECERRO', 'CRIA', 'ACTIVO', '9983200001',
     '{"source":"REGULARIZACION_PADRON","guide_folio":"G-0002","channel":"WHATSAPP"}'),
    ('00000000-0000-4101-8000-000000000003', 9831, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9983100002',
     '{"source":"COMPRA","seller_name":"Vendedor T101","purchase_price":"1000","purchase_date":"2026-11-01"}'),
    ('00000000-0000-4101-8000-000000000004', 9831, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9983100003', '{}'),
    ('00000000-0000-4101-8000-000000000005', 9831, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9983100004', '{"source":"OTRO"}');

-- Snapshot BEFORE (067 state): every row and the column list.
SELECT pg_temp.ok(pg_temp.defmd5() = '726fdf2e20ca6848deb0b1d7cfef66b9', 'A1 the view starts as the 067 definition');
CREATE TEMP TABLE t101_before AS SELECT id, event_type, tenant_id, livestock_id, md5(v::text) AS row_md5 FROM public.vw_cattle_event_log v;
CREATE TEMP TABLE t101_cols (k text PRIMARY KEY, v text);
INSERT INTO t101_cols VALUES ('cols', pg_temp.cols()), ('def', pg_temp.defmd5());
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM t101_before WHERE event_type = 'REGULARIZACION'), 'A2 no REGULARIZACION rows before');
SELECT pg_temp.ok((SELECT count(*) FROM t101_before WHERE event_type = 'COMPRA' AND livestock_id = '00000000-0000-4101-8000-000000000003') = 1, 'A3 the COMPRA fixture is in the view');

-- ---------------------------------------------------------------------------------------------
-- B. Apply 101.
-- ---------------------------------------------------------------------------------------------
\set embedded 1
\ir 101_event_log_regularization.sql
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log WHERE livestock_id = '00000000-0000-4101-8000-000000000001' AND event_type = 'REGULARIZACION') = 1,
                  'B1 a REGULARIZACION_PADRON animal has exactly one REGULARIZACION row');
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log WHERE livestock_id = '00000000-0000-4101-8000-000000000001') = 1,
                  'B2 and no other row for that animal');
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION' AND tenant_id = 9831) = 1
                  AND (SELECT count(*) FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION' AND tenant_id = 9832) = 1,
                  'B3 each tenant sees only its own REGULARIZACION animal when filtered by tenant');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE tenant_id = 9831 AND livestock_id = '00000000-0000-4101-8000-000000000002'),
                  'B4 the animal of the other company does not appear under tenant 9831');
SELECT pg_temp.ok((SELECT description FROM public.vw_cattle_event_log WHERE livestock_id = '00000000-0000-4101-8000-000000000001' AND event_type = 'REGULARIZACION')
                  = 'Alta por regularización de padrón — Guía: G-0001 — UPP origen de la guía: 07-123-4567-890 — Edad aproximada: 8 meses — Categoría dictada: BECERRO — Canal: CHAT_WEB — nota de prueba',
                  'B5 the description is built from the 099 keys');
SELECT pg_temp.ok((SELECT description FROM public.vw_cattle_event_log WHERE livestock_id = '00000000-0000-4101-8000-000000000002' AND event_type = 'REGULARIZACION')
                  = 'Alta por regularización de padrón — Guía: G-0002 — Canal: WHATSAPP',
                  'B6 missing keys are skipped (no empty segments)');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION'
                               AND (description LIKE '%deadbeef%' OR description LIKE '%secret-actor%' OR description LIKE '%example.test%'
                                    OR medicines_json IS NOT NULL)),
                  'B7 neither preview_hash nor the registering e-mail is exposed');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE livestock_id IN
                              ('00000000-0000-4101-8000-000000000004', '00000000-0000-4101-8000-000000000005') AND event_type = 'REGULARIZACION'),
                  'B8 animals without source (or with another source) produce no REGULARIZACION row');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM t101_before b WHERE NOT EXISTS (
                      SELECT 1 FROM public.vw_cattle_event_log v WHERE v.id = b.id AND v.event_type = b.event_type AND md5(v::text) = b.row_md5)),
                  'B9 every row of the 067 view is still there, identical (COMPRA, PESO, SALUD, PARTO, ...)');
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log) = (SELECT count(*) FROM t101_before) + 2,
                  'B10 exactly the two new rows were added');
SELECT pg_temp.ok(pg_temp.cols() = (SELECT v FROM t101_cols WHERE k = 'cols'), 'B11 columns and types are identical to before');
SELECT pg_temp.ok((SELECT event_date FROM public.vw_cattle_event_log WHERE livestock_id = '00000000-0000-4101-8000-000000000001' AND event_type = 'REGULARIZACION')
                  = fn_event_ts_cdmx(NULL, (SELECT created_at FROM public.cattle_livestock WHERE id = '00000000-0000-4101-8000-000000000001')),
                  'B12 the event date goes through fn_event_ts_cdmx like COMPRA');

-- C. State check accepts the applied state.
\set expect applied
\ir 101_state_check.sql
SELECT pg_temp.ok(true, 'C1 state check: applied');

-- D. Idempotence.
\ir 101_event_log_regularization.sql
SELECT pg_temp.ok(pg_temp.cols() = (SELECT v FROM t101_cols WHERE k = 'cols'), 'D1 second apply keeps the columns');
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log) = (SELECT count(*) FROM t101_before) + 2, 'D2 second apply adds nothing');

-- E. Rollback returns the 067 definition, twice.
\ir 101_rollback.sql
SELECT pg_temp.ok(pg_temp.defmd5() = (SELECT v FROM t101_cols WHERE k = 'def'), 'E1 rollback restores the 067 definition (normalized md5)');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION'), 'E2 no REGULARIZACION rows after rollback');
SELECT pg_temp.ok(pg_temp.cols() = (SELECT v FROM t101_cols WHERE k = 'cols'), 'E3 rollback keeps columns and types');
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log) = (SELECT count(*) FROM t101_before), 'E4 same row count as the original');
\set expect before
\ir 101_state_check.sql
SELECT pg_temp.ok(true, 'E5 state check: before');
\ir 101_rollback.sql
SELECT pg_temp.ok(pg_temp.defmd5() = (SELECT v FROM t101_cols WHERE k = 'def'), 'E6 second rollback is a no-op');

-- F. Apply again after the rollback, then roll back again.
\ir 101_event_log_regularization.sql
SELECT pg_temp.ok((SELECT count(*) FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION') = 2, 'F1 re-apply works');
\ir 101_rollback.sql
SELECT pg_temp.ok(pg_temp.defmd5() = (SELECT v FROM t101_cols WHERE k = 'def'), 'F2 final state = original');

\echo === 101 TESTS PASSED (everything rolled back)
ROLLBACK;
