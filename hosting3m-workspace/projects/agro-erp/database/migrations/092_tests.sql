-- 092_tests.sql: LOCAL / throwaway database only (needs 091 applied). Everything is rolled back.
-- psql -v ON_ERROR_STOP=1 -v tenant=3 -v admin=ADMIN_EMAIL -f 092_tests.sql
\set ON_ERROR_STOP on
\if :{?tenant}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 092_tests.sql'
\quit
\endif
\if :{?admin}
\else
\echo 'usage: psql -v tenant=3 -v admin=EMAIL -f 092_tests.sql'
\quit
\endif
BEGIN;
\set embedded true
\ir 092_expense_invoice_drafts.sql
SELECT set_config('t092.tenant', :'tenant', true) AS tenant, set_config('t092.admin', :'admin', true) AS admin;

DO $$
DECLARE
    t       text := current_setting('t092.tenant');
    a       text := current_setting('t092.admin');
    sha     text := repeat('a', 64);
    p       text;
    base    jsonb;
    r       jsonb;
    d1      text;
    d2      text;
    d3      text;
    v_raise boolean;
    n       bigint;
BEGIN
    p := t || '/2026/10/' || sha || '.xml';
    base := jsonb_build_object('uuid', 'AAAAAAAA-0000-4000-8000-000000000001', 'serie', 'T', 'folio', '1',
        'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
        'emisor', jsonb_build_object('rfc', 'OES010209154', 'nombre', 'EMISOR DE PRUEBA'),
        'receptor', jsonb_build_object('rfc', 'XAXX010101000', 'nombre', 'RECEPTOR DE PRUEBA'),
        'moneda', 'MXN', 'subtotalCents', 345842, 'descuentoCents', 0, 'totalCents', 400013,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.160000', 'baseCents', 338569, 'importeCents', 54171)),
        'retenciones', '[]'::jsonb, 'sourceSha256', sha,
        'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'importeCents', 345842)));
    PERFORM public.sp_company_tax_id_set(t, a, 'XAXX010101000', 'test');
    UPDATE public.company_tax_ids SET qa_skip_sat = false WHERE id_company = t::int AND rfc = 'XAXX010101000';

    -- T1 draft creation and its validation
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, p, 'VIGENTE');
    IF r ->> 'status' <> 'draft_created' OR (r #>> '{summary,amount}')::numeric <> 4000.13 OR jsonb_array_length(r #> '{summary,concepts}') <> 1 THEN RAISE EXCEPTION 'FAIL T1 draft: %', r; END IF;
    d1 := r ->> 'draft_id';
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, ((t::int + 1)::text || '/2026/10/' || sha || '.xml'), 'VIGENTE');
    IF r ->> 'code' IS DISTINCT FROM 'ORIGINAL_PATH_INVALID' THEN RAISE EXCEPTION 'FAIL T1b other-company path: %', r; END IF;
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, (t || '/2026/10/' || repeat('b', 64) || '.xml'), 'VIGENTE');
    IF r ->> 'code' IS DISTINCT FROM 'ORIGINAL_PATH_INVALID' THEN RAISE EXCEPTION 'FAIL T1c sha/path mismatch: %', r; END IF;
    r := public.sp_expense_invoice_draft_create(t, a, 'EMAIL', base::text, p, 'VIGENTE');
    IF r ->> 'code' IS DISTINCT FROM 'INVALID_CHANNEL' THEN RAISE EXCEPTION 'FAIL T1d channel: %', r; END IF;
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, p, 'MAYBE');
    IF r ->> 'code' IS DISTINCT FROM 'INVALID_SAT_STATUS' THEN RAISE EXCEPTION 'FAIL T1e sat status: %', r; END IF;
    v_raise := false;
    BEGIN PERFORM public.sp_expense_invoice_draft_create(t, 'nobody@example.invalid', 'CHAT_WEB', base::text, p, 'VIGENTE'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T1f non-member created a draft'; END IF;
    RAISE NOTICE 'OK T1 draft creation and validation';

    -- T2 preview writes no invoice
    r := public.sp_expense_invoice_preview(t, a, d1, 'combustible', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'preview' OR (r ->> 'amount')::numeric <> 4000.13 THEN RAISE EXCEPTION 'FAIL T2 preview: %', r; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T2 preview wrote an invoice'; END IF;
    RAISE NOTICE 'OK T2 preview writes nothing';

    -- T3 confirm brake: different category / description / date than the preview, and a draft never previewed
    r := public.sp_expense_invoice_confirm(t, a, d1, 'ALIMENTO', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3a different category accepted: %', r; END IF;
    r := public.sp_expense_invoice_confirm(t, a, d1, 'COMBUSTIBLE', 'Otra descripcion', '2026-10-30');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3b different description accepted: %', r; END IF;
    r := public.sp_expense_invoice_confirm(t, a, d1, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-29');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3c different date accepted: %', r; END IF;
    r := public.sp_expense_invoice_draft_create(t, a, 'WHATSAPP', base::text, p, 'VIGENTE');
    d2 := r ->> 'draft_id';
    r := public.sp_expense_invoice_confirm(t, a, d2, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3d never-previewed draft accepted: %', r; END IF;
    UPDATE public.expense_invoice_drafts SET previewed_at = now() - interval '16 minutes' WHERE id = d1::uuid;
    r := public.sp_expense_invoice_confirm(t, a, d1, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'preview_required' THEN RAISE EXCEPTION 'FAIL T3e stale preview accepted: %', r; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL T3 a refused confirm wrote an invoice'; END IF;
    RAISE NOTICE 'OK T3 confirm needs a matching, fresh preview';

    -- T4 SAT rules go through the draft (NO_ENCONTRADO / ERROR skipped only for a qa_skip_sat RFC, CANCELADO never)
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, p, 'NO_ENCONTRADO');
    d3 := r ->> 'draft_id';
    r := public.sp_expense_invoice_preview(t, a, d3, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'sat_not_valid' THEN RAISE EXCEPTION 'FAIL T4a NO_ENCONTRADO accepted on a normal company: %', r; END IF;
    UPDATE public.company_tax_ids SET qa_skip_sat = true WHERE id_company = t::int AND rfc = 'XAXX010101000';
    r := public.sp_expense_invoice_preview(t, a, d3, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'preview' OR r ->> 'sat_status' <> 'SKIPPED_TEST' THEN RAISE EXCEPTION 'FAIL T4b QA RFC not skipped: %', r; END IF;
    r := public.sp_expense_invoice_draft_create(t, a, 'CHAT_WEB', base::text, p, 'CANCELADO');
    r := public.sp_expense_invoice_preview(t, a, r ->> 'draft_id', 'COMBUSTIBLE');
    IF r ->> 'status' <> 'sat_not_valid' THEN RAISE EXCEPTION 'FAIL T4c CANCELADO skipped: %', r; END IF;
    UPDATE public.company_tax_ids SET qa_skip_sat = false WHERE id_company = t::int AND rfc = 'XAXX010101000';
    RAISE NOTICE 'OK T4 SAT rules through drafts';

    -- T5 happy path: preview then confirm records the invoice and consumes the draft
    r := public.sp_expense_invoice_preview(t, a, d1, 'combustible', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'preview' THEN RAISE EXCEPTION 'FAIL T5a preview: %', r; END IF;
    r := public.sp_expense_invoice_confirm(t, a, d1, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'recorded' THEN RAISE EXCEPTION 'FAIL T5b not recorded: %', r; END IF;
    SELECT count(*) INTO n FROM public.expense_invoices WHERE id_company = t::int AND uuid = 'AAAAAAAA-0000-4000-8000-000000000001';
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL T5c % invoices after confirm', n; END IF;
    IF (SELECT consumed_at FROM public.expense_invoice_drafts WHERE id = d1::uuid) IS NULL THEN RAISE EXCEPTION 'FAIL T5d draft not consumed'; END IF;
    RAISE NOTICE 'OK T5 preview then confirm records and consumes';

    -- T6 replays: same draft again, and a second draft of the same CFDI
    r := public.sp_expense_invoice_confirm(t, a, d1, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'already_registered' THEN RAISE EXCEPTION 'FAIL T6a confirm replay: %', r; END IF;
    r := public.sp_expense_invoice_preview(t, a, d1, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'already_registered' THEN RAISE EXCEPTION 'FAIL T6b preview replay: %', r; END IF;
    r := public.sp_expense_invoice_preview(t, a, d2, 'COMBUSTIBLE', 'Diesel tractor', '2026-10-30');
    IF r ->> 'status' <> 'duplicate' THEN RAISE EXCEPTION 'FAIL T6c same CFDI in another draft: %', r; END IF;
    RAISE NOTICE 'OK T6 replays and duplicate CFDI';

    -- T7 ownership and expiry
    INSERT INTO public.expense_invoice_drafts (id_company, user_email, channel, invoice, source_sha256, original_path, sat_status)
    VALUES (t::int, 'other.user@example.invalid', 'CHAT_WEB', base, sha, p, 'VIGENTE') RETURNING id::text INTO d3;
    r := public.sp_expense_invoice_preview(t, a, d3, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'not_found' THEN RAISE EXCEPTION 'FAIL T7a another user''s draft visible: %', r; END IF;
    r := public.sp_expense_invoice_preview(t, a, 'not-a-uuid', 'COMBUSTIBLE');
    IF r ->> 'status' <> 'not_found' THEN RAISE EXCEPTION 'FAIL T7b bad id: %', r; END IF;
    INSERT INTO public.expense_invoice_drafts (id_company, user_email, channel, invoice, source_sha256, original_path, sat_status, expires_at)
    VALUES (t::int, lower(a), 'CHAT_WEB', base, sha, p, 'VIGENTE', now() - interval '1 minute') RETURNING id::text INTO d3;
    r := public.sp_expense_invoice_preview(t, a, d3, 'COMBUSTIBLE');
    IF r ->> 'status' <> 'draft_expired' THEN RAISE EXCEPTION 'FAIL T7c expired draft usable: %', r; END IF;
    v_raise := false;
    BEGIN PERFORM public.sp_expense_invoice_preview(t, 'nobody@example.invalid', d1, 'COMBUSTIBLE'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T7d non-member previewed'; END IF;
    RAISE NOTICE 'OK T7 ownership, bad ids and expiry';

    -- T8 immutability
    v_raise := false;
    BEGIN UPDATE public.expense_invoice_drafts SET invoice = '{}'::jsonb WHERE id = d1::uuid; EXCEPTION WHEN SQLSTATE 'P0095' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T8a draft invoice was updatable'; END IF;
    v_raise := false;
    BEGIN UPDATE public.expense_invoice_drafts SET consumed_at = NULL WHERE id = d1::uuid; EXCEPTION WHEN SQLSTATE 'P0095' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T8b consumed_at was resettable'; END IF;
    v_raise := false;
    BEGIN DELETE FROM public.expense_invoice_drafts WHERE id = d1::uuid; EXCEPTION WHEN SQLSTATE 'P0095' THEN v_raise := true; END;
    IF NOT v_raise THEN RAISE EXCEPTION 'FAIL T8c draft was deletable'; END IF;
    RAISE NOTICE 'OK T8 drafts immutable and not deletable';

    RAISE NOTICE 'ALL 092 TESTS OK';
END $$;
ROLLBACK;
\echo '*** 092 tests finished: everything rolled back ***'
