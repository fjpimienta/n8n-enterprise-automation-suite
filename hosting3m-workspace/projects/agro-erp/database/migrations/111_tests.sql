-- 111_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). One transaction, always rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 111_tests.sql     (run from this directory: it includes 109_* and 111_* files)
-- Optional: -v mutation=M1..M6 breaks one protection inside the transaction; the run must then FAIL (see 111_mutation_check.sh).
-- Needs 080, 081, 083, 091, 092, 104 and 109 applied. It includes 111 itself (embedded), so it runs the same before and after 111 is applied.
-- Synthetic data only: fake companies, RFCs, e-mails, names and UUIDs generated here.
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
\if :{?mutation}
\else
\set mutation none
\endif
BEGIN;
\set embedded true
\ir 111_palm_expense_invoices.sql

CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE results (n serial, ok boolean, id text) ON COMMIT DROP;
GRANT ALL ON TABLE ctx, results TO PUBLIC;

CREATE FUNCTION pg_temp.c(k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM ctx WHERE ctx.k = $1 $$;
CREATE FUNCTION pg_temp.ok(p_id text, p_cond boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL [%]', p_id; END IF;
    INSERT INTO results (ok, id) VALUES (true, p_id);
END $$;
CREATE FUNCTION pg_temp.expect_err(p_id text, p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = p_state THEN
            INSERT INTO results (ok, id) VALUES (true, p_id);
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL [%] expected % got % (%)', p_id, p_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL [%] the statement succeeded', p_id;
END $$;

-- Fixtures (synthetic) ---------------------------------------------------------------------------------------
-- The unit catalog is seeded by 081; a throwaway database restored without that seed gets the same rows here (rolled back with everything else).
INSERT INTO public.agri_unit_catalog (unit_code, unit_name, sort_order) VALUES
    ('KG', 'Kilogramos', 10), ('TON', 'Toneladas', 20), ('L', 'Litros', 30), ('PZA', 'Piezas', 40), ('BULTO', 'Bultos', 50),
    ('JORNAL', 'Jornales', 60), ('HA', 'Hectáreas', 70), ('VIAJE', 'Viajes', 80), ('SERVICIO', 'Servicios', 90)
ON CONFLICT (unit_code) DO NOTHING;

-- PA  palm company, 2 plantations (PA1 with lots N-01 and S-01, PA2 with lots N-01 and ONLY-B), own RFCs TPA..PA1 and TPA..PA2, 4 members
-- PT  palm TEST company (company_flags.is_test), one plantation, own RFC TPT..PT1
-- PB  palm company, one plantation, own RFC TPB..PB1 (isolation from PA)
-- L   livestock company with one member
DO $$
DECLARE pa integer; pt integer; pb integer; cl integer; a1 uuid; a2 uuid; t1 uuid; b1 uuid;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T111 Palm A', 'Agricultura') RETURNING id_company INTO pa;
    INSERT INTO public.companys (company_name, industry) VALUES ('T111 Palm Test', 'Agricultura') RETURNING id_company INTO pt;
    INSERT INTO public.companys (company_name, industry) VALUES ('T111 Palm B', 'Agricultura') RETURNING id_company INTO pb;
    INSERT INTO public.companys (company_name, industry) VALUES ('T111 Cattle', 'Ganadería') RETURNING id_company INTO cl;
    INSERT INTO ctx VALUES ('pa', pa::text), ('pt', pt::text), ('pb', pb::text), ('l', cl::text);

    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_flags (id_company, is_test) VALUES (pt, true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES
        (pa, 'TPA010101PA1'), (pa, 'TPA010101PA2'), (pt, 'TPT010101PT1'), (pb, 'TPB010101PB1');
    PERFORM set_config('app.platform_seed', '', true);
    INSERT INTO public.company_tax_ids (id_company, rfc, created_by_email) VALUES (cl, 'TLA010101LA1', 'seed@example.invalid');

    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (pa, 'TP-A1', 'T111 Alfa', 10, 'PROPIA') RETURNING id INTO a1;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (pa, 'TP-A2', 'T111 Beta', 10, 'PROPIA') RETURNING id INTO a2;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (pt, 'TP-T1', 'T111 Unica', 10, 'PROPIA') RETURNING id INTO t1;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (pb, 'TP-B1', 'T111 Otra', 10, 'PROPIA') RETURNING id INTO b1;
    INSERT INTO ctx VALUES ('a1', a1::text), ('a2', a2::text), ('t1', t1::text), ('b1', b1::text);
    INSERT INTO public.agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha) VALUES
        (pa, a1, 'N-01', 'T111 Lote Norte A', 5), (pa, a1, 'S-01', 'T111 Lote Sur', 5),
        (pa, a2, 'N-01', 'T111 Lote Norte B', 5), (pa, a2, 'ONLY-B', 'T111 Solo B', 5);

    INSERT INTO public.users (email, names, password, role, is_active) VALUES
        ('adm.a@example.invalid', 'AA', 'x', 'ADMIN', true), ('own.a@example.invalid', 'OA', 'x', 'ADMIN', true),
        ('edt.a@example.invalid', 'EA', 'x', 'EDITOR', true), ('cus.a@example.invalid', 'CA', 'x', 'CUSTOMER', true),
        ('adm.t@example.invalid', 'AT', 'x', 'ADMIN', true), ('adm.b@example.invalid', 'AB', 'x', 'ADMIN', true),
        ('adm.l@example.invalid', 'AL', 'x', 'ADMIN', true), ('outsider@example.invalid', 'O', 'x', 'ADMIN', true);
    INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES
        ('adm.a@example.invalid', pa, 'ADMIN', true), ('own.a@example.invalid', pa, 'OWNER', true),
        ('edt.a@example.invalid', pa, 'EDITOR', true), ('cus.a@example.invalid', pa, 'CUSTOMER', true),
        ('adm.t@example.invalid', pt, 'ADMIN', true), ('adm.b@example.invalid', pb, 'ADMIN', true),
        ('adm.l@example.invalid', cl, 'ADMIN', true);
END $$;

-- Helpers ----------------------------------------------------------------------------------------------------
-- kind: fuel (one concept, litres), multi_mixed (fuel + another key), multi_fuel (two fuel concepts), unmapped (unknown key and unit),
--       fuel_kg (fuel key, kilograms), fuel_xyz (fuel key, unknown unit), fuel_dec4 (fuel key, 4 decimals)
CREATE FUNCTION pg_temp.inv(p_uuid text, p_emisor text, p_receptor text, p_kind text DEFAULT 'fuel', p_days integer DEFAULT 10,
                            p_pay text DEFAULT '03', p_uso text DEFAULT 'G03', p_tipo text DEFAULT 'I') RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object('uuid', p_uuid, 'serie', 'T', 'folio', '1',
        'fechaEmision', (public.fn_agri_today_cdmx() - p_days)::text || 'T08:49:01', 'fechaTimbrado', (public.fn_agri_today_cdmx() - p_days)::text || 'T08:49:13',
        'emisor', jsonb_build_object('rfc', p_emisor, 'nombre', 'EMISOR DE PRUEBA'),
        'receptor', jsonb_build_object('rfc', p_receptor, 'nombre', 'RECEPTOR DE PRUEBA', 'usoCfdi', p_uso),
        'moneda', 'MXN', 'tipoComprobante', p_tipo, 'formaPago', p_pay, 'metodoPago', 'PUE',
        'subtotalCents', 345842, 'descuentoCents', 0, 'totalCents', 400013,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.160000', 'baseCents', 338569, 'importeCents', 54171)),
        'retenciones', '[]'::jsonb, 'sourceSha256', repeat('a', 64),
        'conceptos', CASE p_kind
            WHEN 'fuel' THEN jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '10.500000', 'valorUnitario', '32.94', 'importeCents', 345842))
            WHEN 'multi_mixed' THEN jsonb_build_array(
                jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '5', 'valorUnitario', '40', 'importeCents', 200000),
                jsonb_build_object('claveProdServ', '81111500', 'descripcion', 'Servicio', 'claveUnidad', 'E48', 'cantidad', '1', 'valorUnitario', '1458.42', 'importeCents', 145842))
            WHEN 'multi_fuel' THEN jsonb_build_array(
                jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '5', 'valorUnitario', '40', 'importeCents', 200000),
                jsonb_build_object('claveProdServ', '15101506', 'descripcion', 'Gasolina', 'claveUnidad', 'LTR', 'cantidad', '4', 'valorUnitario', '36.46', 'importeCents', 145842))
            WHEN 'unmapped' THEN jsonb_build_array(jsonb_build_object('claveProdServ', '99999999', 'descripcion', 'Otro', 'claveUnidad', 'XYZ', 'cantidad', '3', 'valorUnitario', '1', 'importeCents', 345842))
            WHEN 'fuel_kg' THEN jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'KGM', 'cantidad', '25', 'valorUnitario', '1', 'importeCents', 345842))
            WHEN 'fuel_xyz' THEN jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'XYZ', 'cantidad', '3', 'valorUnitario', '1', 'importeCents', 345842))
            WHEN 'fuel_dec4' THEN jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '1.2345', 'valorUnitario', '1', 'importeCents', 345842))
        END)
$$;
CREATE FUNCTION pg_temp.uid() RETURNS text LANGUAGE sql AS $$ SELECT upper(gen_random_uuid()::text) $$;
CREATE FUNCTION pg_temp.path(p_co text) RETURNS text LANGUAGE sql AS $$ SELECT p_co || '/2026/10/' || repeat('a', 64) || '.xml' $$;
-- Draft of the given company and user; returns the draft id (NULL when the procedure refused).
CREATE FUNCTION pg_temp.dr(p_co text, p_email text, p_uuid text, p_emisor text, p_receptor text, p_kind text DEFAULT 'fuel',
                           p_sat text DEFAULT 'VIGENTE', p_days integer DEFAULT 10, p_pay text DEFAULT '03', p_uso text DEFAULT 'G03') RETURNS text LANGUAGE sql AS $$
    SELECT public.sp_agri_expense_invoice_draft_create(p_co, p_email, 'CHAT_WEB', pg_temp.inv(p_uuid, p_emisor, p_receptor, p_kind, p_days, p_pay, p_uso)::text, pg_temp.path(p_co), p_sat) ->> 'draft_id'
$$;
CREATE FUNCTION pg_temp.pv(p_co text, p_email text, p_draft text, p_cat text DEFAULT NULL, p_desc text DEFAULT NULL, p_date text DEFAULT NULL,
                           p_pl text DEFAULT NULL, p_lot text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_agri_expense_invoice_preview(p_co, p_email, p_draft, p_cat, p_desc, p_date, p_pl, p_lot) $$;
CREATE FUNCTION pg_temp.cf(p_co text, p_email text, p_draft text, p_cat text DEFAULT NULL, p_desc text DEFAULT NULL, p_date text DEFAULT NULL,
                           p_pl text DEFAULT NULL, p_lot text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_agri_expense_invoice_confirm(p_co, p_email, p_draft, p_cat, p_desc, p_date, p_pl, p_lot) $$;
-- Direct call of register, unconfirmed or confirmed.
CREATE FUNCTION pg_temp.rg(p_co text, p_email text, p_uuid text, p_emisor text, p_receptor text, p_confirmed text, p_kind text DEFAULT 'fuel',
                           p_sat text DEFAULT 'VIGENTE', p_cat text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_agri_expense_invoice_register(p_co, p_email, pg_temp.inv(p_uuid, p_emisor, p_receptor, p_kind)::text, pg_temp.path(p_co), p_sat, p_cat, NULL, NULL, NULL, NULL, p_confirmed) $$;
-- Everything a registration can write, as one comparable text.
CREATE FUNCTION pg_temp.snap() RETURNS text LANGUAGE sql AS $$
    SELECT (SELECT count(*) FROM public.agri_expenses)::text || '|' || (SELECT count(*) FROM public.agri_expense_invoices)::text || '|'
        || (SELECT count(*) FROM public.expense_invoice_drafts WHERE consumed_at IS NOT NULL)::text || '|' || (SELECT count(*) FROM public.company_issuer_rfcs)::text || '|'
        || (SELECT count(*) FROM public.company_tax_ids)::text || '|' || (SELECT count(*) FROM public.expense_invoices)::text || '|'
        || (SELECT count(*) FROM public.cattle_expenses)::text
$$;
CREATE FUNCTION pg_temp.clean(p_msg text) RETURNS boolean LANGUAGE sql AS $$
    SELECT p_msg IS NOT NULL AND p_msg !~ '[A-Z&Ñ]{3,4}[0-9]{6}' AND p_msg !~ '[0-9]' AND p_msg !~ 'T111|EMISOR|RECEPTOR'
$$;
CREATE FUNCTION pg_temp.row_of(p_uuid text, p_co text) RETURNS public.agri_expense_invoices LANGUAGE sql AS $$
    SELECT i FROM public.agri_expense_invoices i WHERE i.uuid = p_uuid AND i.id_company = p_co::int ORDER BY i.created_at DESC LIMIT 1 $$;
CREATE FUNCTION pg_temp.exp_of(p_uuid text, p_co text) RETURNS public.agri_expenses LANGUAGE sql AS $$
    SELECT e FROM public.agri_expenses e JOIN public.agri_expense_invoices i ON i.expense_id = e.id WHERE i.uuid = p_uuid AND i.id_company = p_co::int ORDER BY i.created_at DESC LIMIT 1 $$;

-- Mutations (inside the transaction; the real file is never changed) -------------------------------------------------------
SELECT set_config('t111.mutation', :'mutation', true) AS mutation_in_use;
DO $$
DECLARE
    v_m   text := current_setting('t111.mutation');
    v_reg text := pg_get_functiondef('public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)'::regprocedure);
    v_hsh text := pg_get_functiondef('public.fn_agri_expense_invoice_params_hash(text,text,text,text,text)'::regprocedure);
    v_trg text := pg_get_functiondef('public.fn_trg_agri_expenses_void_invoice()'::regprocedure);
    v_new text;
    v_old text;
BEGIN
    IF v_m = 'none' THEN RETURN; END IF;
    IF v_m IN ('M1', 'M2', 'M3', 'M6') THEN
        v_old := v_reg;
        v_new := CASE v_m
            -- M1 SALE branch removed
            WHEN 'M1' THEN replace(v_reg, 'RETURN jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_SALE''', 'PERFORM jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_SALE''')
            -- M2 fail-closed branch removed
            WHEN 'M2' THEN replace(v_reg, 'RETURN jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_UNAVAILABLE''', 'PERFORM jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_UNAVAILABLE''')
            -- M3 the test-company SAT skip applies to every company
            WHEN 'M3' THEN replace(v_reg, 'ELSIF v_is_test AND v_sat_in IN', 'ELSIF v_sat_in IN')
            -- M6 EDITOR allowed
            WHEN 'M6' THEN replace(v_reg, 'ARRAY[''ADMIN'', ''OWNER'']', 'ARRAY[''ADMIN'', ''OWNER'', ''EDITOR'']')
        END;
    ELSIF v_m = 'M4' THEN
        -- M4 plantation not part of the preview hash
        v_old := v_hsh;
        v_new := replace(v_hsh, 'lower(coalesce(public.fn_agri_chat_txt(p_plantation), ''''))', '''''');
    ELSIF v_m = 'M5' THEN
        -- M5 voiding the expense no longer voids the link
        v_old := v_trg;
        v_new := replace(v_trg, 'IF NEW.is_void AND NOT OLD.is_void THEN', 'IF false THEN');
    ELSE
        RAISE EXCEPTION 'unknown mutation %', v_m;
    END IF;
    IF v_new = v_old THEN RAISE EXCEPTION 'mutation % did not change the function', v_m; END IF;
    EXECUTE v_new;
END $$;

-- A. Objects, privileges ------------------------------------------------------------------------------------------------------
SELECT pg_temp.ok('A1 the procedures are plain plpgsql VOLATILE, not SECURITY DEFINER, no search_path (pattern of 091 / 092 / 104)',
    (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
      WHERE p.pronamespace = 'public'::regnamespace AND l.lanname = 'plpgsql' AND p.provolatile = 'v' AND NOT p.prosecdef AND p.proconfig IS NULL
        AND p.proname IN ('sp_agri_expense_invoice_draft_create', 'sp_agri_expense_invoice_preview', 'sp_agri_expense_invoice_confirm', 'sp_agri_expense_invoice_register')) = 4);
SELECT pg_temp.ok('A2 nothing is registered in crud_models',
    (SELECT count(*) FROM public.crud_models WHERE table_name ~ 'agri_expense_invoice|expense_invoice' OR model_name ~ 'agri_expense_invoice') = 0);
SELECT pg_temp.ok('A3 the mapping functions are IMMUTABLE and map fuel and the four units',
    (SELECT bool_and(provolatile = 'i') FROM pg_proc WHERE proname IN ('fn_agri_cfdi_category', 'fn_agri_cfdi_unit', 'fn_agri_expense_invoice_params_hash'))
    AND public.fn_agri_cfdi_category('15101505') = 'COMBUSTIBLE' AND public.fn_agri_cfdi_category('99999999') IS NULL AND public.fn_agri_cfdi_category(NULL) IS NULL
    AND public.fn_agri_cfdi_unit('LTR') = 'L' AND public.fn_agri_cfdi_unit('KGM') = 'KG' AND public.fn_agri_cfdi_unit('H87') = 'PZA'
    AND public.fn_agri_cfdi_unit('E48') = 'SERVICIO' AND public.fn_agri_cfdi_unit('XYZ') IS NULL AND public.fn_agri_cfdi_unit(NULL) IS NULL);
SELECT pg_temp.ok('A4 every mapped unit exists in the unit catalog',
    (SELECT count(*) FROM public.agri_unit_catalog WHERE unit_code IN ('L', 'KG', 'PZA', 'SERVICIO') AND is_active) = 4);

-- H. Happy path: ADMIN and OWNER -------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; u text := pg_temp.uid(); r jsonb; s0 text; e public.agri_expenses; i public.agri_expense_invoices;
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.ok('H0 the draft is created for the ADMIN', d IS NOT NULL);
    s0 := pg_temp.snap();
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('H1 ADMIN preview: fuel voucher, category from the voucher, litres',
        r ->> 'status' = 'preview' AND r #>> '{summary,category_code}' = 'COMBUSTIBLE' AND r #>> '{summary,category_source}' = 'VOUCHER'
        AND (r #>> '{summary,amount}')::numeric = 4000.13 AND (r #>> '{summary,quantity}')::numeric = 10.5 AND r #>> '{summary,unit_code}' = 'L'
        AND r #>> '{summary,scope}' = 'GENERAL' AND r #>> '{summary,sat_status}' = 'VIGENTE' AND r ->> 'draft_id' = d
        AND r #>> '{summary,expense_date}' = (public.fn_agri_today_cdmx() - 10)::text);
    PERFORM pg_temp.ok('H2 the preview asks about the scope and writes nothing but the preview mark',
        r ? 'scope_question' AND NOT r ? 'plantation_proposal' AND pg_temp.snap() = s0
        AND (SELECT previewed_at IS NOT NULL AND consumed_at IS NULL AND previewed_hash IS NOT NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('H3 ADMIN confirm records the expense', r ->> 'status' = 'recorded' AND (r ->> 'amount')::numeric = 4000.13 AND r ->> 'scope' = 'GENERAL');
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    i := pg_temp.row_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('H4 the expense row carries the voucher data',
        e.amount = 4000.13 AND e.is_invoiced AND e.invoice_folio = 'T1' AND e.supplier_name = 'EMISOR DE PRUEBA' AND e.description = 'CFDI T1 EMISOR DE PRUEBA'
        AND e.reported_by_email = 'adm.a@example.invalid' AND e.plantation_id IS NULL AND e.lot_id IS NULL AND e.quantity = 10.5 AND e.unit_code = 'L'
        AND e.expense_date = public.fn_agri_today_cdmx() - 10 AND NOT e.is_void
        AND (SELECT category_code FROM public.agri_expense_categories WHERE id = e.category_id) = 'COMBUSTIBLE');
    PERFORM pg_temp.ok('H5 the link row is ACTIVE with the voucher data',
        i.status = 'ACTIVE' AND i.sat_status = 'VIGENTE' AND NOT i.is_test AND i.total_cents = 400013 AND i.subtotal_cents = 345842 AND i.payment_form = '03'
        AND i.uso_cfdi = 'G03' AND i.emisor_rfc = 'TEX010101EX1' AND i.receptor_rfc = 'TPA010101PA1' AND i.expense_id = e.id AND i.registered_by_email = 'adm.a@example.invalid'
        AND i.source_sha256 = repeat('a', 64) AND i.original_path = pg_temp.path(pg_temp.c('pa')));
    PERFORM pg_temp.ok('H6 the draft is consumed', (SELECT consumed_at IS NOT NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    -- OWNER
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'own.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA2');
    r := pg_temp.pv(pg_temp.c('pa'), 'own.a@example.invalid', d);
    PERFORM pg_temp.ok('H7 OWNER preview (second own RFC)', r ->> 'status' = 'preview');
    r := pg_temp.cf(pg_temp.c('pa'), 'own.a@example.invalid', d);
    PERFORM pg_temp.ok('H8 OWNER confirm', r ->> 'status' = 'recorded' AND (pg_temp.exp_of(u, pg_temp.c('pa'))).reported_by_email = 'own.a@example.invalid');
    -- description and date overrides, dates
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, 'Diesel para tractor', (public.fn_agri_today_cdmx() - 3)::text);
    PERFORM pg_temp.ok('H9 description and date overrides appear in the preview', r #>> '{summary,description}' = 'Diesel para tractor' AND r #>> '{summary,expense_date}' = (public.fn_agri_today_cdmx() - 3)::text);
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, 'Diesel para tractor', (public.fn_agri_today_cdmx() - 3)::text);
    PERFORM pg_temp.ok('H10 ...and in the expense row', r ->> 'status' = 'recorded' AND (pg_temp.exp_of(u, pg_temp.c('pa'))).description = 'Diesel para tractor'
        AND (pg_temp.exp_of(u, pg_temp.c('pa'))).expense_date = public.fn_agri_today_cdmx() - 3);
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.ok('H11 a future date is refused', pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, (public.fn_agri_today_cdmx() + 2)::text) ->> 'code' = 'DATE_IN_FUTURE');
    PERFORM pg_temp.ok('H12 an unreadable date is refused', pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, 'mañana') ->> 'code' = 'INVALID_DATE');
END $$;

-- R. Roles and companies -----------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; r jsonb; s0 text; dd text;
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    s0 := pg_temp.snap();
    dd := pg_temp.dr(pg_temp.c('pa'), 'edt.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.ok('R1 EDITOR cannot create a draft', dd IS NULL);
    r := public.sp_agri_expense_invoice_draft_create(pg_temp.c('pa'), 'edt.a@example.invalid', 'CHAT_WEB', pg_temp.inv(pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1')::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('R2 ...it is told so with a fixed message', r ->> 'status' = 'forbidden' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.pv(pg_temp.c('pa'), 'edt.a@example.invalid', d);
    PERFORM pg_temp.ok('R3 EDITOR preview is refused (even for a draft of another user)', r ->> 'status' = 'forbidden');
    r := pg_temp.cf(pg_temp.c('pa'), 'edt.a@example.invalid', d);
    PERFORM pg_temp.ok('R4 EDITOR confirm is refused', r ->> 'status' = 'forbidden');
    r := pg_temp.rg(pg_temp.c('pa'), 'edt.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'true');
    PERFORM pg_temp.ok('R5 EDITOR through register directly is refused', r ->> 'status' = 'forbidden');
    r := pg_temp.pv(pg_temp.c('pa'), 'cus.a@example.invalid', d);
    PERFORM pg_temp.ok('R6 CUSTOMER is refused', r ->> 'status' = 'forbidden');
    r := pg_temp.pv(pg_temp.c('pa'), 'outsider@example.invalid', d);
    PERFORM pg_temp.ok('R7 not a member: refused (no exception)', r ->> 'status' = 'forbidden');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('R8 member of another company only: refused', r ->> 'status' = 'forbidden');
    r := pg_temp.pv('abc', 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('R9 ambiguous tenant fails closed', r ->> 'status' = 'forbidden');
    r := pg_temp.pv(NULL, 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('R10 missing tenant fails closed', r ->> 'status' = 'forbidden');
    r := pg_temp.pv(pg_temp.c('l'), 'adm.l@example.invalid', d);
    PERFORM pg_temp.ok('R11 a livestock company is refused by the palm procedures', r ->> 'status' = 'not_palm');
    r := pg_temp.rg(pg_temp.c('l'), 'adm.l@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TLA010101LA1', 'true');
    PERFORM pg_temp.ok('R12 ...also through register', r ->> 'status' = 'not_palm');
    PERFORM pg_temp.expect_err('R13 a palm company is still refused by the livestock procedure (P0094)',
        format('SELECT public.sp_expense_invoice_register(%L, %L, %L, %L)', pg_temp.c('pa'), 'adm.a@example.invalid', '{}', 'COMBUSTIBLE'), 'P0094');
    PERFORM pg_temp.ok('R14 nothing was written by any refusal', pg_temp.snap() = s0);
END $$;

-- G. Role gate ------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; r jsonb; s0 text; u text := pg_temp.uid();
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TPA010101PA1', 'TEX010101EX1');
    s0 := pg_temp.snap();
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('G1 a sale (company as issuer): refused at preview', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_SALE' AND pg_temp.clean(r ->> 'message'));
    PERFORM pg_temp.ok('G2 nothing written; draft neither previewed nor consumed',
        pg_temp.snap() = s0 AND (SELECT previewed_at IS NULL AND consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    UPDATE public.expense_invoice_drafts SET previewed_at = now(), previewed_hash = public.fn_agri_expense_invoice_params_hash(NULL, NULL, NULL, NULL, NULL) WHERE id = d::uuid;
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('G3 a sale: refused at confirm with the preview mark set', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0
        AND (SELECT consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TPA010101PA1', 'TEX010101EX1', 'true');
    PERFORM pg_temp.ok('G4 a sale: refused through register directly', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0);
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TPA010101PA1', 'XAXX010101000', 'true');
    PERFORM pg_temp.ok('G5 a sale to the public: refused, no RFC registered', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0);
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TPA010101PA1', 'TPA010101PA1', 'false');
    PERFORM pg_temp.ok('G6 a self invoice: ROLE_AMBIGUOUS', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_AMBIGUOUS' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TPA010101PA1', 'TPA010101PA2', 'true');
    PERFORM pg_temp.ok('G7 two own RFCs: ROLE_AMBIGUOUS', r ->> 'code' = 'ROLE_AMBIGUOUS' AND pg_temp.snap() = s0);
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TEY010101EY2', 'true');
    PERFORM pg_temp.ok('G8 neither RFC is the company''s: refused, nothing registered (no self-registration of RFCs in palm)',
        r ->> 'status' = 'rfc_not_registered' AND r ->> 'code' = 'ROLE_UNKNOWN' AND pg_temp.clean(r ->> 'message') AND pg_temp.snap() = s0);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TEY010101EY2'));
    PERFORM pg_temp.ok('G9 ...also at preview', r ->> 'code' = 'ROLE_UNKNOWN');
END $$;

-- G (classifier unavailable). A perfect expense is refused when the classifier cannot answer.
CREATE FUNCTION pg_temp.expense_refused(p_id text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s0 text := pg_temp.snap(); r jsonb; d text;
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok(p_id || 'a preview -> ROLE_UNAVAILABLE', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_UNAVAILABLE' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'true');
    PERFORM pg_temp.ok(p_id || 'b direct confirm -> ROLE_UNAVAILABLE', r ->> 'code' = 'ROLE_UNAVAILABLE');
    PERFORM pg_temp.ok(p_id || 'c nothing written, draft not consumed', pg_temp.snap() = s0 AND (SELECT consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
END $$;
\ir 109_rollback.sql
SELECT pg_temp.expense_refused('G10 109 rollback stub (UNKNOWN / DISABLED): ');
\ir 109_cfdi_role_classifier.sql
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'classifier failure (test)'; END $$;
SELECT pg_temp.expense_refused('G11 classifier raises an exception: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT NULL::jsonb $$;
SELECT pg_temp.expense_refused('G12 classifier answers NULL: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"UNKNOWN","reason":"INVALID_INPUT"}'::jsonb $$;
SELECT pg_temp.expense_refused('G13 UNKNOWN / INVALID_INPUT: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"SURPRISE"}'::jsonb $$;
SELECT pg_temp.expense_refused('G14 an unknown role value: ');
\ir 109_cfdi_role_classifier.sql
SELECT pg_temp.ok('G15 109 re-applied: the expense works again',
    pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'false') ->> 'status' = 'preview');

-- S. SAT --------------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; r jsonb; s0 text := pg_temp.snap(); u text := pg_temp.uid();
BEGIN
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel', 'NO_ENCONTRADO'));
    PERFORM pg_temp.ok('S1 NO_ENCONTRADO on a normal company: sat_not_valid', r ->> 'status' = 'sat_not_valid');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel', 'ERROR'));
    PERFORM pg_temp.ok('S2 ERROR on a normal company: sat_not_valid', r ->> 'status' = 'sat_not_valid');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel', 'CANCELADO'));
    PERFORM pg_temp.ok('S3 CANCELADO on a normal company: sat_not_valid', r ->> 'status' = 'sat_not_valid');
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'true', 'fuel', 'SKIPPED_TEST');
    PERFORM pg_temp.ok('S4 SKIPPED_TEST on a normal company: sat_not_valid, nothing written', r ->> 'status' = 'sat_not_valid' AND pg_temp.snap() = s0);
    -- test company
    d := pg_temp.dr(pg_temp.c('pt'), 'adm.t@example.invalid', u, 'TEX010101EX1', 'TPT010101PT1', 'fuel', 'NO_ENCONTRADO');
    r := pg_temp.pv(pg_temp.c('pt'), 'adm.t@example.invalid', d);
    PERFORM pg_temp.ok('S5 test company: NO_ENCONTRADO is accepted as SKIPPED_TEST', r ->> 'status' = 'preview' AND r #>> '{summary,sat_status}' = 'SKIPPED_TEST');
    r := pg_temp.cf(pg_temp.c('pt'), 'adm.t@example.invalid', d);
    PERFORM pg_temp.ok('S6 ...and stored as SKIPPED_TEST with is_test', r ->> 'status' = 'recorded' AND (pg_temp.row_of(u, pg_temp.c('pt'))).sat_status = 'SKIPPED_TEST' AND (pg_temp.row_of(u, pg_temp.c('pt'))).is_test);
    r := pg_temp.pv(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.dr(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPT010101PT1', 'fuel', 'ERROR'));
    PERFORM pg_temp.ok('S7 test company: ERROR is accepted', r ->> 'status' = 'preview' AND r #>> '{summary,sat_status}' = 'SKIPPED_TEST');
    r := pg_temp.pv(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.dr(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPT010101PT1', 'fuel', 'VIGENTE'));
    PERFORM pg_temp.ok('S8 test company: VIGENTE stays VIGENTE', r #>> '{summary,sat_status}' = 'VIGENTE');
    r := pg_temp.pv(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.dr(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPT010101PT1', 'fuel', 'CANCELADO'));
    PERFORM pg_temp.ok('S9 test company: CANCELADO is never accepted', r ->> 'status' = 'sat_not_valid');
    PERFORM pg_temp.ok('S10 an invalid SAT status is refused at the draft', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel', 'MAYBE') IS NULL);
END $$;

-- D. Duplicates ----------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d1 text; d2 text; d3 text; u text := pg_temp.uid(); r jsonb; s0 text; n bigint;
BEGIN
    d1 := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    d2 := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d1);
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d2);
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d1);
    PERFORM pg_temp.ok('D1 first confirm records', r ->> 'status' = 'recorded');
    s0 := pg_temp.snap();
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d2);
    PERFORM pg_temp.ok('D2 the same UUID from a second draft: duplicate with the registered date and amount (ADMIN)',
        r ->> 'status' = 'duplicate' AND r ->> 'expense_date' = (public.fn_agri_today_cdmx() - 10)::text AND (r ->> 'amount')::numeric = 4000.13);
    s0 := pg_temp.snap();   -- from here on: the duplicate draft is consumed, and no expense or link was added by it
    PERFORM pg_temp.ok('D3 a duplicate consumes its draft', (SELECT consumed_at IS NOT NULL FROM public.expense_invoice_drafts WHERE id = d2::uuid)
        AND (SELECT count(*) FROM public.agri_expense_invoices WHERE uuid = u) = 1);
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d1);
    PERFORM pg_temp.ok('D4 confirming the same draft again is idempotent (already_registered, nothing written)', r ->> 'status' = 'already_registered' AND pg_temp.snap() = s0);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d1);
    PERFORM pg_temp.ok('D5 previewing a consumed draft says it was processed', r ->> 'status' = 'already_registered');
    d3 := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d3);
    PERFORM pg_temp.ok('D6 a new draft of a registered UUID: the preview already says duplicate (no preview mark)',
        r ->> 'status' = 'duplicate' AND (SELECT previewed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d3::uuid));
    r := pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1', 'true');
    PERFORM pg_temp.ok('D7 register directly, confirmed: duplicate, nothing written', r ->> 'status' = 'duplicate' AND pg_temp.snap() = s0);
    SELECT count(*) INTO n FROM public.agri_expense_invoices WHERE uuid = u AND id_company = pg_temp.c('pa')::int AND status = 'ACTIVE';
    PERFORM pg_temp.ok('D8 exactly one ACTIVE link per (company, UUID)', n = 1);
    PERFORM public.sp_agri_record_expense(pg_temp.c('pa')::int, NULL, NULL, (SELECT id FROM public.agri_expense_categories WHERE id_company = pg_temp.c('pa')::int AND category_code = 'OTROS'),
                                          public.fn_agri_today_cdmx(), 5, NULL, NULL, NULL, 'manual', false, NULL, 'adm.a@example.invalid');
    PERFORM pg_temp.expect_err('D9 the unique index refuses a second ACTIVE link even by a direct insert',
        format('INSERT INTO public.agri_expense_invoices (id_company, uuid, emisor_rfc, receptor_rfc, issued_at, stamped_at, subtotal_cents, total_cents, source_sha256, original_path, sat_status, expense_id, registered_by_email)
                SELECT id_company, uuid, emisor_rfc, receptor_rfc, issued_at, stamped_at, subtotal_cents, total_cents, source_sha256, original_path, sat_status, (SELECT id FROM public.agri_expenses WHERE id_company = %s AND id NOT IN (SELECT expense_id FROM public.agri_expense_invoices) LIMIT 1), registered_by_email
                  FROM public.agri_expense_invoices WHERE uuid = %L AND id_company = %s LIMIT 1', pg_temp.c('pa'), u, pg_temp.c('pa')), '23505');
END $$;

-- V. Void and re-register -----------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; u text := pg_temp.uid(); r jsonb; e public.agri_expenses; i public.agri_expense_invoices; n bigint; m bigint;
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    r := public.sp_agri_void_expense(pg_temp.c('pa')::int, e.id, 'registro por error', 'adm.a@example.invalid');
    PERFORM pg_temp.ok('V1 the expense is voided by the existing procedure', (r ->> 'success')::boolean);
    i := pg_temp.row_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('V2 the link was voided in the same transaction', i.status = 'VOID' AND i.voided_at IS NOT NULL AND i.void_reason = 'registro por error' AND i.voided_by_email = 'adm.a@example.invalid');
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('V3 the UUID is free again: normal preview', r ->> 'status' = 'preview');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('V4 ...and it can be registered again', r ->> 'status' = 'recorded');
    SELECT count(*) FILTER (WHERE status = 'ACTIVE'), count(*) FILTER (WHERE status = 'VOID') INTO n, m FROM public.agri_expense_invoices WHERE uuid = u AND id_company = pg_temp.c('pa')::int;
    PERFORM pg_temp.ok('V5 one ACTIVE and one VOID link remain (history kept)', n = 1 AND m = 1);
    -- a manual expense (no voucher) voids without touching any link
    r := public.sp_agri_record_expense(pg_temp.c('pa')::int, NULL, NULL, (SELECT id FROM public.agri_expense_categories WHERE id_company = pg_temp.c('pa')::int AND category_code = 'OTROS'),
                                       public.fn_agri_today_cdmx(), 10, NULL, NULL, NULL, 'manual', false, NULL, 'adm.a@example.invalid');
    SELECT count(*) INTO n FROM public.agri_expense_invoices WHERE status = 'ACTIVE';
    PERFORM public.sp_agri_void_expense(pg_temp.c('pa')::int, (r ->> 'expense_id')::uuid, 'prueba', 'adm.a@example.invalid');
    PERFORM pg_temp.ok('V6 voiding a manual expense leaves every link as it was', (SELECT count(*) FROM public.agri_expense_invoices WHERE status = 'ACTIVE') = n);
    -- the link table is append-only
    PERFORM pg_temp.expect_err('V7 a link cannot be deleted', format('DELETE FROM public.agri_expense_invoices WHERE uuid = %L', u), 'P0095');
    PERFORM pg_temp.expect_err('V8 a link cannot be truncated', 'TRUNCATE public.agri_expense_invoices', 'P0095');
    PERFORM pg_temp.expect_err('V9 a link column cannot be edited', format('UPDATE public.agri_expense_invoices SET total_cents = 1 WHERE uuid = %L AND status = ''ACTIVE''', u), 'P0095');
    PERFORM pg_temp.expect_err('V10 a link cannot be voided by hand', format('UPDATE public.agri_expense_invoices SET status = ''VOID'', voided_at = now() WHERE uuid = %L AND status = ''ACTIVE''', u), 'P0095');
    PERFORM pg_temp.expect_err('V11 a voided link cannot be reactivated', format('UPDATE public.agri_expense_invoices SET status = ''ACTIVE'', voided_at = NULL WHERE uuid = %L AND status = ''VOID''', u), 'P0095');
END $$;

-- P. Plantation and lot ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; u text; r jsonb; s0 text; e public.agri_expenses;
BEGIN
    -- plantation
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1');
    PERFORM pg_temp.ok('P1 preview with a plantation code', r ->> 'status' = 'preview' AND r #>> '{summary,scope}' = 'PLANTATION' AND r #>> '{summary,scope_label}' = 'T111 Alfa' AND NOT r ? 'scope_question');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1');
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('P2 confirm: the expense belongs to the plantation, no lot', r ->> 'status' = 'recorded' AND e.plantation_id = pg_temp.c('a1')::uuid AND e.lot_id IS NULL);
    -- plantation + lot
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'alfa', 'S-01');
    PERFORM pg_temp.ok('P3 plantation by partial name and lot by code', r #>> '{summary,scope}' = 'LOT');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'alfa', 'S-01');
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('P4 confirm: plantation and lot stored', r ->> 'status' = 'recorded' AND e.plantation_id = pg_temp.c('a1')::uuid AND e.lot_id IS NOT NULL);
    -- only a lot (unique): the plantation is inferred
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, NULL, 'solo b');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, NULL, 'solo b');
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('P5 only the lot given: the plantation of the lot is used', r ->> 'status' = 'recorded' AND e.plantation_id = pg_temp.c('a2')::uuid AND e.lot_id IS NOT NULL);
    -- ambiguity and not found never guess
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    s0 := pg_temp.snap();
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, NULL, 'N-01');
    PERFORM pg_temp.ok('P6 a lot code that exists in two plantations: ambiguous, never guessed', r ->> 'status' = 'need_info' AND r #>> '{issues,0,type}' = 'ambiguous' AND r #>> '{issues,0,field}' = 'lot');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'N-01');
    PERFORM pg_temp.ok('P7 ...with the plantation it resolves', r ->> 'status' = 'preview' AND r #>> '{summary,scope}' = 'LOT');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'ONLY-B');
    PERFORM pg_temp.ok('P8 a lot that belongs to another plantation is not found', r ->> 'status' = 'need_info' AND r #>> '{issues,0,type}' = 'not_found' AND r #>> '{issues,0,field}' = 'lot');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP');
    PERFORM pg_temp.ok('P9 a plantation name that matches two: ambiguous', r ->> 'status' = 'need_info' AND r #>> '{issues,0,type}' = 'ambiguous' AND r #>> '{issues,0,field}' = 'plantation');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'nope');
    PERFORM pg_temp.ok('P10 an unknown plantation: not found with options', r #>> '{issues,0,type}' = 'not_found' AND jsonb_array_length(r #> '{issues,0,options}') > 0);
    PERFORM pg_temp.ok('P11 nothing written and the draft has no preview mark after those answers',
        pg_temp.snap() = s0 AND (SELECT consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-B1');
    PERFORM pg_temp.ok('P12 a plantation of another company is not found', r ->> 'status' = 'need_info' AND r #>> '{issues,0,type}' = 'not_found');
    -- proposals
    d := pg_temp.dr(pg_temp.c('pt'), 'adm.t@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPT010101PT1');
    r := pg_temp.pv(pg_temp.c('pt'), 'adm.t@example.invalid', d);
    PERFORM pg_temp.ok('P13 a single active plantation is proposed, not applied',
        r #>> '{summary,scope}' = 'GENERAL' AND r #>> '{plantation_proposal,code}' = 'TP-T1' AND r ? 'scope_question');
    r := pg_temp.cf(pg_temp.c('pt'), 'adm.t@example.invalid', d);
    PERFORM pg_temp.ok('P14 confirming without it records a general expense', r ->> 'status' = 'recorded' AND r ->> 'scope' = 'GENERAL'
        AND (SELECT plantation_id IS NULL FROM public.agri_expenses WHERE id = (r ->> 'expense_id')::uuid));
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.ok('P15 with two plantations nothing is proposed', NOT pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d) ? 'plantation_proposal');
END $$;

-- H (hash). The preview hash covers plantation and lot.
DO $$
DECLARE d text; r jsonb;
BEGIN
    PERFORM pg_temp.ok('H20 the hash differs when the plantation or the lot differs',
        public.fn_agri_expense_invoice_params_hash('X', 'd', '2026-01-01', 'a', NULL) <> public.fn_agri_expense_invoice_params_hash('X', 'd', '2026-01-01', 'b', NULL)
        AND public.fn_agri_expense_invoice_params_hash('X', 'd', '2026-01-01', 'a', 'l1') <> public.fn_agri_expense_invoice_params_hash('X', 'd', '2026-01-01', 'a', 'l2')
        AND public.fn_agri_expense_invoice_params_hash('X', 'd', '2026-01-01', 'a', NULL) = public.fn_agri_expense_invoice_params_hash('x', 'd', '2026-01-01', ' A ', 'null'));
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A2');
    PERFORM pg_temp.ok('H21 previewed with one plantation, confirmed with another: preview_required', r ->> 'status' = 'preview_required');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'S-01');
    PERFORM pg_temp.ok('H22 confirmed with an added lot: preview_required', r ->> 'status' = 'preview_required');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('H23 confirmed without the plantation: preview_required', r ->> 'status' = 'preview_required');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'S-01');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'N-01');
    PERFORM pg_temp.ok('H24 previewed with one lot, confirmed with another: preview_required', r ->> 'status' = 'preview_required');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, 'OTROS', NULL, NULL, 'TP-A1', 'S-01');
    PERFORM pg_temp.ok('H25 a different category: preview_required', r ->> 'status' = 'preview_required');
    UPDATE public.expense_invoice_drafts SET previewed_at = now() - interval '20 minutes' WHERE id = d::uuid;
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'S-01');
    PERFORM pg_temp.ok('H26 a stale preview (older than 15 minutes): preview_required', r ->> 'status' = 'preview_required');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'S-01');
    r := pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, NULL, NULL, NULL, 'TP-A1', 'S-01');
    PERFORM pg_temp.ok('H27 the same arguments: recorded', r ->> 'status' = 'recorded');
END $$;

-- C. Category and unit mapping ----------------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; u text; r jsonb; s0 text := pg_temp.snap(); e public.agri_expenses;
BEGIN
    u := pg_temp.uid();
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1', 'multi_mixed');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.ok('C1 concepts that map to different categories: the preview asks, listing the company categories',
        r ->> 'status' = 'need_info' AND r #>> '{issues,0,field}' = 'category_code' AND jsonb_array_length(r #> '{issues,0,options}') = 13);
    PERFORM pg_temp.ok('C2 ...and writes nothing', pg_temp.snap() = s0);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d, 'Mano de obra');
    PERFORM pg_temp.ok('C3 the user picks a category by name: it is used, source USER; no quantity for several concepts',
        r ->> 'status' = 'preview' AND r #>> '{summary,category_code}' = 'MANO_OBRA' AND r #>> '{summary,category_source}' = 'USER' AND r #> '{summary,quantity}' = 'null'::jsonb AND r #> '{summary,unit_code}' = 'null'::jsonb);
    PERFORM pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d, 'Mano de obra');
    e := pg_temp.exp_of(u, pg_temp.c('pa'));
    PERFORM pg_temp.ok('C4 multi-concept expense: quantity and unit are both NULL', e.quantity IS NULL AND e.unit_code IS NULL);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'multi_mixed'), 'NO_EXISTE');
    PERFORM pg_temp.ok('C5 an unknown category: need_info with the options', r #>> '{issues,0,type}' = 'invalid' AND jsonb_array_length(r #> '{issues,0,options}') = 13);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'multi_fuel'));
    PERFORM pg_temp.ok('C6 several concepts that all map to fuel: category from the voucher, no quantity',
        r #>> '{summary,category_code}' = 'COMBUSTIBLE' AND r #> '{summary,quantity}' = 'null'::jsonb AND (r #>> '{summary,concepts}')::int = 2);
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'unmapped'));
    PERFORM pg_temp.ok('C7 an unmapped product key: the category is never invented', r ->> 'status' = 'need_info' AND r #>> '{issues,0,field}' = 'category_code');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel_kg'));
    PERFORM pg_temp.ok('C8 kilograms: KG with the quantity', (r #>> '{summary,quantity}')::numeric = 25 AND r #>> '{summary,unit_code}' = 'KG');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel_xyz'));
    PERFORM pg_temp.ok('C9 an unknown unit: no quantity and no unit', r #> '{summary,quantity}' = 'null'::jsonb AND r #> '{summary,unit_code}' = 'null'::jsonb AND r ->> 'status' = 'preview');
    r := pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'fuel_dec4'));
    PERFORM pg_temp.ok('C10 a quantity with more than 3 decimals: no quantity and no unit', r #> '{summary,quantity}' = 'null'::jsonb AND r #> '{summary,unit_code}' = 'null'::jsonb);
    -- a company that retired the category
    UPDATE public.agri_expense_categories SET is_active = false WHERE id_company = pg_temp.c('pb')::int AND category_code = 'COMBUSTIBLE';
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPB010101PB1'));
    PERFORM pg_temp.ok('C11 the mapped category is retired in the company: the preview asks instead of using it', r ->> 'status' = 'need_info' AND jsonb_array_length(r #> '{issues,0,options}') = 12);
END $$;

-- W. Warnings: informational, never block ------------------------------------------------------------------------------------------------------
DO $$
DECLARE d text; u text := pg_temp.uid(); r jsonb;
BEGIN
    -- a company with no history has no usual uso CFDI
    d := pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', u, 'TEX010101EX1', 'TPB010101PB1', 'multi_fuel', 'VIGENTE', 10, '01', 'P01');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', d);
    PERFORM pg_temp.ok('W1 (company B has retired fuel: the category is asked) preview of a cash voucher still lists the warning only once the category is given',
        r ->> 'status' = 'need_info');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', d, 'OTROS');
    PERFORM pg_temp.ok('W2 cash payment form: a warning line, status preview', r ->> 'status' = 'preview' AND jsonb_array_length(r -> 'warnings') = 1 AND r -> 'warnings' ->> 0 LIKE '%efectivo%');
    r := pg_temp.cf(pg_temp.c('pb'), 'adm.b@example.invalid', d, 'OTROS');
    PERFORM pg_temp.ok('W3 warnings never block: recorded', r ->> 'status' = 'recorded' AND jsonb_array_length(r -> 'warnings') = 1);
    -- company B now has one voucher with uso P01: a different uso warns
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPB010101PB1', 'multi_fuel', 'VIGENTE', 10, '03', 'G03'), 'OTROS');
    PERFORM pg_temp.ok('W4 a uso CFDI different from the company''s usual: a warning', jsonb_array_length(r -> 'warnings') = 1 AND r -> 'warnings' ->> 0 LIKE '%uso de CFDI%');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPB010101PB1', 'multi_fuel', 'VIGENTE', 10, '03', 'P01'), 'OTROS');
    PERFORM pg_temp.ok('W5 the usual uso CFDI: no warning', jsonb_array_length(r -> 'warnings') = 0);
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPB010101PB1', 'multi_fuel', 'VIGENTE', 400, '03', 'P01'), 'OTROS');
    PERFORM pg_temp.ok('W6 a date older than 365 days: a warning, still a preview', r ->> 'status' = 'preview' AND jsonb_array_length(r -> 'warnings') = 1 AND r -> 'warnings' ->> 0 LIKE '%365%');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.dr(pg_temp.c('pb'), 'adm.b@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPB010101PB1', 'multi_fuel', 'VIGENTE', 364, '03', 'P01'), 'OTROS');
    PERFORM pg_temp.ok('W7 364 days old: no warning', jsonb_array_length(r -> 'warnings') = 0);
END $$;

-- I. Isolation between companies -----------------------------------------------------------------------------------------------------------------
DO $$
DECLARE da text; u text := pg_temp.uid(); r jsonb; s0 text;
BEGIN
    da := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', da);
    PERFORM pg_temp.ok('I1 a draft of company A is not found by company B', r ->> 'status' = 'not_found');
    r := pg_temp.cf(pg_temp.c('pb'), 'adm.b@example.invalid', da);
    PERFORM pg_temp.ok('I2 ...nor confirmed', r ->> 'status' = 'not_found');
    r := pg_temp.pv(pg_temp.c('pa'), 'own.a@example.invalid', da);
    PERFORM pg_temp.ok('I3 a draft of one user is not found by another user of the same company', r ->> 'status' = 'not_found');
    r := pg_temp.pv(pg_temp.c('pb'), 'adm.b@example.invalid', 'not-a-uuid');
    PERFORM pg_temp.ok('I4 a malformed draft id is not found (no exception)', r ->> 'status' = 'not_found');
    -- the voucher of A is not an expense for B
    s0 := pg_temp.snap();
    r := pg_temp.rg(pg_temp.c('pb'), 'adm.b@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1', 'true');
    PERFORM pg_temp.ok('I5 company B cannot book a voucher addressed to company A''s RFC', r ->> 'code' = 'ROLE_UNKNOWN' AND pg_temp.snap() = s0);
    PERFORM pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1'));
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', da);
    PERFORM pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', da);
    -- a UUID registered by A does not exist for B
    r := pg_temp.rg(pg_temp.c('pb'), 'adm.b@example.invalid', u, 'TEX010101EX1', 'TPB010101PB1', 'false', 'multi_fuel', 'VIGENTE', 'OTROS');
    PERFORM pg_temp.ok('I6 a UUID already registered by A is invisible to B (its own voucher previews normally)', r ->> 'status' = 'preview');
    PERFORM pg_temp.expect_err('I7 a link cannot point to an expense of another company',
        format('INSERT INTO public.agri_expense_invoices (id_company, uuid, emisor_rfc, receptor_rfc, issued_at, stamped_at, subtotal_cents, total_cents, source_sha256, original_path, sat_status, expense_id, registered_by_email)
                SELECT %s, %L, ''TEX010101EX1'', ''TPB010101PB1'', now(), now(), 1, 1, repeat(''a'', 64), %L, ''VIGENTE'', e.id, ''x@example.invalid'' FROM public.agri_expenses e WHERE e.id_company = %s LIMIT 1',
               pg_temp.c('pb'), pg_temp.uid(), pg_temp.path(pg_temp.c('pb')), pg_temp.c('pa')), 'P0096');
END $$;

-- X. Voucher validation ------------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; j jsonb := pg_temp.inv(pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1'); s0 text := pg_temp.snap();
BEGIN
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', 'not json', pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X1 malformed voucher: INVALID_INVOICE', r ->> 'code' = 'INVALID_INVOICE');
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', (j || '{"totalCents": 400014}')::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X2 totals that do not reconcile to the cent: AMOUNTS_MISMATCH', r ->> 'code' = 'AMOUNTS_MISMATCH');
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', (j || '{"moneda": "USD"}')::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X3 a foreign currency: UNSUPPORTED_CURRENCY', r ->> 'code' = 'UNSUPPORTED_CURRENCY');
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', (j || '{"tipoComprobante": "E"}')::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X4 a voucher that is not an income voucher: UNSUPPORTED_TYPE', r ->> 'code' = 'UNSUPPORTED_TYPE');
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', j::text, pg_temp.path(pg_temp.c('pb')), 'VIGENTE');
    PERFORM pg_temp.ok('X5 an original path of another company: ORIGINAL_PATH_INVALID', r ->> 'code' = 'ORIGINAL_PATH_INVALID');
    r := public.sp_agri_expense_invoice_register(pg_temp.c('pa'), 'adm.a@example.invalid', (j #- '{receptor,rfc}')::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X6 a missing receptor RFC: INVALID_RFC', r ->> 'code' = 'INVALID_RFC');
    r := public.sp_agri_expense_invoice_draft_create(pg_temp.c('pa'), 'adm.a@example.invalid', 'CHAT_WEB', j::text, pg_temp.path(pg_temp.c('pb')), 'VIGENTE');
    PERFORM pg_temp.ok('X7 a draft with the path of another company: refused', r ->> 'code' = 'ORIGINAL_PATH_INVALID');
    r := public.sp_agri_expense_invoice_draft_create(pg_temp.c('pa'), 'adm.a@example.invalid', 'FAX', j::text, pg_temp.path(pg_temp.c('pa')), 'VIGENTE');
    PERFORM pg_temp.ok('X8 an unknown channel: refused', r ->> 'code' = 'INVALID_CHANNEL');
    PERFORM pg_temp.ok('X9 nothing written', pg_temp.snap() = s0);
END $$;

-- Z. Rollback and re-apply -----------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE u text := pg_temp.uid(); d text; e public.agri_expenses;
BEGIN
    d := pg_temp.dr(pg_temp.c('pa'), 'adm.a@example.invalid', u, 'TEX010101EX1', 'TPA010101PA1');
    PERFORM pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    PERFORM pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', d);
    INSERT INTO ctx VALUES ('zu', u);
END $$;
\ir 111_rollback.sql
SELECT pg_temp.ok('Z1 after the rollback the four procedures answer disabled and write nothing',
    pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', gen_random_uuid()::text) ->> 'status' = 'disabled'
    AND pg_temp.cf(pg_temp.c('pa'), 'adm.a@example.invalid', gen_random_uuid()::text) ->> 'status' = 'disabled'
    AND pg_temp.rg(pg_temp.c('pa'), 'adm.a@example.invalid', pg_temp.uid(), 'TEX010101EX1', 'TPA010101PA1', 'true') ->> 'status' = 'disabled'
    AND public.sp_agri_expense_invoice_draft_create(pg_temp.c('pa'), 'adm.a@example.invalid', 'CHAT_WEB', '{}', 'x', 'VIGENTE') ->> 'status' = 'disabled');
SELECT pg_temp.ok('Z2 the table, its rows and the void trigger stay', to_regclass('public.agri_expense_invoices') IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.agri_expense_invoices WHERE uuid = pg_temp.c('zu'))
    AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expenses_void_invoice' AND tgenabled <> 'D'));
SELECT public.sp_agri_void_expense(pg_temp.c('pa')::int, (pg_temp.exp_of(pg_temp.c('zu'), pg_temp.c('pa'))).id, 'prueba', 'adm.a@example.invalid') ->> 'success' AS voided \gset
SELECT pg_temp.ok('Z3 after the rollback a void still voids the link', (pg_temp.row_of(pg_temp.c('zu'), pg_temp.c('pa'))).status = 'VOID');
\ir 111_palm_expense_invoices.sql
SELECT pg_temp.ok('Z4 re-applying restores the procedures',
    pg_temp.pv(pg_temp.c('pa'), 'adm.a@example.invalid', gen_random_uuid()::text) ->> 'status' = 'not_found');

SELECT count(*) AS assertions_run FROM results \gset
\echo 111 TESTS: :assertions_run assertions passed (mutation=:mutation)
ROLLBACK;
