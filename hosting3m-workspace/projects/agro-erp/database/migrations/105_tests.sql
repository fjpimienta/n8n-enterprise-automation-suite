-- 105_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). Everything runs inside ONE transaction that is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 105_tests.sql
-- Needs migration 104 applied (this file includes 105_agri_sale_gateway_models.sql with `embedded` set). Synthetic data only: fake companies, fake
-- RFCs, fake e-mails. The gateway itself (n8n) is not exercised here: the operation / role check of its "Security Validation" node is reproduced in SQL.
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true
\ir 105_agri_sale_gateway_models.sql

-- Helpers ----------------------------------------------------------------------------------------------
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

-- The operation / role check of Security Validation: getall, getone and select need "select"; call_sp is an "insert"; the operation must be in
-- allowed_ops and the role in the matching allowed_roles_* list.
CREATE FUNCTION pg_temp.can(p_model text, p_op text, p_role text) RETURNS boolean LANGUAGE sql AS $$
    SELECT coalesce(bool_or(
        (CASE WHEN lower(p_op) IN ('getall', 'getone', 'select', 'list') THEN 'select' WHEN lower(p_op) = 'call_sp' THEN 'insert' ELSE lower(p_op) END)
            = ANY (SELECT lower(o) FROM unnest(m.allowed_ops) o)
        AND upper(p_role) = ANY (SELECT upper(btrim(r)) FROM unnest(string_to_array(
            CASE WHEN lower(p_op) IN ('getall', 'getone', 'select', 'list') THEN m.allowed_roles_select
                 WHEN lower(p_op) IN ('insert', 'call_sp') THEN m.allowed_roles_insert
                 WHEN lower(p_op) = 'update' THEN m.allowed_roles_update
                 ELSE m.allowed_roles_delete END, ',')) r)), false)
      FROM crud_models m WHERE m.model_name = p_model $$;

CREATE FUNCTION pg_temp.sha(p_uuid text) RETURNS text LANGUAGE sql AS $$ SELECT encode(sha256(convert_to(p_uuid, 'UTF8')), 'hex') $$;

-- Fixtures: two fake palm companies (A, B), their issuer RFCs (platform seed), a plantation each ------------------------------------
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
DO $$
DECLARE ca integer; cb integer; pa uuid; pb uuid;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T105 Palm A', 'Agricultura') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T105 Palm B', 'Agricultura') RETURNING id_company INTO cb;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (ca, 'PA1', 'Plantation A', 10, 'PROPIA') RETURNING id INTO pa;
    INSERT INTO public.agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure) VALUES (cb, 'PB1', 'Plantation B', 10, 'PROPIA') RETURNING id INTO pb;
    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (ca, 'AAA010101AAA'), (cb, 'BBB020202BBB');
    PERFORM set_config('app.platform_seed', '', true);
    INSERT INTO ctx VALUES ('a', ca::text), ('b', cb::text), ('pa', pa::text), ('pb', pb::text);
END $$;

-- Four sales for A (one with a plantation, one voided afterwards) and one for B. The table guard checks company, issuer RFC and amounts.
CREATE FUNCTION pg_temp.sale(p_company integer, p_uuid text, p_emisor text, p_ticket text, p_plantation uuid, p_total bigint) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, serie, folio, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_ref, ticket_warning, plantation_id,
        source_sha256, original_path, sat_status, registered_by_email)
    VALUES (p_company, p_uuid, p_emisor, 'CCC040404CCC', 'COMPRADOR SINTETICO', 'S', '1', public.fn_agri_today_cdmx()::timestamp, public.fn_agri_today_cdmx()::timestamp, p_total, p_total,
        '{"traslados":[],"retenciones":[]}'::jsonb, '03', 'PUE', '50307008', 'KGM', 10, p_total::numeric / 1000, p_ticket, p_ticket IS NULL, p_plantation,
        pg_temp.sha(p_uuid), p_company::text || '/2026/11/' || pg_temp.sha(p_uuid) || '.xml', 'VIGENTE', 'admin@example.invalid')
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); pa uuid := (SELECT v FROM ctx WHERE k = 'pa')::uuid;
        a3 uuid;
BEGIN
    PERFORM pg_temp.sale(ca, 'A1000000-0000-4000-8000-000000000001', 'AAA010101AAA', 'T1', NULL, 1000000);
    PERFORM pg_temp.sale(ca, 'A1000000-0000-4000-8000-000000000002', 'AAA010101AAA', NULL, pa, 2000000);
    a3 := pg_temp.sale(ca, 'A1000000-0000-4000-8000-000000000003', 'AAA010101AAA', 'T3', NULL, 4000000);
    PERFORM pg_temp.sale(cb, 'B1000000-0000-4000-8000-000000000001', 'BBB020202BBB', 'T9', NULL, 8000000);
    PERFORM set_config('app.agri_sale_void', 'on', true);
    UPDATE public.agri_sale_invoices SET status = 'VOID', void_reason = 'Voided by the test', voided_by_email = 'admin@example.invalid', voided_at = now() WHERE id = a3;
    PERFORM set_config('app.agri_sale_void', '', true);
    INSERT INTO public.agri_sale_audit (id_company, event, code, actor_email) VALUES (ca, 'REJECT', 'TEST_CODE', 'admin@example.invalid');
    RAISE NOTICE 'OK T0 fixtures: 3 sales for A (1 voided), 1 for B';
END $$;

-- T1. id_company is in allowed_fields of every new / changed model ---------------------------------------------------------------
DO $$
DECLARE v_missing text;
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')) <> 6 THEN
        RAISE EXCEPTION 'FAIL T1 expected 6 model rows';
    END IF;
    SELECT string_agg(model_name, ',') INTO v_missing FROM crud_models
     WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs') AND NOT (allowed_fields ? 'id_company');
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL T1 id_company missing in allowed_fields of: %', v_missing; END IF;
    RAISE NOTICE 'OK T1 id_company in allowed_fields of the 6 models';
END $$;

-- T2. the four restricted rows: no operation, no role, registered under their own table name -------------------------------------
DO $$
DECLARE t text; r crud_models;
BEGIN
    FOREACH t IN ARRAY ARRAY['agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs'] LOOP
        SELECT * INTO r FROM crud_models WHERE model_name = t;
        IF NOT FOUND THEN RAISE EXCEPTION 'FAIL T2 % is not registered', t; END IF;
        IF r.table_name <> t OR cardinality(r.allowed_ops) <> 0 OR r.allowed_roles_select <> 'NONE' OR r.allowed_roles_insert <> 'NONE'
           OR r.allowed_roles_update <> 'NONE' OR r.allowed_roles_delete <> 'NONE' THEN
            RAISE EXCEPTION 'FAIL T2 % is not restricted: ops %, roles %/%/%/%', t, r.allowed_ops, r.allowed_roles_select, r.allowed_roles_insert, r.allowed_roles_update, r.allowed_roles_delete;
        END IF;
        IF pg_temp.can(t, 'getall', 'ADMIN') OR pg_temp.can(t, 'getone', 'ADMIN') OR pg_temp.can(t, 'insert', 'ADMIN') OR pg_temp.can(t, 'update', 'ADMIN')
           OR pg_temp.can(t, 'delete', 'ADMIN') OR pg_temp.can(t, 'call_sp', 'ADMIN') THEN
            RAISE EXCEPTION 'FAIL T2 % allows an operation to ADMIN', t;
        END IF;
    END LOOP;
    RAISE NOTICE 'OK T2 the four restricted models have no operation and no role';
END $$;

-- T3. the read models: only SELECT / GETONE / GETALL, only ADMIN -----------------------------------------------------------------
DO $$
DECLARE m text; role_ text; op text;
BEGIN
    FOREACH m IN ARRAY ARRAY['agri_sales', 'agri_sale_summary'] LOOP
        IF NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = m AND allowed_ops = '{SELECT,GETONE,GETALL}' AND allowed_roles_select = 'ADMIN'
                         AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                         AND is_global = false AND sp_requires_tenant = true AND NOT (allowed_fields ? 'id') AND default_filter IS NULL AND joins = '[]'::jsonb) THEN
            RAISE EXCEPTION 'FAIL T3 % has other values', m;
        END IF;
        FOREACH role_ IN ARRAY ARRAY['ADMIN', 'OWNER', 'EDITOR', 'CUSTOMER', 'GUEST'] LOOP
            FOREACH op IN ARRAY ARRAY['getall', 'getone', 'select', 'list'] LOOP
                IF pg_temp.can(m, op, role_) <> (role_ = 'ADMIN') THEN RAISE EXCEPTION 'FAIL T3 % % by %: read must be ADMIN only', m, op, role_; END IF;
            END LOOP;
            FOREACH op IN ARRAY ARRAY['insert', 'update', 'delete', 'call_sp'] LOOP
                IF pg_temp.can(m, op, role_) THEN RAISE EXCEPTION 'FAIL T3 % % allowed for %: no write operation may exist', m, op, role_; END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    IF (SELECT table_name FROM crud_models WHERE model_name = 'agri_sales') <> 'vw_agri_sale_ui_list'
       OR (SELECT table_name FROM crud_models WHERE model_name = 'agri_sale_summary') <> 'vw_agri_sale_summary' THEN RAISE EXCEPTION 'FAIL T3 wrong source view'; END IF;
    RAISE NOTICE 'OK T3 read models: SELECT/GETONE/GETALL for ADMIN only; no insert, update, delete or call_sp for anybody';
END $$;

-- T4. the browser view: exact column list, id_company present, none of the forbidden columns ---------------------------------------
DO $$
DECLARE v_cols text; v_bad text;
BEGIN
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';
    IF v_cols IS DISTINCT FROM 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at' THEN
        RAISE EXCEPTION 'FAIL T4 columns: %', v_cols;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list' AND column_name = 'id_company') THEN
        RAISE EXCEPTION 'FAIL T4 id_company missing';
    END IF;
    SELECT string_agg(column_name, ',') INTO v_bad FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list'
       AND (column_name IN ('uuid', 'buyer_rfc', 'receptor_rfc', 'emisor_rfc', 'sat_status', 'registered_by_email', 'voided_by_email', 'original_path', 'source_sha256', 'payment_form')
            OR column_name ~* '(uuid|rfc|sat_|email|path|sha|hash|cert|sello)');
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL T4 forbidden column(s): %', v_bad; END IF;
    RAISE NOTICE 'OK T4 vw_agri_sale_ui_list: exact column list, id_company present, no forbidden column';
END $$;

-- T5. the summary: aggregates + id_company only, VOID excluded -----------------------------------------------------------------------
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); v_cols text; v_n bigint; v_sum numeric;
BEGIN
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_summary';
    IF v_cols <> 'id,id_company,grain,period_start,period_end,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,total_amount,total_quantity,sale_count,created_at' THEN
        RAISE EXCEPTION 'FAIL T5 summary columns: %', v_cols;
    END IF;
    IF v_cols ~* '(uuid|rfc|sat_|email|path|sha|hash|buyer|reason|folio)' THEN RAISE EXCEPTION 'FAIL T5 summary carries a non-aggregate column'; END IF;
    SELECT sum(sale_count), sum(total_amount) INTO v_n, v_sum FROM public.vw_agri_sale_summary WHERE id_company = ca AND grain = 'DAY';
    IF v_n <> 2 OR v_sum <> 30000.00 THEN RAISE EXCEPTION 'FAIL T5 summary of A: % sale(s), % (the voided sale must not count)', v_n, v_sum; END IF;
    IF (SELECT count(*) FROM public.agri_sale_invoices WHERE id_company = ca AND status = 'VOID') <> 1 THEN RAISE EXCEPTION 'FAIL T5 fixture'; END IF;
    RAISE NOTICE 'OK T5 summary: aggregates + id_company only; the voided sale is excluded';
END $$;

-- T6. the list shows the voided sale with its status; values come from the voucher ----------------------------------------------------
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a');
BEGIN
    IF (SELECT count(*) FROM public.vw_agri_sale_ui_list WHERE id_company = ca) <> 3
       OR (SELECT count(*) FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND status = 'VOID' AND void_reason = 'Voided by the test' AND voided_at IS NOT NULL) <> 1
       OR (SELECT count(*) FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND status = 'ACTIVE') <> 2 THEN
        RAISE EXCEPTION 'FAIL T6 list statuses';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND folio = 'S1' AND ticket_ref = 'T1' AND total_amount = 10000.00 AND quantity = 10 AND unit_code = 'KGM'
                     AND payment_method = 'PUE' AND buyer_name = 'COMPRADOR SINTETICO' AND ticket_warning = false AND is_test = false AND sale_date = public.fn_agri_today_cdmx()) THEN
        RAISE EXCEPTION 'FAIL T6 list values';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND ticket_ref IS NULL AND ticket_warning AND plantation_code = 'PA1' AND plantation_name = 'Plantation A') THEN
        RAISE EXCEPTION 'FAIL T6 plantation / ticket warning';
    END IF;
    RAISE NOTICE 'OK T6 list: VOID row with status and reason, values from the voucher';
END $$;

-- T7. two companies never mix when filtered by id_company (what the gateway adds) ------------------------------------------------------
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b'); pb uuid := (SELECT v FROM ctx WHERE k = 'pb')::uuid;
BEGIN
    IF (SELECT count(DISTINCT id_company) FROM public.vw_agri_sale_ui_list WHERE id_company = ca) <> 1 OR (SELECT count(*) FROM public.vw_agri_sale_ui_list WHERE id_company = cb) <> 1
       OR EXISTS (SELECT 1 FROM public.vw_agri_sale_ui_list a JOIN public.vw_agri_sale_ui_list b ON a.id = b.id WHERE a.id_company = ca AND b.id_company = cb) THEN
        RAISE EXCEPTION 'FAIL T7 list isolation';
    END IF;
    IF (SELECT sum(total_amount) FROM public.vw_agri_sale_ui_list WHERE id_company = cb) <> 80000.00
       OR (SELECT sum(total_amount) FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND status = 'ACTIVE') <> 30000.00 THEN
        RAISE EXCEPTION 'FAIL T7 amounts mixed';
    END IF;
    IF (SELECT sum(sale_count) FROM public.vw_agri_sale_summary WHERE id_company = cb AND grain = 'DAY') <> 1 OR (SELECT sum(total_amount) FROM public.vw_agri_sale_summary WHERE id_company = cb AND grain = 'DAY') <> 80000.00
       OR EXISTS (SELECT 1 FROM public.vw_agri_sale_summary WHERE id_company = ca AND plantation_id = pb) THEN
        RAISE EXCEPTION 'FAIL T7 summary isolation';
    END IF;
    IF EXISTS (SELECT 1 FROM public.vw_agri_sale_ui_list WHERE id_company = ca AND plantation_name = 'Plantation B') THEN RAISE EXCEPTION 'FAIL T7 plantation of B in A'; END IF;
    -- a sale cannot point at a plantation of another company (composite key)
    PERFORM pg_temp.expect_err(format('SELECT pg_temp.sale(%s, %L, %L, %L, %L, 1000)', ca, 'A1000000-0000-4000-8000-000000000009', 'AAA010101AAA', 'TX', pb), ARRAY['23503']);
    RAISE NOTICE 'OK T7 two companies never mix (list, summary, plantations)';
END $$;

-- T8. the sale tables of migration 104 still reject direct changes ------------------------------------------------------------------
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a');
BEGIN
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET buyer_name = %L WHERE id_company = %s', 'OTHER', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('UPDATE public.agri_sale_invoices SET total_cents = 1 WHERE id_company = %s', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('DELETE FROM public.agri_sale_invoices WHERE id_company = %s', ca), ARRAY['P0110']);
    PERFORM pg_temp.expect_err('TRUNCATE public.agri_sale_invoices', ARRAY['P0110', '0A000']);
    PERFORM pg_temp.expect_err('UPDATE public.agri_sale_audit SET code = ''X''', ARRAY['P0110']);
    PERFORM pg_temp.expect_err('DELETE FROM public.agri_sale_audit', ARRAY['P0110']);
    PERFORM pg_temp.expect_err(format('INSERT INTO public.company_flags (id_company, is_test) VALUES (%s, true)', ca), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('DELETE FROM public.company_issuer_rfcs WHERE id_company = %s', ca), ARRAY['P0111']);
    PERFORM pg_temp.expect_err(format('UPDATE public.company_issuer_rfcs SET is_active = false WHERE id_company = %s', ca), ARRAY['P0111']);
    RAISE NOTICE 'OK T8 the 104 tables still reject direct changes';
END $$;

-- T9. 105 changes nothing else in crud_models: a row of any other model is not among the six names --------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM crud_models WHERE model_name NOT IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
                AND table_name IN ('vw_agri_sale_ui_list', 'vw_agri_sale_summary', 'vw_agri_sale_list', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')) THEN
        RAISE EXCEPTION 'FAIL T9 another model serves one of the sale objects';
    END IF;
    IF to_regclass('public.crud_models_backup_20261112_105') IS NULL THEN RAISE EXCEPTION 'FAIL T9 backup table missing'; END IF;
    RAISE NOTICE 'OK T9 no other model serves the sale objects; the backup table exists';
END $$;

-- T10. generic tenant column check over ALL models (report only: existing rows are not changed) --------------------------------------------
DO $$
DECLARE v_total integer; v_ic text; v_tn text; v_new text;
BEGIN
    SELECT count(*) INTO v_total FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'id_company';
    SELECT string_agg(m.model_name, ', ' ORDER BY m.model_name) INTO v_ic FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'id_company'
     WHERE NOT (m.allowed_fields ? 'id_company');
    SELECT string_agg(m.model_name, ', ' ORDER BY m.model_name) INTO v_tn FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'tenant_id'
     WHERE NOT (m.allowed_fields ? 'tenant_id') AND NOT (m.allowed_fields ? 'id_company');
    RAISE NOTICE 'GENERIC TENANT CHECK (report only): % model(s) over a table/view with id_company; id_company missing in allowed_fields: %', v_total, coalesce(v_ic, '(none)');
    RAISE NOTICE 'GENERIC TENANT CHECK (report only): models over a table/view with tenant_id and no tenant column in allowed_fields: %', coalesce(v_tn, '(none)');
    -- the models of THIS migration must never be on the list
    SELECT string_agg(m.model_name, ',') INTO v_new FROM crud_models m
     WHERE m.model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
       AND m.model_name = ANY (string_to_array(replace(coalesce(v_ic, ''), ', ', ','), ','));
    IF v_new IS NOT NULL THEN RAISE EXCEPTION 'FAIL T10 a model of 105 fails the tenant check: %', v_new; END IF;
    RAISE NOTICE 'OK T10 generic tenant check done (the 6 models of 105 pass)';
END $$;

DO $$ BEGIN RAISE NOTICE 'ALL 105 TESTS OK'; END $$;
ROLLBACK;
\echo '*** 105 tests finished; everything rolled back ***'
