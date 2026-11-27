-- 114_tests.sql: THROWAWAY database only (name must contain "test" or "rehearsal"). Everything is rolled back.
--   psql -X -v ON_ERROR_STOP=1 -f 114_tests.sql
-- Applies the migration inside the transaction (embedded), runs the checks, runs the rollback, re-applies, and rolls everything back.
-- Synthetic data only: new companies, fake animals, fake e-mails (@example.test). No real identifier is read or printed.
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true

-- Synthetic fixtures: two companies and one animal each ---------------------------------------------------------------------------------
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v text) ON COMMIT DROP;
DO $$
DECLARE
    v_a integer; v_b integer; v_la uuid; v_lb uuid;
BEGIN
    SELECT coalesce(max(id_company), 0) + 1 INTO v_a FROM public.companys;
    v_b := v_a + 1;
    INSERT INTO public.companys (id_company, company_name, metadata) VALUES (v_a, 'TEST history company A', '{"qa_tenant": true}'), (v_b, 'TEST history company B', '{"qa_tenant": true}');
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, rfid_siniiga, species)
        VALUES (v_a, 'CRIA', 'VACA', 'ACTIVO', '9900000001', 'BOVINO') RETURNING id INTO v_la;
    INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, rfid_siniiga, species)
        VALUES (v_b, 'CRIA', 'VACA', 'ACTIVO', '9900000002', 'BOVINO') RETURNING id INTO v_lb;
    -- A legacy history row written the OLD way (no id_company column yet), to prove the backfill.
    INSERT INTO t_ids VALUES ('a', v_a::text), ('b', v_b::text), ('la', v_la::text), ('lb', v_lb::text);
END $$;

-- Legacy row before the migration (the column does not exist yet in a pre-migration database; skipped when it already does)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cattle_identifier_history' AND column_name = 'id_company') THEN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, identifier_type, previous_value, new_value, reason)
        SELECT v::uuid, 'SINIIGA', '9900000009', '9900000001', 'CAPTURE_CORRECTION' FROM t_ids WHERE k = 'la';
    END IF;
END $$;

\ir 114_identifier_history_tenant_guards.sql

-- T1 backfill: every row carries the company of its animal -------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.cattle_identifier_history h JOIN public.cattle_livestock c ON c.id = h.cattle_livestock_id WHERE h.id_company IS DISTINCT FROM c.tenant_id) THEN
        RAISE EXCEPTION 'T1 FAILED: a history row carries another company than its animal.';
    END IF;
    RAISE NOTICE 'T1 OK backfill';
END $$;

-- T2 append-only ------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE v_la uuid := (SELECT v::uuid FROM t_ids WHERE k = 'la'); v_state text;
BEGIN
    INSERT INTO public.cattle_identifier_history (cattle_livestock_id, identifier_type, previous_value, new_value, reason)
        VALUES (v_la, 'CHIP', NULL, '990000000000001', 'INITIAL_ASSIGNMENT');
    BEGIN UPDATE public.cattle_identifier_history SET notes = 'x' WHERE cattle_livestock_id = v_la;
        RAISE EXCEPTION 'T2 FAILED: UPDATE was allowed';
    EXCEPTION WHEN SQLSTATE 'P0131' THEN NULL; END;
    BEGIN DELETE FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la;
        RAISE EXCEPTION 'T2 FAILED: DELETE was allowed';
    EXCEPTION WHEN SQLSTATE 'P0131' THEN NULL; END;
    BEGIN TRUNCATE public.cattle_identifier_history;
        RAISE EXCEPTION 'T2 FAILED: TRUNCATE was allowed';
    EXCEPTION WHEN SQLSTATE 'P0131' THEN NULL; END;
    RAISE NOTICE 'T2 OK append-only';
END $$;

-- T3 id_company comes from the animal ---------------------------------------------------------------------------------------------------
DO $$
DECLARE v_la uuid := (SELECT v::uuid FROM t_ids WHERE k = 'la'); v_a integer := (SELECT v::integer FROM t_ids WHERE k = 'a'); v_b integer := (SELECT v::integer FROM t_ids WHERE k = 'b'); v_got integer;
BEGIN
    INSERT INTO public.cattle_identifier_history (cattle_livestock_id, identifier_type, new_value, reason)
        VALUES (v_la, 'FUEGO', 'T3', 'CAPTURE_CORRECTION') RETURNING id_company INTO v_got;
    IF v_got <> v_a THEN RAISE EXCEPTION 'T3 FAILED: id_company not taken from the animal'; END IF;
    BEGIN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, id_company, identifier_type, new_value, reason) VALUES (v_la, v_b, 'FUEGO', 'T3b', 'CAPTURE_CORRECTION');
        RAISE EXCEPTION 'T3 FAILED: a foreign company was accepted';
    EXCEPTION WHEN SQLSTATE 'P0130' THEN NULL; END;
    BEGIN
        INSERT INTO public.cattle_identifier_history (cattle_livestock_id, identifier_type, new_value, reason) VALUES (gen_random_uuid(), 'FUEGO', 'T3c', 'CAPTURE_CORRECTION');
        RAISE EXCEPTION 'T3 FAILED: an unknown animal was accepted';
    EXCEPTION WHEN SQLSTATE 'P0130' THEN NULL; END;
    RAISE NOTICE 'T3 OK company from the animal';
END $$;

-- T4 logger: actor, reason, notes, defaults -----------------------------------------------------------------------------------------------
DO $$
DECLARE v_la uuid := (SELECT v::uuid FROM t_ids WHERE k = 'la'); r record; n integer;
BEGIN
    -- with settings
    PERFORM set_config('app.identifier_change_user', 'approver@example.test', true);
    PERFORM set_config('app.identifier_change_reason', 'AUTHORIZED_CHANGE', true);
    PERFORM set_config('app.identifier_change_notes', 'tag lost in the field', true);
    UPDATE public.cattle_livestock SET rfid_siniiga = '9900000011' WHERE id = v_la;
    SELECT * INTO r FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la AND new_value = '9900000011';
    IF r.changed_by <> 'approver@example.test' OR r.reason <> 'AUTHORIZED_CHANGE' OR r.notes <> 'tag lost in the field' OR r.previous_value <> '9900000001' THEN
        RAISE EXCEPTION 'T4 FAILED: actor/reason/notes not recorded';
    END IF;
    -- without settings
    PERFORM set_config('app.identifier_change_user', '', true);
    PERFORM set_config('app.identifier_change_reason', '', true);
    PERFORM set_config('app.identifier_change_notes', '', true);
    UPDATE public.cattle_livestock SET rfid_siniiga = '9900000012' WHERE id = v_la;
    SELECT * INTO r FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la AND new_value = '9900000012';
    IF r.changed_by <> 'UNKNOWN' OR r.reason <> 'CAPTURE_CORRECTION' OR r.notes IS NOT NULL THEN RAISE EXCEPTION 'T4 FAILED: defaults wrong'; END IF;
    -- NULL <-> '' and edge spaces are not changes
    SELECT count(*) INTO n FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la;
    UPDATE public.cattle_livestock SET numero_fuego = '' WHERE id = v_la;
    UPDATE public.cattle_livestock SET rfid_siniiga = ' 9900000012 ' WHERE id = v_la;
    IF (SELECT count(*) FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la) <> n THEN RAISE EXCEPTION 'T4 FAILED: a non-change was logged'; END IF;
    -- two columns in one UPDATE = two rows
    UPDATE public.cattle_livestock SET numero_fuego = 'F-1', electronic_rfid = '990000000000002' WHERE id = v_la;
    IF (SELECT count(*) FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la) <> n + 2 THEN RAISE EXCEPTION 'T4 FAILED: expected two rows'; END IF;
    -- an unknown reason fails closed with the named error P0132 (not the raw CHECK), and the animal is left unchanged
    PERFORM set_config('app.identifier_change_reason', 'MADE_UP', true);
    BEGIN
        UPDATE public.cattle_livestock SET numero_fuego = 'F-2' WHERE id = v_la;
        RAISE EXCEPTION 'T4 FAILED: an invalid reason was accepted';
    EXCEPTION WHEN SQLSTATE 'P0132' THEN NULL; END;
    IF (SELECT numero_fuego FROM public.cattle_livestock WHERE id = v_la) <> 'F-1' THEN RAISE EXCEPTION 'T4 FAILED: the refused UPDATE changed the animal'; END IF;
    -- unset again: the default applies (set_config survives the caught error, so it MUST be reset for the tests that follow)
    PERFORM set_config('app.identifier_change_reason', '', true);
    UPDATE public.cattle_livestock SET numero_fuego = 'F-3' WHERE id = v_la;
    IF (SELECT reason FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la AND new_value = 'F-3') <> 'CAPTURE_CORRECTION' THEN RAISE EXCEPTION 'T4 FAILED: default reason after reset'; END IF;
    RAISE NOTICE 'T4 OK logger';
END $$;

-- T5 isolation: rows of company A are invisible when filtering by company B ----------------------------------------------------------------
DO $$
DECLARE v_a integer := (SELECT v::integer FROM t_ids WHERE k = 'a'); v_b integer := (SELECT v::integer FROM t_ids WHERE k = 'b'); v_lb uuid := (SELECT v::uuid FROM t_ids WHERE k = 'lb');
BEGIN
    UPDATE public.cattle_livestock SET rfid_siniiga = '9900000022' WHERE id = v_lb;
    IF EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE id_company = v_b AND cattle_livestock_id <> v_lb) THEN RAISE EXCEPTION 'T5 FAILED: company B sees another animal'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE id_company = v_a) THEN RAISE EXCEPTION 'T5 FAILED: company A has no rows'; END IF;
    RAISE NOTICE 'T5 OK isolation';
END $$;

-- T6 gateway model --------------------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'cattle_identifier_history' AND NOT ('INSERT' = ANY (allowed_ops)) AND allowed_roles_insert = 'NONE'
                      AND allowed_fields::jsonb ? 'id_company' AND allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER') THEN
        RAISE EXCEPTION 'T6 FAILED: gateway model';
    END IF;
    RAISE NOTICE 'T6 OK gateway model';
END $$;

-- T7 idempotent re-apply: nothing changes ---------------------------------------------------------------------------------------------------
INSERT INTO t_ids VALUES
    ('f1', md5(pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure))),
    ('m1', (SELECT md5(to_jsonb(m)::text) FROM public.crud_models m WHERE model_name = 'cattle_identifier_history')),
    ('n1', (SELECT count(*)::text FROM public.cattle_identifier_history));
\ir 114_identifier_history_tenant_guards.sql
DO $$
BEGIN
    IF md5(pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure)) <> (SELECT v FROM t_ids WHERE k = 'f1')
       OR (SELECT md5(to_jsonb(m)::text) FROM public.crud_models m WHERE model_name = 'cattle_identifier_history') <> (SELECT v FROM t_ids WHERE k = 'm1')
       OR (SELECT count(*)::text FROM public.cattle_identifier_history) <> (SELECT v FROM t_ids WHERE k = 'n1') THEN
        RAISE EXCEPTION 'T7 FAILED: re-applying changed something';
    END IF;
    RAISE NOTICE 'T7 OK idempotent';
END $$;

-- T8 rollback: old logger text restored, append-only off, gateway INSERT back; then re-apply works --------------------------------------------
\ir 114_rollback.sql
DO $$
DECLARE v_la uuid := (SELECT v::uuid FROM t_ids WHERE k = 'la');
BEGIN
    -- the live logger is the hardened 047 text (marker), not the new one and not the exact 047 text
    IF pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%hardened-047-logger%'
       OR pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) LIKE '%identifier_change_notes%' THEN
        RAISE EXCEPTION 'T8 FAILED: the rollback did not leave the hardened logger';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'cattle_identifier_history' AND 'INSERT' = ANY (allowed_ops)) THEN RAISE EXCEPTION 'T8 FAILED: gateway INSERT not restored'; END IF;
    -- the hardened logger works with settings that read '' (the session state after a custom setting was used) ...
    PERFORM set_config('app.identifier_change_reason', '', true);
    PERFORM set_config('app.identifier_change_user', '', true);
    UPDATE public.cattle_livestock SET rfid_siniiga = '9900000031' WHERE id = v_la;
    IF NOT EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la AND new_value = '9900000031' AND id_company IS NOT NULL
                      AND reason = 'CAPTURE_CORRECTION' AND changed_by IS NULL) THEN RAISE EXCEPTION 'T8 FAILED: hardened logger with empty settings'; END IF;
    -- ... and with a real reason (still accepted by the CHECK; no validation in this version)
    PERFORM set_config('app.identifier_change_reason', 'LOST', true);
    UPDATE public.cattle_livestock SET rfid_siniiga = '9900000032' WHERE id = v_la;
    IF NOT EXISTS (SELECT 1 FROM public.cattle_identifier_history WHERE cattle_livestock_id = v_la AND new_value = '9900000032' AND reason = 'LOST') THEN RAISE EXCEPTION 'T8 FAILED: reason not recorded'; END IF;
    PERFORM set_config('app.identifier_change_reason', '', true);
    RAISE NOTICE 'T8 OK rollback';
END $$;
\ir 114_identifier_history_tenant_guards.sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.cattle_identifier_history'::regclass AND tgname = 'trg_identifier_history_no_update_delete' AND tgenabled = 'O') THEN
        RAISE EXCEPTION 'T8 FAILED: append-only trigger not re-enabled by re-applying';
    END IF;
    RAISE NOTICE 'T8b OK re-apply after rollback';
END $$;

\echo 'ALL TESTS PASSED (rolled back)'
ROLLBACK;
