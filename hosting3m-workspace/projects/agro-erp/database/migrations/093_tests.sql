-- 093_tests.sql: LOCAL / throwaway database only (needs 091 and 092 applied). Everything is rolled back.
-- psql -v ON_ERROR_STOP=1 -v tenant=3 -v admin=ADMIN_EMAIL -f 093_tests.sql
\set ON_ERROR_STOP on
\if :{?tenant}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 093_tests.sql'
\quit
\endif
\if :{?admin}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 093_tests.sql'
\quit
\endif
BEGIN;
\set embedded true
\ir 093_auto_receptor_rfc.sql
SELECT set_config('t093.tenant', :'tenant', true) AS tenant, set_config('t093.admin', :'admin', true) AS admin;

DO $$
DECLARE
    t       text := current_setting('t093.tenant');
    a       text := current_setting('t093.admin');
    sha     text := repeat('a', 64);
    p       text;
    base    jsonb;
    r       jsonb;
    d       text;
    n       bigint;
    v_role  text;
    v_raise boolean;
    rfc1    constant text := 'TST010101AB1';
    rfc2    constant text := 'TST010101AB2';
    rfc3    constant text := 'TST010101AB3';
    rfc_prev text;
BEGIN
    p := t || '/2026/10/' || sha || '.xml';
    base := jsonb_build_object('uuid', 'BBBBBBBB-0000-4000-8000-000000000001', 'serie', 'T', 'folio', '1',
        'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
        'emisor', jsonb_build_object('rfc', 'OES010209154', 'nombre', 'EMISOR DE PRUEBA'),
        'receptor', jsonb_build_object('rfc', rfc1, 'nombre', 'RECEPTOR DE PRUEBA'),
        'moneda', 'MXN', 'subtotalCents', 345842, 'descuentoCents', 0, 'totalCents', 400013,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.160000', 'baseCents', 338569, 'importeCents', 54171)),
        'retenciones', '[]'::jsonb, 'sourceSha256', sha,
        'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'importeCents', 345842)));
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc IN (rfc1, rfc2, rfc3);
    IF n <> 0 THEN RAISE EXCEPTION 'SETUP: test RFCs already exist in company %', t; END IF;
    SELECT uc.role INTO v_role FROM public.user_companies uc WHERE uc.id_company = t::int AND lower(uc.email) = lower(a) AND uc.is_active IS TRUE LIMIT 1;
    IF v_role NOT IN ('ADMIN', 'OWNER') THEN RAISE EXCEPTION 'SETUP: % is not ADMIN/OWNER in company %', a, t; END IF;

    -- T1 preview of an unregistered receiver: warns, writes no RFC row
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, p, 'VIGENTE');
    d := r ->> 'draft_id';
    r := public.sp_expense_invoice_preview(t, a, d, 'COMBUSTIBLE', 'Diesel', '2026-10-30');
    IF r ->> 'status' <> 'preview' OR (r ->> 'rfc_new')::boolean IS NOT TRUE OR r ->> 'rfc_new_notice' NOT LIKE '%' || rfc1 || '%' OR jsonb_typeof(r -> 'company_rfcs') <> 'array' THEN
        RAISE EXCEPTION 'FAIL T1 preview: %', r;
    END IF;
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc = rfc1;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T1 preview created the RFC'; END IF;
    RAISE NOTICE 'OK T1 preview warns and writes nothing';

    -- T2 an EDITOR is still refused
    UPDATE public.user_companies SET role = 'EDITOR' WHERE id_company = t::int AND lower(email) = lower(a);
    r := public.sp_expense_invoice_preview(t, a, d, 'COMBUSTIBLE', 'Diesel', '2026-10-30');
    IF r ->> 'status' <> 'rfc_not_registered' THEN RAISE EXCEPTION 'FAIL T2 EDITOR got: %', r; END IF;
    UPDATE public.user_companies SET role = v_role WHERE id_company = t::int AND lower(email) = lower(a);
    RAISE NOTICE 'OK T2 EDITOR refused';

    -- T3 confirm without a preview of the same parameters is still refused and creates nothing
    r := public.sp_expense_invoice_confirm(t, a, d, 'COMBUSTIBLE', 'Otra', '2026-10-30');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3 gate: %', r; END IF;
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc = rfc1;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T3 refused confirm created the RFC'; END IF;
    RAISE NOTICE 'OK T3 preview gate intact';

    -- T4 preview then confirm: expense, invoice and the new RFC in one go
    r := public.sp_expense_invoice_preview(t, a, d, 'COMBUSTIBLE', 'Diesel', '2026-10-30');
    r := public.sp_expense_invoice_confirm(t, a, d, 'COMBUSTIBLE', 'Diesel', '2026-10-30');
    IF r ->> 'status' <> 'recorded' OR r ->> 'rfc_registered' <> rfc1 THEN RAISE EXCEPTION 'FAIL T4 confirm: %', r; END IF;
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc = rfc1 AND is_active IS TRUE AND qa_skip_sat IS FALSE
        AND label LIKE 'AUTO%' AND created_by_email = lower(a);
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL T4 RFC row missing or wrong (%)', n; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE id_company = t::int AND uuid = 'BBBBBBBB-0000-4000-8000-000000000001' AND receptor_rfc = rfc1;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL T4 invoice missing'; END IF;
    RAISE NOTICE 'OK T4 confirm registers expense, invoice and RFC';

    -- T5 next invoice for the same RFC: no warning any more
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', (base || jsonb_build_object('uuid', 'BBBBBBBB-0000-4000-8000-000000000002'))::text, p, 'VIGENTE');
    r := public.sp_expense_invoice_preview(t, a, r ->> 'draft_id', 'COMBUSTIBLE');
    IF r ->> 'status' <> 'preview' OR r ? 'rfc_new' THEN RAISE EXCEPTION 'FAIL T5 second invoice: %', r; END IF;
    RAISE NOTICE 'OK T5 registered RFC no longer warns';

    -- T6 a deactivated RFC is never reactivated automatically
    PERFORM public.sp_company_tax_id_set(t, a, rfc1, NULL, 'false');
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', (base || jsonb_build_object('uuid', 'BBBBBBBB-0000-4000-8000-000000000003'))::text, p, 'VIGENTE');
    d := r ->> 'draft_id';
    r := public.sp_expense_invoice_preview(t, a, d, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'rfc_not_registered' THEN RAISE EXCEPTION 'FAIL T6a preview: %', r; END IF;
    r := public.sp_expense_invoice_confirm(t, a, d, 'COMBUSTIBLE');
    IF r ->> 'status' NOT IN ('rfc_not_registered', 'preview_required') THEN RAISE EXCEPTION 'FAIL T6b confirm: %', r; END IF;
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc = rfc1 AND is_active IS TRUE;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T6 deactivated RFC was reactivated'; END IF;
    RAISE NOTICE 'OK T6 deactivated RFC stays deactivated';

    -- T7 SAT must still be VIGENTE for a new RFC (no qa skip) and nothing is created otherwise
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB',
        (base || jsonb_build_object('uuid', 'BBBBBBBB-0000-4000-8000-000000000004', 'receptor', jsonb_build_object('rfc', rfc2, 'nombre', 'X')))::text, p, 'NO_ENCONTRADO');
    d := r ->> 'draft_id';
    r := public.sp_expense_invoice_preview(t, a, d, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'sat_not_valid' THEN RAISE EXCEPTION 'FAIL T7a preview: %', r; END IF;
    r := public.sp_expense_invoice_confirm(t, a, d, 'COMBUSTIBLE');
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc = rfc2;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T7 RFC created for a non-valid SAT status'; END IF;
    RAISE NOTICE 'OK T7 non-valid SAT creates nothing';

    -- T8 a non-member cannot reach anything (fail-closed tenant context)
    v_raise := false;
    BEGIN PERFORM public.sp_expense_invoice_preview(t, 'nobody@example.invalid', d, 'COMBUSTIBLE'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T8 non-member previewed'; END IF;
    v_raise := false;
    BEGIN PERFORM public.sp_expense_invoice_confirm(t, 'nobody@example.invalid', d, 'COMBUSTIBLE'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T8 non-member confirmed'; END IF;
    SELECT count(*) INTO n FROM public.company_tax_ids WHERE id_company = t::int AND rfc IN (rfc2, rfc3);
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T8 unexpected RFC rows'; END IF;
    RAISE NOTICE 'OK T8 tenant isolation';

    RAISE NOTICE 'ALL 093 TESTS OK';
END $$;
ROLLBACK;
\echo '*** 093 tests finished: everything rolled back ***'
