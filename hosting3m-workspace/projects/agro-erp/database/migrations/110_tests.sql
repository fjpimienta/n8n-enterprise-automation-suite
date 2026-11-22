-- 110_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). One transaction, always rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 110_tests.sql     (run from this directory: it includes 109_* and 110_* files)
-- Optional: -v mutation=M1..M4 breaks one protection inside the transaction; the run must then FAIL (see 110_mutation_check.sh).
-- Needs 080, 084, 091, 092, 093, 104 and 109 applied, with the functions of 091 / 093 still at their repository text (the first apply checks it).
-- Synthetic data only: fake companies, RFCs, e-mails and UUIDs generated here.
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
-- L livestock company: own tax ids TLA (active), TLC (active), TLB (inactive)  (issuer RFCs exist only for palm companies, which the register refuses before the gate)
-- P palm company with one admin (the livestock tools are refused for it)
DO $$
DECLARE cl integer; cp integer;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T110 Cattle', 'Ganadería') RETURNING id_company INTO cl;
    INSERT INTO public.companys (company_name, industry) VALUES ('T110 Palm', 'Agricultura') RETURNING id_company INTO cp;
    INSERT INTO ctx VALUES ('l', cl::text), ('p', cp::text);
    INSERT INTO public.company_tax_ids (id_company, rfc, created_by_email, is_active) VALUES
        (cl, 'TLA010101LA1', 'seed@example.invalid', true), (cl, 'TLC010101LC3', 'seed@example.invalid', true),
        (cl, 'TLB010101LB2', 'seed@example.invalid', false), (cp, 'TPA010101PA1', 'seed@example.invalid', true);
    INSERT INTO public.users (email, names, password, role, is_active) VALUES
        ('admin.l@example.invalid', 'AL', 'x', 'ADMIN', true), ('editor.l@example.invalid', 'EL', 'x', 'EDITOR', true),
        ('viewer.l@example.invalid', 'VL', 'x', 'CUSTOMER', true), ('admin.p@example.invalid', 'AP', 'x', 'ADMIN', true),
        ('outsider@example.invalid', 'O', 'x', 'ADMIN', true);
    INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES
        ('admin.l@example.invalid', cl, 'ADMIN', true), ('editor.l@example.invalid', cl, 'EDITOR', true),
        ('viewer.l@example.invalid', cl, 'CUSTOMER', true), ('admin.p@example.invalid', cp, 'ADMIN', true);
END $$;

-- Helpers ----------------------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.inv(p_uuid text, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object('uuid', p_uuid, 'serie', 'T', 'folio', '1',
        'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
        'emisor', jsonb_build_object('rfc', p_emisor, 'nombre', 'EMISOR DE PRUEBA'),
        'receptor', jsonb_build_object('rfc', p_receptor, 'nombre', 'RECEPTOR DE PRUEBA'),
        'moneda', 'MXN', 'subtotalCents', 345842, 'descuentoCents', 0, 'totalCents', 400013,
        'traslados', jsonb_build_array(jsonb_build_object('impuesto', '002', 'tipoFactor', 'Tasa', 'tasaOCuota', '0.160000', 'baseCents', 338569, 'importeCents', 54171)),
        'retenciones', '[]'::jsonb, 'sourceSha256', repeat('a', 64),
        'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'importeCents', 345842)))
$$;
CREATE FUNCTION pg_temp.path() RETURNS text LANGUAGE sql AS $$ SELECT pg_temp.c('l') || '/2026/10/' || repeat('a', 64) || '.xml' $$;
CREATE FUNCTION pg_temp.uid() RETURNS text LANGUAGE sql AS $$ SELECT upper(gen_random_uuid()::text) $$;
-- A draft for the livestock company created by the given user; returns the draft id.
CREATE FUNCTION pg_temp.draft(p_email text, p_emisor text, p_receptor text, p_uuid text DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
    SELECT public.sp_expense_invoice_draft_create(pg_temp.c('l'), p_email, 'CHAT_WEB',
        pg_temp.inv(coalesce(p_uuid, pg_temp.uid()), p_emisor, p_receptor)::text, pg_temp.path(), 'VIGENTE') ->> 'draft_id'
$$;
CREATE FUNCTION pg_temp.preview(p_email text, p_draft text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_expense_invoice_preview(pg_temp.c('l'), p_email, p_draft, 'COMBUSTIBLE', 'Diesel', '2026-10-30') $$;
CREATE FUNCTION pg_temp.confirm(p_email text, p_draft text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_expense_invoice_confirm(pg_temp.c('l'), p_email, p_draft, 'COMBUSTIBLE', 'Diesel', '2026-10-30') $$;
-- Direct call of register (what a bypassed n8n / model could do), confirmed or not.
CREATE FUNCTION pg_temp.reg(p_email text, p_emisor text, p_receptor text, p_confirmed text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT public.sp_expense_invoice_register(pg_temp.c('l'), p_email, pg_temp.inv(pg_temp.uid(), p_emisor, p_receptor)::text, 'COMBUSTIBLE', 'Diesel', '2026-10-30',
        pg_temp.path(), 'VIGENTE', p_confirmed) $$;
-- Everything the registration can write, as one comparable text.
CREATE FUNCTION pg_temp.snap() RETURNS text LANGUAGE sql AS $$
    SELECT (SELECT count(*) FROM public.expense_invoices)::text || '|' || (SELECT count(*) FROM public.cattle_expenses)::text || '|'
        || (SELECT count(*) FROM public.company_tax_ids)::text || '|' || (SELECT count(*) FROM public.expense_invoice_drafts WHERE consumed_at IS NOT NULL)::text || '|'
        || coalesce((SELECT md5(string_agg(x::text, '|' ORDER BY x::text)) FROM public.company_tax_ids x), '')
$$;
CREATE FUNCTION pg_temp.clean(p_msg text) RETURNS boolean LANGUAGE sql AS $$
    SELECT p_msg IS NOT NULL AND p_msg !~ '[A-Z&Ñ]{3,4}[0-9]{6}' AND p_msg !~ '[0-9]' AND p_msg !~ 'BBBB|T110|EMISOR|RECEPTOR'
$$;
CREATE FUNCTION pg_temp.reg_md5() RETURNS text LANGUAGE sql AS $$ SELECT md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure)) $$;
CREATE FUNCTION pg_temp.tax_md5() RETURNS text LANGUAGE sql AS $$ SELECT md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure)) $$;
CREATE FUNCTION pg_temp.attrs() RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef || ':' || coalesce(p.proconfig::text, '-') || ':' || l.lanname || ':'
        || has_function_privilege('public', p.oid, 'EXECUTE') || ':' || coalesce(p.proacl::text, '-') || ':' || p.proowner::regrole::text, '|' ORDER BY p.proname)
      FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
     WHERE p.oid IN ('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure, 'public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure)
$$;

-- Attributes and privileges of the two functions BEFORE 110 (they must be identical after) ---------------------------
INSERT INTO ctx VALUES ('attr_before', pg_temp.attrs()), ('reg_old', pg_temp.reg_md5()), ('tax_old', pg_temp.tax_md5());

-- Apply 110 (first application over the repository 091 / 093 text: this also proves the embedded md5 constants) --------------
\ir 110_expense_invoice_role_gate.sql
INSERT INTO ctx VALUES ('reg_new', pg_temp.reg_md5()), ('tax_new', pg_temp.tax_md5());
SELECT pg_temp.ok('Z1 the functions changed', pg_temp.c('reg_new') <> pg_temp.c('reg_old') AND pg_temp.c('tax_new') <> pg_temp.c('tax_old'));
SELECT pg_temp.ok('Z2 same attributes, owner and privileges as before', pg_temp.attrs() = pg_temp.c('attr_before'));

-- D. Drift guard ---------------------------------------------------------------------------------------------------------
-- A function whose live text differs makes the migration abort and leaves the function as it was. ON_ERROR_STOP is off only around the included file.
CREATE FUNCTION pg_temp.drift(p_sig text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_def text := pg_get_functiondef(p_sig::regprocedure);
BEGIN
    EXECUTE replace(v_def, 'BEGIN', E'BEGIN\n    -- local edit');
END $$;
SAVEPOINT d0;
SELECT pg_temp.drift('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)');
SELECT pg_temp.reg_md5() AS drift_reg \gset
SAVEPOINT d1;
\echo '--- expected errors below: the drift guard aborting (register edited) ---'
\set ON_ERROR_STOP off
\ir 110_expense_invoice_role_gate.sql
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT d1;
SELECT pg_temp.ok('D1 drifted register: migration aborted and the function was not overwritten',
    pg_temp.reg_md5() = :'drift_reg' AND :'drift_reg' <> pg_temp.c('reg_new') AND pg_temp.tax_md5() = pg_temp.c('tax_new'));
ROLLBACK TO SAVEPOINT d0;
SELECT pg_temp.ok('D2 the edit was undone', pg_temp.reg_md5() = pg_temp.c('reg_new'));

SAVEPOINT d2;
SELECT pg_temp.drift('public.sp_company_tax_id_set(text,text,text,text,text)');
SELECT pg_temp.tax_md5() AS drift_tax \gset
SAVEPOINT d3;
\echo '--- expected errors below: the drift guard aborting (tax id function edited) ---'
\set ON_ERROR_STOP off
\ir 110_expense_invoice_role_gate.sql
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT d3;
SELECT pg_temp.ok('D3 drifted tax id function: migration aborted and nothing was overwritten',
    pg_temp.tax_md5() = :'drift_tax' AND :'drift_tax' <> pg_temp.c('tax_new') AND pg_temp.reg_md5() = pg_temp.c('reg_new'));
ROLLBACK TO SAVEPOINT d2;

\ir 110_expense_invoice_role_gate.sql
SELECT pg_temp.ok('D4 re-applying over the 110 text is a no-op', pg_temp.reg_md5() = pg_temp.c('reg_new') AND pg_temp.tax_md5() = pg_temp.c('tax_new'));

-- Mutations (inside the transaction; the real file is never changed) -------------------------------------------------------
SELECT set_config('t110.mutation', :'mutation', true) AS mutation_in_use;
DO $$
DECLARE
    v_reg text := pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure);
    v_tax text := pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure);
    v_m   text := current_setting('t110.mutation');
    v_r2  text; v_t2 text;
BEGIN
    v_r2 := CASE v_m
        WHEN 'none' THEN v_reg
        -- M1 SALE branch removed
        WHEN 'M1' THEN replace(v_reg, 'RETURN jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_SALE''', 'PERFORM jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_SALE''')
        -- M2 AMBIGUOUS branch removed
        WHEN 'M2' THEN replace(v_reg, 'RETURN jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_AMBIGUOUS''', 'PERFORM jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_AMBIGUOUS''')
        -- M3 fail-closed branch removed
        WHEN 'M3' THEN replace(v_reg, 'RETURN jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_UNAVAILABLE''', 'PERFORM jsonb_build_object(''status'', ''not_an_expense'', ''code'', ''ROLE_UNAVAILABLE''')
        -- M4 generic-RFC deny-list removed (register and tax id function)
        WHEN 'M4' THEN replace(v_reg, 'ARRAY[''XAXX010101000'', ''XEXX010101000'']', 'ARRAY[]::text[]')
        ELSE NULL END;
    v_t2 := CASE WHEN v_m = 'M4' THEN replace(v_tax, 'ARRAY[''XAXX010101000'', ''XEXX010101000'']', 'ARRAY[]::text[]') ELSE v_tax END;
    IF v_r2 IS NULL THEN RAISE EXCEPTION 'unknown mutation %', v_m; END IF;
    IF v_m <> 'none' AND v_r2 = v_reg THEN RAISE EXCEPTION 'mutation % did not change the function', v_m; END IF;
    EXECUTE v_r2;
    EXECUTE v_t2;
END $$;

-- S. Sales are refused -------------------------------------------------------------------------------------------------------
-- (the preview of a sale: own tax id as issuer, a receiver that is not registered)
DO $$
DECLARE d text; s0 text; r jsonb;
BEGIN
    d := pg_temp.draft('admin.l@example.invalid', 'TLA010101LA1', 'TEX010101EX1');
    s0 := pg_temp.snap();
    r := pg_temp.preview('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('S1 sale preview -> not_an_expense / ROLE_SALE', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_SALE' AND NOT r ? 'rfc_new');
    PERFORM pg_temp.ok('S2 sale message is fixed text (no RFC, UUID, name or amount)', pg_temp.clean(r ->> 'message'));
    PERFORM pg_temp.ok('S3 nothing written by the sale preview (invoices, expenses, RFCs, consumed drafts)', pg_temp.snap() = s0);
    PERFORM pg_temp.ok('S4 the receiver RFC of a sale was NOT auto-registered', NOT EXISTS (SELECT 1 FROM public.company_tax_ids WHERE rfc = 'TEX010101EX1'));
    PERFORM pg_temp.ok('S5 the draft is not previewed / consumed', (SELECT previewed_at IS NULL AND consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    -- confirm path through the wrapper: no preview mark exists, the wrapper stops it first and nothing is written
    r := pg_temp.confirm('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('S6 sale confirm without a preview mark is refused, nothing written', r ->> 'status' = 'preview_required' AND pg_temp.snap() = s0);
    -- a forged preview mark (what a bypassed preview could leave): the gate in register still refuses the confirm
    UPDATE public.expense_invoice_drafts SET previewed_at = now(), previewed_hash = public.fn_expense_invoice_params_hash('COMBUSTIBLE', 'Diesel', '2026-10-30') WHERE id = d::uuid;
    r := pg_temp.confirm('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('S7 sale confirm with a forged preview mark -> ROLE_SALE', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_SALE');
    PERFORM pg_temp.ok('S8 nothing written and the draft is NOT consumed', pg_temp.snap() = s0 AND (SELECT consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    -- register called directly (n8n / model bypassed), preview and confirm
    r := pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'TEX010101EX1', 'false');
    PERFORM pg_temp.ok('S9 direct register, unconfirmed -> ROLE_SALE', r ->> 'code' = 'ROLE_SALE');
    r := pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'TEX010101EX1', 'true');
    PERFORM pg_temp.ok('S10 direct register, confirmed -> ROLE_SALE and nothing written', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0);
    -- a sale to the generic public RFC
    r := pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'XAXX010101000', 'true');
    PERFORM pg_temp.ok('S12 sale to the generic public RFC -> ROLE_SALE, no RFC registered', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0);
    -- the same rules for an EDITOR (the gate precedes the EDITOR rejection of 093)
    r := pg_temp.reg('editor.l@example.invalid', 'TLA010101LA1', 'TEX010101EX1', 'false');
    PERFORM pg_temp.ok('S13 EDITOR sees the same refusal for a sale', r ->> 'code' = 'ROLE_SALE');
    -- lower case does not bypass it
    r := public.sp_expense_invoice_register(pg_temp.c('l'), 'admin.l@example.invalid', pg_temp.inv(pg_temp.uid(), 'tla010101la1', 'TEX010101EX1')::text, 'COMBUSTIBLE', NULL, '2026-10-30', pg_temp.path(), 'VIGENTE', 'true');
    PERFORM pg_temp.ok('S14 lower-case issuer RFC is still a sale', r ->> 'code' = 'ROLE_SALE' AND pg_temp.snap() = s0);
END $$;

-- A. Ambiguous ------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE s0 text := pg_temp.snap(); r jsonb;
BEGIN
    r := pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'TLA010101LA1', 'false');
    PERFORM pg_temp.ok('A1 self invoice -> ROLE_AMBIGUOUS', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_AMBIGUOUS' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'TLC010101LC3', 'true');
    PERFORM pg_temp.ok('A2 two own RFCs (issuer and receiver) -> ROLE_AMBIGUOUS', r ->> 'code' = 'ROLE_AMBIGUOUS');
    PERFORM pg_temp.ok('A4 nothing written by any ambiguous voucher', pg_temp.snap() = s0);
END $$;

-- E. Expenses keep working as in 093 ----------------------------------------------------------------------------------------------
DO $$
DECLARE d text; d2 text; u text := pg_temp.uid(); r jsonb; s0 text := pg_temp.snap(); n_inv bigint; n_exp bigint;
BEGIN
    d := pg_temp.draft('admin.l@example.invalid', 'TEX010101EX1', 'TLA010101LA1', u);
    r := pg_temp.preview('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('E1 expense with an own receptor: normal preview, no rfc_new',
        r ->> 'status' = 'preview' AND NOT r ? 'rfc_new' AND r ->> 'category' = 'COMBUSTIBLE' AND (r ->> 'amount')::numeric = 4000.13 AND r ->> 'expense_date' = '2026-10-30');
    PERFORM pg_temp.ok('E2 preview writes only the preview mark', pg_temp.snap() = s0 AND (SELECT previewed_at IS NOT NULL AND consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    r := pg_temp.confirm('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('E3 confirm records the expense', r ->> 'status' = 'recorded' AND (r ->> 'amount')::numeric = 4000.13 AND NOT r ? 'rfc_registered');
    SELECT count(*) INTO n_inv FROM public.expense_invoices WHERE uuid = u AND id_company = pg_temp.c('l')::int;
    SELECT count(*) INTO n_exp FROM public.cattle_expenses WHERE tenant_id = pg_temp.c('l')::int AND amount = 4000.13;
    PERFORM pg_temp.ok('E4 one invoice and one expense row, draft consumed', n_inv = 1 AND n_exp = 1 AND (SELECT consumed_at IS NOT NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
    d2 := pg_temp.draft('admin.l@example.invalid', 'TEX010101EX1', 'TLA010101LA1', u);
    r := pg_temp.preview('admin.l@example.invalid', d2);
    PERFORM pg_temp.ok('E5 the same UUID again -> duplicate (unchanged)', r ->> 'status' = 'duplicate');
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'TLC010101LC3', 'false');
    PERFORM pg_temp.ok('E6 second own RFC as receptor -> preview', r ->> 'status' = 'preview');
    r := pg_temp.reg('editor.l@example.invalid', 'TEX010101EX1', 'TLC010101LC3', 'false');
    PERFORM pg_temp.ok('E7 EDITOR on an own receptor -> preview as in 093', r ->> 'status' = 'preview');
    r := pg_temp.reg('viewer.l@example.invalid', 'TEX010101EX1', 'TLC010101LC3', 'false');
    PERFORM pg_temp.ok('E8 role without permission -> forbidden (unchanged, before the gate)', r ->> 'status' = 'forbidden');
END $$;

-- N. UNKNOWN / NEITHER keeps the 093 flow --------------------------------------------------------------------------------------------
DO $$
DECLARE d text; r jsonb; s0 text; u text := pg_temp.uid();
BEGIN
    d := pg_temp.draft('admin.l@example.invalid', 'TEX010101EX1', 'TNW010101NW1', u);
    s0 := pg_temp.snap();
    r := pg_temp.preview('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('N1 unknown receptor, issuer not own: ADMIN preview with rfc_new (093)', r ->> 'status' = 'preview' AND (r ->> 'rfc_new')::boolean IS TRUE AND r ->> 'rfc_new_notice' LIKE '%TNW010101NW1%');
    PERFORM pg_temp.ok('N2 the preview wrote no RFC', pg_temp.snap() = s0);
    r := pg_temp.confirm('admin.l@example.invalid', d);
    PERFORM pg_temp.ok('N3 ADMIN confirm records the voucher and registers the receptor RFC (093)', r ->> 'status' = 'recorded' AND r ->> 'rfc_registered' = 'TNW010101NW1');
    PERFORM pg_temp.ok('N4 the RFC row is active, AUTO label, no qa skip',
        (SELECT count(*) FROM public.company_tax_ids WHERE id_company = pg_temp.c('l')::int AND rfc = 'TNW010101NW1' AND is_active AND NOT qa_skip_sat AND label LIKE 'AUTO%') = 1);
    r := pg_temp.reg('editor.l@example.invalid', 'TEX010101EX1', 'TNE010101NE1', 'false');
    PERFORM pg_temp.ok('N5 EDITOR with an unknown receptor -> rfc_not_registered (093)', r ->> 'status' = 'rfc_not_registered');
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'TLB010101LB2', 'false');
    PERFORM pg_temp.ok('N6 deactivated receptor RFC -> rfc_not_registered, never reactivated',
        r ->> 'status' = 'rfc_not_registered' AND r ->> 'message' LIKE '%desactivado%'
        AND (SELECT NOT is_active FROM public.company_tax_ids WHERE id_company = pg_temp.c('l')::int AND rfc = 'TLB010101LB2'));
    r := public.sp_expense_invoice_register(pg_temp.c('l'), 'admin.l@example.invalid', pg_temp.inv(pg_temp.uid(), 'TEX010101EX1', 'TLA010101LA1')::text, 'COMBUSTIBLE', NULL, '2026-10-30', pg_temp.path(), 'CANCELADO', 'false');
    PERFORM pg_temp.ok('N7 SAT status still enforced -> sat_not_valid', r ->> 'status' = 'sat_not_valid');
    r := public.sp_expense_invoice_register(pg_temp.c('l'), 'admin.l@example.invalid', pg_temp.inv(pg_temp.uid(), 'TLA010101LA1', 'TEX010101EX1')::text, '', NULL, '2026-10-30', pg_temp.path(), 'VIGENTE', 'false');
    PERFORM pg_temp.ok('N8 existing validations come before the gate (category required)', r ->> 'code' = 'CATEGORY_REQUIRED');
END $$;

-- G. Generic RFCs ----------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; s0 text := pg_temp.snap();
BEGIN
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', 'XAXX010101000', 'x', 'true');
    PERFORM pg_temp.ok('G1 tax_id_set refuses the public-in-general RFC', r ->> 'status' = 'rfc_generic' AND pg_temp.clean(r ->> 'message'));
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', ' xexx010101000 ', NULL, 'true');
    PERFORM pg_temp.ok('G2 tax_id_set refuses the foreign RFC (case and spaces normalised)', r ->> 'status' = 'rfc_generic');
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', 'XAXX010101000', NULL, 'false');
    PERFORM pg_temp.ok('G3 a deactivated row cannot be created for a generic RFC either', r ->> 'status' = 'rfc_generic');
    PERFORM pg_temp.ok('G4 no generic row exists after the refusals', pg_temp.snap() = s0 AND NOT EXISTS (SELECT 1 FROM public.company_tax_ids WHERE rfc IN ('XAXX010101000', 'XEXX010101000')));
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', 'TNG010101NG1', 'ok', 'true');
    PERFORM pg_temp.ok('G5 a normal RFC is still saved', r ->> 'status' = 'saved' AND r ->> 'rfc' = 'TNG010101NG1');
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'editor.l@example.invalid', 'TNG010101NH2', NULL, 'true');
    PERFORM pg_temp.ok('G6 role rule unchanged: EDITOR cannot register RFCs', r ->> 'status' = 'forbidden');
    s0 := pg_temp.snap();
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'XAXX010101000', 'false');
    PERFORM pg_temp.ok('G7 auto-register branch, preview: generic receptor -> rfc_generic', r ->> 'status' = 'rfc_generic' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'XEXX010101000', 'true');
    PERFORM pg_temp.ok('G8 auto-register branch, confirm: foreign receptor -> rfc_generic, nothing written', r ->> 'status' = 'rfc_generic' AND pg_temp.snap() = s0);
    r := pg_temp.reg('editor.l@example.invalid', 'TEX010101EX1', 'XAXX010101000', 'false');
    PERFORM pg_temp.ok('G9 EDITOR with a generic receptor -> rfc_not_registered (unchanged)', r ->> 'status' = 'rfc_not_registered');
    -- a generic row that already exists (legacy) keeps working and can be deactivated, never reactivated
    INSERT INTO public.company_tax_ids (id_company, rfc, created_by_email, is_active) VALUES (pg_temp.c('l')::int, 'XAXX010101000', 'seed@example.invalid', true);
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'XAXX010101000', 'false');
    PERFORM pg_temp.ok('G10 an existing generic row still receives vouchers (093 found-row path)', r ->> 'status' = 'preview' AND NOT r ? 'rfc_new');
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', 'XAXX010101000', NULL, 'false');
    PERFORM pg_temp.ok('G11 an existing generic row can be deactivated', r ->> 'status' = 'saved' AND (SELECT NOT is_active FROM public.company_tax_ids WHERE id_company = pg_temp.c('l')::int AND rfc = 'XAXX010101000'));
    r := public.sp_company_tax_id_set(pg_temp.c('l'), 'admin.l@example.invalid', 'XAXX010101000', NULL, 'true');
    PERFORM pg_temp.ok('G12 ...and never reactivated', r ->> 'status' = 'rfc_generic' AND (SELECT NOT is_active FROM public.company_tax_ids WHERE id_company = pg_temp.c('l')::int AND rfc = 'XAXX010101000'));
    ALTER TABLE public.company_tax_ids DISABLE TRIGGER USER;
    DELETE FROM public.company_tax_ids WHERE rfc = 'XAXX010101000';   -- fixture cleanup (the table is append-only for the application)
    ALTER TABLE public.company_tax_ids ENABLE TRIGGER USER;
    PERFORM pg_temp.ok('G13 classifier: an unregistered generic RFC is not own',
        public.fn_classify_cfdi_role(pg_temp.c('l')::int, 'XAXX010101000', 'XEXX010101000') = 'UNKNOWN');
END $$;

-- P. Context checks unchanged ---------------------------------------------------------------------------------------------------------------
SELECT pg_temp.expect_err('P1 palm company: still rejected (P0094)',
    format('SELECT public.sp_expense_invoice_register(%L, %L, %L, %L)', pg_temp.c('p'), 'admin.p@example.invalid', '{}', 'COMBUSTIBLE'), 'P0094');
SELECT pg_temp.expect_err('P2 not a member: still rejected (P0001)',
    format('SELECT public.sp_expense_invoice_register(%L, %L, %L, %L)', pg_temp.c('l'), 'outsider@example.invalid', '{}', 'COMBUSTIBLE'), 'P0001');
SELECT pg_temp.expect_err('P3 member of another company only: rejected (P0001)',
    format('SELECT public.sp_expense_invoice_register(%L, %L, %L, %L)', pg_temp.c('l'), 'admin.p@example.invalid', '{}', 'COMBUSTIBLE'), 'P0001');
SELECT pg_temp.ok('P4 malformed voucher still reports INVALID_INVOICE before the gate',
    public.sp_expense_invoice_register(pg_temp.c('l'), 'admin.l@example.invalid', 'not json', 'COMBUSTIBLE') ->> 'code' = 'INVALID_INVOICE');

-- C. The classifier is unavailable: fail closed ----------------------------------------------------------------------------------------------
-- (an otherwise perfect expense: own receptor, foreign issuer)
CREATE FUNCTION pg_temp.expense_refused(p_id text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s0 text := pg_temp.snap(); r jsonb; d text;
BEGIN
    d := pg_temp.draft('admin.l@example.invalid', 'TEX010101EX1', 'TLA010101LA1');
    r := pg_temp.preview('admin.l@example.invalid', d);
    PERFORM pg_temp.ok(p_id || 'a preview -> ROLE_UNAVAILABLE', r ->> 'status' = 'not_an_expense' AND r ->> 'code' = 'ROLE_UNAVAILABLE' AND pg_temp.clean(r ->> 'message'));
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'TLA010101LA1', 'true');
    PERFORM pg_temp.ok(p_id || 'b direct confirm -> ROLE_UNAVAILABLE', r ->> 'code' = 'ROLE_UNAVAILABLE');
    r := pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'TNZ010101NZ1', 'true');
    PERFORM pg_temp.ok(p_id || 'c unknown receptor also refused (no auto-register)', r ->> 'code' = 'ROLE_UNAVAILABLE');
    PERFORM pg_temp.ok(p_id || 'd nothing written, draft not consumed', pg_temp.snap() = s0 AND (SELECT consumed_at IS NULL FROM public.expense_invoice_drafts WHERE id = d::uuid));
END $$;

\ir 109_rollback.sql
SELECT pg_temp.expense_refused('C1 109 rollback stub (UNKNOWN / DISABLED): ');
\ir 109_cfdi_role_classifier.sql
SELECT pg_temp.ok('C2 109 re-applied: the expense works again', pg_temp.reg('admin.l@example.invalid', 'TEX010101EX1', 'TLA010101LA1', 'false') ->> 'status' = 'preview');

CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'classifier failure (test)'; END $$;
SELECT pg_temp.expense_refused('C3 classifier raises an exception: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT NULL::jsonb $$;
SELECT pg_temp.expense_refused('C4 classifier answers NULL: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"UNKNOWN","reason":"INVALID_INPUT"}'::jsonb $$;
SELECT pg_temp.expense_refused('C5 UNKNOWN / INVALID_INPUT: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"UNKNOWN","reason":"FORBIDDEN"}'::jsonb $$;
SELECT pg_temp.expense_refused('C6 UNKNOWN / FORBIDDEN: ');
CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"SURPRISE"}'::jsonb $$;
SELECT pg_temp.expense_refused('C7 an unknown role value: ');
\ir 109_cfdi_role_classifier.sql

-- R. Rollback, order with 109 and re-apply ------------------------------------------------------------------------------------------------------
\ir 110_rollback.sql
SELECT pg_temp.ok('R1 rollback restores the exact 093 / 091 texts', pg_temp.reg_md5() = pg_temp.c('reg_old') AND pg_temp.tax_md5() = pg_temp.c('tax_old'));
SELECT pg_temp.ok('R2 rollback: a sale is no longer refused by the gate (back to the 093 behaviour)',
    pg_temp.reg('admin.l@example.invalid', 'TLA010101LA1', 'TEX010101EX1', 'false') ->> 'status' = 'preview');
SELECT pg_temp.ok('R3 rollback keeps attributes, owner and privileges', pg_temp.attrs() = pg_temp.c('attr_before'));
\ir 110_rollback.sql
SELECT pg_temp.ok('R4 rollback is idempotent', pg_temp.reg_md5() = pg_temp.c('reg_old'));
\ir 109_rollback.sql
SAVEPOINT r1;
\echo '--- expected errors below: 110 refusing to apply over the 109 stub ---'
\set ON_ERROR_STOP off
\ir 110_expense_invoice_role_gate.sql
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT r1;
SELECT pg_temp.ok('R5 110 does not apply while 109 is the rolled-back stub', pg_temp.reg_md5() = pg_temp.c('reg_old') AND pg_temp.tax_md5() = pg_temp.c('tax_old'));
\ir 109_cfdi_role_classifier.sql
\ir 110_expense_invoice_role_gate.sql
SELECT pg_temp.ok('R6 re-apply restores the 110 texts', pg_temp.reg_md5() = pg_temp.c('reg_new') AND pg_temp.tax_md5() = pg_temp.c('tax_new'));

SELECT count(*) AS assertions_run FROM results \gset
\echo 110 TESTS: :assertions_run assertions passed (mutation=:mutation)
ROLLBACK;
