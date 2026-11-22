-- 109_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). One transaction, always rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 109_tests.sql            (run from this directory: it includes 109_cfdi_role_classifier.sql and 109_rollback.sql)
-- Optional: -v mutation=M1..M5 breaks one protection inside the transaction; the run must then FAIL (see 109_mutation_check.sh).
-- Needs 080, 091 and 104 applied. Synthetic data only: fake companies, RFCs and e-mails.
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
\ir 109_cfdi_role_classifier.sql

CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE TEMP TABLE results (n serial, ok boolean, id text) ON COMMIT DROP;
GRANT ALL ON TABLE ctx, results TO PUBLIC;

-- Assertion helpers --------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.c(k text) RETURNS integer LANGUAGE sql AS $$ SELECT v::integer FROM ctx WHERE ctx.k = $1 $$;
CREATE FUNCTION pg_temp.ok(p_id text, p_cond boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL [%]', p_id; END IF;
    INSERT INTO results (ok, id) VALUES (true, p_id);
END $$;
CREATE FUNCTION pg_temp.role(p_co integer, p_e text, p_r text) RETURNS text LANGUAGE sql AS $$ SELECT public.fn_classify_cfdi_role(p_co, p_e, p_r) $$;
CREATE FUNCTION pg_temp.det(p_co integer, p_e text, p_r text) RETURNS jsonb LANGUAGE sql AS $$ SELECT public.fn_classify_cfdi_role_detail(p_co, p_e, p_r) $$;
CREATE FUNCTION pg_temp.expect_err(p_id text, p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = p_state THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL [%] expected % got % (%)', p_id, p_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL [%] the statement succeeded', p_id;
END $$;

-- Fixtures (synthetic) ------------------------------------------------------------------------------------
-- A palm company: tax id TAA (active), issuer RFC TAB (active), tax id TAC (inactive), issuer RFC TAD (inactive), SHARED (tax id, active)
-- L livestock company: tax id TLA (active), TLB (inactive)
-- B palm company holding the same TAA RFC as tax id (same RFC, another company)
-- T palm TEST company (company_flags.is_test) with one issuer RFC; I inactive company; E livestock company with an empty set
DO $$
DECLARE ca integer; cl integer; cb integer; ct integer; ci integer; ce integer;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T109 Palm A', 'Agricultura') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T109 Cattle L', 'Ganadería') RETURNING id_company INTO cl;
    INSERT INTO public.companys (company_name, industry) VALUES ('T109 Palm B', 'Agricultura') RETURNING id_company INTO cb;
    INSERT INTO public.companys (company_name, industry) VALUES ('T109 Palm Test', 'Agricultura') RETURNING id_company INTO ct;
    INSERT INTO public.companys (company_name, industry, is_active) VALUES ('T109 Inactive', 'Ganadería', false) RETURNING id_company INTO ci;
    INSERT INTO public.companys (company_name, industry) VALUES ('T109 Cattle Empty', 'Ganadería') RETURNING id_company INTO ce;
    INSERT INTO ctx VALUES ('a', ca::text), ('l', cl::text), ('b', cb::text), ('t', ct::text), ('i', ci::text), ('e', ce::text);

    INSERT INTO public.company_tax_ids (id_company, rfc, created_by_email, is_active) VALUES
        (ca, 'TAA010101AA1', 'seed@example.invalid', true),
        (ca, 'TAC010101AC3', 'seed@example.invalid', false),
        (ca, 'TSH010101SH1', 'seed@example.invalid', true),
        (cl, 'TLA010101LA1', 'seed@example.invalid', true),
        (cl, 'TLB010101LB2', 'seed@example.invalid', false),
        (cb, 'TAA010101AA1', 'seed@example.invalid', true),
        (ci, 'TIA010101IA1', 'seed@example.invalid', true);
    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_flags (id_company, is_test) VALUES (ct, true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES
        (ca, 'TAB010101AB2'), (ca, 'TAD010101AD4'), (ct, 'TTT010101TT1');
    UPDATE public.company_issuer_rfcs SET is_active = false WHERE id_company = ca AND rfc = 'TAD010101AD4';
    PERFORM set_config('app.platform_seed', '', true);

    INSERT INTO public.users (email, names, password, role, is_active) VALUES
        ('member.a@example.invalid', 'A', 'x', 'EDITOR', true), ('member.l@example.invalid', 'L', 'x', 'ADMIN', true),
        ('member.i@example.invalid', 'I', 'x', 'ADMIN', true), ('outsider@example.invalid', 'O', 'x', 'ADMIN', true),
        ('offmember@example.invalid', 'F', 'x', 'ADMIN', true), ('offuser@example.invalid', 'U', 'x', 'ADMIN', false);
    INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES
        ('member.a@example.invalid', ca, 'EDITOR', true), ('member.l@example.invalid', cl, 'ADMIN', true),
        ('member.i@example.invalid', ci, 'ADMIN', true), ('offmember@example.invalid', ca, 'ADMIN', false),
        ('offuser@example.invalid', ca, 'ADMIN', true);
END $$;

-- Mutations (inside the transaction; the real file is never changed) ------------------------------------------
SELECT set_config('t109.mutation', :'mutation', true) AS mutation_in_use;
DO $$
DECLARE
    v_def text := pg_get_functiondef('public.fn_classify_cfdi_role_detail(integer,text,text)'::regprocedure);
    v_new text;
    v_m   text := current_setting('t109.mutation');
BEGIN
    v_new := CASE v_m
        WHEN 'none' THEN v_def
        WHEN 'M1' THEN replace(v_def, 't.id_company = p_co AND t.is_active', 'false')              -- tax ids half of the union removed
        WHEN 'M2' THEN replace(v_def, 'i.id_company = p_co AND i.is_active', 'false')              -- issuer RFCs half of the union removed
        WHEN 'M3' THEN replace(replace(v_def, 't.id_company = p_co AND t.is_active', 't.is_active'),
                               'i.id_company = p_co AND i.is_active', 'i.is_active')                -- company scope removed
        WHEN 'M4' THEN replace(replace(v_def, 't.id_company = p_co AND t.is_active', 't.id_company = p_co'),
                               'i.id_company = p_co AND i.is_active', 'i.id_company = p_co')        -- deactivated RFCs counted
        WHEN 'M5' THEN replace(v_def, 'upper(btrim(p_emisor))', 'btrim(p_emisor)')                 -- issuer not normalised
        ELSE NULL END;
    IF v_new IS NULL THEN RAISE EXCEPTION 'unknown mutation %', v_m; END IF;
    IF v_m <> 'none' AND v_new = v_def THEN RAISE EXCEPTION 'mutation % did not change the function', v_m; END IF;
    EXECUTE v_new;
END $$;

-- Table state before (for the "writes nothing" check) ------------------------------------------------------------
INSERT INTO ctx SELECT 'n_tax', count(*)::text FROM public.company_tax_ids;
INSERT INTO ctx SELECT 'n_iss', count(*)::text FROM public.company_issuer_rfcs;
INSERT INTO ctx SELECT 'h_tax', md5(string_agg(x::text, '|' ORDER BY x::text)) FROM public.company_tax_ids x;
INSERT INTO ctx SELECT 'h_iss', md5(string_agg(x::text, '|' ORDER BY x::text)) FROM public.company_issuer_rfcs x;

-- A. Truth table, palm company A -------------------------------------------------------------------------------
SELECT pg_temp.ok('A1 issuer own (tax id) -> SALE', pg_temp.role(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') = 'SALE');
SELECT pg_temp.ok('A2 issuer own (issuer rfc) -> SALE', pg_temp.role(pg_temp.c('a'), 'TAB010101AB2', 'TEX010101EX1') = 'SALE');
SELECT pg_temp.ok('A3 receptor own (tax id) -> EXPENSE', pg_temp.role(pg_temp.c('a'), 'TEX010101EX1', 'TAA010101AA1') = 'EXPENSE');
SELECT pg_temp.ok('A4 receptor own (issuer rfc) -> EXPENSE', pg_temp.role(pg_temp.c('a'), 'TEX010101EX1', 'TAB010101AB2') = 'EXPENSE');
SELECT pg_temp.ok('A5 both own, different -> AMBIGUOUS BOTH_ROLES',
    pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TAB010101AB2') @> '{"role":"AMBIGUOUS","reason":"BOTH_ROLES"}');
SELECT pg_temp.ok('A6 self invoice -> AMBIGUOUS SELF_INVOICE',
    pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TAA010101AA1') @> '{"role":"AMBIGUOUS","reason":"SELF_INVOICE"}');
SELECT pg_temp.ok('A7 neither -> UNKNOWN NEITHER',
    pg_temp.det(pg_temp.c('a'), 'TEX010101EX1', 'TEY010101EY2') @> '{"role":"UNKNOWN","reason":"NEITHER"}');
SELECT pg_temp.ok('A8 reasons of SALE / EXPENSE',
    pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') ->> 'reason' = 'ISSUER_OWN'
    AND pg_temp.det(pg_temp.c('a'), 'TEX010101EX1', 'TAA010101AA1') ->> 'reason' = 'RECEPTOR_OWN');

-- B. Truth table, livestock company L ---------------------------------------------------------------------------
SELECT pg_temp.ok('B1 livestock SALE', pg_temp.role(pg_temp.c('l'), 'TLA010101LA1', 'TEX010101EX1') = 'SALE');
SELECT pg_temp.ok('B2 livestock EXPENSE', pg_temp.role(pg_temp.c('l'), 'TEX010101EX1', 'TLA010101LA1') = 'EXPENSE');
SELECT pg_temp.ok('B3 livestock self invoice', pg_temp.det(pg_temp.c('l'), 'TLA010101LA1', 'TLA010101LA1') ->> 'reason' = 'SELF_INVOICE');
SELECT pg_temp.ok('B4 company domains',
    pg_temp.det(pg_temp.c('l'), 'TLA010101LA1', 'TEX010101EX1') ->> 'company_domain' = 'LIVESTOCK'
    AND pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') ->> 'company_domain' = 'PALM');

-- C. Deactivated RFCs: not in the set, flagged ---------------------------------------------------------------------
SELECT pg_temp.ok('C1 inactive tax id on the issuer side',
    pg_temp.det(pg_temp.c('a'), 'TAC010101AC3', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"NEITHER","emisor_inactive_match":true,"receptor_inactive_match":false}');
SELECT pg_temp.ok('C2 inactive tax id on the receptor side',
    pg_temp.det(pg_temp.c('a'), 'TEX010101EX1', 'TAC010101AC3') @> '{"role":"UNKNOWN","reason":"NEITHER","emisor_inactive_match":false,"receptor_inactive_match":true}');
SELECT pg_temp.ok('C3 inactive issuer RFC on each side',
    pg_temp.det(pg_temp.c('a'), 'TAD010101AD4', 'TEX010101EX1') @> '{"role":"UNKNOWN","emisor_inactive_match":true}'
    AND pg_temp.det(pg_temp.c('a'), 'TEX010101EX1', 'TAD010101AD4') @> '{"role":"UNKNOWN","receptor_inactive_match":true}');
SELECT pg_temp.ok('C4 an inactive RFC does not hide an active counterpart',
    pg_temp.role(pg_temp.c('a'), 'TAC010101AC3', 'TAA010101AA1') = 'EXPENSE'
    AND pg_temp.role(pg_temp.c('a'), 'TAA010101AA1', 'TAD010101AD4') = 'SALE');
SELECT pg_temp.ok('C5 livestock inactive tax id',
    pg_temp.det(pg_temp.c('l'), 'TLB010101LB2', 'TEX010101EX1') @> '{"role":"UNKNOWN","emisor_inactive_match":true}');
SELECT pg_temp.ok('C6 flags false for plain external RFCs',
    pg_temp.det(pg_temp.c('a'), 'TEX010101EX1', 'TEY010101EY2') @> '{"emisor_inactive_match":false,"receptor_inactive_match":false,"own_set_empty":false}');

-- D. Tenant isolation -------------------------------------------------------------------------------------------------
SELECT pg_temp.ok('D1 company A RFC never classifies for company L',
    pg_temp.role(pg_temp.c('l'), 'TAA010101AA1', 'TEX010101EX1') = 'UNKNOWN'
    AND pg_temp.role(pg_temp.c('l'), 'TEX010101EX1', 'TAB010101AB2') = 'UNKNOWN');
SELECT pg_temp.ok('D2 company L RFC never classifies for company A',
    pg_temp.role(pg_temp.c('a'), 'TLA010101LA1', 'TEX010101EX1') = 'UNKNOWN');
SELECT pg_temp.ok('D3 same RFC in two companies: each one decides alone',
    pg_temp.role(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') = 'SALE'
    AND pg_temp.role(pg_temp.c('b'), 'TAA010101AA1', 'TEX010101EX1') = 'SALE'
    AND pg_temp.role(pg_temp.c('a'), 'TAB010101AB2', 'TAA010101AA1') = 'AMBIGUOUS'
    AND pg_temp.role(pg_temp.c('b'), 'TAB010101AB2', 'TAA010101AA1') = 'EXPENSE');
SELECT pg_temp.ok('D4 same RFC, different roles per company',
    pg_temp.role(pg_temp.c('a'), 'TSH010101SH1', 'TLA010101LA1') = 'SALE'
    AND pg_temp.role(pg_temp.c('l'), 'TSH010101SH1', 'TLA010101LA1') = 'EXPENSE');
SELECT pg_temp.ok('D5 company B has no issuer RFC of company A',
    pg_temp.role(pg_temp.c('b'), 'TAB010101AB2', 'TEX010101EX1') = 'UNKNOWN');
SELECT pg_temp.ok('D6 empty own set is reported',
    pg_temp.det(pg_temp.c('e'), 'TAA010101AA1', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"NEITHER","own_set_empty":true}');

-- E. Test company vs real company ---------------------------------------------------------------------------------------
SELECT pg_temp.ok('E1 test company classifies like a real one',
    pg_temp.role(pg_temp.c('t'), 'TTT010101TT1', 'TEX010101EX1') = 'SALE'
    AND pg_temp.role(pg_temp.c('t'), 'TEX010101EX1', 'TTT010101TT1') = 'EXPENSE');
SELECT pg_temp.ok('E2 test company RFC does not classify for a real company',
    pg_temp.role(pg_temp.c('a'), 'TTT010101TT1', 'TEX010101EX1') = 'UNKNOWN');

-- F. Input handling -----------------------------------------------------------------------------------------------------
SELECT pg_temp.ok('F1 null company', pg_temp.det(NULL, 'TAA010101AA1', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"INVALID_INPUT"}');
SELECT pg_temp.ok('F2 non-existent company', pg_temp.det(2147483000, 'TAA010101AA1', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"INVALID_INPUT"}');
SELECT pg_temp.ok('F3 inactive company', pg_temp.det(pg_temp.c('i'), 'TIA010101IA1', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"INVALID_INPUT"}');
SELECT pg_temp.ok('F4 null / blank RFC',
    pg_temp.det(pg_temp.c('a'), NULL, 'TAA010101AA1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', NULL) ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), '', 'TAA010101AA1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), '   ', '  ') ->> 'reason' = 'INVALID_INPUT');
SELECT pg_temp.ok('F5 malformed RFC',
    pg_temp.det(pg_temp.c('a'), 'TAA0101AA1', 'TEX010101EX1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TEX01010EX1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), 'TAA010101AA1-', 'TEX010101EX1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), 'TAA 010101AA1', 'TEX010101EX1') ->> 'reason' = 'INVALID_INPUT'
    AND pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', '12345678901234') ->> 'reason' = 'INVALID_INPUT');
SELECT pg_temp.ok('F6 lowercase with spaces is normalised',
    pg_temp.role(pg_temp.c('a'), '  taa010101aa1 ', ' tex010101ex1') = 'SALE'
    AND pg_temp.role(pg_temp.c('a'), ' tex010101ex1 ', '  TAB010101AB2  ') = 'EXPENSE'
    AND pg_temp.role(pg_temp.c('a'), ' taa010101aa1', 'TAA010101AA1') = 'AMBIGUOUS');
SELECT pg_temp.ok('F7 detail never carries an RFC value and has a fixed key set',
    pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1')::text !~ 'TAA010101AA1|TEX010101EX1'
    AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(pg_temp.det(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1')) k)
        = ARRAY['company_domain','emisor_inactive_match','own_set_empty','reason','receptor_inactive_match','role']);
SELECT pg_temp.ok('F8 companys.metadata is not read',
    (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_classify_cfdi_role_detail','fn_classify_cfdi_role','sp_cfdi_classify')
        AND prosrc ~* 'metadata') = 0);

-- G. sp_cfdi_classify: membership, fail-closed -----------------------------------------------------------------------------
SELECT pg_temp.ok('G1 member of palm company',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') @> '{"role":"SALE","company_domain":"PALM"}');
SELECT pg_temp.ok('G2 member of livestock company; e-mail case and spaces ignored',
    public.sp_cfdi_classify(' ' || pg_temp.c('l')::text, ' MEMBER.L@example.invalid ', 'TEX010101EX1', 'TLA010101LA1') @> '{"role":"EXPENSE","company_domain":"LIVESTOCK"}');
SELECT pg_temp.ok('G3 non-member -> FORBIDDEN',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'outsider@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G4 member of another company -> FORBIDDEN',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'member.l@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G5 inactive membership / inactive user -> FORBIDDEN',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'offmember@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify(pg_temp.c('a')::text, 'offuser@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G6 inactive company -> FORBIDDEN even for a member',
    public.sp_cfdi_classify(pg_temp.c('i')::text, 'member.i@example.invalid', 'TIA010101IA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G7 ambiguous tenant -> FORBIDDEN',
    public.sp_cfdi_classify(NULL, 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify('', 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify('1,2', 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify('1 OR 1=1', 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify('99999999999999', 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G8 null / blank e-mail -> FORBIDDEN',
    public.sp_cfdi_classify(pg_temp.c('a')::text, NULL, 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}'
    AND public.sp_cfdi_classify(pg_temp.c('a')::text, '  ', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"FORBIDDEN"}');
SELECT pg_temp.ok('G9 member, invalid RFC -> INVALID_INPUT',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'member.a@example.invalid', 'nope', 'TEX010101EX1') @> '{"role":"UNKNOWN","reason":"INVALID_INPUT"}');
SELECT pg_temp.ok('G10 the FORBIDDEN answer carries only role and reason',
    (SELECT count(*) FROM jsonb_object_keys(public.sp_cfdi_classify(pg_temp.c('a')::text, 'outsider@example.invalid', 'TAA010101AA1', 'TEX010101EX1'))) = 2);

-- H. Writes nothing ----------------------------------------------------------------------------------------------------------
SELECT pg_temp.ok('H1 the three functions are STABLE (a write would raise)',
    (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_classify_cfdi_role_detail','fn_classify_cfdi_role','sp_cfdi_classify') AND provolatile = 's') = 3);
SELECT pg_temp.ok('H2 both RFC tables unchanged after all the calls (counts and content)',
    (SELECT count(*) FROM public.company_tax_ids) = pg_temp.c('n_tax')
    AND (SELECT count(*) FROM public.company_issuer_rfcs) = pg_temp.c('n_iss')
    AND (SELECT md5(string_agg(x::text, '|' ORDER BY x::text)) FROM public.company_tax_ids x) = (SELECT v FROM ctx WHERE k = 'h_tax')
    AND (SELECT md5(string_agg(x::text, '|' ORDER BY x::text)) FROM public.company_issuer_rfcs x) = (SELECT v FROM ctx WHERE k = 'h_iss'));

-- I. Privileges and gateway isolation ------------------------------------------------------------------------------------------
SELECT pg_temp.ok('I1 PUBLIC cannot execute any of the three',
    NOT has_function_privilege('public', 'public.fn_classify_cfdi_role_detail(integer,text,text)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'public.fn_classify_cfdi_role(integer,text,text)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE'));
SELECT pg_temp.ok('I2 the workflow role (superuser, like 099 / 102) can execute sp_cfdi_classify',
    has_function_privilege(current_user, 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE'));
CREATE ROLE t109_plain NOLOGIN;
CREATE ROLE t109_workflow NOLOGIN;
GRANT EXECUTE ON FUNCTION public.sp_cfdi_classify(text, text, text, text) TO t109_workflow;
GRANT USAGE ON SCHEMA public TO t109_plain, t109_workflow;
SET LOCAL ROLE t109_plain;
SELECT pg_temp.expect_err('I3 plain role: detail denied', 'SELECT public.fn_classify_cfdi_role_detail(1, ''TAA010101AA1'', ''TEX010101EX1'')', '42501');
SELECT pg_temp.expect_err('I4 plain role: role denied', 'SELECT public.fn_classify_cfdi_role(1, ''TAA010101AA1'', ''TEX010101EX1'')', '42501');
SELECT pg_temp.expect_err('I5 plain role: sp denied', 'SELECT public.sp_cfdi_classify(''1'', ''x@example.invalid'', ''TAA010101AA1'', ''TEX010101EX1'')', '42501');
RESET ROLE;
SET LOCAL ROLE t109_workflow;
SELECT pg_temp.expect_err('I6 workflow-only role: fn detail still denied', 'SELECT public.fn_classify_cfdi_role_detail(1, ''TAA010101AA1'', ''TEX010101EX1'')', '42501');
SELECT pg_temp.expect_err('I6b workflow-only role: RFC table read denied', 'SELECT count(*) FROM public.company_tax_ids', '42501');
SELECT public.sp_cfdi_classify(v::text, 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') ->> 'role' AS wf_role FROM ctx WHERE k = 'a' \gset
RESET ROLE;
SELECT pg_temp.ok('I7 workflow-only role: sp works (SECURITY DEFINER)', :'wf_role' = 'SALE');
SELECT pg_temp.ok('I8 no classifier function is registered in crud_models',
    (SELECT count(*) FROM public.crud_models WHERE table_name ~* 'classify|cfdi_role' OR model_name ~* 'classify|cfdi_role') = 0);

-- J. Rollback stub and re-apply -------------------------------------------------------------------------------------------------
\ir 109_rollback.sql
SELECT pg_temp.ok('J1 rollback stub: fail-closed DISABLED, signatures kept',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') = '{"role":"UNKNOWN","reason":"DISABLED"}'
    AND public.fn_classify_cfdi_role_detail(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') ->> 'reason' = 'DISABLED'
    AND public.fn_classify_cfdi_role(pg_temp.c('a'), 'TAA010101AA1', 'TEX010101EX1') = 'UNKNOWN');
SELECT pg_temp.ok('J2 rollback keeps the privileges closed',
    NOT has_function_privilege('public', 'public.fn_classify_cfdi_role_detail(integer,text,text)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'public.fn_classify_cfdi_role(integer,text,text)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE'));
\ir 109_cfdi_role_classifier.sql
SELECT pg_temp.ok('J3 re-apply restores the classifier',
    public.sp_cfdi_classify(pg_temp.c('a')::text, 'member.a@example.invalid', 'TAA010101AA1', 'TEX010101EX1') ->> 'role' = 'SALE');

SELECT count(*) AS assertions_run FROM results \gset
\echo 109 TESTS: :assertions_run assertions passed (mutation=:mutation)
ROLLBACK;
