-- 091_tests.sql: LOCAL / throwaway database only. Everything is rolled back.
-- psql -v ON_ERROR_STOP=1 -v tenant=3 -v admin=ADMIN_EMAIL -f 091_tests.sql
-- tenant = a non-palm company; admin = an ACTIVE ADMIN (or OWNER) member of it. Includes 091_expense_invoices.sql with embedded set.
\set ON_ERROR_STOP on
\if :{?tenant}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 091_tests.sql'
\quit
\endif
\if :{?admin}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 091_tests.sql'
\quit
\endif
BEGIN;
\set embedded true
\ir 091_expense_invoices.sql
SELECT set_config('t091.tenant', :'tenant', true) AS tenant, set_config('t091.admin', :'admin', true) AS admin;

DO $$
DECLARE
    t       text := current_setting('t091.tenant');
    a       text := current_setting('t091.admin');
    p       text := current_setting('t091.tenant') || '/2026/10/test.xml';
    base    jsonb;
    r       jsonb;
    v_raise boolean;
    n       bigint;
    v_amt   numeric;
BEGIN
    base := jsonb_build_object('uuid', 'AAAAAAAA-0000-4000-8000-000000000001', 'serie', 'T', 'folio', '1',
        'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
        'emisor', jsonb_build_object('rfc', 'OES010209154', 'nombre', 'EMISOR DE PRUEBA'),
        'receptor', jsonb_build_object('rfc', 'XAXX010101000', 'nombre', 'RECEPTOR DE PRUEBA'),
        'moneda', 'MXN', 'subtotalCents', 345842, 'descuentoCents', 0, 'totalCents', 400013,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.160000', 'baseCents', 338569, 'importeCents', 54171)),
        'retenciones', '[]'::jsonb, 'sourceSha256', repeat('a', 64));

    r := public.sp_company_tax_id_set(t, a, 'xaxx010101000', 'test');
    IF r ->> 'status' <> 'saved' THEN RAISE EXCEPTION 'FAIL T1 tax id not saved: %', r; END IF;
    r := public.sp_company_tax_id_set(t, a, 'NOT-AN-RFC');
    IF r ->> 'status' <> 'invalid' THEN RAISE EXCEPTION 'FAIL T1b bad RFC accepted: %', r; END IF;
    v_raise := false;
    BEGIN PERFORM public.sp_company_tax_id_set(t, 'nobody@example.invalid', 'XAXX010101000'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T1c non-member accepted'; END IF;
    v_raise := false;
    BEGIN PERFORM public.sp_expense_invoice_register(t, 'nobody@example.invalid', base::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'true'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T1d non-member registered an invoice'; END IF;
    RAISE NOTICE 'OK T1 tax ids and membership';

    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'false');
    IF r ->> 'status' <> 'preview' OR (r ->> 'amount')::numeric <> 4000.13 THEN RAISE EXCEPTION 'FAIL T2 preview: %', r; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T2 preview wrote a row'; END IF;
    RAISE NOTICE 'OK T2 preview writes nothing';

    r := public.sp_expense_invoice_register(t, a, (base || jsonb_build_object('receptor', jsonb_build_object('rfc', 'AAA010101AAA')))::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'status' <> 'rfc_not_registered' THEN RAISE EXCEPTION 'FAIL T3 unregistered receiver: %', r; END IF;
    RAISE NOTICE 'OK T3 receiver RFC must be registered';

    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, p, 'SKIPPED_TEST', 'false');
    IF r ->> 'status' <> 'sat_not_valid' THEN RAISE EXCEPTION 'FAIL T4a SKIPPED_TEST accepted without flag: %', r; END IF;
    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, p, 'CANCELADO', 'false');
    IF r ->> 'status' <> 'sat_not_valid' THEN RAISE EXCEPTION 'FAIL T4b cancelled accepted: %', r; END IF;
    UPDATE public.company_tax_ids SET qa_skip_sat = true WHERE id_company = t::int AND rfc = 'XAXX010101000';
    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, p, 'SKIPPED_TEST', 'false');
    IF r ->> 'status' <> 'preview' THEN RAISE EXCEPTION 'FAIL T4c SKIPPED_TEST rejected with flag: %', r; END IF;
    UPDATE public.company_tax_ids SET qa_skip_sat = false WHERE id_company = t::int AND rfc = 'XAXX010101000';
    RAISE NOTICE 'OK T4 SAT status rules';

    r := public.sp_expense_invoice_register(t, a, (base || jsonb_build_object('totalCents', 400014))::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'code' IS DISTINCT FROM 'AMOUNTS_MISMATCH' THEN RAISE EXCEPTION 'FAIL T5 off-by-one-cent accepted: %', r; END IF;
    r := public.sp_expense_invoice_register(t, a, (base || jsonb_build_object('subtotalCents', 3458.42))::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'status' <> 'invalid' THEN RAISE EXCEPTION 'FAIL T5b decimal cents accepted: %', r; END IF;
    RAISE NOTICE 'OK T5 amounts reconcile exactly';

    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, '../x.xml', 'VIGENTE', 'true');
    IF r ->> 'code' IS DISTINCT FROM 'ORIGINAL_PATH_INVALID' THEN RAISE EXCEPTION 'FAIL T6a traversal path: %', r; END IF;
    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, ((t::int + 1)::text || '/x.xml'), 'VIGENTE', 'true');
    IF r ->> 'code' IS DISTINCT FROM 'ORIGINAL_PATH_INVALID' THEN RAISE EXCEPTION 'FAIL T6b other-company path: %', r; END IF;
    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, '2999-01-01', p, 'VIGENTE', 'true');
    IF r ->> 'code' IS DISTINCT FROM 'DATE_IN_FUTURE' THEN RAISE EXCEPTION 'FAIL T6c future date: %', r; END IF;
    r := public.sp_expense_invoice_register(t, a, base::text, '', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'code' IS DISTINCT FROM 'CATEGORY_REQUIRED' THEN RAISE EXCEPTION 'FAIL T6d empty category: %', r; END IF;
    RAISE NOTICE 'OK T6 path, date and category validation';

    r := public.sp_expense_invoice_register(t, a, base::text, 'combustible', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'status' <> 'recorded' THEN RAISE EXCEPTION 'FAIL T7 not recorded: %', r; END IF;
    SELECT e.amount INTO v_amt FROM public.expense_invoices i JOIN public.cattle_expenses e ON e.id = i.expense_id
     WHERE i.id_company = t::int AND i.uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF v_amt IS DISTINCT FROM 4000.13 THEN RAISE EXCEPTION 'FAIL T7 amount is %', v_amt; END IF;
    RAISE NOTICE 'OK T7 recorded: expense amount 4000.13 and a linked invoice';

    r := public.sp_expense_invoice_register(t, a, base::text, 'COMBUSTIBLE', NULL, NULL, p, 'VIGENTE', 'true');
    IF r ->> 'status' <> 'duplicate' THEN RAISE EXCEPTION 'FAIL T8 duplicate not detected: %', r; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE id_company = t::int AND uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL T8 % rows for one UUID', n; END IF;
    RAISE NOTICE 'OK T8 duplicate by company and UUID';

    v_raise := false;
    BEGIN UPDATE public.expense_invoices SET total_cents = 1 WHERE uuid = 'AAAAAAAA-0000-4000-8000-000000000001'; EXCEPTION WHEN SQLSTATE 'P0095' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T9 invoice was updatable'; END IF;
    v_raise := false;
    BEGIN DELETE FROM public.cattle_expenses WHERE id = (SELECT expense_id FROM public.expense_invoices WHERE uuid = 'AAAAAAAA-0000-4000-8000-000000000001'); EXCEPTION WHEN SQLSTATE '23503' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T10 an invoiced expense was deletable'; END IF;
    RAISE NOTICE 'OK T9/T10 append-only and expense delete restricted';

    RAISE NOTICE 'ALL 091 TESTS OK';
END $$;
ROLLBACK;
\echo '*** 091 tests finished: everything rolled back ***'
