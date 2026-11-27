-- 116_tests.sql: THROWAWAY database only (name must contain "test" or "rehearsal"). Everything is rolled back.
--   psql -X -v ON_ERROR_STOP=1 -f 116_tests.sql
-- Applies step 1 and PR 2a inside the transaction when they are missing, then the guard, runs the checks, the rollback, and re-applies.
-- Synthetic data only. Pending requests are inserted directly (this file tests the wrapper, not the request functions).
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true

SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cattle_identifier_history' AND column_name = 'id_company') AS has_step1 \gset
\if :has_step1
\else
\ir 114_identifier_history_tenant_guards.sql
\endif
SELECT to_regprocedure('public.sp_apply_tag_change(uuid,text)') IS NOT NULL AS has_2a \gset
\if :has_2a
\else
\ir 115_tag_change_authorization.sql
\endif

CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.chk(p boolean, m text, ctx text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: % | context: %', m, coalesce(ctx, '(none)'); END IF; END $f$;
CREATE FUNCTION pg_temp.eq(actual text, expected text, m text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FAILED: % | expected=[%] actual=[%]', m, coalesce(expected, '<NULL>'), coalesce(actual, '<NULL>'); END IF; END $f$;
CREATE FUNCTION pg_temp.tid(k text) RETURNS text LANGUAGE sql AS $f$ SELECT v FROM t_ids WHERE k = $1 $f$;

-- Start from the TRUE original wrapper whether or not the guard is already applied in this database: roll it back inside this transaction first.
SELECT pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure) LIKE '%chat-guard-cambio-arete%' AS guard_applied \gset
\if :guard_applied
\echo 'NOTE: the chat guard is already applied here; rolling it back inside this transaction so the test starts from the original text.'
\ir 116_rollback.sql
\endif
SELECT pg_temp.eq(md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)), '69721334b082bdf3aa1f70a362e3440c', 'start: the wrapper is the measured original (md5 69721334...)');
INSERT INTO t_ids VALUES ('md5_before', md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)));

-- Fixtures: two companies, an ADMIN and an EDITOR in A, four animals, one pending request each --------------------------------------------------
DO $$
DECLARE a integer; b integer; a1 uuid; a2 uuid; a3 uuid; p uuid;
BEGIN
    SELECT coalesce(max(id_company), 0) + 1 INTO a FROM public.companys; b := a + 1;
    INSERT INTO public.companys (id_company, company_name, industry) VALUES (a, 'TEST guard company A', 'ganaderia'), (b, 'TEST guard company B', 'ganaderia');
    INSERT INTO t_ids VALUES ('A', a::text), ('B', b::text);
    INSERT INTO public.users (email, tenant_id, names, password, role, is_active) VALUES
        ('tg-adm@example.test', a, 'G adm', 'x', 'ADMIN', true), ('tg-edt@example.test', a, 'G edt', 'x', 'EDITOR', true);
    INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES ('tg-adm@example.test', a, 'ADMIN', true), ('tg-edt@example.test', a, 'EDITOR', true);
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga, electronic_rfid) VALUES
        (a, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000701', '990000000000701'),
        (a, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000702', '990000000000702'),
        (a, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', '9900000703', NULL);
    INSERT INTO t_ids SELECT 'a1', id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000701';
    INSERT INTO t_ids SELECT 'a2', id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000702';
    INSERT INTO t_ids SELECT 'a3', id::text FROM public.cattle_livestock WHERE tenant_id = a AND rfid_siniiga = '9900000703';
    -- p1: tag change on a1 (chat refusals, then a rejection); p2: tag change on a2 (approved by the web-panel path); p3: a baja on a3 (must still go through the wrapper)
    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (a, pg_temp.tid('a1')::uuid, 'CAMBIO_ARETE', jsonb_build_object('tag_type', 'CHIP', 'old_value', '990000000000701', 'new_value', '990000000000711', 'reason', 'guard test'), 'tg-edt@example.test')
        RETURNING id INTO p;
    INSERT INTO t_ids VALUES ('p1', p::text);
    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (a, pg_temp.tid('a2')::uuid, 'CAMBIO_ARETE', jsonb_build_object('tag_type', 'CHIP', 'old_value', '990000000000702', 'new_value', '990000000000712', 'reason', 'panel path'), 'tg-edt@example.test')
        RETURNING id INTO p;
    INSERT INTO t_ids VALUES ('p2', p::text);
    INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (a, pg_temp.tid('a3')::uuid, 'BAJA_MORTANDAD', '{}'::jsonb, 'tg-edt@example.test') RETURNING id INTO p;
    INSERT INTO t_ids VALUES ('p3', p::text);
END $$;

\ir 116_tag_change_chat_guard.sql

-- T1 the chat wrapper refuses every approval of a tag change (ADMIN, EDITOR, any spelling, NULL) ------------------------------------------------------
DO $$
DECLARE dec text; who text;
BEGIN
    FOREACH who IN ARRAY ARRAY['tg-adm@example.test', 'tg-edt@example.test'] LOOP
        FOREACH dec IN ARRAY ARRAY['APROBADO', 'APROBADO_CON_EXCEPCION', 'aprobado', 'x', ''] LOOP
            BEGIN
                PERFORM public.sp_review_pending_request(pg_temp.tid('p1')::uuid, pg_temp.tid('A')::integer, dec, who, 'note');
                RAISE EXCEPTION 'FAILED: T1 % approved a tag change with decision [%]', who, dec;
            EXCEPTION WHEN SQLSTATE 'P0136' THEN NULL; END;
        END LOOP;
        BEGIN
            PERFORM public.sp_review_pending_request(pg_temp.tid('p1')::uuid, pg_temp.tid('A')::integer, NULL, who, 'note');
            RAISE EXCEPTION 'FAILED: T1 % passed with a NULL decision', who;
        EXCEPTION WHEN SQLSTATE 'P0136' THEN NULL; END;
    END LOOP;
    PERFORM pg_temp.eq((SELECT estado FROM public.pending_authorizations WHERE id = pg_temp.tid('p1')::uuid), 'PENDIENTE', 'T1 the request is still PENDIENTE');
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.tid('a1')::uuid), '990000000000701', 'T1 the animal is unchanged');
    RAISE NOTICE 'T1 OK approvals refused from chat';
END $$;

-- T2 rejection from chat still works (with a note) -------------------------------------------------------------------------------------------------
DO $$
DECLARE r jsonb;
BEGIN
    BEGIN
        PERFORM public.sp_review_pending_request(pg_temp.tid('p1')::uuid, pg_temp.tid('A')::integer, 'RECHAZADO', 'tg-adm@example.test', '   ');
        RAISE EXCEPTION 'FAILED: T2 rejected without a note';
    EXCEPTION WHEN SQLSTATE 'P0018' THEN NULL; END;
    BEGIN
        PERFORM public.sp_review_pending_request(pg_temp.tid('p1')::uuid, pg_temp.tid('A')::integer, 'RECHAZADO', 'tg-edt@example.test', 'not my call');
        RAISE EXCEPTION 'FAILED: T2 an EDITOR rejected';
    EXCEPTION WHEN SQLSTATE 'P0016' THEN NULL; END;
    r := public.sp_review_pending_request(pg_temp.tid('p1')::uuid, pg_temp.tid('A')::integer, 'RECHAZADO', 'tg-adm@example.test', 'not needed');
    PERFORM pg_temp.eq(r ->> 'estado', 'RECHAZADO', 'T2 ADMIN rejects a tag change from chat');
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.tid('a1')::uuid), '990000000000701', 'T2 rejected: animal unchanged');
    RAISE NOTICE 'T2 OK rejection from chat';
END $$;

-- T3 the guard sits AFTER the tenant check and does not touch other request types -----------------------------------------------------------------------
DO $$
DECLARE r jsonb;
BEGIN
    BEGIN
        PERFORM public.sp_review_pending_request(pg_temp.tid('p2')::uuid, pg_temp.tid('B')::integer, 'APROBADO', 'tg-adm@example.test', NULL);
        RAISE EXCEPTION 'FAILED: T3 wrong tenant accepted';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL; END;
    BEGIN
        PERFORM public.sp_review_pending_request(gen_random_uuid(), pg_temp.tid('A')::integer, 'APROBADO', 'tg-adm@example.test', NULL);
        RAISE EXCEPTION 'FAILED: T3 unknown request accepted';
    EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL; END;
    -- a baja reaches the resolver (its own P0016 for a non-ADMIN proves the guard did not intercept it) and can be rejected normally
    BEGIN
        PERFORM public.sp_review_pending_request(pg_temp.tid('p3')::uuid, pg_temp.tid('A')::integer, 'APROBADO', 'tg-edt@example.test', NULL);
        RAISE EXCEPTION 'FAILED: T3 an EDITOR approved a baja';
    EXCEPTION WHEN SQLSTATE 'P0016' THEN NULL; END;
    r := public.sp_review_pending_request(pg_temp.tid('p3')::uuid, pg_temp.tid('A')::integer, 'RECHAZADO', 'tg-adm@example.test', 'baja rejected in test');
    PERFORM pg_temp.eq(r ->> 'estado', 'RECHAZADO', 'T3 a baja is still resolved through the wrapper');
    RAISE NOTICE 'T3 OK scope of the guard';
END $$;

-- T4 the web-panel path (sp_resolver_autorizacion directly) still approves a tag change -----------------------------------------------------------------
DO $$
DECLARE r jsonb;
BEGIN
    r := public.sp_resolver_autorizacion(pg_temp.tid('p2')::uuid, 'APROBADO', 'tg-adm@example.test', 'ok');
    PERFORM pg_temp.chk((r ->> 'success')::boolean AND r ->> 'estado' = 'APROBADO', 'T4 the panel path approves', r::text);
    PERFORM pg_temp.eq((SELECT electronic_rfid FROM public.cattle_livestock WHERE id = pg_temp.tid('a2')::uuid), '990000000000712', 'T4 the chip changed');
    RAISE NOTICE 'T4 OK panel path';
END $$;

-- T5 idempotent re-apply and rollback round trip -------------------------------------------------------------------------------------------------------
INSERT INTO t_ids VALUES ('md5_after', md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)));
\ir 116_tag_change_chat_guard.sql
SELECT pg_temp.eq(md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)), pg_temp.tid('md5_after'), 'T5 re-apply changes nothing');
\ir 116_rollback.sql
SELECT pg_temp.eq(md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)), pg_temp.tid('md5_before'), 'T5 rollback restores the exact original text');
\ir 116_tag_change_chat_guard.sql
SELECT pg_temp.eq(md5(pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure)), pg_temp.tid('md5_after'), 'T5 re-apply after rollback gives the same text');

\echo 'ALL TESTS PASSED (rolled back)'
ROLLBACK;
