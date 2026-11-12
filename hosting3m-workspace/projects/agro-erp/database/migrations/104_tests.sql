-- 104_tests.sql: LOCAL / throwaway database only (name must contain "test" or "rehearsal"). Everything is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 104_tests.sql
-- Includes 104_agri_sale_invoices.sql with `embedded` set. Uses ONLY synthetic data (fake UUIDs, fake RFCs, fake e-mails, new companies).
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true
\ir 104_agri_sale_invoices.sql

-- Helpers (session-local) -----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.expect_err(p_sql text, p_states text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        IF v_state = ANY (p_states) THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL: expected one of % but got % (%): %', p_states, v_state, SQLERRM, left(p_sql, 120);
    END;
    RAISE EXCEPTION 'FAIL: expected one of % but the statement succeeded: %', p_states, left(p_sql, 120);
END $$;

CREATE FUNCTION pg_temp.sha(p_uuid text) RETURNS text LANGUAGE sql AS $$ SELECT encode(sha256(convert_to(p_uuid, 'UTF8')), 'hex') $$;
CREATE FUNCTION pg_temp.path(p_tenant integer, p_uuid text) RETURNS text LANGUAGE sql AS $$
    SELECT p_tenant::text || '/2026/11/' || pg_temp.sha(p_uuid) || '.xml' $$;

-- A valid synthetic voucher (parser output shape). Issuer and buyer RFCs are fake.
CREATE FUNCTION pg_temp.voucher(p_uuid text, p_emisor text, p_desc text DEFAULT 'Fruto fresco de palma (ticket 4521)', p_days_ago integer DEFAULT 1)
RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object(
        'tipoComprobante', 'I', 'uuid', p_uuid, 'folio', '77',
        'fechaEmision', to_char(public.fn_agri_today_cdmx() - p_days_ago, 'YYYY-MM-DD') || 'T10:15:00',
        'fechaTimbrado', to_char(public.fn_agri_today_cdmx() - p_days_ago, 'YYYY-MM-DD') || 'T10:16:00',
        'emisor', jsonb_build_object('rfc', p_emisor, 'nombre', 'EMISOR SINTETICO'),
        'receptor', jsonb_build_object('rfc', 'CCC040404CCC', 'nombre', 'COMPRADOR SINTETICO'),
        'moneda', 'MXN', 'formaPago', '03', 'metodoPago', 'PUE',
        'subtotalCents', 1000000, 'descuentoCents', 0, 'totalCents', 1000000,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.000000', 'baseCents', 1000000, 'importeCents', 0)),
        'retenciones', '[]'::jsonb,
        'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '50307008', 'claveUnidad', 'KGM',
            'cantidad', '1234.567891', 'valorUnitario', '8.100000', 'descripcion', p_desc, 'importeCents', 1000000)),
        'sourceSha256', pg_temp.sha(p_uuid)) $$;

CREATE FUNCTION pg_temp.reg(p_tenant integer, p_actor text, p_v jsonb, p_sat text DEFAULT 'VIGENTE') RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_agri_register_sale(p_tenant, p_actor, p_v, p_sat, pg_temp.path(p_tenant, p_v ->> 'uuid'), pg_temp.sha(p_v ->> 'uuid')) $$;

-- Fixtures: four palm companies (A real, B real, T test, N without issuer RFC) and one livestock company (L) ---------------
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
DO $$
DECLARE
    ca integer; cb integer; ct integer; cn integer; cl integer;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T104 Palm A', 'Agricultura') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T104 Palm B', 'Agricultura') RETURNING id_company INTO cb;
    INSERT INTO public.companys (company_name, industry) VALUES ('T104 Palm Test', 'Agricultura') RETURNING id_company INTO ct;
    INSERT INTO public.companys (company_name, industry) VALUES ('T104 Palm NoIssuer', 'Agricultura') RETURNING id_company INTO cn;
    INSERT INTO public.companys (company_name, industry) VALUES ('T104 Cattle', 'Ganadería') RETURNING id_company INTO cl;
    INSERT INTO public.users (email, names, password, role) VALUES
        ('admin.a@example.invalid', 'A', 'x', 'ADMIN'), ('editor.a@example.invalid', 'E', 'x', 'EDITOR'),
        ('admin.b@example.invalid', 'B', 'x', 'ADMIN'), ('admin.t@example.invalid', 'T', 'x', 'ADMIN'),
        ('admin.n@example.invalid', 'N', 'x', 'ADMIN'), ('admin.l@example.invalid', 'L', 'x', 'ADMIN'),
        ('outsider@example.invalid', 'O', 'x', 'ADMIN');
    INSERT INTO public.user_companies (email, id_company, role) VALUES
        ('admin.a@example.invalid', ca, 'ADMIN'), ('editor.a@example.invalid', ca, 'EDITOR'),
        ('admin.b@example.invalid', cb, 'ADMIN'), ('admin.t@example.invalid', ct, 'ADMIN'),
        ('admin.n@example.invalid', cn, 'ADMIN'), ('admin.l@example.invalid', cl, 'ADMIN');
    INSERT INTO ctx VALUES ('a', ca::text), ('b', cb::text), ('t', ct::text), ('n', cn::text), ('l', cl::text);
END $$;

-- T0. Platform seed rows: flags first, then issuer RFCs (all with the platform setting).
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b');
        ct integer := (SELECT v FROM ctx WHERE k = 't'); cl integer := (SELECT v FROM ctx WHERE k = 'l');
BEGIN
    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_flags (id_company, is_test) VALUES (ct, true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (ca, 'AAA010101AAA'), (cb, 'BBB020202BBB'), (ct, 'TTT030303TTT');
    PERFORM set_config('app.platform_seed', '', true);
    IF (SELECT is_test FROM public.company_issuer_rfcs WHERE id_company = ct) IS NOT TRUE
       OR (SELECT is_test FROM public.company_issuer_rfcs WHERE id_company = ca) IS NOT FALSE THEN
        RAISE EXCEPTION 'FAIL T0 is_test not copied from company_flags';
    END IF;
    RAISE NOTICE 'OK T0 fixtures and platform seed';
END $$;

-- T1-T3. Valid sale, idempotency, ticket handling.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); r jsonb; r2 jsonb; s record;
BEGIN
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000001', 'AAA010101AAA'));
    IF r ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T1 valid sale: %', r; END IF;
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid;
    IF s.total_cents <> 1000000 OR s.quantity <> 1234.567891 OR s.unit_price <> 8.1 OR s.ticket_ref <> '4521' OR s.ticket_warning
       OR s.is_test OR s.status <> 'ACTIVE' OR s.unit_code <> 'KGM' OR s.buyer_name <> 'COMPRADOR SINTETICO' OR s.sat_status <> 'VIGENTE' THEN
        RAISE EXCEPTION 'FAIL T1 stored values: %', to_jsonb(s);
    END IF;
    IF (SELECT count(*) FROM public.agri_sale_audit WHERE sale_id = s.id AND event = 'REGISTER' AND code = 'OK') <> 1 THEN
        RAISE EXCEPTION 'FAIL T1 audit REGISTER row'; END IF;
    RAISE NOTICE 'OK T1 valid sale (6-decimal quantity kept, ticket 4521, total from the voucher)';

    r2 := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000001', 'AAA010101AAA'));
    IF r2 ->> 'status' <> 'ALREADY_REGISTERED' OR r2 ->> 'sale_id' <> r ->> 'sale_id' THEN RAISE EXCEPTION 'FAIL T2 idempotent: %', r2; END IF;
    IF (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = 'A0000000-0000-4000-8000-000000000001') <> 1 THEN
        RAISE EXCEPTION 'FAIL T2 duplicate row'; END IF;
    RAISE NOTICE 'OK T2 same uuid, same tenant: ALREADY_REGISTERED';

    -- Missing ticket, changed pattern, two tickets: accepted with ticket_ref NULL and a warning.
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000002', 'AAA010101AAA', 'Fruto fresco de palma'));
    IF r ->> 'status' <> 'OK' OR NOT (r -> 'warnings') ? 'ticket_missing_or_unrecognized' THEN RAISE EXCEPTION 'FAIL T3a missing ticket: %', r; END IF;
    IF (SELECT ticket_ref IS NOT NULL OR NOT ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) THEN RAISE EXCEPTION 'FAIL T3a row'; END IF;
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000003', 'AAA010101AAA', 'Fruto de palma, ticket: 99'));
    IF r ->> 'status' <> 'OK' OR (SELECT ticket_ref IS NOT NULL OR NOT ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) THEN RAISE EXCEPTION 'FAIL T3b changed pattern: %', r; END IF;
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000004', 'AAA010101AAA', 'Fruto (ticket 11) y (ticket 12)'));
    IF r ->> 'status' <> 'OK' OR (SELECT ticket_ref IS NOT NULL OR NOT ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) THEN RAISE EXCEPTION 'FAIL T3c two tickets: %', r; END IF;
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000005', 'AAA010101AAA', 'Fruto (Ticket #A-77)'));
    IF r ->> 'status' <> 'OK' OR (SELECT ticket_ref <> 'A-77' OR ticket_warning FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) THEN RAISE EXCEPTION 'FAIL T3d case-insensitive ticket: %', r; END IF;
    RAISE NOTICE 'OK T3 ticket missing / changed / several / case-insensitive';

    -- Same ticket, different uuid in the same company: accepted with a warning.
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000006', 'AAA010101AAA', 'Fruto (ticket 4521)'));
    IF r ->> 'status' <> 'OK' OR NOT (r -> 'warnings') ? 'ticket_already_used' THEN RAISE EXCEPTION 'FAIL T15 same ticket other uuid: %', r; END IF;
    RAISE NOTICE 'OK T15 same ticket, another uuid: warning ticket_already_used, not blocked';
END $$;

-- More helpers: reason of a rejected voucher, and a direct INSERT used to exercise the table guards.
CREATE FUNCTION pg_temp.reason(p_tenant integer, p_actor text, p_v jsonb, p_sat text DEFAULT 'VIGENTE') RETURNS text LANGUAGE sql AS $$
    SELECT CASE WHEN q.r ->> 'status' = 'INVALID_VOUCHER' THEN q.r ->> 'reason' ELSE q.r ->> 'status' END
      FROM (SELECT pg_temp.reg(p_tenant, p_actor, p_v, p_sat) AS r) q $$;

CREATE FUNCTION pg_temp.dins(p_company integer, p_uuid text, p_emisor text, p_total bigint DEFAULT 1000000, p_sat text DEFAULT 'VIGENTE',
                             p_is_test boolean DEFAULT false, p_plantation uuid DEFAULT NULL, p_lot uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_warning, plantation_id, lot_id,
        source_sha256, original_path, sat_status, is_test, registered_by_email)
    VALUES (p_company, p_uuid, p_emisor, 'CCC040404CCC', 'COMPRADOR SINTETICO', public.fn_agri_today_cdmx()::timestamp, public.fn_agri_today_cdmx()::timestamp, 1000000, p_total,
        '{"traslados":[],"retenciones":[]}'::jsonb, '03', 'PUE', '50307008', 'KGM', 10, 1, true, p_plantation, p_lot,
        pg_temp.sha(p_uuid), pg_temp.path(p_company, p_uuid), p_sat, p_is_test, 'admin@example.invalid');
END $$;

-- T4-T9, T17b, T18, T25, T26. Voucher rules (reason codes).
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); ct integer := (SELECT v FROM ctx WHERE k = 't');
        a text := 'admin.a@example.invalid'; v jsonb; r jsonb; c jsonb;
BEGIN
    v := pg_temp.voucher('B0000000-0000-4000-8000-000000000001', 'AAA010101AAA');
    c := v -> 'conceptos';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', c || c)) <> 'CONCEPT_COUNT' THEN RAISE EXCEPTION 'FAIL T4 two concepts'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', '[]'::jsonb)) <> 'CONCEPT_COUNT' THEN RAISE EXCEPTION 'FAIL T4b no concept'; END IF;
    IF pg_temp.reason(ca, a, v || '{"moneda":"USD"}') <> 'CURRENCY' THEN RAISE EXCEPTION 'FAIL T5 USD'; END IF;
    IF pg_temp.reason(ca, a, v || '{"metodoPago":"PPD"}') <> 'PAYMENT_METHOD' THEN RAISE EXCEPTION 'FAIL T6 PPD'; END IF;
    IF pg_temp.reason(ca, a, v || '{"tipoComprobante":"E"}') <> 'TIPO' THEN RAISE EXCEPTION 'FAIL T7 type E'; END IF;
    IF pg_temp.reason(ca, a, v - 'tipoComprobante') <> 'TIPO' THEN RAISE EXCEPTION 'FAIL T7b missing type'; END IF;
    IF pg_temp.reason(ca, a, v || '{"totalCents":1000001}') <> 'AMOUNTS_MISMATCH' THEN RAISE EXCEPTION 'FAIL T8 total off by one cent'; END IF;
    IF pg_temp.reason(ca, a, v || '{"totalCents":999999}') <> 'AMOUNTS_MISMATCH' THEN RAISE EXCEPTION 'FAIL T8b total short by one cent'; END IF;
    IF pg_temp.reason(ca, a, v || '{"traslados":[{"impuesto":"002","tipoFactor":"Tasa","tasaOCuota":"0.160000","baseCents":1000000,"importeCents":160000}]}') <> 'AMOUNTS_MISMATCH' THEN
        RAISE EXCEPTION 'FAIL T9a 16 percent tax line without matching total'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array((c -> 0) || '{"claveUnidad":"H87"}'))) <> 'UNIT' THEN RAISE EXCEPTION 'FAIL T4c unit'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array((c -> 0) || '{"cantidad":"1.1234567"}'))) <> 'QUANTITY' THEN RAISE EXCEPTION 'FAIL T4d seven decimals'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array((c -> 0) || '{"cantidad":"0"}'))) <> 'QUANTITY' THEN RAISE EXCEPTION 'FAIL T4e zero quantity'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('receptor', jsonb_build_object('rfc', 'AAA010101AAA', 'nombre', 'X'))) <> 'BUYER_IS_ISSUER' THEN RAISE EXCEPTION 'FAIL T4f buyer is issuer'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('receptor', jsonb_build_object('rfc', 'CCC040404CCC', 'nombre', ' '))) <> 'BUYER_NAME' THEN RAISE EXCEPTION 'FAIL T4g buyer name'; END IF;
    IF pg_temp.reason(ca, a, v || '{"fechaEmision":"2026-13-45"}') <> 'BAD_PAYLOAD' THEN RAISE EXCEPTION 'FAIL T4h bad date'; END IF;
    IF pg_temp.reason(ca, a, '[]'::jsonb) <> 'BAD_PAYLOAD' OR pg_temp.reason(ca, a, NULL) <> 'BAD_PAYLOAD' THEN RAISE EXCEPTION 'FAIL T4i payload'; END IF;
    IF pg_temp.reason(ca, a, v || '{"uuid":"not-a-uuid"}') <> 'UUID' THEN RAISE EXCEPTION 'FAIL T4j uuid'; END IF;
    RAISE NOTICE 'OK T4-T8 concepts, USD, PPD, type E, total off by 1 cent, unit, quantity, buyer, payload';

    -- Concept amount consistency (single concept): 7900.000000 x 3.940000 = 31126.00 -> 3112600 cents.
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000001', 'AAA010101AAA');
    v := v || '{"subtotalCents":3112600,"totalCents":3112600,"traslados":[]}';
    c := jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000","importeCents":3112600}');
    r := pg_temp.reg(ca, a, v || jsonb_build_object('conceptos', c));
    IF r ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T29a valid sample: %', r; END IF;
    -- one cent of issuer rounding is accepted (concept amount and subtotal both 3112601)
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000002', 'AAA010101AAA') || '{"subtotalCents":3112601,"totalCents":3112601,"traslados":[]}';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000","importeCents":3112601}'))) <> 'OK' THEN
        RAISE EXCEPTION 'FAIL T29b one cent off must be accepted'; END IF;
    -- two cents off is rejected
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000003', 'AAA010101AAA') || '{"subtotalCents":3112602,"totalCents":3112602,"traslados":[]}';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000","importeCents":3112602}'))) <> 'AMOUNTS_MISMATCH_CONCEPT' THEN
        RAISE EXCEPTION 'FAIL T29c two cents off must be rejected'; END IF;
    -- missing or invalid concept amount
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000004', 'AAA010101AAA') || '{"subtotalCents":3112600,"totalCents":3112600,"traslados":[]}';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array((((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000"}') - 'importeCents'))) <> 'CONCEPT_AMOUNT' THEN
        RAISE EXCEPTION 'FAIL T29d missing importeCents'; END IF;
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000","importeCents":"31126.00"}'))) <> 'CONCEPT_AMOUNT' THEN
        RAISE EXCEPTION 'FAIL T29e invalid importeCents'; END IF;
    -- subtotal different from the concept amount (total reconciled with the subtotal)
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000005', 'AAA010101AAA') || '{"subtotalCents":3112700,"totalCents":3112700,"traslados":[]}';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"7900.000000","valorUnitario":"3.940000","importeCents":3112600}'))) <> 'AMOUNTS_MISMATCH_CONCEPT' THEN
        RAISE EXCEPTION 'FAIL T29f subtotal differs from the concept amount'; END IF;
    -- quantity changed, totals unchanged
    v := pg_temp.voucher('B1000000-0000-4000-8000-000000000006', 'AAA010101AAA') || '{"subtotalCents":3112600,"totalCents":3112600,"traslados":[]}';
    IF pg_temp.reason(ca, a, v || jsonb_build_object('conceptos', jsonb_build_array(((v -> 'conceptos') -> 0) || '{"cantidad":"8000.000000","valorUnitario":"3.940000","importeCents":3112600}'))) <> 'AMOUNTS_MISMATCH_CONCEPT' THEN
        RAISE EXCEPTION 'FAIL T29g quantity changed, total unchanged'; END IF;
    RAISE NOTICE 'OK T29 concept amount vs quantity x unit price (one cent), subtotal = concept amount';

    -- IVA 16 percent: the total is taken from the voucher (subtotal + transferred tax), stored as issued.
    r := pg_temp.reg(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000002', 'AAA010101AAA')
        || '{"totalCents":1160000,"traslados":[{"impuesto":"002","tipoFactor":"Tasa","tasaOCuota":"0.160000","baseCents":1000000,"importeCents":160000}]}');
    IF r ->> 'status' <> 'OK' OR (SELECT total_cents FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) <> 1160000 THEN RAISE EXCEPTION 'FAIL T9 IVA 16: %', r; END IF;
    RAISE NOTICE 'OK T9 IVA 16 percent total taken from the voucher';

    -- Hash and path.
    r := public.sp_agri_register_sale(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000003', 'AAA010101AAA'), 'VIGENTE',
        pg_temp.path(cb, 'B0000000-0000-4000-8000-000000000003'), pg_temp.sha('B0000000-0000-4000-8000-000000000003'));
    IF r ->> 'reason' <> 'PATH' THEN RAISE EXCEPTION 'FAIL T26a path of another tenant: %', r; END IF;
    r := public.sp_agri_register_sale(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000003', 'AAA010101AAA'), 'VIGENTE',
        pg_temp.path(ca, 'B0000000-0000-4000-8000-000000000003'), repeat('b', 64));
    IF r ->> 'reason' <> 'HASH' THEN RAISE EXCEPTION 'FAIL T26b hash mismatch: %', r; END IF;
    r := public.sp_agri_register_sale(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000003', 'AAA010101AAA'), 'VIGENTE',
        '../' || pg_temp.path(ca, 'B0000000-0000-4000-8000-000000000003'), pg_temp.sha('B0000000-0000-4000-8000-000000000003'));
    IF r ->> 'reason' <> 'PATH' THEN RAISE EXCEPTION 'FAIL T26c path traversal: %', r; END IF;
    RAISE NOTICE 'OK T26 hash and path';

    -- Dates: future, too old, boundary (365 days is accepted, 366 is not).
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000004', 'AAA010101AAA', 'x (ticket 1)', -1)) <> 'DATE_FUTURE' THEN RAISE EXCEPTION 'FAIL T18a future'; END IF;
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000005', 'AAA010101AAA', 'x (ticket 1)', 366)) <> 'DATE_TOO_OLD' THEN RAISE EXCEPTION 'FAIL T18b too old'; END IF;
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000006', 'AAA010101AAA', 'x (ticket 1)', 365)) <> 'OK' THEN RAISE EXCEPTION 'FAIL T18c boundary 365'; END IF;
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000007', 'AAA010101AAA', 'x (ticket 1)', 0)) <> 'OK' THEN RAISE EXCEPTION 'FAIL T18d today'; END IF;
    RAISE NOTICE 'OK T18 future date, older than 365 days, boundaries';

    -- SAT: CANCELADO never; NO_ENCONTRADO / ERROR only for test companies (stored as SKIPPED_TEST).
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000008', 'AAA010101AAA'), 'CANCELADO') <> 'SAT_NOT_VALID' THEN RAISE EXCEPTION 'FAIL T25a cancelled'; END IF;
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000008', 'AAA010101AAA'), 'NO_ENCONTRADO') <> 'SAT_NOT_VALID' THEN RAISE EXCEPTION 'FAIL T25b real company skipping the SAT'; END IF;
    IF pg_temp.reason(ca, a, pg_temp.voucher('B0000000-0000-4000-8000-000000000008', 'AAA010101AAA'), 'SKIPPED_TEST') <> 'SAT_NOT_VALID' THEN RAISE EXCEPTION 'FAIL T25c real company SKIPPED_TEST'; END IF;
    IF pg_temp.reason(ct, 'admin.t@example.invalid', pg_temp.voucher('B0000000-0000-4000-8000-000000000009', 'TTT030303TTT'), 'CANCELADO') <> 'SAT_NOT_VALID' THEN RAISE EXCEPTION 'FAIL T25d test company cancelled'; END IF;
    r := pg_temp.reg(ct, 'admin.t@example.invalid', pg_temp.voucher('B0000000-0000-4000-8000-000000000009', 'TTT030303TTT'), 'NO_ENCONTRADO');
    IF r ->> 'status' <> 'OK' OR (SELECT sat_status <> 'SKIPPED_TEST' OR NOT is_test FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) THEN RAISE EXCEPTION 'FAIL T25e test company: %', r; END IF;
    RAISE NOTICE 'OK T25 SAT status handling';
END $$;

-- T10-T14, T16, T17. Issuer list, duplicates across tenants, roles, domain.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); ct integer := (SELECT v FROM ctx WHERE k = 't');
        cn integer := (SELECT v FROM ctx WHERE k = 'n'); cl integer := (SELECT v FROM ctx WHERE k = 'l'); r jsonb; r2 jsonb;
BEGIN
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000001', 'ZZZ999999ZZZ'));
    IF r ->> 'status' <> 'ISSUER_RFC_MISMATCH' THEN RAISE EXCEPTION 'FAIL T10 issuer not in the list: %', r; END IF;
    r := pg_temp.reg(cn, 'admin.n@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000002', 'AAA010101AAA'));
    IF r ->> 'status' <> 'ISSUER_RFC_NOT_CONFIGURED' THEN RAISE EXCEPTION 'FAIL T11 company without issuer list: %', r; END IF;
    -- B tries the RFC of A: mismatch for B (the list is per company).
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000003', 'AAA010101AAA'));
    IF r ->> 'status' <> 'ISSUER_RFC_MISMATCH' THEN RAISE EXCEPTION 'FAIL T10b issuer of another company: %', r; END IF;
    RAISE NOTICE 'OK T10-T11 issuer list per company, never filled from a voucher';

    -- T13. Same uuid in another real company: DUPLICATE with a generic answer and no owner information.
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000001', 'BBB020202BBB'));
    IF r ->> 'status' <> 'DUPLICATE' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) <> ARRAY['code', 'message', 'status'] THEN RAISE EXCEPTION 'FAIL T13 cross-tenant uuid: %', r; END IF;
    IF r ->> 'message' <> 'No se pudo registrar la factura.' OR r ->> 'code' <> 'DUPLICATE_UUID' THEN RAISE EXCEPTION 'FAIL T13 answer is not generic: %', r; END IF;
    IF (SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'A0000000-0000-4000-8000-000000000001' AND id_company = cb) <> 0 THEN RAISE EXCEPTION 'FAIL T13 row created'; END IF;
    RAISE NOTICE 'OK T13 same uuid in another real tenant: DUPLICATE, generic answer';

    -- T14. A test company may register a uuid used by a real company, and a real company a uuid used by a test company.
    r := pg_temp.reg(ct, 'admin.t@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000001', 'TTT030303TTT'), 'NO_ENCONTRADO');
    IF r ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T14a test tenant reusing a real uuid: %', r; END IF;
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.voucher('B0000000-0000-4000-8000-000000000009', 'BBB020202BBB'));
    IF r ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T14b real tenant reusing a test uuid: %', r; END IF;
    r2 := pg_temp.reg(ct, 'admin.t@example.invalid', pg_temp.voucher('A0000000-0000-4000-8000-000000000001', 'TTT030303TTT'), 'NO_ENCONTRADO');
    IF r2 ->> 'status' <> 'ALREADY_REGISTERED' THEN RAISE EXCEPTION 'FAIL T14c test tenant idempotent: %', r2; END IF;
    RAISE NOTICE 'OK T14 uuid in a test tenant and a real tenant is allowed; per-company idempotency holds';

    -- T16. Roles: only an ADMIN of the tenant loads; the role is read from the membership.
    r := pg_temp.reg(ca, 'editor.a@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000004', 'AAA010101AAA'));
    IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T16a editor: %', r; END IF;
    r := pg_temp.reg(ca, 'outsider@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000004', 'AAA010101AAA'));
    IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T16b non-member: %', r; END IF;
    r := pg_temp.reg(ca, 'admin.b@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000004', 'AAA010101AAA'));
    IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T16c admin of another company: %', r; END IF;
    r := public.sp_agri_register_sale(NULL, 'admin.a@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000004', 'AAA010101AAA'), 'VIGENTE', 'x', 'y');
    IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T16d null tenant: %', r; END IF;
    r := pg_temp.reg(ca, NULL, pg_temp.voucher('C0000000-0000-4000-8000-000000000004', 'AAA010101AAA'));
    IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T16e null actor: %', r; END IF;
    IF (SELECT count(*) FROM public.agri_sale_invoices WHERE uuid = 'C0000000-0000-4000-8000-000000000004') <> 0 THEN RAISE EXCEPTION 'FAIL T16 a rejected caller wrote a sale'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.agri_sale_audit WHERE actor_email = 'editor.a@example.invalid' AND code = 'FORBIDDEN')
       OR EXISTS (SELECT 1 FROM public.agri_sale_audit WHERE actor_email = 'outsider@example.invalid') THEN RAISE EXCEPTION 'FAIL T16 audit of rejections'; END IF;
    RAISE NOTICE 'OK T16 EDITOR, non-member and ADMIN of another company rejected';

    -- T17. Livestock company rejected, also at table level.
    r := pg_temp.reg(cl, 'admin.l@example.invalid', pg_temp.voucher('C0000000-0000-4000-8000-000000000005', 'AAA010101AAA'));
    IF r ->> 'status' <> 'NOT_PALM' THEN RAISE EXCEPTION 'FAIL T17 livestock company: %', r; END IF;
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L)', cl, 'C0000000-0000-4000-8000-000000000006', 'AAA010101AAA'), ARRAY['P0093']);
    RAISE NOTICE 'OK T17 livestock company rejected (procedure and table)';
END $$;

-- T19. Void.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); r jsonb; v_id uuid; s record;
        a text := 'admin.a@example.invalid';
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.voucher('D0000000-0000-4000-8000-000000000001', 'AAA010101AAA'));
    v_id := (r ->> 'sale_id')::uuid;
    IF (pg_temp.reg(ca, a, pg_temp.voucher('D0000000-0000-4000-8000-000000000001', 'AAA010101AAA')) ->> 'status') <> 'ALREADY_REGISTERED' THEN RAISE EXCEPTION 'FAIL T19 setup'; END IF;

    IF (public.sp_agri_void_sale(ca, 'editor.a@example.invalid', v_id, 'Duplicated by mistake') ->> 'status') <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T19a editor void'; END IF;
    IF (public.sp_agri_void_sale(ca, 'outsider@example.invalid', v_id, 'Duplicated by mistake') ->> 'status') <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T19a2 non-member void'; END IF;
    IF (public.sp_agri_void_sale(ca, a, v_id, 'abcd') ->> 'status') <> 'INVALID_REASON' THEN RAISE EXCEPTION 'FAIL T19b short reason'; END IF;
    IF (public.sp_agri_void_sale(ca, a, v_id, repeat('x', 301)) ->> 'status') <> 'INVALID_REASON' THEN RAISE EXCEPTION 'FAIL T19c long reason'; END IF;
    IF (public.sp_agri_void_sale(ca, a, v_id, NULL) ->> 'status') <> 'INVALID_REASON' THEN RAISE EXCEPTION 'FAIL T19d null reason'; END IF;
    IF (public.sp_agri_void_sale(cb, 'admin.b@example.invalid', v_id, 'Duplicated by mistake') ->> 'status') <> 'NOT_FOUND' THEN RAISE EXCEPTION 'FAIL T19e other tenant sale'; END IF;
    IF (SELECT status FROM public.agri_sale_invoices WHERE id = v_id) <> 'ACTIVE' THEN RAISE EXCEPTION 'FAIL T19 voided by a rejected caller'; END IF;

    r := public.sp_agri_void_sale(ca, a, v_id, 'Duplicated by mistake');
    IF r ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T19f void: %', r; END IF;
    SELECT * INTO s FROM public.agri_sale_invoices WHERE id = v_id;
    IF s.status <> 'VOID' OR s.void_reason <> 'Duplicated by mistake' OR s.voided_by_email <> a OR s.voided_at IS NULL THEN RAISE EXCEPTION 'FAIL T19f row: %', to_jsonb(s); END IF;
    IF (SELECT count(*) FROM public.agri_sale_audit WHERE sale_id = v_id AND event = 'VOID') <> 1 THEN RAISE EXCEPTION 'FAIL T19f audit'; END IF;
    r := public.sp_agri_void_sale(ca, a, v_id, 'A second reason that must not replace the first');
    IF r ->> 'status' <> 'ALREADY_VOID' OR (SELECT void_reason FROM public.agri_sale_invoices WHERE id = v_id) <> 'Duplicated by mistake'
       OR (SELECT count(*) FROM public.agri_sale_audit WHERE sale_id = v_id AND event = 'VOID') <> 1 THEN RAISE EXCEPTION 'FAIL T19g void twice: %', r; END IF;
    RAISE NOTICE 'OK T19 void: ADMIN only, reason 5..300, audited, idempotent';
END $$;

-- T30. A voided voucher can be loaded again by the same company; cross-company rules still hold.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); ct integer := (SELECT v FROM ctx WHERE k = 't');
        a text := 'admin.a@example.invalid'; u text := '1A000000-0000-4000-8000-000000000001'; r jsonb; s1 uuid; s2 uuid; s3 uuid;
BEGIN
    r := pg_temp.reg(ca, a, pg_temp.voucher(u, 'AAA010101AAA', 'Fruto (ticket 8801)')); s1 := (r ->> 'sale_id')::uuid;
    IF r ->> 'status' <> 'OK' OR r -> 'warnings' ? 'previous_sale_voided' THEN RAISE EXCEPTION 'FAIL T30a first load: %', r; END IF;
    -- an ACTIVE sale still answers ALREADY_REGISTERED
    IF pg_temp.reg(ca, a, pg_temp.voucher(u, 'AAA010101AAA', 'Fruto (ticket 8801)')) ->> 'status' <> 'ALREADY_REGISTERED' THEN RAISE EXCEPTION 'FAIL T30b'; END IF;
    -- two ACTIVE rows with the same uuid in one company are impossible
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L)', ca, u, 'AAA010101AAA'), ARRAY['23505']);
    PERFORM public.sp_agri_void_sale(ca, a, s1, 'Wrong buyer, to be reloaded');
    -- reload after the first void: new row, warning, the VOID row stays
    r := pg_temp.reg(ca, a, pg_temp.voucher(u, 'AAA010101AAA', 'Fruto (ticket 8801)')); s2 := (r ->> 'sale_id')::uuid;
    IF r ->> 'status' <> 'OK' OR NOT (r -> 'warnings') ? 'previous_sale_voided' OR s2 = s1 THEN RAISE EXCEPTION 'FAIL T30c reload after void: %', r; END IF;
    IF (SELECT count(*) FILTER (WHERE status = 'VOID') FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = u) <> 1
       OR (SELECT count(*) FILTER (WHERE status = 'ACTIVE') FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = u) <> 1 THEN RAISE EXCEPTION 'FAIL T30c rows'; END IF;
    -- the ticket warning ignores VOID rows (s1 is void, s2 is the only active one with this ticket)
    IF (r -> 'warnings') ? 'ticket_already_used' THEN RAISE EXCEPTION 'FAIL T30d void row counted for the ticket warning: %', r; END IF;
    -- reload twice after two voids
    PERFORM public.sp_agri_void_sale(ca, a, s2, 'Reloaded by mistake again');
    r := pg_temp.reg(ca, a, pg_temp.voucher(u, 'AAA010101AAA', 'Fruto (ticket 8801)')); s3 := (r ->> 'sale_id')::uuid;
    IF r ->> 'status' <> 'OK' OR NOT (r -> 'warnings') ? 'previous_sale_voided' OR s3 IN (s1, s2) THEN RAISE EXCEPTION 'FAIL T30e second reload: %', r; END IF;
    IF (SELECT count(*) FILTER (WHERE status = 'VOID') FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = u) <> 2
       OR (SELECT count(*) FILTER (WHERE status = 'ACTIVE') FROM public.agri_sale_invoices WHERE id_company = ca AND uuid = u) <> 1 THEN RAISE EXCEPTION 'FAIL T30e rows'; END IF;
    -- reads ignore VOID rows
    IF (SELECT count(*) FROM public.vw_agri_sale_list WHERE id_company = ca AND uuid = u) <> 3
       OR (SELECT count(*) FROM public.vw_agri_sale_list WHERE id_company = ca AND uuid = u AND status = 'ACTIVE') <> 1
       OR (SELECT sale_count FROM public.vw_agri_sale_summary WHERE id_company = ca AND grain = 'DAY' AND period_start = public.fn_agri_today_cdmx() - 1 AND plantation_id IS NULL)
          <> (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = ca AND status = 'ACTIVE' AND issued_at::date = public.fn_agri_today_cdmx() - 1) THEN
        RAISE EXCEPTION 'FAIL T30f list shows all rows, summary only the ACTIVE ones'; END IF;
    RAISE NOTICE 'OK T30a-f void then reload in the same company (new row, warning, VOID rows kept, one ACTIVE row)';

    -- Another real company cannot load it while the first company holds it ACTIVE or VOID; the answer is the same generic one.
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.voucher(u, 'BBB020202BBB', 'Fruto (ticket 9901)'));
    IF r ->> 'status' <> 'DUPLICATE' OR r ->> 'message' <> 'No se pudo registrar la factura.' THEN RAISE EXCEPTION 'FAIL T30g other company, ACTIVE: %', r; END IF;
    PERFORM public.sp_agri_void_sale(ca, a, s3, 'Voided by the first company');
    r := pg_temp.reg(cb, 'admin.b@example.invalid', pg_temp.voucher(u, 'BBB020202BBB', 'Fruto (ticket 9901)'));
    IF r ->> 'status' <> 'DUPLICATE' OR r ->> 'message' <> 'No se pudo registrar la factura.' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) <> ARRAY['code', 'message', 'status'] THEN
        RAISE EXCEPTION 'FAIL T30h other company, all rows VOID: %', r; END IF;
    IF (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = cb AND uuid = u) <> 0 THEN RAISE EXCEPTION 'FAIL T30h row created'; END IF;
    -- the first company can still reload it after its own void
    IF pg_temp.reg(ca, a, pg_temp.voucher(u, 'AAA010101AAA', 'Fruto (ticket 8801)')) ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T30i reload by the first company'; END IF;
    -- a test company may still load a uuid used (ACTIVE or VOID) by a real company
    IF pg_temp.reg(ct, 'admin.t@example.invalid', pg_temp.voucher(u, 'TTT030303TTT', 'Fruto (ticket 7701)'), 'NO_ENCONTRADO') ->> 'status' <> 'OK' THEN RAISE EXCEPTION 'FAIL T30j test company'; END IF;
    RAISE NOTICE 'OK T30g-j cross-company rule (ACTIVE or VOID, generic answer); test company unaffected';
END $$;

-- T20. Balance.
DO $$
DECLARE cb integer := (SELECT v FROM ctx WHERE k = 'b'); ca integer := (SELECT v FROM ctx WHERE k = 'a'); cl integer := (SELECT v FROM ctx WHERE k = 'l');
        b text := 'admin.b@example.invalid'; t date := public.fn_agri_today_cdmx(); r jsonb; x jsonb; s1 uuid; s2 uuid;
BEGIN
    r := pg_temp.reg(cb, b, pg_temp.voucher('E0000000-0000-4000-8000-000000000001', 'BBB020202BBB', 'Fruto (ticket 501)', 2)); s1 := (r ->> 'sale_id')::uuid;
    r := pg_temp.reg(cb, b, pg_temp.voucher('E0000000-0000-4000-8000-000000000002', 'BBB020202BBB', 'Fruto (ticket 502)', 1)
        || '{"totalCents":1160000,"traslados":[{"impuesto":"002","tipoFactor":"Tasa","tasaOCuota":"0.160000","baseCents":1000000,"importeCents":160000}]}'); s2 := (r ->> 'sale_id')::uuid;
    x := public.sp_agri_sales_balance(cb, t - 3, t, 'DAY', NULL, NULL, b);
    IF jsonb_array_length(x -> 'by_period') <> 4 THEN RAISE EXCEPTION 'FAIL T20a periods: %', x; END IF;
    -- B already holds the test-uuid sale from T14b (1 day ago, 10000.00): 10000.00 + 10000.00 + 11600.00 = 31600.00, 3 sales.
    IF (x ->> 'total_amount')::numeric <> 31600.00 THEN RAISE EXCEPTION 'FAIL T20a2 balance total: %', x; END IF;
    IF x -> 'previous' IS NULL OR (x #>> '{previous,date_to}')::date <> t - 4 OR (x ->> 'delta_pct') IS NOT NULL THEN RAISE EXCEPTION 'FAIL T20b previous period: %', x; END IF;
    IF (public.sp_agri_sales_balance(ca, t - 3, t, 'DAY', NULL, NULL, 'admin.a@example.invalid') ->> 'sale_count')::int
       <> (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = ca AND status = 'ACTIVE' AND issued_at::date BETWEEN t - 3 AND t)
       OR (x ->> 'sale_count')::int <> (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = cb AND status = 'ACTIVE' AND issued_at::date BETWEEN t - 3 AND t) THEN
        RAISE EXCEPTION 'FAIL T20c company isolation'; END IF;
    PERFORM public.sp_agri_void_sale(cb, b, s2, 'Wrong buyer, to be re-issued');
    x := public.sp_agri_sales_balance(cb, t - 3, t, 'DAY', NULL, NULL, b);
    IF (x ->> 'total_amount')::numeric <> 20000.00 OR (x ->> 'sale_count')::int <> 2 THEN RAISE EXCEPTION 'FAIL T20d voided sale still counted: %', x; END IF;
    x := public.sp_agri_sales_balance(cb, NULL, NULL, NULL, NULL, NULL, b);
    IF x ->> 'grain' <> 'MONTH' OR NOT (x ->> 'success')::boolean THEN RAISE EXCEPTION 'FAIL T20e defaults: %', x; END IF;
    IF (SELECT count(*) FROM public.vw_agri_sale_summary WHERE id_company = cb AND grain = 'DAY') <> 2
       OR (SELECT count(*) FROM public.vw_agri_sale_list WHERE id_company = cb) <> 3
       OR (SELECT count(*) FROM public.vw_agri_sale_list WHERE id_company = cb AND status = 'VOID') <> 1 THEN RAISE EXCEPTION 'FAIL T20f views'; END IF;
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, NULL, NULL, NULL, %L)', cb, 'admin.a@example.invalid'), ARRAY['P0084']);
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, NULL, NULL, NULL, %L)', ca, 'editor.a@example.invalid'), ARRAY['P0084']);
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, NULL, NULL, NULL, %L)', cl, 'admin.l@example.invalid'), ARRAY['P0093']);
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, %L, NULL, NULL, %L)', cb, 'DECADE', b), ARRAY['P0092']);
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, NULL, %L, NULL, %L)', cb, gen_random_uuid(), b), ARRAY['P0080']);
    RAISE NOTICE 'OK T20 balance: voided sales excluded, previous period, ADMIN only, company isolation, filters validated';
END $$;

-- T21-T22. Platform-managed tables.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); ct integer := (SELECT v FROM ctx WHERE k = 't');
        cn integer := (SELECT v FROM ctx WHERE k = 'n'); cl integer := (SELECT v FROM ctx WHERE k = 'l');
BEGIN
    -- Without the platform setting nothing can be written.
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_flags (id_company, is_test) VALUES (%s, true)', cn), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_flags SET is_test = false WHERE id_company = %s', ct), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (%s, %L)', cn, 'NNN050505NNN'), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_issuer_rfcs SET is_active = false WHERE id_company = %s', ca), ARRAY['P0111']);
    -- The sale procedures cannot change them either (they never write these tables); the setting is not something a caller can pass.
    PERFORM set_config('app.platform_seed', 'on', true);
    -- Never deletable, even for the platform seed.
    PERFORM pg_temp.expect_err('DELETE FROM public.company_flags', ARRAY['P0111']);
    PERFORM pg_temp.expect_err('TRUNCATE public.company_flags', ARRAY['P0111']);
    PERFORM pg_temp.expect_err('DELETE FROM public.company_issuer_rfcs', ARRAY['P0111']);
    PERFORM pg_temp.expect_err('TRUNCATE public.company_issuer_rfcs', ARRAY['P0111']);
    -- is_test is fixed once the company has issuer RFCs or sales (T has issuer RFCs; A has sales and issuer RFCs).
    PERFORM pg_temp.expect_err(format('UPDATE public.company_flags SET is_test = false WHERE id_company = %s', ct), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_flags (id_company, is_test) VALUES (%s, true)', ca), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_flags SET id_company = %s WHERE id_company = %s', cn, ct), ARRAY['P0111']);
    -- A company with neither can be flagged and unflagged.
    INSERT INTO public.company_flags (id_company, is_test) VALUES (cn, true);
    UPDATE public.company_flags SET is_test = false WHERE id_company = cn;
    IF (SELECT is_test FROM public.company_flags WHERE id_company = cn) THEN RAISE EXCEPTION 'FAIL T21 unflag'; END IF;
    UPDATE public.company_flags SET is_test = true WHERE id_company = cn;

    -- Issuer RFCs: palm companies only; is_test copied from the flag whatever the caller sends; immutable except is_active.
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (%s, %L)', cl, 'LLL060606LLL'), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (%s, %L)', cn, 'not-an-rfc'), ARRAY['23514']);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc, is_test) VALUES (ca, 'AAA010101AA1', true);
    IF (SELECT is_test FROM public.company_issuer_rfcs WHERE rfc = 'AAA010101AA1') THEN RAISE EXCEPTION 'FAIL T22 is_test sent by the caller was kept'; END IF;
    PERFORM pg_temp.expect_err('UPDATE public.company_issuer_rfcs SET is_test = NOT is_test WHERE rfc = ''AAA010101AA1''', ARRAY['P0111']);
    PERFORM pg_temp.expect_err('UPDATE public.company_issuer_rfcs SET rfc = ''AAA010101AA2'' WHERE rfc = ''AAA010101AA1''', ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_issuer_rfcs SET id_company = %s WHERE rfc = %L', cb, 'AAA010101AA1'), ARRAY['P0111']);
    UPDATE public.company_issuer_rfcs SET is_active = false WHERE rfc = 'AAA010101AA1';
    -- One active real company per issuer RFC; a test company is not constrained by real ones.
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (%s, %L)', cb, 'AAA010101AAA'), ARRAY['23505']);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (cn, 'AAA010101AAA');
    IF NOT (SELECT is_test FROM public.company_issuer_rfcs WHERE id_company = cn AND rfc = 'AAA010101AAA') THEN RAISE EXCEPTION 'FAIL T22 test copy'; END IF;
    PERFORM set_config('app.platform_seed', '', true);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_flags SET is_test = false WHERE id_company = %s', cn), ARRAY['P0111']);
    RAISE NOTICE 'OK T21-T22 company_flags and company_issuer_rfcs: platform-managed, not deletable, is_test fixed and derived';
END $$;

-- T23-T24, T27, T28. Amounts, append-only guards, derived flags, composite keys, audit content.
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); ct integer := (SELECT v FROM ctx WHERE k = 't');
        r jsonb; v_pa uuid; v_pb uuid; v_args text[];
BEGIN
    -- T23. No amount parameter anywhere; extra keys in the voucher are ignored; a total that does not reconcile cannot be inserted.
    SELECT proargnames INTO v_args FROM pg_proc WHERE oid = 'public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure;
    IF EXISTS (SELECT 1 FROM unnest(v_args) n WHERE n ~* '(amount|total|monto|importe|price|precio)') THEN RAISE EXCEPTION 'FAIL T23 amount-like parameter: %', v_args; END IF;
    r := pg_temp.reg(ca, 'admin.a@example.invalid', pg_temp.voucher('F0000000-0000-4000-8000-000000000001', 'AAA010101AAA') || '{"amount":1,"total":2,"totalAmount":3,"monto":4}');
    IF r ->> 'status' <> 'OK' OR (SELECT total_cents FROM public.agri_sale_invoices WHERE id = (r ->> 'sale_id')::uuid) <> 1000000 THEN RAISE EXCEPTION 'FAIL T23 amount supplied by the caller was used: %', r; END IF;
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L, 1000001)', ca, 'F0000000-0000-4000-8000-000000000002', 'AAA010101AAA'), ARRAY['P0110']);
    RAISE NOTICE 'OK T23 the stored amount is only the voucher total; amounts reconcile at table level';

    -- T24. Append-only.
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET buyer_name = %L WHERE id_company = %s', 'OTHER', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET total_cents = 1 WHERE id_company = %s', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET is_test = true WHERE id_company = %s', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format($q$UPDATE public.agri_sale_invoices SET status = 'VOID', void_reason = 'Manual change attempt', voided_by_email = 'x@example.invalid', voided_at = now() WHERE id_company = %s$q$, ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('DELETE FROM public.agri_sale_invoices WHERE id_company = %s', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err('TRUNCATE public.agri_sale_invoices', ARRAY['P0110', '0A000']);
    PERFORM pg_temp.expect_err('UPDATE public.agri_sale_audit SET code = ''X''', ARRAY['P0110']);
    PERFORM pg_temp.expect_err('DELETE FROM public.agri_sale_audit', ARRAY['P0110']);
    PERFORM pg_temp.expect_err('TRUNCATE public.agri_sale_audit', ARRAY['P0110', '0A000']);
    PERFORM set_config('app.agri_sale_void', 'on', true);   -- the void setting alone cannot change anything else
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET buyer_name = %L WHERE id_company = %s', 'OTHER', ca), ARRAY['P0110']);
    PERFORM set_config('app.agri_sale_void', '', true);
    RAISE NOTICE 'OK T24 UPDATE / DELETE / TRUNCATE blocked on invoices and audit';

    -- Derived flag: the table decides is_test, not the caller.
    PERFORM pg_temp.dins(ca, 'F0000000-0000-4000-8000-000000000003', 'AAA010101AAA', 1000000, 'VIGENTE', true);
    PERFORM pg_temp.dins(ct, 'F0000000-0000-4000-8000-000000000004', 'TTT030303TTT', 1000000, 'SKIPPED_TEST', false);
    IF (SELECT is_test FROM public.agri_sale_invoices WHERE uuid = 'F0000000-0000-4000-8000-000000000003' AND id_company = ca)
       OR NOT (SELECT is_test FROM public.agri_sale_invoices WHERE uuid = 'F0000000-0000-4000-8000-000000000004' AND id_company = ct) THEN RAISE EXCEPTION 'FAIL T24 derived is_test'; END IF;
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L, 1000000, %L)', ca, 'F0000000-0000-4000-8000-000000000005', 'AAA010101AAA', 'SKIPPED_TEST'), ARRAY['23514']);
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L)', cb, 'F0000000-0000-4000-8000-000000000003', 'BBB020202BBB'), ARRAY['23505']);
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L)', ca, 'F0000000-0000-4000-8000-000000000006', 'ZZZ999999ZZZ'), ARRAY['P0110']);
    RAISE NOTICE 'OK T24b is_test derived from company_flags; SKIPPED_TEST only for test companies; global uuid index';

    -- T27. Composite keys: plantation and lot must belong to the company.
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (ca, 'PA1', 'Plantation A', 10, 'PROPIA') RETURNING id INTO v_pa;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (cb, 'PB1', 'Plantation B', 10, 'PROPIA') RETURNING id INTO v_pb;
    PERFORM pg_temp.dins(ca, 'F0000000-0000-4000-8000-000000000007', 'AAA010101AAA', 1000000, 'VIGENTE', false, v_pa);
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L, 1000000, %L, false, %L)', ca, 'F0000000-0000-4000-8000-000000000008', 'AAA010101AAA', 'VIGENTE', v_pb), ARRAY['23503']);
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.dins(%s, %L, %L, 1000000, %L, false, NULL, %L)', ca, 'F0000000-0000-4000-8000-000000000009', 'AAA010101AAA', 'VIGENTE', gen_random_uuid()), ARRAY['23514']);
    IF (public.sp_agri_sales_balance(ca, public.fn_agri_today_cdmx() - 3, public.fn_agri_today_cdmx(), 'DAY', v_pa, NULL, 'admin.a@example.invalid') ->> 'sale_count')::int <> 1 THEN RAISE EXCEPTION 'FAIL T27 plantation filter'; END IF;
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, NULL, NULL, NULL, %L, NULL, %L)', ca, v_pb, 'admin.a@example.invalid'), ARRAY['P0080']);
    RAISE NOTICE 'OK T27 plantation / lot keys scoped to the company';

    -- T28. Audit: codes only, never a voucher uuid; no seal or certificate column anywhere in the sale tables.
    IF EXISTS (SELECT 1 FROM public.agri_sale_audit a JOIN public.agri_sale_invoices s ON to_jsonb(a)::text ILIKE '%' || s.uuid || '%') THEN RAISE EXCEPTION 'FAIL T28 audit holds a uuid'; END IF;
    IF EXISTS (SELECT 1 FROM public.agri_sale_audit WHERE event = 'REJECT' AND code = 'DUPLICATE_UUID' AND sale_id IS NOT NULL) THEN RAISE EXCEPTION 'FAIL T28 duplicate rejection linked to a sale'; END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
                  AND column_name ~* '(sello|certificad|cert_|xml)') THEN RAISE EXCEPTION 'FAIL T28 seal / certificate / xml column'; END IF;
    IF (SELECT count(*) FROM public.agri_sale_audit WHERE event = 'REJECT' AND code = 'DUPLICATE_UUID') < 2 THEN RAISE EXCEPTION 'FAIL T28 expected duplicate rejections in the audit'; END IF;
    RAISE NOTICE 'OK T28 audit holds codes only; no seal / certificate / xml columns';

    -- Isolation summary: every sale row belongs to a company created by this script.
    IF EXISTS (SELECT 1 FROM public.agri_sale_invoices s WHERE s.id_company NOT IN (SELECT v::integer FROM ctx)) THEN RAISE EXCEPTION 'FAIL isolation'; END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'ALL 104 TESTS OK'; END $$;
ROLLBACK;
\echo '*** 104 tests finished; everything rolled back ***'
