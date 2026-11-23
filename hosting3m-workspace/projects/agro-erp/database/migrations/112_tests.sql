-- 112_tests.sql: LOCAL / throwaway database only (name must contain "test" or "rehearsal"). Everything is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 112_tests.sql
-- Works before or after 112 is applied: it includes 104 and 105 when they are missing and 112 when it is not applied (all inside the rolled-back
-- transaction). Uses ONLY synthetic data (fake UUIDs, fake RFCs, fake e-mails, new companies, invented amounts).
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true

SELECT to_regclass('public.agri_sale_invoices') IS NOT NULL AS has104 \gset
\if :has104
\else
\ir 104_agri_sale_invoices.sql
\ir 105_agri_sale_gateway_models.sql
\endif
SELECT pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure) LIKE '%TNE%' AS has112 \gset
\if :has112
\else
\ir 112_agri_sale_multi_concept.sql
\endif

-- Helpers (session-local) -----------------------------------------------------------------------------
CREATE TEMP TABLE tcount (n integer NOT NULL) ON COMMIT DROP;
INSERT INTO tcount VALUES (0);
CREATE FUNCTION pg_temp.chk(p_cond boolean, p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_name; END IF;
    UPDATE tcount SET n = n + 1;
END $$;

CREATE FUNCTION pg_temp.expect_err(p_sql text, p_states text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        IF v_state = ANY (p_states) THEN UPDATE tcount SET n = n + 1; RETURN; END IF;
        RAISE EXCEPTION 'FAIL: expected one of % but got % (%): %', p_states, v_state, SQLERRM, left(p_sql, 120);
    END;
    RAISE EXCEPTION 'FAIL: expected one of % but the statement succeeded: %', p_states, left(p_sql, 120);
END $$;

CREATE FUNCTION pg_temp.sha(p_uuid text) RETURNS text LANGUAGE sql AS $$ SELECT encode(sha256(convert_to(p_uuid, 'UTF8')), 'hex') $$;
CREATE FUNCTION pg_temp.path(p_tenant integer, p_uuid text) RETURNS text LANGUAGE sql AS $$
    SELECT p_tenant::text || '/2026/11/' || pg_temp.sha(p_uuid) || '.xml' $$;

-- One concept (parser output shape). Default product key and description are synthetic.
CREATE FUNCTION pg_temp.cn(p_unit text, p_qty text, p_price text, p_cents bigint, p_desc text DEFAULT 'Fruto fresco de palma', p_key text DEFAULT '50307008')
RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object('claveProdServ', p_key, 'claveUnidad', p_unit, 'cantidad', p_qty, 'valorUnitario', p_price, 'descripcion', p_desc, 'importeCents', p_cents) $$;

-- A voucher with no taxes (total = subtotal unless given), issued p_days_ago days before today.
CREATE FUNCTION pg_temp.vch(p_uuid text, p_emisor text, p_concepts jsonb, p_sub bigint, p_total bigint DEFAULT NULL, p_days_ago integer DEFAULT 1)
RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object(
        'tipoComprobante', 'I', 'uuid', p_uuid, 'folio', '77',
        'fechaEmision', to_char(public.fn_agri_today_cdmx() - p_days_ago, 'YYYY-MM-DD') || 'T10:15:00',
        'fechaTimbrado', to_char(public.fn_agri_today_cdmx() - p_days_ago, 'YYYY-MM-DD') || 'T10:16:00',
        'emisor', jsonb_build_object('rfc', p_emisor, 'nombre', 'EMISOR SINTETICO'),
        'receptor', jsonb_build_object('rfc', 'CCC040404CCC', 'nombre', 'COMPRADOR SINTETICO'),
        'moneda', 'MXN', 'formaPago', '03', 'metodoPago', 'PUE',
        'subtotalCents', p_sub, 'descuentoCents', 0, 'totalCents', coalesce(p_total, p_sub),
        'traslados', '[]'::jsonb, 'retenciones', '[]'::jsonb, 'conceptos', p_concepts,
        'sourceSha256', pg_temp.sha(p_uuid)) $$;

CREATE FUNCTION pg_temp.reg(p_tenant integer, p_actor text, p_v jsonb, p_sat text DEFAULT 'VIGENTE') RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_agri_register_sale(p_tenant, p_actor, p_v, p_sat, pg_temp.path(p_tenant, p_v ->> 'uuid'), pg_temp.sha(p_v ->> 'uuid')) $$;
CREATE FUNCTION pg_temp.reason(p_tenant integer, p_actor text, p_v jsonb, p_sat text DEFAULT 'VIGENTE') RETURNS text LANGUAGE sql AS $$
    SELECT CASE WHEN q.r ->> 'status' = 'INVALID_VOUCHER' THEN q.r ->> 'reason' ELSE q.r ->> 'status' END
      FROM (SELECT pg_temp.reg(p_tenant, p_actor, p_v, p_sat) AS r) q $$;

-- Fixtures: palm companies A and B (real), D (balance tests), T (test company) and a livestock company L --------------------
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
DO $$
DECLARE ca integer; cb integer; cd integer; ct integer; cl integer;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T112 Palm A', 'Agricultura') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T112 Palm B', 'Agricultura') RETURNING id_company INTO cb;
    INSERT INTO public.companys (company_name, industry) VALUES ('T112 Palm D', 'Agricultura') RETURNING id_company INTO cd;
    INSERT INTO public.companys (company_name, industry) VALUES ('T112 Palm Test', 'Agricultura') RETURNING id_company INTO ct;
    INSERT INTO public.companys (company_name, industry) VALUES ('T112 Cattle', 'Ganadería') RETURNING id_company INTO cl;
    INSERT INTO public.users (email, names, password, role) VALUES
        ('admin.a@example.invalid', 'A', 'x', 'ADMIN'), ('editor.a@example.invalid', 'E', 'x', 'EDITOR'),
        ('admin.b@example.invalid', 'B', 'x', 'ADMIN'), ('admin.d@example.invalid', 'D', 'x', 'ADMIN'),
        ('admin.t@example.invalid', 'T', 'x', 'ADMIN'), ('admin.l@example.invalid', 'L', 'x', 'ADMIN'),
        ('outsider@example.invalid', 'O', 'x', 'ADMIN');
    INSERT INTO public.user_companies (email, id_company, role) VALUES
        ('admin.a@example.invalid', ca, 'ADMIN'), ('editor.a@example.invalid', ca, 'EDITOR'),
        ('admin.b@example.invalid', cb, 'ADMIN'), ('admin.d@example.invalid', cd, 'ADMIN'),
        ('admin.t@example.invalid', ct, 'ADMIN'), ('admin.l@example.invalid', cl, 'ADMIN');
    INSERT INTO ctx VALUES ('a', ca::text), ('b', cb::text), ('d', cd::text), ('t', ct::text), ('l', cl::text);
    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_flags (id_company, is_test) VALUES (ct, true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (ca, 'AAA010101AAA'), (cb, 'BBB020202BBB'), (cd, 'DDD050505DDD'), (ct, 'TTT030303TTT');
    PERFORM set_config('app.platform_seed', '', true);
END $$;
CREATE FUNCTION pg_temp.co(p_k text) RETURNS integer LANGUAGE sql AS $$ SELECT v::integer FROM ctx WHERE k = p_k $$;

-- A direct INSERT of a row as 104 wrote it (without the 112 columns), used for the legacy-row tests.
CREATE FUNCTION pg_temp.legacy(p_company integer, p_uuid text, p_emisor text, p_ticket text DEFAULT '9001') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_ref, ticket_warning,
        source_sha256, original_path, sat_status, registered_by_email)
    VALUES (p_company, p_uuid, p_emisor, 'CCC040404CCC', 'COMPRADOR SINTETICO', public.fn_agri_today_cdmx()::timestamp, public.fn_agri_today_cdmx()::timestamp, 1000000, 1000000,
        '{"traslados":[],"retenciones":[]}'::jsonb, '03', 'PUE', '50307008', 'KGM', 100, 100, p_ticket, false,
        pg_temp.sha(p_uuid), pg_temp.path(p_company, p_uuid), 'VIGENTE', 'admin@example.invalid')
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- T1. One KGM concept: the 104 behaviour is unchanged (values, keys of the answer, audit), now with a one-element detail ----------
DO $$
DECLARE ca integer := pg_temp.co('a'); r jsonb; s record; a text := 'admin.a@example.invalid'; v jsonb;
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.vch('A1000000-0000-4000-8000-000000000001', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '7900.000000', '3.940000', 3112600, 'Fruto fresco de palma (ticket 4521)')), 3112600));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK', 'T1 single KGM voucher registers: ' || r::text);
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(s.quantity = 7900 AND s.unit_price = 3.94 AND s.unit_code = 'KGM' AND s.total_cents = 3112600 AND s.subtotal_cents = 3112600
        AND s.ticket_ref = '4521' AND NOT s.ticket_warning AND s.concept_count = 1 AND s.product_key = '50307008' AND s.status = 'ACTIVE', 'T1 stored values of a single KGM concept');
    PERFORM pg_temp.chk(jsonb_array_length(s.ticket_detail) = 1 AND s.ticket_detail -> 0 ->> 'ticket' = '4521' AND s.ticket_detail -> 0 ->> 'unit' = 'KGM'
        AND (s.ticket_detail -> 0 ->> 'kg')::numeric = 7900 AND (s.ticket_detail -> 0 ->> 'amount_cents')::bigint = 3112600, 'T1 one-element detail');
    PERFORM pg_temp.chk((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r -> 'summary') k)
        @> ARRAY['buyer_name', 'folio', 'quantity_kg', 'sale_date', 'sat_status', 'ticket_ref', 'total_amount', 'unit_price'], 'T1 the keys of the 104 answer are still there');
    PERFORM pg_temp.chk((r -> 'summary' ->> 'concept_count')::int = 1 AND r -> 'summary' -> 'tickets' = '["4521"]'::jsonb AND r -> 'summary' ->> 'source_unit' = 'KGM', 'T1 additive summary keys');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_audit WHERE sale_id = s.id AND event = 'REGISTER' AND code = 'OK') = 1, 'T1 audit');
    -- six-decimal quantity and price are kept exactly as before (the 104 fixture)
    r := pg_temp.reg(ca, a, pg_temp.vch('A1000000-0000-4000-8000-000000000002', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '1234.567891', '8.100000', 1000000, 'Fruto (ticket 4522)')), 1000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.quantity = 1234.567891 AND s.unit_price = 8.1, 'T1b six-decimal quantity and the voucher unit price are stored as before');
    -- lowercase unit key is accepted (the parser output is upper-cased by the procedure)
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A1000000-0000-4000-8000-000000000003', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('kgm', '100', '100.00', 1000000, 'x (ticket 4523)')), 1000000)) = 'OK', 'T1c lowercase unit');
    -- idempotency
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A1000000-0000-4000-8000-000000000001', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '7900.000000', '3.940000', 3112600, 'Fruto fresco de palma (ticket 4521)')), 3112600)) = 'ALREADY_REGISTERED', 'T1d same voucher twice');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = 'A1000000-0000-4000-8000-000000000001') = 1, 'T1d one row');
END $$;

-- T2. Two and three KGM concepts: one sale, totals of the set ------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); r jsonb; s record; a text := 'admin.a@example.invalid';
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '3950.000000', '3.940000', 1556300, 'Fruto (ticket 5001)'),
            pg_temp.cn('KGM', '3950.000000', '3.940000', 1556300, 'Fruto (ticket 5002)')), 3112600));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK', 'T2a two concepts register: ' || r::text);
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(s.concept_count = 2 AND s.quantity = 7900 AND s.unit_price = 3.94 AND s.total_cents = 3112600 AND s.ticket_ref = '5001' AND NOT s.ticket_warning
        AND jsonb_array_length(s.ticket_detail) = 2 AND s.ticket_detail -> 1 ->> 'ticket' = '5002', 'T2a one row with the sums, first ticket in ticket_ref, both in the detail');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'A2000000-0000-4000-8000-000000000001') = 1, 'T2a one sale per voucher');
    PERFORM pg_temp.chk(r -> 'summary' -> 'tickets' = '["5001","5002"]'::jsonb AND (r -> 'summary' ->> 'concept_count')::int = 2, 'T2a answer lists both tickets');

    -- different prices: price per kilogram = subtotal / kilograms (before taxes), six decimals
    r := pg_temp.reg(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '3000', '4.10', 1230000, 'Fruto (ticket 5003)'),
            pg_temp.cn('KGM', '4900', '3.95', 1935500, 'Fruto (ticket 5004)')), 3165500, 3165500));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.quantity = 7900 AND s.unit_price = round(31655.00 / 7900, 6) AND s.unit_price = 4.006962, 'T2b weighted price per kilogram: ' || r::text);
    -- with taxes the price stays before taxes (subtotal / kg) and the total is the voucher total
    r := pg_temp.reg(ca, a, (pg_temp.vch('A2000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 5005)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 5006)')), 2000000, 2320000))
        || '{"traslados":[{"impuesto":"002","tipoFactor":"Tasa","tasaOCuota":"0.160000","baseCents":2000000,"importeCents":320000}]}');
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.total_cents = 2320000 AND s.subtotal_cents = 2000000 AND s.unit_price = 100 AND s.quantity = 200, 'T2c total from the voucher, price before taxes');

    -- three concepts
    r := pg_temp.reg(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000004', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 6001)'), pg_temp.cn('KGM', '200', '100.00', 2000000, 'x (ticket 6002)'),
            pg_temp.cn('KGM', '300', '100.00', 3000000, 'x (ticket 6003)')), 6000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.concept_count = 3 AND s.quantity = 600 AND s.unit_price = 100 AND jsonb_array_length(s.ticket_detail) = 3
        AND (SELECT sum((d ->> 'amount_cents')::bigint) FROM jsonb_array_elements(s.ticket_detail) d) = 6000000, 'T2d three concepts');
    -- ten concepts are accepted, eleven are not
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000005', 'AAA010101AAA',
            (SELECT jsonb_agg(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 7' || lpad(g::text, 3, '0') || ')')) FROM generate_series(1, 10) g), 10000000)) = 'OK', 'T2e ten concepts');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000006', 'AAA010101AAA',
            (SELECT jsonb_agg(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 8' || lpad(g::text, 3, '0') || ')')) FROM generate_series(1, 11) g), 11000000)) = 'CONCEPT_COUNT', 'T2f eleven concepts');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A2000000-0000-4000-8000-000000000007', 'AAA010101AAA', '[]'::jsonb, 1000000)) = 'CONCEPT_COUNT', 'T2g no concept');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid IN ('A2000000-0000-4000-8000-000000000006', 'A2000000-0000-4000-8000-000000000007')) = 0, 'T2 refused vouchers wrote nothing');
END $$;

-- T3. One TNE concept (9.1 t at 4011.00 per tonne, total 36500.10) and the tonne arithmetic ----------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); r jsonb; s record; a text := 'admin.a@example.invalid';
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000001', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '9.100000', '4011.000000', 3650010, 'Fruto (ticket 4601)')), 3650010));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK', 'T3a tonne voucher registers: ' || r::text);
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(s.quantity = 9100 AND s.unit_code = 'KGM' AND s.total_cents = 3650010 AND s.subtotal_cents = 3650010 AND s.unit_price = 4.011, 'T3a stored in kilograms, price per kilogram = subtotal / kilograms');
    PERFORM pg_temp.chk(s.ticket_detail -> 0 ->> 'unit' = 'TNE' AND (s.ticket_detail -> 0 ->> 'qty')::numeric = 9.1 AND (s.ticket_detail -> 0 ->> 'kg')::numeric = 9100
        AND (s.ticket_detail -> 0 ->> 'unit_price')::numeric = 4011 AND (s.ticket_detail -> 0 ->> 'amount_cents')::bigint = 3650010, 'T3a the original unit, quantity and price are kept in the detail');
    PERFORM pg_temp.chk((r -> 'summary' ->> 'quantity_kg')::numeric = 9100 AND r -> 'summary' ->> 'source_unit' = 'TNE', 'T3a answer reports kilograms and the source unit');
    -- the per-concept check works on kilograms: one cent of difference is rounding, two are not
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000002', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '9.100000', '4011.000000', 3650011, 'x (ticket 4602)')), 3650011)) = 'OK', 'T3b one cent of rounding');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000003', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '9.100000', '4011.000000', 3650012, 'x (ticket 4603)')), 3650012)) = 'AMOUNTS_MISMATCH_CONCEPT', 'T3b two cents are refused');
    -- six-decimal tonnes become three-decimal kilograms, exactly
    r := pg_temp.reg(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000004', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '0.123456', '1000.000000', 12346, 'x (ticket 4604)')), 12346));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.quantity = 123.456, 'T3c 0.123456 t = 123.456 kg: ' || r::text);
    r := pg_temp.reg(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000005', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '0.000001', '1000000.000000', 100, 'x (ticket 4605)')), 100));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.quantity = 0.001, 'T3d the smallest tonne quantity is one gram');
    -- two tonne concepts
    r := pg_temp.reg(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000006', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('TNE', '4.000000', '4000.000000', 1600000, 'x (ticket 4606)'), pg_temp.cn('TNE', '5.500000', '4000.000000', 2200000, 'x (ticket 4607)')), 3800000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.quantity = 9500 AND s.unit_price = 4 AND s.concept_count = 2, 'T3e two tonne concepts');
    -- the kilogram total must stay below 10^12 (the column holds 12 integer digits)
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A3000000-0000-4000-8000-000000000007', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '1000000000.000000', '1.000000', 100000000000, 'x (ticket 4608)')), 100000000000)) = 'QUANTITY', 'T3f 10^12 kilograms');
END $$;

-- T4. The ticket is optional --------------------------------------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); r jsonb; s record; a text := 'admin.a@example.invalid';
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000001', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto fresco de palma')), 1000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.ticket_ref IS NULL AND s.ticket_warning AND (r -> 'warnings') ? 'ticket_missing_or_unrecognized'
        AND s.ticket_detail -> 0 -> 'ticket' = 'null'::jsonb, 'T4a one concept without ticket registers, ticket_ref null');
    -- several concepts, none with a ticket
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto fresco'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto fresco')), 2000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.ticket_ref IS NULL AND s.ticket_warning AND s.concept_count = 2, 'T4b two concepts without ticket');
    -- some concepts with a ticket, some without: ticket_ref is the first ticket found
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto fresco'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto (ticket 9101)')), 2000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.ticket_ref = '9101' AND s.ticket_warning AND s.ticket_detail -> 0 -> 'ticket' = 'null'::jsonb AND s.ticket_detail -> 1 ->> 'ticket' = '9101', 'T4c mixed: first ticket found, warning on');
    -- unrecognized patterns (changed wording, two references in one description) are not refusals
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000004', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto, boleta 77')), 1000000)) = 'OK', 'T4d changed wording');
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000005', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto (ticket 11) y (ticket 12)')), 1000000));
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND s.ticket_ref IS NULL AND s.ticket_warning, 'T4e two references in one description: none, warning');
    -- case-insensitive keyword, hash sign and dash
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000006', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'Fruto (Ticket #A-77)')), 1000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (SELECT ticket_ref = 'A-77' AND NOT ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid), 'T4f case-insensitive keyword');
    -- the same invoice without a ticket for a tonne concept
    r := pg_temp.reg(ca, a, pg_temp.vch('A4000000-0000-4000-8000-000000000007', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '9.100000', '4011.000000', 3650010, 'Fruto fresco de palma')), 3650010));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (SELECT ticket_ref IS NULL AND ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid), 'T4g tonne concept without ticket');
END $$;

-- T5. Duplicate tickets: inside one voucher refused, across vouchers a warning --------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); cb integer := pg_temp.co('b'); r jsonb; a text := 'admin.a@example.invalid';
BEGIN
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3001)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3001)')), 2000000)) = 'TICKET_DUPLICATE', 'T5a same ticket twice in a voucher');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket ab-1)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (Ticket AB-1)')), 2000000)) = 'TICKET_DUPLICATE', 'T5b different case');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3002)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3003)'),
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3002)')), 3000000)) = 'TICKET_DUPLICATE', 'T5c first and third');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid LIKE 'A5000000-%') = 0, 'T5 refused vouchers wrote nothing');
    -- two concepts without a ticket are not duplicates
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000004', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 2000000)) = 'OK', 'T5d missing tickets are not duplicates');
    -- a ticket already present in another ACTIVE sale of the company: warning (also when it is only in the detail of that sale)
    r := pg_temp.reg(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000005', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3100)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3101)')), 2000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND NOT (r -> 'warnings') ? 'ticket_already_used', 'T5e first load without warning');
    r := pg_temp.reg(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000006', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3101)')), 1000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (r -> 'warnings') ? 'ticket_already_used', 'T5f ticket found in the detail of another sale: warning, not a refusal');
    r := pg_temp.reg(ca, a, pg_temp.vch('A5000000-0000-4000-8000-000000000007', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3200)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3100)')), 2000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (r -> 'warnings') ? 'ticket_already_used', 'T5g any ticket of the voucher counts');
    -- the same ticket in another company is not visible and gives no warning
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.vch('A5000000-0000-4000-8000-000000000008', 'BBB020202BBB', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 3100)')), 1000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND NOT (r -> 'warnings') ? 'ticket_already_used', 'T5h other company: no warning, no information about tickets of A');
END $$;

-- T6. Units, product keys, quantities ---------------------------------------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); a text := 'admin.a@example.invalid';
BEGIN
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2001)'), pg_temp.cn('TNE', '0.1', '100000.00', 1000000, 'x (ticket 2002)')), 2000000)) = 'UNIT_MIXED', 'T6a KGM and TNE in one voucher');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2003)', '50307008'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2004)', '50307009')), 2000000)) = 'PRODUCT_KEY_MIXED', 'T6b two product keys');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000003', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('H87', '100', '100.00', 1000000, 'x (ticket 2005)')), 1000000)) = 'UNIT', 'T6c a single unsupported unit');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000004', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2006)'), pg_temp.cn('LTR', '100', '100.00', 1000000, 'x (ticket 2007)')), 2000000)) = 'UNIT', 'T6d an unsupported unit among kilograms');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000005', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x', 'abc')), 1000000)) = 'PRODUCT_KEY', 'T6e product key format');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000006', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn(NULL, '100', '100.00', 1000000, 'x')), 1000000)) = 'UNIT', 'T6f missing unit');
    -- quantities and prices
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000007', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2008)'), pg_temp.cn('KGM', '0', '100.00', 0, 'x (ticket 2009)')), 1000000)) = 'QUANTITY', 'T6g zero quantity');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000008', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2010)'), pg_temp.cn('KGM', '100', '0', 0, 'x (ticket 2011)')), 1000000)) = 'QUANTITY', 'T6h zero price');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-000000000009', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '-5', '100.00', 1000000, 'x')), 1000000)) = 'QUANTITY', 'T6i negative quantity');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000A', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '1.1234567', '100.00', 1000000, 'x')), 1000000)) = 'QUANTITY', 'T6j seven decimals');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000B', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', NULL, 'x')), 1000000)) = 'CONCEPT_AMOUNT', 'T6k missing concept amount');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000C', 'AAA010101AAA',
            jsonb_build_array((pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')) || '{"importeCents":"10000.00"}'), 1000000)) = 'CONCEPT_AMOUNT', 'T6l non-integer concept amount');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000D', 'AAA010101AAA', jsonb_build_array('7'::jsonb), 1000000)) <> 'OK', 'T6m a concept that is not an object');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000E', 'AAA010101AAA', '"x"'::jsonb, 1000000)) = 'BAD_PAYLOAD', 'T6n conceptos not an array');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A6000000-0000-4000-8000-00000000000F', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2012)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2013)')), 1000000, 1000000)) = 'AMOUNTS_MISMATCH_SUBTOTAL', 'T6o a concept amount missing from the subtotal');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid LIKE 'A6000000-%') = 0, 'T6 refused vouchers wrote nothing');
END $$;

-- T7. Amounts: per concept and subtotal tolerance of (n - 1) cents ------------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); a text := 'admin.a@example.invalid';
        c1 jsonb := pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1001)');
        c2 jsonb := pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1002)');
        c3 jsonb := pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1003)');
BEGIN
    -- one concept: exact, as before (the code did not change)
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(c1), 1000001)) = 'AMOUNTS_MISMATCH_CONCEPT', 'T7a one concept: subtotal 1 cent away is refused');
    -- two concepts: 1 cent allowed, 2 refused (and the total must reconcile with the subtotal)
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(c1, c2), 2000001)) = 'OK', 'T7b two concepts: 1 cent up');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1004)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1005)')), 1999999)) = 'OK', 'T7c two concepts: 1 cent down');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000004', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1006)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1007)')), 2000002)) = 'AMOUNTS_MISMATCH_SUBTOTAL', 'T7d two concepts: 2 cents refused');
    -- three concepts: 2 cents allowed, 3 refused
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000005', 'AAA010101AAA', jsonb_build_array(c1, c2, c3), 3000002)) = 'OK', 'T7e three concepts: 2 cents');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000006', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1008)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1009)'),
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1010)')), 3000003)) = 'AMOUNTS_MISMATCH_SUBTOTAL', 'T7f three concepts: 3 cents refused');
    -- a concept whose amount does not follow kilograms x price (one cent is rounding, two are not)
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000007', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000001, 'x (ticket 1011)'), pg_temp.cn('KGM', '100', '100.00', 999999, 'x (ticket 1012)')), 2000000)) = 'OK', 'T7g concept amounts off by one cent each, sum exact');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000008', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000002, 'x (ticket 1013)'), pg_temp.cn('KGM', '100', '100.00', 999998, 'x (ticket 1014)')), 2000000)) = 'AMOUNTS_MISMATCH_CONCEPT', 'T7h concept amount two cents away');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-000000000009', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '200', '100.00', 1000000, 'x (ticket 1015)'), c2), 2000000)) = 'AMOUNTS_MISMATCH_CONCEPT', 'T7i quantity changed, amount not');
    -- the voucher totals must still reconcile exactly
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('A7000000-0000-4000-8000-00000000000A', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1016)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1017)')), 2000000, 2000001)) = 'AMOUNTS_MISMATCH', 'T7j total does not reconcile');
END $$;

-- T8. Same voucher twice, void, tenant isolation, roles --------------------------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); cb integer := pg_temp.co('b'); ct integer := pg_temp.co('t'); cl integer := pg_temp.co('l');
        a text := 'admin.a@example.invalid'; r jsonb; r2 jsonb; v jsonb; v_id uuid;
BEGIN
    v := pg_temp.vch('A8000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 4001)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 4002)')), 2000000);
    r := pg_temp.reg(ca, a, v);
    r2 := pg_temp.reg(ca, a, v);
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND r2 ->> 'status' = 'ALREADY_REGISTERED' AND r2 ->> 'sale_id' = r ->> 'sale_id', 'T8a multi-concept voucher sent twice');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'A8000000-0000-4000-8000-000000000001') = 1, 'T8a one row');
    -- void is per invoice; the voucher can be loaded again (new row, warning)
    v_id := (r ->> 'sale_id')::uuid;
    PERFORM pg_temp.chk((public.sp_agri_void_sale(ca, a, v_id, 'Duplicated by mistake') ->> 'status') = 'OK', 'T8b void of a multi-concept sale');
    PERFORM pg_temp.chk((SELECT status = 'VOID' AND concept_count = 2 AND jsonb_array_length(ticket_detail) = 2 FROM public.agri_sale_invoices WHERE id = v_id), 'T8b the voided row keeps its detail');
    r2 := pg_temp.reg(ca, a, v);
    PERFORM pg_temp.chk(r2 ->> 'status' = 'OK' AND (r2 -> 'warnings') ? 'previous_sale_voided' AND r2 ->> 'sale_id' <> r ->> 'sale_id', 'T8c reload after a void');
    -- another real company: same voucher is refused with the generic answer; the issuer list is per company
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000001', 'BBB020202BBB', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 4001)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 4002)')), 2000000));
    PERFORM pg_temp.chk(r ->> 'status' = 'DUPLICATE' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) = ARRAY['code', 'message', 'status'], 'T8d same uuid in another real company: generic DUPLICATE');
    PERFORM pg_temp.chk(pg_temp.reason(cb, 'admin.b@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000002', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 2000000)) = 'ISSUER_RFC_MISMATCH', 'T8e issuer RFC of another company');
    -- roles and domain
    PERFORM pg_temp.chk(pg_temp.reason(ca, 'editor.a@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 1000000)) = 'FORBIDDEN', 'T8f EDITOR');
    PERFORM pg_temp.chk(pg_temp.reason(ca, 'outsider@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 1000000)) = 'FORBIDDEN', 'T8g non-member');
    PERFORM pg_temp.chk(pg_temp.reason(ca, 'admin.b@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 1000000)) = 'FORBIDDEN', 'T8h ADMIN of another company');
    PERFORM pg_temp.chk(pg_temp.reason(cl, 'admin.l@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 1000000)) = 'NOT_PALM', 'T8i livestock company');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'A8000000-0000-4000-8000-000000000003') = 0, 'T8 rejected callers wrote nothing');
    -- a test company may reuse a real uuid (multi-concept too) and stays idempotent
    r := pg_temp.reg(ct, 'admin.t@example.invalid', pg_temp.vch('A8000000-0000-4000-8000-000000000001', 'TTT030303TTT', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x')), 2000000), 'NO_ENCONTRADO');
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (SELECT is_test AND sat_status = 'SKIPPED_TEST' FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid), 'T8j test company');
    -- the views of one company never show the sales of another
    PERFORM pg_temp.chk((SELECT count(*) FROM public.vw_agri_sale_ui_list WHERE id_company = cb) = (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = cb)
        AND NOT EXISTS (SELECT 1 FROM public.vw_agri_sale_ui_list v JOIN public.agri_sale_invoices s ON s.id = v.id WHERE v.id_company = cb AND s.id_company <> cb)
        AND NOT EXISTS (SELECT 1 FROM public.vw_agri_sale_list WHERE id_company = cb AND uuid = 'A8000000-0000-4000-8000-000000000001'), 'T8k views filter by company');
END $$;

-- T9. Balance and summary with a multi-concept sale; void -------------------------------------------------------------------------------
DO $$
DECLARE cd integer := pg_temp.co('d'); d text := 'admin.d@example.invalid'; r1 jsonb; r2 jsonb; r3 jsonb; b jsonb; v_from date := public.fn_agri_today_cdmx() - 5; v_to date := public.fn_agri_today_cdmx();
BEGIN
    r1 := pg_temp.reg(cd, d, pg_temp.vch('A9000000-0000-4000-8000-000000000001', 'DDD050505DDD',
            jsonb_build_array(pg_temp.cn('KGM', '1000', '10.00', 1000000, 'x (ticket 1)')), 1000000));
    r2 := pg_temp.reg(cd, d, pg_temp.vch('A9000000-0000-4000-8000-000000000002', 'DDD050505DDD', jsonb_build_array(
            pg_temp.cn('KGM', '500', '10.00', 500000, 'x (ticket 2)'), pg_temp.cn('KGM', '1500', '10.00', 1500000, 'x (ticket 3)'), pg_temp.cn('KGM', '1000', '10.00', 1000000, 'x (ticket 4)')), 3000000));
    r3 := pg_temp.reg(cd, d, pg_temp.vch('A9000000-0000-4000-8000-000000000003', 'DDD050505DDD',
            jsonb_build_array(pg_temp.cn('TNE', '2.000000', '10000.000000', 2000000, 'x (ticket 5)')), 2000000));
    PERFORM pg_temp.chk(r1 ->> 'status' = 'OK' AND r2 ->> 'status' = 'OK' AND r3 ->> 'status' = 'OK', 'T9 three sales (1 KGM concept, 3 KGM concepts, 1 TNE concept)');
    b := public.sp_agri_sales_balance(cd, v_from, v_to, 'MONTH', NULL, NULL, d);
    PERFORM pg_temp.chk((b ->> 'sale_count')::int = 3 AND (b ->> 'total_amount')::numeric = 60000.00 AND (b ->> 'total_quantity_kg')::numeric = 6000, 'T9a balance counts one sale per voucher and adds kilograms: ' || b::text);
    PERFORM pg_temp.chk((SELECT sale_count = 3 AND total_amount = 60000 AND total_quantity = 6000 FROM public.vw_agri_sale_summary WHERE id_company = cd AND grain = 'YEAR'
        AND period_start = date_trunc('year', public.fn_agri_today_cdmx()::timestamp)::date AND plantation_id IS NULL), 'T9b summary view');
    PERFORM pg_temp.chk((public.sp_agri_void_sale(cd, d, (r2 ->> 'sale_id')::uuid, 'Voided for the test') ->> 'status') = 'OK', 'T9c void the multi-concept sale');
    b := public.sp_agri_sales_balance(cd, v_from, v_to, 'MONTH', NULL, NULL, d);
    PERFORM pg_temp.chk((b ->> 'sale_count')::int = 2 AND (b ->> 'total_amount')::numeric = 30000.00 AND (b ->> 'total_quantity_kg')::numeric = 3000, 'T9d the whole invoice leaves the balance (no per-ticket void)');
    PERFORM pg_temp.chk((SELECT status FROM public.vw_agri_sale_ui_list WHERE id = (r2 ->> 'sale_id')::uuid) = 'VOID'
        AND (SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'A9000000-0000-4000-8000-000000000002') = 1, 'T9e one row, VOID');
    PERFORM pg_temp.chk((public.sp_agri_void_sale(cd, d, (r2 ->> 'sale_id')::uuid, 'Another reason') ->> 'status') = 'ALREADY_VOID', 'T9f void twice');
    -- a different company never reads these totals
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, %L, %L, %L, NULL, NULL, %L)', pg_temp.co('a'), v_from, v_to, 'MONTH', d), ARRAY['P0084']);
END $$;

-- T10. Rows written before 112 and the table guards ---------------------------------------------------------------------------------------
DO $$
DECLARE ca integer := pg_temp.co('a'); v_id uuid; v_d jsonb;
BEGIN
    v_id := pg_temp.legacy(ca, 'AA000000-0000-4000-8000-000000000001', 'AAA010101AAA', '9001');
    PERFORM pg_temp.chk((SELECT concept_count = 1 AND ticket_detail IS NULL FROM public.agri_sale_invoices WHERE id = v_id), 'T10a an old-style row: concept_count 1, no stored detail');
    SELECT ticket_detail INTO v_d FROM public.vw_agri_sale_ui_list WHERE id = v_id;
    PERFORM pg_temp.chk(jsonb_array_length(v_d) = 1 AND v_d -> 0 ->> 'ticket' = '9001' AND (v_d -> 0 ->> 'kg')::numeric = 100 AND (v_d -> 0 ->> 'amount_cents')::bigint = 1000000
        AND v_d -> 0 ->> 'unit' = 'KGM' AND (v_d -> 0 ->> 'unit_price')::numeric = 100, 'T10b the view builds the detail of an old-style row from its columns');
    PERFORM pg_temp.chk((SELECT ticket_detail = v_d FROM public.vw_agri_sale_list WHERE id = v_id), 'T10b the same detail in both views');
    PERFORM pg_temp.chk((public.sp_agri_void_sale(ca, 'admin.a@example.invalid', v_id, 'Old row voided') ->> 'status') = 'OK', 'T10c an old-style row can still be voided');
    -- the table: consistency of the detail with the row
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000001', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 100, 100, true, 2, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110']);   -- two concepts without detail
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, ticket_detail, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000002', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 100, 100, true, 2, '[{"n":1,"ticket":null,"unit":"KGM","qty":"100","kg":"100","unit_price":"100","amount_cents":1000000}]'::jsonb, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110', '23514']);   -- detail length differs from concept_count
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, ticket_detail, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000003', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 150, 100, true, 1, '[{"n":1,"ticket":null,"unit":"KGM","qty":"100","kg":"100","unit_price":"100","amount_cents":1000000}]'::jsonb, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110']);   -- kilograms differ from the detail
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, ticket_detail, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000004', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 100, 100, true, 1, '[{"n":1,"ticket":null,"unit":"KGM","qty":"100","kg":"100","unit_price":"100","amount_cents":1000005}]'::jsonb, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110']);   -- amount differs from the subtotal
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, ticket_detail, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000005', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 2000000, 2000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 200, 100, false, 2, '[{"n":1,"ticket":"A1","unit":"KGM","qty":"100","kg":"100","unit_price":"100","amount_cents":1000000},{"n":2,"ticket":"a1","unit":"KGM","qty":"100","kg":"100","unit_price":"100","amount_cents":1000000}]'::jsonb, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110']);   -- duplicate tickets
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, ticket_detail, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000006', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 100, 100, true, 1, '[{"n":1,"ticket":null,"unit":"LTR","qty":"100","kg":"100","unit_price":"100","amount_cents":1000000}]'::jsonb, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110']);   -- unit not accepted
    PERFORM pg_temp.expect_err(format($f$INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, concept_count, source_sha256, original_path, sat_status, registered_by_email)
        VALUES (%s, 'AB000000-0000-4000-8000-000000000007', 'AAA010101AAA', 'CCC040404CCC', 'X', now()::timestamp, now()::timestamp, 1000000, 1000000, '{"traslados":[],"retenciones":[]}'::jsonb,
        '03', 'PUE', '50307008', 'KGM', 100, 100, true, 11, %L, 'a/b.xml', 'VIGENTE', 'a@example.invalid')$f$, ca, repeat('a', 64)), ARRAY['P0110', '23514']);   -- more than ten concepts
    -- append-only: the two columns of a registered sale never change and the sale is never deleted
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET concept_count = 2 WHERE id_company = %s AND uuid = %L', ca, 'A1000000-0000-4000-8000-000000000001'), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET ticket_detail = ''[]''::jsonb WHERE id_company = %s AND uuid = %L', ca, 'A1000000-0000-4000-8000-000000000001'), ARRAY['P0110', '23514']);
    PERFORM pg_temp.expect_err(format('DELETE FROM public.agri_sale_invoices WHERE id_company = %s', ca), ARRAY['P0110']);
END $$;

-- T11. Contract of the procedure and the views ------------------------------------------------------------------------------------------------------
DO $$
DECLARE v_def text := pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure); v_cols text;
BEGIN
    PERFORM pg_temp.chk((SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_agri_register_sale') = 1, 'T11a one signature, no overload');
    PERFORM pg_temp.chk(NOT v_def LIKE '%disabled%' AND NOT v_def ILIKE '%SECURITY DEFINER%', 'T11b no stub word, attributes as in 104');
    PERFORM pg_temp.chk((SELECT provolatile = 'v' AND NOT prosecdef AND prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql') FROM pg_proc WHERE oid = 'public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure), 'T11c plpgsql VOLATILE, not SECURITY DEFINER');
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';
    PERFORM pg_temp.chk(v_cols = 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at,concept_count,ticket_detail', 'T11d the 105 columns come first, the new ones are appended');
    PERFORM pg_temp.chk((SELECT count(*) FROM public.crud_models WHERE model_name IN ('agri_sale_invoices', 'agri_sale_audit') AND cardinality(allowed_ops) <> 0) = 0, 'T11e nothing was exposed in crud_models');
    PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.agri_sale_audit WHERE code ~ '[0-9A-F]{8}-[0-9A-F]{4}-'), 'T11f the audit trail carries no voucher uuid');
END $$;

-- T12. Rollback and re-apply inside the transaction ----------------------------------------------------------------------------------------------
\ir 112_rollback.sql
DO $$
DECLARE ca integer := pg_temp.co('a'); a text := 'admin.a@example.invalid'; r jsonb;
BEGIN
    PERFORM pg_temp.chk(md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure)) = '425229fb6036884d5c5dcd7527d7c674', 'T12a the rollback restores the exact 104 procedure');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('AC000000-0000-4000-8000-000000000001', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 1)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 2)')), 2000000)) = 'CONCEPT_COUNT', 'T12b after the rollback two concepts are refused again');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('AC000000-0000-4000-8000-000000000002', 'AAA010101AAA',
            jsonb_build_array(pg_temp.cn('TNE', '9.1', '4011.00', 3650010, 'x (ticket 3)')), 3650010)) = 'UNIT', 'T12c after the rollback tonnes are refused again');
    r := pg_temp.reg(ca, a, pg_temp.vch('AC000000-0000-4000-8000-000000000003', 'AAA010101AAA', jsonb_build_array(pg_temp.cn('KGM', '7900', '3.94', 3112600, 'x (ticket 4)')), 3112600));
    PERFORM pg_temp.chk(r ->> 'status' = 'OK' AND (SELECT concept_count = 1 AND ticket_detail IS NULL AND quantity = 7900 FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid), 'T12d a single KGM voucher still registers after the rollback');
    PERFORM pg_temp.chk((SELECT concept_count = 2 AND quantity = 7900 AND status = 'ACTIVE' FROM public.agri_sale_invoices WHERE uuid = 'A2000000-0000-4000-8000-000000000001'), 'T12e a sale registered under 112 stays readable after the rollback');
    PERFORM pg_temp.chk((SELECT ticket_detail IS NOT NULL FROM public.vw_agri_sale_ui_list WHERE id = (r ->> 'sale_id')::uuid), 'T12f the views keep working after the rollback');
END $$;
\ir 112_agri_sale_multi_concept.sql
DO $$
DECLARE ca integer := pg_temp.co('a'); a text := 'admin.a@example.invalid';
BEGIN
    PERFORM pg_temp.chk(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure) LIKE '%TNE%', 'T12g re-applying 112 restores the new rules');
    PERFORM pg_temp.chk(pg_temp.reason(ca, a, pg_temp.vch('AC000000-0000-4000-8000-000000000004', 'AAA010101AAA', jsonb_build_array(
            pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 5)'), pg_temp.cn('KGM', '100', '100.00', 1000000, 'x (ticket 6)')), 2000000)) = 'OK', 'T12h two concepts register again');
END $$;

SELECT '112 TESTS: ' || n || ' assertions passed' AS result FROM tcount;
ROLLBACK;
