-- 108_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). Everything runs inside ONE transaction that is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 108_tests.sql
-- Needs migrations 028, 086 and 090 applied (this file includes 108_palpation_views.sql, 108_state_check.sql and 108_rollback.sql with `embedded` set).
-- 100% SYNTHETIC data: two fictitious companies (A and B), fictitious animals with identifiers that start with 9999 (no real INEGI state code), a fictitious brand.
-- No data of any real company is read or written. The gateway itself (n8n) is not exercised here: the operation / role check of its "Security Validation" node
-- and the company filter of "Build Query" are reproduced in SQL; the real node is exercised by 108_gateway_tests.md (LOCAL gateway).
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;

CREATE TEMP TABLE snap (k text PRIMARY KEY, v text) ON COMMIT DROP;
INSERT INTO snap SELECT 'others_before', coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
  FROM public.crud_models c WHERE c.model_name NOT IN ('vw_palpation_events', 'vw_palpation_herd');

\set embedded true
\set expect before
\ir 108_state_check.sql
\ir 108_palpation_views.sql
\set expect applied
\ir 108_state_check.sql

-- Helpers ------------------------------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.eq(p_name text, p_got anyelement, p_expected anyelement) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_expected THEN
        RAISE EXCEPTION 'FAIL %: got <%> expected <%>', p_name, p_got, p_expected;
    END IF;
    RAISE NOTICE 'PASS %', p_name;
END $$;

-- The operation / role check of Security Validation: getall / getone are "select"; call_sp is "insert".
CREATE FUNCTION pg_temp.can(p_model text, p_op text, p_role text) RETURNS boolean LANGUAGE sql AS $$
    SELECT coalesce(bool_or(
        (CASE WHEN lower(p_op) IN ('getall', 'getone', 'select', 'list') THEN 'select' WHEN lower(p_op) = 'call_sp' THEN 'insert' ELSE lower(p_op) END)
            = ANY (SELECT lower(o) FROM unnest(m.allowed_ops) o)
        AND upper(p_role) = ANY (SELECT upper(btrim(r)) FROM unnest(string_to_array(
            CASE WHEN lower(p_op) IN ('getall', 'getone', 'select', 'list') THEN m.allowed_roles_select
                 WHEN lower(p_op) IN ('insert', 'call_sp') THEN m.allowed_roles_insert
                 WHEN lower(p_op) = 'update' THEN m.allowed_roles_update
                 ELSE m.allowed_roles_delete END, ',')) r)), false)
      FROM public.crud_models m WHERE m.model_name = p_model $$;

-- Fixtures ------------------------------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE an  (label text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP TABLE ev  (label text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE seq_ear START 1;

CREATE FUNCTION pg_temp.mk_animal(p_label text, p_company integer, p_status text, p_brand uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, brand_id)
    VALUES (p_company, '9999' || lpad(nextval('seq_ear')::text, 6, '0'), 'CRIA', 'VACA', p_status, p_brand) RETURNING id INTO v_id;
    INSERT INTO an VALUES (p_label, v_id);
END $$;

-- One palpation event (plus an optional details row of 086). p_json is the raw medicines_json.
CREATE FUNCTION pg_temp.mk_event(p_label text, p_animal text, p_company integer, p_date timestamp, p_json jsonb,
                                 p_type text DEFAULT 'PALPACION', p_det_result text DEFAULT NULL, p_raw text DEFAULT NULL,
                                 p_cond text DEFAULT NULL, p_map text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_an uuid := (SELECT id FROM an WHERE label = p_animal);
BEGIN
    INSERT INTO public.cattle_health_logs (livestock_id, event_type, event_date, medicines_json)
    VALUES (v_an, p_type, p_date, p_json) RETURNING id INTO v_id;
    INSERT INTO ev VALUES (p_label, v_id);
    IF p_det_result IS NOT NULL THEN
        INSERT INTO public.palpation_repro_details (id_company, health_log_id, livestock_id, result, raw_code, repro_condition, mapping_status, registered_by_email)
        VALUES (p_company, v_id, v_an, p_det_result, p_raw, p_cond, p_map, 'synthetic@example.invalid');
    END IF;
END $$;

DO $$
DECLARE ca integer; cb integer; v_brand uuid;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T108 Cattle A', 'Ganaderia') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T108 Cattle B', 'Ganaderia') RETURNING id_company INTO cb;
    INSERT INTO ctx VALUES ('a', ca::text), ('b', cb::text);

    INSERT INTO public.brand_registrations (brand_code, owner_name) VALUES ('ZZ1', 'Synthetic Owner') RETURNING id INTO v_brand;

    -- Ranch / unconfirmed codes. Company B has the SAME code 'NR' with another meaning: company A must keep its own (PRIMARY KEY (id_company, code)).
    INSERT INTO public.repro_condition_codes (id_company, code, repro_condition, source, meaning) VALUES
        (ca, 'NR',      NULL, 'TEST', 'NOT_EXAMINED'),
        (ca, 'RP',      NULL, 'TEST', 'POSTPARTUM'),
        (ca, 'NO APTO', NULL, 'TEST', 'UNFIT'),
        (ca, 'DF15',    NULL, 'TEST', 'UNFIT'),      -- a meaning exists for DF15, but the event is UNMAPPED: code_meaning must still be NULL
        (cb, 'NR',      NULL, 'TEST', 'UNFIT');

    -- Company A animals
    PERFORM pg_temp.mk_animal('A01', ca, 'PREÑADA');      -- historical load, pregnant
    PERFORM pg_temp.mk_animal('A02', ca, 'PREÑADA', v_brand);  -- new format, pregnant, with detail and technician, branded
    PERFORM pg_temp.mk_animal('A03', ca, 'VACÍA');        -- new, empty, CICLANDO (explicit)
    PERFORM pg_temp.mk_animal('A04', ca, 'VACÍA');        -- new, empty, UNMAPPED code DF15
    PERFORM pg_temp.mk_animal('A05', ca, 'ACTIVO');       -- NR (not examined)
    PERFORM pg_temp.mk_animal('A06', ca, 'VACÍA');        -- RP
    PERFORM pg_temp.mk_animal('A07', ca, 'VACÍA');        -- NO APTO
    PERFORM pg_temp.mk_animal('A08', ca, 'PREÑADA');      -- MATRIZ OCUPADA
    PERFORM pg_temp.mk_animal('A09', ca, 'PREÑADA');      -- pregnant without usable gestation days
    PERFORM pg_temp.mk_animal('A10', ca, 'ACTIVO');       -- never palpated
    PERFORM pg_temp.mk_animal('A11', ca, 'VENDIDO');      -- sold, historical palpation only
    PERFORM pg_temp.mk_animal('A12', ca, 'PREÑADA');      -- two palpations + a non-palpation event
    PERFORM pg_temp.mk_animal('A13', ca, 'VACÍA');        -- accented event type, no detail row
    PERFORM pg_temp.mk_animal('A14', ca, 'ACTIVO');       -- medicines_json is not an object
    -- Company B animals
    PERFORM pg_temp.mk_animal('B01', cb, 'PREÑADA');
    PERFORM pg_temp.mk_animal('B02', cb, 'ACTIVO');       -- never palpated
    PERFORM pg_temp.mk_animal('B03', cb, 'VENDIDO');

    -- Company A events
    PERFORM pg_temp.mk_event('A01', 'A01', ca, '2023-07-20 00:00:00', '{"resultado":"PRENADA","dias_gestacion":"180"}');
    PERFORM pg_temp.mk_event('A02', 'A02', ca, '2026-11-05 10:30:00', '{"result":"PRENADA","gestation_days":"90","technician_name":"Synthetic Tech"}',
                             'PALPACION', 'PREÑADA', NULL, NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A03', 'A03', ca, '2026-11-06 09:00:00', '{"result":"VACIA"}',
                             'PALPACION', 'VACÍA', 'CICLANDO', 'CICLANDO', 'EXPLICIT');
    PERFORM pg_temp.mk_event('A04', 'A04', ca, '2026-11-06 09:10:00', '{"result":"VACIA"}',
                             'PALPACION', 'VACÍA', 'DF15', NULL, 'UNMAPPED');
    PERFORM pg_temp.mk_event('A05', 'A05', ca, '2026-11-07 08:00:00', '{"result":"VACIA"}',
                             'PALPACION', 'VACÍA', 'NR', NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A06', 'A06', ca, '2026-11-07 08:05:00', '{"result":"VACIA"}',
                             'PALPACION', 'VACÍA', 'RP', NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A07', 'A07', ca, '2026-11-07 08:10:00', '{"result":"VACIA"}',
                             'PALPACION', 'VACÍA', 'NO APTO', NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A08', 'A08', ca, '2026-11-07 08:15:00', '{"result":"PRENADA"}',
                             'PALPACION', 'PREÑADA', 'MATRIZ OCUPADA', NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A09', 'A09', ca, '2026-11-07 08:20:00', '{"result":"PRENADA","gestation_days":"0"}',
                             'PALPACION', 'PREÑADA', NULL, NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A11', 'A11', ca, '2023-07-20 00:00:00', '{"resultado":"VACIA"}');
    -- A12a carries BOTH keys (mixed format): it is NOT the historical load, which is "resultado without result".
    PERFORM pg_temp.mk_event('A12a', 'A12', ca, '2026-10-01 07:00:00', '{"result":"VACIA","resultado":"VACIA"}');
    PERFORM pg_temp.mk_event('A12b', 'A12', ca, '2026-11-08 07:00:00', '{"result":"PRENADA","gestation_days":"60"}',
                             'PALPACION', 'PREÑADA', NULL, NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('A12v', 'A12', ca, '2026-11-09 07:00:00', '{"vaccine":"synthetic"}', 'VACUNACION');
    PERFORM pg_temp.mk_event('A13', 'A13', ca, '2026-11-08 07:30:00', '{"result":"VACIA"}', 'PALPACIÓN');
    PERFORM pg_temp.mk_event('A14', 'A14', ca, '2026-11-08 07:40:00', '[]');
    -- Company B events
    PERFORM pg_temp.mk_event('B01', 'B01', cb, '2026-11-05 10:00:00', '{"result":"PRENADA","gestation_days":"120","technician_name":"Synthetic Tech B"}',
                             'PALPACION', 'PREÑADA', NULL, NULL, 'NOT_APPLICABLE');
    PERFORM pg_temp.mk_event('B03', 'B03', cb, '2023-07-20 00:00:00', '{"resultado":"VACIA"}');
END $$;

SELECT v::integer AS ca FROM ctx WHERE k = 'a' \gset
SELECT v::integer AS cb FROM ctx WHERE k = 'b' \gset

-- 1) vw_palpation_events, company A ------------------------------------------------------------------------------------------------------------
SELECT pg_temp.eq('A events (the VACUNACION event is excluded)', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca), 14::bigint);
SELECT pg_temp.eq('A result PREÑADA', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND result = 'PREÑADA'), 5::bigint);
SELECT pg_temp.eq('A result VACÍA',   (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND result = 'VACÍA'), 8::bigint);
SELECT pg_temp.eq('A result NULL (medicines_json not an object)', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND result IS NULL), 1::bigint);
SELECT pg_temp.eq('A historical load (key resultado without result)', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND is_historical_load), 2::bigint);
SELECT pg_temp.eq('A event with both keys is not historical',
       (SELECT is_historical_load FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A12a')), false);
SELECT pg_temp.eq('A historical event keeps gestation from dias_gestacion',
       (SELECT gestation_days FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A01')), 180);
SELECT pg_temp.eq('A historical event has no technician',
       (SELECT technician FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A01')), NULL::text);
SELECT pg_temp.eq('A technician only where technician_name exists', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND technician IS NOT NULL), 1::bigint);
SELECT pg_temp.eq('A technician value', (SELECT technician FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A02')), 'Synthetic Tech');
SELECT pg_temp.eq('A gestation days present', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND gestation_days IS NOT NULL), 3::bigint);
SELECT pg_temp.eq('A pregnant without usable gestation (0 days) is NULL',
       (SELECT gestation_days FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A09')), NULL::integer);
SELECT pg_temp.eq('A CICLANDO subtype only from the details row', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND repro_condition = 'CICLANDO'), 1::bigint);
SELECT pg_temp.eq('A UNMAPPED events', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND mapping_status = 'UNMAPPED'), 1::bigint);
SELECT pg_temp.eq('A UNMAPPED keeps the raw code', (SELECT raw_code FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A04')), 'DF15');
SELECT pg_temp.eq('A UNMAPPED forces code_meaning NULL even if the code has a meaning',
       (SELECT code_meaning FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A04')), NULL::text);
SELECT pg_temp.eq('A UNMAPPED is not a ranch term', (SELECT ranch_term FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A04')), NULL::text);
SELECT pg_temp.eq('A ranch terms', (SELECT string_agg(ranch_term, ',' ORDER BY ranch_term) FROM vw_palpation_events WHERE id_company = :ca AND ranch_term IS NOT NULL),
                  'MATRIZ OCUPADA,NO APTO,NR,RP');
SELECT pg_temp.eq('A NR takes the meaning of ITS company, not the same code of company B',
       (SELECT code_meaning FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A05')), 'NOT_EXAMINED');
SELECT pg_temp.eq('A NR does not count as a palpation', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND NOT counts_as_palpation), 1::bigint);
SELECT pg_temp.eq('A clinical results exclude ranch terms and NULL results', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :ca AND is_clinical_result), 9::bigint);
SELECT pg_temp.eq('A MATRIZ OCUPADA is pregnant but not clinical',
       (SELECT result || '/' || is_clinical_result::text FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A08')), 'PREÑADA/false');
SELECT pg_temp.eq('A accented event type is a palpation', (SELECT count(*) FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A13')), 1::bigint);
SELECT pg_temp.eq('A non-palpation event is excluded', (SELECT count(*) FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A12v')), 0::bigint);
SELECT pg_temp.eq('A event_date is a plain date (no time-zone shift)',
       (SELECT event_date FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'A02')), DATE '2026-11-05');

-- 2) vw_palpation_events, company B and isolation -----------------------------------------------------------------------------------------------
SELECT pg_temp.eq('B events', (SELECT count(*) FROM vw_palpation_events WHERE id_company = :cb), 2::bigint);
SELECT pg_temp.eq('B events contain no event of A',
       (SELECT count(*) FROM vw_palpation_events e JOIN ev ON ev.id = e.health_log_id WHERE e.id_company = :cb AND ev.label NOT IN ('B01', 'B03')), 0::bigint);
SELECT pg_temp.eq('A events contain no event of B',
       (SELECT count(*) FROM vw_palpation_events e JOIN ev ON ev.id = e.health_log_id WHERE e.id_company = :ca AND ev.label IN ('B01', 'B03')), 0::bigint);
SELECT pg_temp.eq('every event row carries the company of its animal',
       (SELECT count(*) FROM vw_palpation_events e JOIN public.cattle_livestock l ON l.id = e.livestock_id WHERE e.id_company <> l.tenant_id), 0::bigint);
SELECT pg_temp.eq('no row of a third company', (SELECT count(*) FROM vw_palpation_events e JOIN ev ON ev.id = e.health_log_id WHERE e.id_company NOT IN (:ca, :cb)), 0::bigint);

-- 3) vw_palpation_herd --------------------------------------------------------------------------------------------------------------------------
SELECT pg_temp.eq('A herd rows (whole herd, palpated or not)', (SELECT count(*) FROM vw_palpation_herd WHERE id_company = :ca), 14::bigint);
SELECT pg_temp.eq('B herd rows', (SELECT count(*) FROM vw_palpation_herd WHERE id_company = :cb), 3::bigint);
SELECT pg_temp.eq('A animals with at least one counted palpation', (SELECT count(*) FROM vw_palpation_herd WHERE id_company = :ca AND palpation_count > 0), 12::bigint);
SELECT pg_temp.eq('A never palpated (A10) and NR only (A05)', (SELECT count(*) FROM vw_palpation_herd WHERE id_company = :ca AND palpation_count = 0), 2::bigint);
SELECT pg_temp.eq('A animals with more than one palpation', (SELECT count(*) FROM vw_palpation_herd WHERE id_company = :ca AND palpation_count > 1), 1::bigint);
SELECT pg_temp.eq('A last palpation of the animal with two',
       (SELECT last_event_date::text || '/' || last_result FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'A12')), '2026-11-08/PREÑADA');
SELECT pg_temp.eq('A NR-only animal has no last palpation', (SELECT last_event_date FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'A05')), NULL::date);
SELECT pg_temp.eq('A sold animal keeps status and historical flag',
       (SELECT current_status || '/' || last_is_historical::text FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'A11')), 'VENDIDO/true');
SELECT pg_temp.eq('A never palpated has NULL last result', (SELECT last_result FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'A10')), NULL::text);
SELECT pg_temp.eq('A ranch term of the last palpation', (SELECT last_ranch_term FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'A06')), 'RP');
SELECT pg_temp.eq('brand_code comes only from the registered brand', (SELECT string_agg(brand_code, ',') FROM vw_palpation_herd WHERE id_company = :ca AND brand_code IS NOT NULL), 'ZZ1');
SELECT pg_temp.eq('herd view carries the animal key', (SELECT count(DISTINCT livestock_id) FROM vw_palpation_herd WHERE id_company = :ca), 14::bigint);
SELECT pg_temp.eq('no herd row of a third company', (SELECT count(*) FROM vw_palpation_herd h JOIN an ON an.id = h.livestock_id WHERE h.id_company NOT IN (:ca, :cb)), 0::bigint);

-- 4) Columns: nothing sensitive ------------------------------------------------------------------------------------------------------------------
SELECT pg_temp.eq('views expose no description / notes / metadata / owner_* / medicines_json / password column',
       (SELECT count(*) FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name IN ('vw_palpation_events', 'vw_palpation_herd')
           AND (column_name ~ '^(description|notes|metadata|medicines_json|password)$' OR column_name ~ '^owner_')), 0::bigint);
SELECT pg_temp.eq('both views have id_company and created_at',
       (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('vw_palpation_events', 'vw_palpation_herd')
           AND column_name IN ('id_company', 'created_at')), 4::bigint);

-- 5) Gateway gate (reproduced from Security Validation) and the filter Build Query adds ----------------------------------------------------------------
SELECT pg_temp.eq('events: ADMIN getall', pg_temp.can('vw_palpation_events', 'getall', 'ADMIN'), true);
SELECT pg_temp.eq('events: EDITOR getall', pg_temp.can('vw_palpation_events', 'getall', 'EDITOR'), true);
SELECT pg_temp.eq('events: EDITOR getone (same select permission)', pg_temp.can('vw_palpation_events', 'getone', 'EDITOR'), true);
SELECT pg_temp.eq('events: CUSTOMER getall denied', pg_temp.can('vw_palpation_events', 'getall', 'CUSTOMER'), false);
SELECT pg_temp.eq('herd: CUSTOMER getall denied', pg_temp.can('vw_palpation_herd', 'getall', 'CUSTOMER'), false);
SELECT pg_temp.eq('herd: ADMIN getall', pg_temp.can('vw_palpation_herd', 'getall', 'ADMIN'), true);
SELECT pg_temp.eq('writes denied for every role and model',
       (SELECT count(*) FROM (VALUES ('vw_palpation_events'), ('vw_palpation_herd')) m(model)
         CROSS JOIN (VALUES ('insert'), ('update'), ('delete'), ('call_sp')) o(op)
         CROSS JOIN (VALUES ('ADMIN'), ('EDITOR'), ('CUSTOMER'), ('OWNER')) r(role)
        WHERE pg_temp.can(m.model, o.op, r.role)), 0::bigint);
-- What Build Query does for getall: fields.id_company = header (only because id_company is in allowed_fields), ORDER BY <table>.created_at DESC LIMIT 1500.
SELECT pg_temp.eq('getall as the gateway builds it, company A', (SELECT count(*) FROM (SELECT * FROM vw_palpation_events WHERE id_company = :ca ORDER BY created_at DESC LIMIT 1500) q), 14::bigint);
SELECT pg_temp.eq('getall as the gateway builds it, company B', (SELECT count(*) FROM (SELECT * FROM vw_palpation_events WHERE id_company = :cb ORDER BY created_at DESC LIMIT 1500) q), 2::bigint);
SELECT pg_temp.eq('getone of an event of B filtered by company A is empty',
       (SELECT count(*) FROM vw_palpation_events WHERE health_log_id = (SELECT id FROM ev WHERE label = 'B01') AND id_company = :ca), 0::bigint);
SELECT pg_temp.eq('getone of an animal of B filtered by company A is empty',
       (SELECT count(*) FROM vw_palpation_herd WHERE livestock_id = (SELECT id FROM an WHERE label = 'B01') AND id_company = :ca), 0::bigint);

-- 6) The migration did not touch anything else ----------------------------------------------------------------------------------------------------
SELECT pg_temp.eq('other crud_models rows unchanged after 108',
       (SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') FROM public.crud_models c
         WHERE c.model_name NOT IN ('vw_palpation_events', 'vw_palpation_herd')), (SELECT v FROM snap WHERE k = 'others_before'));

-- 7) Rollback: models disabled, views and every other row untouched ---------------------------------------------------------------------------------
\ir 108_rollback.sql
\set expect rolled_back
\ir 108_state_check.sql
SELECT pg_temp.eq('after rollback: ADMIN getall denied', pg_temp.can('vw_palpation_events', 'getall', 'ADMIN'), false);
SELECT pg_temp.eq('after rollback: EDITOR getall denied', pg_temp.can('vw_palpation_herd', 'getall', 'EDITOR'), false);
SELECT pg_temp.eq('after rollback: both rows still registered', (SELECT count(*) FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')), 2::bigint);
SELECT pg_temp.eq('after rollback: views still exist', (to_regclass('public.vw_palpation_events') IS NOT NULL AND to_regclass('public.vw_palpation_herd') IS NOT NULL), true);
SELECT pg_temp.eq('other crud_models rows unchanged after the rollback',
       (SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') FROM public.crud_models c
         WHERE c.model_name NOT IN ('vw_palpation_events', 'vw_palpation_herd')), (SELECT v FROM snap WHERE k = 'others_before'));

\echo '*** 108 TESTS PASSED (rolled back) ***'
ROLLBACK;
