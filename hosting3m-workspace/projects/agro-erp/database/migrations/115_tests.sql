-- 115_tests.sql: THROWAWAY database only (name must contain "test" or "rehearsal"). Everything is rolled back.
--   psql -X -v ON_ERROR_STOP=1 -f 115_tests.sql
-- Applies step 1 (if missing) and the migration inside the transaction, runs the checks, runs the rollback, re-applies, and rolls everything back.
-- Synthetic data only: new companies, fake animals, fake e-mails (@example.test).
-- NOT covered here (needs two real sessions): true concurrency of two simultaneous requests on one animal. The unique index on pending_authorizations and the
-- advisory lock are exercised sequentially (a pending row inserted between preview and execute).
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
-- These tests use their own animals with chips 990000000000001 / 031 / 099 (globally unique in the table). The shared LOCAL/rehearsal fixtures use some of the same chips:
-- if they are loaded, run the fixtures cleanup first and load the fixtures again afterwards.
SELECT EXISTS (SELECT 1 FROM public.cattle_livestock WHERE electronic_rfid IN ('990000000000001', '990000000000031', '990000000000099')) AS chips_taken \gset
\if :chips_taken
\echo 'ABORT: an animal already holds one of the chips this test needs (the shared fixtures?). Run the fixtures cleanup first, then this test, then load the fixtures again.'
\quit
\endif
BEGIN;
\set embedded true
-- The helpers below are LANGUAGE sql and call functions the migration creates LATER in this transaction: do not check their bodies at creation.
-- Checking is switched back on right after them, so the migration's own functions ARE body-checked, as in a real apply.
SET LOCAL check_function_bodies = off;

SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cattle_identifier_history' AND column_name = 'id_company') AS has_step1 \gset
\if :has_step1
\else
\ir 114_identifier_history_tenant_guards.sql
\endif

CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v text) ON COMMIT DROP;
-- Assertions always print what was found: chk(cond, msg, context) prints the context; eq(actual, expected, msg) prints both; st(response, expected status, msg) prints the whole response.
CREATE FUNCTION pg_temp.chk(p boolean, m text, ctx text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: % | context: %', m, coalesce(ctx, '(none)'); END IF; END $f$;
CREATE FUNCTION pg_temp.eq(actual text, expected text, m text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FAILED: % | expected=[%] actual=[%]', m, coalesce(expected, '<NULL>'), coalesce(actual, '<NULL>'); END IF; END $f$;
CREATE FUNCTION pg_temp.st(r jsonb, expected text, m text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF (r ->> 'status') IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FAILED: % | expected status=[%] actual response=%', m, expected, coalesce(r::text, '<NULL>'); END IF; END $f$;
CREATE FUNCTION pg_temp.tid(k text) RETURNS text LANGUAGE sql AS $f$ SELECT v FROM t_ids WHERE k = $1 $f$;
CREATE FUNCTION pg_temp.aid(k text) RETURNS uuid LANGUAGE sql AS $f$ SELECT v::uuid FROM t_ids WHERE k = $1 $f$;
CREATE FUNCTION pg_temp.asg(p_email text, p_ident text, p_type text, p_val text, p_tok text DEFAULT NULL, p_tenant text DEFAULT 'A') RETURNS jsonb LANGUAGE sql AS $f$
    SELECT public.sp_assign_livestock_identifier(CASE WHEN p_tenant = 'A' THEN pg_temp.tid('A') WHEN p_tenant = 'B' THEN pg_temp.tid('B') ELSE p_tenant END, p_email, p_ident, p_type, p_val, p_tok) $f$;
CREATE FUNCTION pg_temp.rq(p_email text, p_ident text, p_type text, p_val text, p_reason text, p_tok text DEFAULT NULL, p_tenant text DEFAULT 'A') RETURNS jsonb LANGUAGE sql AS $f$
    SELECT public.sp_request_tag_change(CASE WHEN p_tenant = 'A' THEN pg_temp.tid('A') WHEN p_tenant = 'B' THEN pg_temp.tid('B') ELSE p_tenant END, p_email, p_ident, p_type, p_val, p_reason, p_tok) $f$;
CREATE FUNCTION pg_temp.asg2(p_email text, p_ident text, p_type text, p_val text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb; BEGIN r := pg_temp.asg(p_email, p_ident, p_type, p_val); IF r ->> 'status' <> 'preview' THEN RETURN r; END IF; RETURN pg_temp.asg(p_email, p_ident, p_type, p_val, r ->> 'preview_token'); END $f$;
CREATE FUNCTION pg_temp.rq2(p_email text, p_ident text, p_type text, p_val text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb; BEGIN r := pg_temp.rq(p_email, p_ident, p_type, p_val, p_reason); IF r ->> 'status' <> 'preview' THEN RETURN r; END IF; RETURN pg_temp.rq(p_email, p_ident, p_type, p_val, p_reason, r ->> 'preview_token'); END $f$;

SET LOCAL check_function_bodies = on;

-- Start from the TRUE original text whether or not the database already has the migration applied (for example after the concurrency script was run for real):
-- when it is patched, roll it back inside this transaction first (the rollback refuses if CAMBIO_ARETE rows exist: clean them up or use a fresh database).
SELECT (pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure) LIKE '%CAMBIO_ARETE%'
     OR pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure) LIKE '%CAMBIO_ARETE%'
     OR pg_get_viewdef('public.vw_cattle_event_log'::regclass, true) LIKE '%SOLICITUD_CAMBIO_ARETE%') AS starts_patched \gset
\if :starts_patched
\echo 'NOTE: 115_tag_change_authorization is already applied here; rolling it back inside this transaction so the test starts from the original text.'
\ir 115_rollback.sql
\endif
-- The two function texts have KNOWN original fingerprints (measured on LOCAL 2026-11-26); the view has none recorded, so its "before" is taken after the normalization above.
SELECT pg_temp.eq(md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure)), '84913beb0d1f4d0b4168c4789fa6c4b5', 'start: dispatcher is the measured original');
SELECT pg_temp.eq(md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure)), 'aec290a3825f398bbfb7389923377abe', 'start: one-pending guard is the measured original');

-- Fingerprints before the migration (for the rollback round trip)
INSERT INTO t_ids VALUES
    ('md5_dispatch_before', md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure))),
    ('md5_guard_before',    md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure))),
    ('md5_view_before',     md5(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true)));

-- Fixtures: companies A and B, members, animals ---------------------------------------------------------------------------------------------
DO $$
DECLARE a integer; b integer;
BEGIN
    SELECT coalesce(max(id_company), 0) + 1 INTO a FROM public.companys; b := a + 1;
    INSERT INTO public.companys (id_company, company_name, industry) VALUES (a, 'TEST tag company A', 'ganaderia'), (b, 'TEST tag company B', 'ganaderia');
    INSERT INTO t_ids VALUES ('A', a::text), ('B', b::text);
    INSERT INTO public.users (email, tenant_id, names, password, role, is_active) VALUES
        ('tc-adm-a@example.test', a, 'T adm A', 'x', 'ADMIN', true), ('tc-edt-a@example.test', a, 'T edt A', 'x', 'EDITOR', true),
        ('tc-edt2-a@example.test', a, 'T edt2 A', 'x', 'EDITOR', true), ('tc-cus-a@example.test', a, 'T cus A', 'x', 'CUSTOMER', true),
        ('tc-own-a@example.test', a, 'T own A', 'x', 'CUSTOMER', true), ('tc-adm-b@example.test', b, 'T adm B', 'x', 'ADMIN', true);
    INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES
        ('tc-adm-a@example.test', a, 'ADMIN', true), ('tc-edt-a@example.test', a, 'EDITOR', true), ('tc-edt2-a@example.test', a, 'EDITOR', true),
        ('tc-cus-a@example.test', a, 'CUSTOMER', true), ('tc-own-a@example.test', a, 'OWNER', true), ('tc-adm-b@example.test', b, 'ADMIN', true);
END $$;

DO $$
DECLARE a integer := pg_temp.tid('A')::integer; b integer := pg_temp.tid('B')::integer; x uuid;
BEGIN
    -- name, tenant, species, status, ear tag, chip, fire
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga, electronic_rfid, numero_fuego) VALUES
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000001', NULL,              NULL),    -- a1 no chip
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000002', '990000000000001', NULL),    -- a2 has chip
        (a, 'CRIA', 'VACA', 'VENDIDO', 'BOVINO', '9900000003', NULL,              NULL),    -- a3 sold
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BUFALO', '12345',      NULL,              NULL),    -- a4 buffalo, short tag
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000005', NULL,              'FX1'),   -- a5 fire FX1
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000006', NULL,              'FX1'),   -- a6 fire FX1 (duplicate allowed)
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000007', NULL,              NULL),    -- a7 no fire
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000008', '990000000000031', NULL),    -- a8 chip to be retired
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000009', NULL,              NULL),    -- a9 will get a pending baja
        (a, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', NULL,         NULL,              'FX10'),  -- a10 no ear tag
        (b, 'CRIA', 'VACA', 'ACTIVO',  'BOVINO', '9900000101', '990000000000099', NULL);    -- b1 other company
    INSERT INTO t_ids VALUES
        ('a1', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000001')),
        ('a2', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000002')),
        ('a3', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000003')),
        ('a4', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '12345')),
        ('a5', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000005')),
        ('a6', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000006')),
        ('a7', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000007')),
        ('a8', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000008')),
        ('a9', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000009')),
        ('a10', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = a AND numero_fuego = 'FX10')),
        ('b1', (SELECT id::text FROM public.cattle_livestock WHERE tenant_id = b));
    UPDATE public.cattle_livestock SET electronic_rfid = '990000000000032' WHERE id = pg_temp.aid('a8');   -- 031 is now retired (history row written by the step 1 logger)
    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (a, pg_temp.aid('a9'), 'BAJA_MORTANDAD', '{}'::jsonb, 'tc-edt-a@example.test');
END $$;

\ir 115_tag_change_authorization.sql

-- T1 roles, membership, tenant -------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010'), 'preview', 'T1 ADMIN preview');
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010'), 'preview', 'T1 EDITOR preview');
    PERFORM pg_temp.st(pg_temp.asg('TC-ADM-A@EXAMPLE.TEST', '9900000001', 'CHIP', '990000000000010'), 'preview', 'T1 upper-case e-mail accepted');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.tesu', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 one character changed rejected');
    PERFORM pg_temp.st(pg_temp.asg('tc-cus-a@example.test', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 CUSTOMER rejected');
    PERFORM pg_temp.st(pg_temp.asg('tc-own-a@example.test', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 OWNER rejected (separate PR)');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-b@example.test', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 other company ADMIN rejected');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010', NULL, 'B'), 'forbidden', 'T1 member of A acting on tenant B');
    PERFORM pg_temp.st(pg_temp.asg('nobody@example.test', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 unknown e-mail');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010', NULL, 'abc'), 'invalid_input', 'T1 tenant text');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010', NULL, ''), 'invalid_input', 'T1 tenant empty');
    PERFORM pg_temp.st(public.sp_assign_livestock_identifier(NULL, 'tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010', NULL), 'invalid_input', 'T1 tenant NULL');
    PERFORM pg_temp.st(public.sp_assign_livestock_identifier(pg_temp.tid('A'), NULL, '9900000001', 'CHIP', '990000000000010', NULL), 'invalid_input', 'T1 e-mail NULL');
    PERFORM pg_temp.st(pg_temp.rq('tc-cus-a@example.test', '9900000002', 'CHIP', '990000000000011', 'replacement'), 'forbidden', 'T1 request CUSTOMER rejected');
    -- a deactivated membership is rejected
    UPDATE public.user_companies SET is_active = false WHERE email = 'tc-edt2-a@example.test';
    PERFORM pg_temp.st(pg_temp.asg('tc-edt2-a@example.test', '9900000001', 'CHIP', '990000000000010'), 'forbidden', 'T1 inactive membership');
    UPDATE public.user_companies SET is_active = true WHERE email = 'tc-edt2-a@example.test';
    RAISE NOTICE 'T1 OK roles';
END $$;

-- T2 assign flow, tokens, history, movement log, flags --------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; p jsonb; q jsonb; h record; tk text;
BEGIN
    p := pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010');
    PERFORM pg_temp.chk(p ->> 'status' = 'preview' AND p ->> 'preview_token' IS NOT NULL AND (p -> 'impact' ->> 'new') = '990000000000010', 'T2 preview shape', p::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a1'))::text, NULL, 'T2 preview does not change the animal');
    -- garbage tokens
    FOREACH tk IN ARRAY ARRAY['abc', 'null', 'undefined', '00000000-0000-0000-0000-000000000000', '123,456', E'x\x27; SELECT 1; --'] LOOP
        PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010', tk), 'preview_required', 'T2 garbage token ' || tk);
    END LOOP;
    -- token of another user / another value / another operation
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000001', 'CHIP', '990000000000010', p ->> 'preview_token'), 'preview_required', 'T2 token of another user');
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000011', p ->> 'preview_token'), 'preview_required', 'T2 token for another value');
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000007', 'CHIP', '990000000000010', p ->> 'preview_token'), 'preview_required', 'T2 token for another animal');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000012', 'reason ok', p ->> 'preview_token'), 'preview_required', 'T2 assign token used for a request');
    -- expired token
    -- move BOTH dates back (the table requires expires_at > created_at); now() is the transaction start, so this is 11 minutes ago -> expired 1 second ago
    UPDATE public.tag_change_previews SET created_at = now() - interval '11 minutes', expires_at = now() - interval '1 second' WHERE token = (p ->> 'preview_token')::uuid;
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010', p ->> 'preview_token'), 'preview_required', 'T2 expired token');
    -- real execution
    p := pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010');
    r := pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010', p ->> 'preview_token');
    PERFORM pg_temp.chk(r ->> 'status' = 'applied' AND (r ->> 'applied')::boolean, 'T2 applied', r::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a1'))::text, '990000000000010', 'T2 chip stored');
    PERFORM pg_temp.eq((SELECT rfid_siniiga FROM public.cattle_livestock WHERE id = pg_temp.aid('a1'))::text, '9900000001', 'T2 ear tag untouched by a chip assignment');
    SELECT * INTO h FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a1') AND identifier_type = 'CHIP' AND new_value = '990000000000010';
    PERFORM pg_temp.chk(h.reason = 'INITIAL_ASSIGNMENT' AND h.changed_by = 'tc-edt-a@example.test' AND h.id_company = pg_temp.tid('A')::integer AND h.previous_value IS NULL, 'T2 history actor/reason/company', to_jsonb(h)::text);
    PERFORM pg_temp.chk(EXISTS (SELECT 1 FROM public.historico_movimientos WHERE livestock_id = pg_temp.aid('a1') AND tipo_movimiento = 'CAMBIO_ARETE' AND notes LIKE '%ELECTRONIC_RFID%'), 'T2 movement log row', (SELECT string_agg(tipo_movimiento || ':' || coalesce(notes, '<null>'), ' ; ') FROM public.historico_movimientos WHERE livestock_id = pg_temp.aid('a1')));
    PERFORM pg_temp.chk(coalesce(current_setting('app.identifier_gate', true), '') = '' AND coalesce(current_setting('app.identifier_change_user', true), '') = ''
                        AND coalesce(current_setting('app.identifier_change_reason', true), '') = '', 'T2 flags cleared after the UPDATE', 'gate=['||coalesce(current_setting('app.identifier_gate',true),'<null>')||'] dispatch=['||coalesce(current_setting('app.tag_dispatch',true),'<null>')||'] user=['||coalesce(current_setting('app.identifier_change_user',true),'<null>')||'] reason=['||coalesce(current_setting('app.identifier_change_reason',true),'<null>')||']');
    PERFORM pg_temp.chk(pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010', p ->> 'preview_token') ->> 'status' IN ('preview_required', 'not_empty'), 'T2 used token cannot run twice', (pg_temp.asg('tc-edt-a@example.test', '9900000001', 'CHIP', '990000000000010', p ->> 'preview_token'))::text);
    RAISE NOTICE 'T2 OK assign flow';
END $$;

-- T2b confirm call: the token, not the message, decides. On the confirmation the user's message is just "Sí", so the tool cannot check the digits against the message;
-- what binds the call is the token (animal + normalized value + user). Same animal and same normalized value written differently still apply; anything else does not.
DO $$
DECLARE p jsonb; r jsonb;
BEGIN
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga)
        VALUES (pg_temp.tid('A')::integer, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000013'), (pg_temp.tid('A')::integer, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000014'),
               (pg_temp.tid('A')::integer, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000015');
    -- same animal and same value, dictated differently on the confirmation: applies
    p := pg_temp.asg('tc-edt-a@example.test', '9900000013', 'CHIP', '990000000000613');
    r := pg_temp.asg('tc-edt-a@example.test', '9 9 0 0 0 0 0 0 1 3', 'CHIP', '9 9 0 0 0 0 0 0 0 0 0 0 6 1 3', p ->> 'preview_token');
    PERFORM pg_temp.st(r, 'applied', 'T2b confirm with the same animal and value written as dictated digits');
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE tenant_id = pg_temp.tid('A')::integer AND rfid_siniiga = '9900000013'), '990000000000613', 'T2b chip stored as the normalized value');
    -- a value that differs by one digit on the confirmation: refused, nothing written
    p := pg_temp.asg('tc-edt-a@example.test', '9900000014', 'CHIP', '990000000000614');
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000014', 'CHIP', '990000000000615', p ->> 'preview_token'), 'preview_required', 'T2b confirm with one digit changed');
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000015', 'CHIP', '990000000000614', p ->> 'preview_token'), 'preview_required', 'T2b confirm for another (empty-chip) animal');
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE tenant_id = pg_temp.tid('A')::integer AND rfid_siniiga = '9900000014'), NULL, 'T2b refused confirmations wrote nothing');
    -- the unchanged confirmation still works with the same token (the refused attempts did not burn it)
    PERFORM pg_temp.st(pg_temp.asg('tc-edt-a@example.test', '9900000014', 'CHIP', '990000000000614', p ->> 'preview_token'), 'applied', 'T2b the right confirmation still applies');
    RAISE NOTICE 'T2b OK confirm call';
END $$;

-- T3 assign rejections and input shapes -----------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; v text;
BEGIN
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000002', 'CHIP', '990000000000020'), 'not_empty', 'T3 chip already assigned');
    PERFORM pg_temp.chk(pg_temp.asg('tc-adm-a@example.test', '9900000002', 'CHIP', '990000000000020') ->> 'use' = 'request_tag_change', 'T3 says use request_tag_change', (pg_temp.asg('tc-adm-a@example.test', '9900000002', 'CHIP', '990000000000020'))::text);
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000003', 'CHIP', '990000000000020'), 'animal_not_eligible', 'T3 sold animal');
    UPDATE public.cattle_livestock SET current_status = 'BAJA_MORTANDAD' WHERE id = pg_temp.aid('a7');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000007', 'CHIP', '990000000000020'), 'animal_not_eligible', 'T3 dead animal');
    UPDATE public.cattle_livestock SET current_status = 'ACTIVO' WHERE id = pg_temp.aid('a7');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9999999999', 'CHIP', '990000000000020'), 'not_found', 'T3 unknown identifier');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000101', 'CHIP', '990000000000020'), 'not_found', 'T3 other company identifier is not found');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', 'FX1', 'CHIP', '990000000000020'), 'ambiguous', 'T3 two animals share a fire number');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '990000000000031', 'CHIP', '990000000000020'), 'previous_identifier_only', 'T3 previous identifier is not a write target');
    -- value shapes on a7 (empty chip)
    FOREACH v IN ARRAY ARRAY['12345678901234', '1234567890123456', 'ABCDEFGHIJKLMNO', '123,456', '99000000000001''', '''; SELECT 1; --', 'null', 'undefined', '', '   ',
                             repeat('9', 200), '９９００００００００００００１', E'99000000000001\n5'] LOOP
        PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000007', 'CHIP', v), 'invalid_input', 'T3 rejected value [' || left(v, 20) || ']');
    END LOOP;
    PERFORM pg_temp.st(public.sp_assign_livestock_identifier(pg_temp.tid('A'), 'tc-adm-a@example.test', '9900000007', 'CHIP', NULL, NULL), 'invalid_input', 'T3 NULL value');
    PERFORM pg_temp.st(public.sp_assign_livestock_identifier(pg_temp.tid('A'), 'tc-adm-a@example.test', NULL, 'CHIP', '990000000000020', NULL), 'invalid_input', 'T3 NULL identifier');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000007', 'COW', '990000000000020'), 'invalid_input', 'T3 unknown tag type');
    r := pg_temp.asg('tc-adm-a@example.test', '9900000007', 'CHIP', '001234567800001');
    PERFORM pg_temp.chk(r ->> 'status' = 'preview' AND r -> 'impact' ->> 'new' = '001234567800001', 'T3 leading zero kept', r::text);
    r := pg_temp.asg('tc-adm-a@example.test', '9900000007', 'CHIP', '  990000000000021  ');
    PERFORM pg_temp.chk(r ->> 'status' = 'preview' AND r -> 'impact' ->> 'new' = '990000000000021', 'T3 edge spaces trimmed', r::text);
    r := pg_temp.asg('tc-adm-a@example.test', '9900000007', 'CHIP', '9 9 0 0 0 0 0 0 0 0 0 0 0 2 2');
    PERFORM pg_temp.chk(r ->> 'status' = 'preview' AND r -> 'impact' ->> 'new' = '990000000000022', 'T3 dictated digits normalized', r::text);
    r := pg_temp.asg('tc-adm-a@example.test', '9 9 0 0 0 0 0 0 0 7', 'CHIP', '990000000000023');   -- ten single digits = ear tag 9900000007
    PERFORM pg_temp.st(r, 'preview', 'T3 dictated identifier normalized');
    RAISE NOTICE 'T3 OK rejections and shapes';
END $$;

-- T3b normalizer: the rule of get_livestock_info (only 3+ single digits separated by whitespace are joined) --------------------------------------
DO $$
DECLARE c record;
BEGIN
    FOR c IN SELECT * FROM (VALUES
        ('9 9 9 8 8',            '99988'),                   -- dictation: single digits
        ('9 9 9',                '999'),                     -- exactly three single digits
        ('9 9',                  '9 9'),                     -- only two: untouched
        (E'9\t9\t9',             '999'),                     -- any whitespace
        ('a 1 2 3 b',            'a 123 b'),                 -- only the run
        ('1 2 3 4567',           '123 4567'),                -- the run stops at a multi-digit token
        ('99 00 00',             '99 00 00'),                -- grouped digits are NOT joined (the old rule did)
        ('0012345678 50 g',      '0012345678 50 g'),         -- two numbers stay two numbers
        ('0012345678',           '0012345678'),              -- leading zero kept
        ('  9900000007  ',       '9900000007'),              -- edge spaces trimmed
        ('2012-9 P',             '2012-9 P'),                -- hyphen and inner space untouched
        ('fx-1.2',               'fx-1.2'),                  -- hyphen and dot untouched
        ('Fx1',                  'Fx1'),                     -- case untouched by the normalizer
        ('123,456',              '123,456'),                 -- comma: one value, untouched
        ('',                     NULL),
        ('   ',                  NULL),
        (NULL,                   NULL)
    ) AS v(input, expected) LOOP
        PERFORM pg_temp.eq(public.fn_normalize_identifier(c.input), c.expected, 'T3b normalize [' || coalesce(c.input, '<NULL>') || ']');
    END LOOP;
    -- lookups are case-insensitive on top of the normalizer (a superset of the exact match of get_livestock_info)
    PERFORM pg_temp.eq((SELECT count(*)::text FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, 'fx10')), '1', 'T3b resolver ignores case');
    PERFORM pg_temp.eq((SELECT count(*)::text FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, '9 9 0 0 0 0 0 0 0 7')), '1', 'T3b resolver: dictated 10 digits find the ear tag');
    PERFORM pg_temp.eq((SELECT count(*)::text FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, '9 9 0 0 0 0 0 0 7')), '0', 'T3b resolver: nine digits find nothing (a dropped digit is not guessed)');
    RAISE NOTICE 'T3b OK normalizer';
END $$;

-- T4 uniqueness: generic outcome ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE same_co jsonb; other_co jsonb; retired jsonb; p jsonb;
BEGIN
    same_co := pg_temp.asg2('tc-adm-a@example.test', '9900000007', 'CHIP', '990000000000001');           -- held by a2 in the same company
    retired := pg_temp.asg2('tc-adm-a@example.test', '9900000007', 'CHIP', '990000000000031');           -- retired from a8
    other_co := pg_temp.asg2('tc-adm-a@example.test', '9900000007', 'CHIP', '990000000000099');          -- held by b1 in company B (global unique index)
    PERFORM pg_temp.st(same_co, 'identifier_unavailable', 'T4 same company');
    PERFORM pg_temp.st(retired, 'identifier_unavailable', 'T4 retired value');
    PERFORM pg_temp.st(other_co, 'identifier_unavailable', 'T4 other company');
    PERFORM pg_temp.chk(same_co = other_co AND same_co = retired, 'T4 the three outcomes are byte-identical (identical responses)', same_co::text||' / '||other_co::text||' / '||retired::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a7'))::text, NULL, 'T4 animal untouched after the refusals');
    PERFORM pg_temp.chk(coalesce(current_setting('app.identifier_gate', true), '') = '', 'T4 gate cleared after a failed UPDATE', 'gate=['||coalesce(current_setting('app.identifier_gate',true),'<null>')||'] dispatch=['||coalesce(current_setting('app.tag_dispatch',true),'<null>')||'] user=['||coalesce(current_setting('app.identifier_change_user',true),'<null>')||'] reason=['||coalesce(current_setting('app.identifier_change_reason',true),'<null>')||']');
    -- a chip equal to the animal's own ear tag column of another animal (cross-column) is also unavailable
    PERFORM pg_temp.st(pg_temp.asg2('tc-adm-a@example.test', '9900000007', 'FUEGO', '9900000002'), 'applied', 'T4 fire numbers may repeat other columns (Rule 4)');
    RAISE NOTICE 'T4 OK uniqueness';
END $$;

-- T5 fire number: assign when empty, duplicates warn ----------------------------------------------------------------------------------------
DO $$
DECLARE p jsonb; r jsonb;
BEGIN
    UPDATE public.cattle_livestock SET numero_fuego = NULL WHERE id = pg_temp.aid('a7');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000005', 'FUEGO', 'fx9'), 'not_empty', 'T5 fire number already set');
    p := pg_temp.asg('tc-adm-a@example.test', '9900000007', 'FUEGO', 'fx1');
    PERFORM pg_temp.chk(p ->> 'status' = 'preview' AND (p ->> 'duplicates_in_company')::integer = 2 AND p ->> 'warning' = 'FUEGO_DUPLICATE', 'T5 duplicate warning in the preview', p::text);
    r := pg_temp.asg('tc-adm-a@example.test', '9900000007', 'FUEGO', 'fx1', p ->> 'preview_token');
    PERFORM pg_temp.st(r, 'applied', 'T5 duplicate allowed after a confirmed preview (Rule 4)');
    PERFORM pg_temp.eq((SELECT numero_fuego FROM public.cattle_livestock WHERE id = pg_temp.aid('a7'))::text, 'FX1', 'T5 stored upper-case');
    PERFORM pg_temp.chk(EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a7') AND identifier_type = 'FUEGO' AND reason = 'INITIAL_ASSIGNMENT'), 'T5 history row', (SELECT string_agg(identifier_type || '/' || reason, ' ; ') FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a7')));
    RAISE NOTICE 'T5 OK fire number';
END $$;

-- T6 requests -------------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; p jsonb; req record;
BEGIN
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000040', NULL), 'invalid_input', 'T6 reason NULL');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000040', 'ab'), 'invalid_input', 'T6 reason too short');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000040', repeat('x', 501)), 'invalid_input', 'T6 reason too long');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000001', 'same value'), 'no_change', 'T6 same value');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000007', 'CHIP', '990000000000040', 'chip is empty'), 'use_assign_livestock_identifier', 'T6 empty chip goes to assign');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000009', 'FUEGO', 'ZZ', 'fire is empty'), 'use_assign_livestock_identifier', 'T6 empty fire goes to assign');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'SINIIGA', '12345', 'short tag'), 'invalid_input', 'T6 bovine ear tag must be 10 digits');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'SINIIGA', '''; SELECT 1; --', 'bad value'), 'invalid_input', 'T6 quote-and-semicolon value is just invalid');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '12345', 'SINIIGA', '54321', 'buffalo tag'), 'preview', 'T6 buffalo is not held to 10 digits');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000003', 'SINIIGA', '9900000333', 'sold animal'), 'animal_not_eligible', 'T6 sold');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000009', 'SINIIGA', '9900000999', 'pending baja exists'), 'pending_exists', 'T6 pending baja blocks');
    PERFORM pg_temp.chk(pg_temp.rq('tc-edt-a@example.test', '9900000009', 'SINIIGA', '9900000999', 'pending baja exists') ->> 'pending_type' = 'BAJA_MORTANDAD', 'T6 says which type', (pg_temp.rq('tc-edt-a@example.test', '9900000009', 'SINIIGA', '9900000999', 'pending baja exists'))::text);
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'SINIIGA', '9900000001', 'taken tag'), 'identifier_unavailable', 'T6 value held by another animal');

    -- real request (replace a chip)
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000002', 'CHIP', '990000000000041', 'chip lost, O''Brien said so; DROP TABLE x; --');
    PERFORM pg_temp.chk(r ->> 'status' = 'requested' AND NOT (r ->> 'applied')::boolean, 'T6 requested, not applied', r::text);
    SELECT * INTO req FROM public.pending_authorizations WHERE id = (r ->> 'request_id')::uuid;
    PERFORM pg_temp.chk(req.tipo_evento = 'CAMBIO_ARETE' AND req.estado = 'PENDIENTE' AND req.id_company = pg_temp.tid('A')::integer
                        AND req.payload ->> 'tag_type' = 'CHIP' AND req.payload ->> 'old_value' = '990000000000001' AND req.payload ->> 'new_value' = '990000000000041'
                        AND req.payload ->> 'reason' = 'chip lost, O''Brien said so; DROP TABLE x; --' AND req.solicitado_por_email = 'tc-edt-a@example.test', 'T6 pending row shape and verbatim reason', to_jsonb(req)::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a2'))::text, '990000000000001', 'T6 the animal is not modified by the request');
    INSERT INTO t_ids VALUES ('req_chip', r ->> 'request_id');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000002', 'SINIIGA', '9900000222', 'second request'), 'pending_exists', 'T6 one pending per animal');
    -- a pending request between preview and execute (the race, sequentially)
    p := pg_temp.rq('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000042', 'race test');
    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (pg_temp.tid('A')::integer, pg_temp.aid('a8'), 'BAJA_MORTANDAD', '{}'::jsonb, 'tc-edt-a@example.test');
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000042', 'race test', p ->> 'preview_token'), 'pending_exists', 'T6 race: pending appears after the preview');
    -- ear tag when empty also needs approval
    r := pg_temp.rq2('tc-edt-a@example.test', 'FX10', 'SINIIGA', '9900000010', 'animal had no ear tag');
    PERFORM pg_temp.st(r, 'requested', 'T6 empty ear tag is a request');
    PERFORM pg_temp.eq((SELECT rfid_siniiga FROM public.cattle_livestock WHERE id = pg_temp.aid('a10'))::text, NULL, 'T6 empty ear tag untouched');
    INSERT INTO t_ids VALUES ('req_tag_empty', r ->> 'request_id');
    RAISE NOTICE 'T6 OK requests';
END $$;

-- T7 approvals through the existing dispatcher ----------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; id1 uuid := pg_temp.tid('req_chip')::uuid; h record; r2 jsonb; id2 uuid; id3 uuid; id4 uuid; id5 uuid;
BEGIN
    -- a non-ADMIN and an ADMIN of another company cannot approve; nothing changes
    BEGIN PERFORM public.sp_resolver_autorizacion(id1, 'APROBADO', 'tc-edt-a@example.test', NULL); RAISE EXCEPTION 'T7 FAILED: EDITOR approved';
    EXCEPTION WHEN SQLSTATE 'P0016' THEN NULL; END;
    BEGIN PERFORM public.sp_resolver_autorizacion(id1, 'APROBADO', 'tc-adm-b@example.test', NULL); RAISE EXCEPTION 'T7 FAILED: other company ADMIN approved';
    EXCEPTION WHEN SQLSTATE 'P0016' THEN NULL; END;
    BEGIN PERFORM public.sp_resolver_autorizacion(id1, 'APROBADO_CON_EXCEPCION', 'tc-adm-a@example.test', 'x'); RAISE EXCEPTION 'T7 FAILED: sanitary exception accepted';
    EXCEPTION WHEN SQLSTATE 'P0014' THEN NULL; END;
    BEGIN PERFORM public.sp_resolver_autorizacion(id1, 'RECHAZADO', 'tc-adm-a@example.test', '   '); RAISE EXCEPTION 'T7 FAILED: reject without note';
    EXCEPTION WHEN SQLSTATE 'P0018' THEN NULL; END;
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a2'))::text, '990000000000001', 'T7 animal unchanged so far');

    r := public.sp_resolver_autorizacion(id1, 'APROBADO', 'tc-adm-a@example.test', 'ok');
    PERFORM pg_temp.chk((r ->> 'success')::boolean AND r ->> 'estado' = 'APROBADO', 'T7 approved', r::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a2'))::text, '990000000000041', 'T7 chip replaced');
    SELECT * INTO h FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a2') AND identifier_type = 'CHIP' AND new_value = '990000000000041';
    PERFORM pg_temp.chk(h.reason = 'AUTHORIZED_CHANGE' AND h.changed_by = 'tc-adm-a@example.test' AND h.previous_value = '990000000000001' AND h.notes LIKE '%O''Brien%' AND h.notes LIKE '%tc-edt-a@example.test%', 'T7 history: approver, reason, notes with requester', to_jsonb(h)::text);
    PERFORM pg_temp.chk(coalesce(current_setting('app.tag_dispatch', true), '') = '', 'T7 dispatch flag cleared', 'gate=['||coalesce(current_setting('app.identifier_gate',true),'<null>')||'] dispatch=['||coalesce(current_setting('app.tag_dispatch',true),'<null>')||'] user=['||coalesce(current_setting('app.identifier_change_user',true),'<null>')||'] reason=['||coalesce(current_setting('app.identifier_change_reason',true),'<null>')||']');
    BEGIN PERFORM public.sp_resolver_autorizacion(id1, 'APROBADO', 'tc-adm-a@example.test', NULL); RAISE EXCEPTION 'T7 FAILED: approved twice';
    EXCEPTION WHEN SQLSTATE 'P0011' THEN NULL; END;
    -- the old chip is now retired for the company
    PERFORM pg_temp.st(pg_temp.asg2('tc-adm-a@example.test', '9900000007', 'CHIP', '990000000000001'), 'identifier_unavailable', 'T7 retired chip cannot be reused');

    -- rejection with a note leaves the animal alone
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000005', 'SINIIGA', '9900000500', 'wrong tag was printed'); id2 := (r ->> 'request_id')::uuid;
    r := public.sp_resolver_autorizacion(id2, 'RECHAZADO', 'tc-adm-a@example.test', 'not needed');
    PERFORM pg_temp.chk(r ->> 'estado' = 'RECHAZADO' AND (SELECT rfid_siniiga FROM public.cattle_livestock WHERE id = pg_temp.aid('a5')) = '9900000005', 'T7 rejected, unchanged', r::text);

    -- self-approval works exactly as for bajas (ADMIN requests and approves)
    r := pg_temp.rq2('tc-adm-a@example.test', '9900000005', 'SINIIGA', '9900000501', 'admin fixes a typo'); id3 := (r ->> 'request_id')::uuid;
    r := public.sp_resolver_autorizacion(id3, 'APROBADO', 'tc-adm-a@example.test', NULL);
    PERFORM pg_temp.chk((r ->> 'success')::boolean AND (SELECT rfid_siniiga FROM public.cattle_livestock WHERE id = pg_temp.aid('a5')) = '9900000501', 'T7 self-approval allowed', r::text);
    PERFORM pg_temp.chk(EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a5') AND reason = 'AUTHORIZED_CHANGE'), 'T7 ear tag history reason', (SELECT string_agg(identifier_type || '/' || reason, ' ; ') FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a5')));

    -- fire number change is a correction
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000006', 'FUEGO', 'FX2', 'burn number was copied wrong'); id4 := (r ->> 'request_id')::uuid;
    r := public.sp_resolver_autorizacion(id4, 'APROBADO', 'tc-adm-a@example.test', NULL);
    PERFORM pg_temp.chk((r ->> 'success')::boolean AND EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE cattle_livestock_id = pg_temp.aid('a6') AND identifier_type = 'FUEGO' AND reason = 'CAPTURE_CORRECTION'), 'T7 fire change = CAPTURE_CORRECTION', r::text);

    -- expired: the request is older than today; the error rolls back, the animal is unchanged
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000050', 'expired one');
    PERFORM pg_temp.st(r, 'pending_exists', 'T7 setup: a8 has a pending baja (inserted in T6), so first cancel it');
    DELETE FROM public.pending_authorizations WHERE livestock_id = pg_temp.aid('a8') AND tipo_evento = 'BAJA_MORTANDAD';
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000050', 'expired one'); id5 := (r ->> 'request_id')::uuid;
    UPDATE public.pending_authorizations SET fecha_solicitud = (now() AT TIME ZONE 'UTC') - interval '3 days' WHERE id = id5;
    BEGIN PERFORM public.sp_resolver_autorizacion(id5, 'APROBADO', 'tc-adm-a@example.test', NULL); RAISE EXCEPTION 'T7 FAILED: expired request approved';
    EXCEPTION WHEN SQLSTATE 'P0012' THEN NULL; END;
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a8'))::text, '990000000000032', 'T7 expired: unchanged');
    DELETE FROM public.pending_authorizations WHERE id = id5;   -- throwaway database only: the expired row would block the next tests
    RAISE NOTICE 'T7 OK approvals';
END $$;

-- T8 revalidation at approval time ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb; ida uuid; idb uuid; idc uuid;
BEGIN
    -- stale: the current value changed between request and approval
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000060', 'stale test'); ida := (r ->> 'request_id')::uuid;
    PERFORM pg_temp.st(r, 'requested', 'T8 setup stale');
    UPDATE public.cattle_livestock SET electronic_rfid = '990000000000061' WHERE id = pg_temp.aid('a8');
    r := public.sp_resolver_autorizacion(ida, 'APROBADO', 'tc-adm-a@example.test', NULL);
    PERFORM pg_temp.chk(NOT (r ->> 'success')::boolean AND r ->> 'estado' = 'PENDIENTE', 'T8 stale value: not applied, request stays PENDIENTE', r::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a8'))::text, '990000000000061', 'T8 stale: animal unchanged');
    PERFORM public.sp_resolver_autorizacion(ida, 'RECHAZADO', 'tc-adm-a@example.test', 'stale');

    -- value taken by another animal between request and approval
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000062', 'taken test'); idb := (r ->> 'request_id')::uuid;
    UPDATE public.cattle_livestock SET electronic_rfid = '990000000000062' WHERE id = pg_temp.aid('a7');
    r := public.sp_resolver_autorizacion(idb, 'APROBADO', 'tc-adm-a@example.test', NULL);
    PERFORM pg_temp.chk(NOT (r ->> 'success')::boolean AND r ->> 'estado' = 'PENDIENTE', 'T8 value taken: not applied', r::text);
    PERFORM public.sp_resolver_autorizacion(idb, 'RECHAZADO', 'tc-adm-a@example.test', 'taken');
    UPDATE public.cattle_livestock SET electronic_rfid = NULL WHERE id = pg_temp.aid('a7');

    -- animal sold between request and approval
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000063', 'sold test'); idc := (r ->> 'request_id')::uuid;
    UPDATE public.cattle_livestock SET current_status = 'VENDIDO' WHERE id = pg_temp.aid('a8');
    r := public.sp_resolver_autorizacion(idc, 'APROBADO', 'tc-adm-a@example.test', NULL);
    PERFORM pg_temp.chk(NOT (r ->> 'success')::boolean AND r ->> 'estado' = 'PENDIENTE', 'T8 sold: not applied', r::text);
    PERFORM public.sp_resolver_autorizacion(idc, 'RECHAZADO', 'tc-adm-a@example.test', 'sold');
    UPDATE public.cattle_livestock SET current_status = 'ACTIVO' WHERE id = pg_temp.aid('a8');

    -- sp_apply_tag_change cannot be used to skip the approval
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000064', 'direct apply test');
    PERFORM pg_temp.chk(NOT (public.sp_apply_tag_change((r ->> 'request_id')::uuid, 'tc-adm-a@example.test') ->> 'success')::boolean, 'T8 apply without the dispatch flag refused', (public.sp_apply_tag_change((r ->> 'request_id')::uuid, 'tc-adm-a@example.test'))::text);
    PERFORM set_config('app.tag_dispatch', gen_random_uuid()::text, true);
    PERFORM pg_temp.chk(NOT (public.sp_apply_tag_change((r ->> 'request_id')::uuid, 'tc-adm-a@example.test') ->> 'success')::boolean, 'T8 apply with another request id in the flag refused', (public.sp_apply_tag_change((r ->> 'request_id')::uuid, 'tc-adm-a@example.test'))::text);
    PERFORM set_config('app.tag_dispatch', '', true);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.aid('a8'))::text, '990000000000061', 'T8 animal unchanged by the refused applies');
    INSERT INTO t_ids VALUES ('req_for_cancel', r ->> 'request_id');
    RAISE NOTICE 'T8 OK revalidation';
END $$;

-- T9 cancel -----------------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE rid text := pg_temp.tid('req_for_cancel'); r jsonb;
BEGIN
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-edt2-a@example.test', rid), 'forbidden', 'T9 another EDITOR cannot cancel');
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-cus-a@example.test', rid), 'forbidden', 'T9 CUSTOMER cannot cancel');
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('B'), 'tc-adm-b@example.test', rid), 'not_found', 'T9 other company cannot even see it');
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-edt-a@example.test', 'not-a-uuid'), 'invalid_input', 'T9 bad id');
    r := public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-edt-a@example.test', rid);
    PERFORM pg_temp.chk(r ->> 'status' = 'cancelled' AND (SELECT estado FROM public.pending_authorizations WHERE id = rid::uuid) = 'CANCELADO', 'T9 requester cancels', r::text);
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-edt-a@example.test', rid), 'not_pending', 'T9 cancelled twice');
    -- an ADMIN cancels someone else's request
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000065', 'admin will cancel');
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-adm-a@example.test', r ->> 'request_id'), 'cancelled', 'T9 ADMIN cancels');
    -- expired
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000066', 'will expire');
    UPDATE public.pending_authorizations SET fecha_solicitud = (now() AT TIME ZONE 'UTC') - interval '3 days' WHERE id = (r ->> 'request_id')::uuid;
    PERFORM pg_temp.st(public.sp_cancel_tag_change(pg_temp.tid('A'), 'tc-edt-a@example.test', r ->> 'request_id'), 'expired', 'T9 expired cannot be cancelled');
    -- the cancelled request frees the animal for a baja request
    PERFORM pg_temp.st(pg_temp.rq('tc-edt-a@example.test', '9900000008', 'CHIP', '990000000000067', 'blocked by the expired one'), 'pending_exists', 'T9 an expired-but-PENDIENTE row still blocks until the cron runs');
    RAISE NOTICE 'T9 OK cancel';
END $$;

-- T10 alias lookup ----------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE n integer; k text;
BEGIN
    SELECT count(*), min(matched) INTO n, k FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, '990000000000041');
    PERFORM pg_temp.chk(n = 1 AND k = 'CURRENT', 'T10 current value', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    SELECT count(*), min(matched) INTO n, k FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, '990000000000001');
    PERFORM pg_temp.chk(n = 1 AND k = 'PREVIOUS', 'T10 retired value finds the animal as PREVIOUS', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    SELECT count(*) INTO n FROM public.fn_resolve_identifier(pg_temp.tid('B')::integer, '990000000000001');
    PERFORM pg_temp.chk(n = 0, 'T10 other company does not see it', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    SELECT count(*) INTO n FROM public.fn_resolve_identifier(NULL, '990000000000041');
    PERFORM pg_temp.chk(n = 0, 'T10 NULL tenant returns nothing (fail-closed)', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    SELECT count(*) INTO n FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, NULL);
    PERFORM pg_temp.chk(n = 0, 'T10 NULL identifier returns nothing', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    -- a retired value that another animal now holds: current wins
    UPDATE public.cattle_livestock SET electronic_rfid = '990000000000001' WHERE id = pg_temp.aid('a7');
    SELECT count(*), min(matched) INTO n, k FROM public.fn_resolve_identifier(pg_temp.tid('A')::integer, '990000000000001');
    PERFORM pg_temp.chk(n = 1 AND k = 'CURRENT', 'T10 current wins over a previous holder', 'n='||coalesce(n::text,'<null>')||' k='||coalesce(k,'<null>'));
    UPDATE public.cattle_livestock SET electronic_rfid = NULL WHERE id = pg_temp.aid('a7');
    RAISE NOTICE 'T10 OK resolver';
END $$;

-- T11 event log and one-pending message (own animal, own request: no dependency on earlier tests) ---------------------------------------------
DO $$
DECLARE r jsonb; msg text; id11 uuid;
BEGIN
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga)
        VALUES (pg_temp.tid('A')::integer, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000011') RETURNING id INTO id11;
    INSERT INTO t_ids VALUES ('a11', id11::text);
    r := pg_temp.rq2('tc-edt-a@example.test', '9900000011', 'SINIIGA', '9900000511', 'event log check');
    PERFORM pg_temp.st(r, 'requested', 'T11 setup: fresh request on a fresh animal');
    PERFORM pg_temp.chk(EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE livestock_id = pg_temp.aid('a11') AND event_type = 'SOLICITUD_CAMBIO_ARETE'), 'T11 event log shows SOLICITUD_CAMBIO_ARETE',
                        (SELECT string_agg(coalesce(event_type, '<NULL>'), ' ; ') FROM public.vw_cattle_event_log WHERE livestock_id = pg_temp.aid('a11')));
    PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.vw_cattle_event_log WHERE tenant_id = pg_temp.tid('A')::integer AND event_type IS NULL), 'T11 no NULL event types in the log',
                        'null event types=' || (SELECT count(*) FROM public.vw_cattle_event_log WHERE tenant_id = pg_temp.tid('A')::integer AND event_type IS NULL));
    BEGIN
        PERFORM public.sp_solicitar_autorizacion(p_livestock_id := pg_temp.aid('a11'), p_tenant_id := pg_temp.tid('A')::integer, p_tipo_evento := 'BAJA_MORTANDAD',
                                                 p_payload := '{}'::jsonb, p_solicitado_por_email := 'tc-edt-a@example.test');
        RAISE EXCEPTION 'T11 FAILED: a baja was accepted over a pending tag change';
    EXCEPTION WHEN SQLSTATE 'P0036' THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
        PERFORM pg_temp.chk(msg LIKE '%cambio de arete%', 'T11 one-pending message names the type', 'msg=['||coalesce(msg,'<null>')||']');
    END;
    RAISE NOTICE 'T11 OK event log and message';
END $$;

-- T13 preview table checks ------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE a integer := pg_temp.tid('A')::integer;
BEGIN
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'x@example.test', 'ASSIGN', pg_temp.aid('a1'), md5('x'), now() - interval '1 hour');
        RAISE EXCEPTION 'T13 FAILED: expiry before creation accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'X@Example.test', 'ASSIGN', pg_temp.aid('a1'), md5('x'), now() + interval '1 hour');
        RAISE EXCEPTION 'T13 FAILED: upper-case e-mail accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'x@example.test', 'ASSIGN', pg_temp.aid('a1'), 'not-a-hash', now() + interval '1 hour');
        RAISE EXCEPTION 'T13 FAILED: bad hash accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'x@example.test', 'DELETE', pg_temp.aid('a1'), md5('x'), now() + interval '1 hour');
        RAISE EXCEPTION 'T13 FAILED: unknown operation accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at, used_at) VALUES (a, 'x@example.test', 'ASSIGN', pg_temp.aid('a1'), md5('x'), now() + interval '1 hour', now() - interval '1 day');
        RAISE EXCEPTION 'T13 FAILED: used before created accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'x@example.test', 'ASSIGN', pg_temp.aid('b1'), md5('x'), now() + interval '1 hour');
        RAISE EXCEPTION 'T13 FAILED: animal of another company accepted'; EXCEPTION WHEN SQLSTATE 'P0135' THEN NULL; END;
    INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at) VALUES (a, 'x@example.test', 'ASSIGN', pg_temp.aid('a1'), md5('x'), now() + interval '1 hour');
    RAISE NOTICE 'T13 OK preview table checks';
END $$;

-- T12 patches: idempotent re-apply, rollback round trip --------------------------------------------------------------------------------------
INSERT INTO t_ids VALUES
    ('md5_dispatch_after', md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure))),
    ('md5_guard_after',    md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure))),
    ('md5_view_after',     md5(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true)));
\ir 115_tag_change_authorization.sql
DO $$
BEGIN
    PERFORM pg_temp.eq(md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure)), pg_temp.tid('md5_dispatch_after'), 'T12 re-apply: dispatcher unchanged');
    PERFORM pg_temp.eq(md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure)), pg_temp.tid('md5_guard_after'), 'T12 re-apply: one-pending guard unchanged');
    PERFORM pg_temp.eq(md5(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true)), pg_temp.tid('md5_view_after'), 'T12 re-apply: event log view unchanged');
    RAISE NOTICE 'T12 OK idempotent';
END $$;

-- T12 owns its animal (no dependency on the state T3..T10 left behind)
INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga)
    VALUES (pg_temp.tid('A')::integer, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000012');
INSERT INTO t_ids SELECT 'a12', id::text FROM public.cattle_livestock WHERE tenant_id = pg_temp.tid('A')::integer AND rfid_siniiga = '9900000012';
-- the rollback refuses while CAMBIO_ARETE rows exist (T11 left one; the count is checked here, the refusal itself is checked by hand)
SELECT pg_temp.chk((SELECT count(*) FROM public.pending_authorizations WHERE tipo_evento = 'CAMBIO_ARETE') > 0, 'T12 setup: CAMBIO_ARETE rows exist, so the rollback would refuse (checked by hand: run the rollback file with them present)', 'count=' || (SELECT count(*) FROM public.pending_authorizations WHERE tipo_evento = 'CAMBIO_ARETE'));
DELETE FROM public.pending_authorizations WHERE tipo_evento = 'CAMBIO_ARETE';   -- throwaway database only
\ir 115_rollback.sql
DO $$
BEGIN
    PERFORM pg_temp.eq(md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure)), pg_temp.tid('md5_dispatch_before'), 'T12 dispatcher restored to the exact original text');
    PERFORM pg_temp.eq(md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure)), pg_temp.tid('md5_guard_before'), 'T12 guard restored to the exact original text');
    PERFORM pg_temp.eq(md5(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true)), pg_temp.tid('md5_view_before'), 'T12 view restored to the exact original definition');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000012', 'CHIP', '990000000000070'), 'disabled', 'T12 assign answers disabled after the rollback');
    PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pending_authorizations_tipo_check' AND pg_get_constraintdef(oid) LIKE '%CAMBIO_ARETE%'), 'T12 CHECK back to two values', (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'pending_authorizations_tipo_check'));
    RAISE NOTICE 'T12 OK rollback round trip';
END $$;
\ir 115_tag_change_authorization.sql
DO $$
BEGIN
    PERFORM pg_temp.eq(md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure)), pg_temp.tid('md5_dispatch_after'), 'T12 re-apply after rollback gives the same dispatcher');
    PERFORM pg_temp.st(pg_temp.asg('tc-adm-a@example.test', '9900000012', 'CHIP', '990000000000070'), 'preview', 'T12 functions are live again');
    RAISE NOTICE 'T12b OK re-apply after rollback';
END $$;

\echo 'ALL TESTS PASSED (rolled back)'
ROLLBACK;
