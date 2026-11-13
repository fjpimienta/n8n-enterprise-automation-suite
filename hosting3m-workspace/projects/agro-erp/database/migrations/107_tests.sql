-- 107_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). Everything runs inside ONE transaction that is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 107_tests.sql
-- Needs migration 104 applied (this file includes 107_agri_sale_gateway_sp.sql and 107_rollback.sql with `embedded` set). Synthetic data only: fake companies,
-- fake RFCs, fake e-mails. The gateway itself (n8n) is not exercised here: the operation / role check of its "Security Validation" node is reproduced in SQL;
-- the gateway entries are covered by the offline test workflows/06-dynamic-crud-engine/v6/tests/test_agri_sale_sp.mjs.
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;

-- Snapshot of every other row BEFORE 107 (compared again after the migration, after the rollback and after the re-apply).
CREATE TEMP TABLE snap (k text PRIMARY KEY, v text) ON COMMIT DROP;
INSERT INTO snap SELECT 'others_before',
    coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
  FROM crud_models c WHERE c.model_name NOT IN ('agri_sale_void', 'agri_sale_balance');
INSERT INTO snap SELECT 'm104_functions_before',
    md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.proname))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('sp_agri_register_sale', 'sp_agri_void_sale', 'sp_agri_sales_balance');

\set embedded true
\ir 107_agri_sale_gateway_sp.sql

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

-- The operation / role check of Security Validation: call_sp is an "insert"; the operation must be in allowed_ops and the role in the matching allowed_roles_* list.
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

-- Fixtures: two fake palm companies, members of every membership role in A (GUEST has no membership role: it appears only in the gateway matrix), an ADMIN of B, an issuer RFC each, one sale each ----------------------
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
DO $$
DECLARE ca integer; cb integer;
BEGIN
    INSERT INTO public.companys (company_name, industry) VALUES ('T107 Palm A', 'Agricultura') RETURNING id_company INTO ca;
    INSERT INTO public.companys (company_name, industry) VALUES ('T107 Palm B', 'Agricultura') RETURNING id_company INTO cb;
    INSERT INTO public.users (email, names, password, role) VALUES
        ('admin.a@example.invalid', 'A', 'x', 'ADMIN'), ('owner.a@example.invalid', 'O', 'x', 'ADMIN'), ('editor.a@example.invalid', 'E', 'x', 'EDITOR'),
        ('customer.a@example.invalid', 'C', 'x', 'CUSTOMER'), ('admin.b@example.invalid', 'B', 'x', 'ADMIN'),
        ('outsider@example.invalid', 'X', 'x', 'ADMIN');
    INSERT INTO public.user_companies (email, id_company, role) VALUES
        ('admin.a@example.invalid', ca, 'ADMIN'), ('owner.a@example.invalid', ca, 'OWNER'), ('editor.a@example.invalid', ca, 'EDITOR'),
        ('customer.a@example.invalid', ca, 'CUSTOMER'), ('admin.b@example.invalid', cb, 'ADMIN');
    PERFORM set_config('app.platform_seed', 'on', true);
    INSERT INTO public.company_issuer_rfcs (id_company, rfc) VALUES (ca, 'AAA010101AAA'), (cb, 'BBB020202BBB');
    PERFORM set_config('app.platform_seed', '', true);
    INSERT INTO ctx VALUES ('a', ca::text), ('b', cb::text);
END $$;

CREATE FUNCTION pg_temp.sale(p_company integer, p_uuid text, p_emisor text, p_total bigint) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, receptor_rfc, buyer_name, serie, folio, issued_at, stamped_at, subtotal_cents, total_cents, taxes,
        payment_form, payment_method, product_key, unit_code, quantity, unit_price, ticket_ref, ticket_warning,
        source_sha256, original_path, sat_status, registered_by_email)
    VALUES (p_company, p_uuid, p_emisor, 'CCC040404CCC', 'COMPRADOR SINTETICO', 'S', '1', public.fn_agri_today_cdmx()::timestamp, public.fn_agri_today_cdmx()::timestamp, p_total, p_total,
        '{"traslados":[],"retenciones":[]}'::jsonb, '03', 'PUE', '50307008', 'KGM', 10, p_total::numeric / 1000, 'T1', false,
        pg_temp.sha(p_uuid), p_company::text || '/2026/11/' || pg_temp.sha(p_uuid) || '.xml', 'VIGENTE', 'admin@example.invalid')
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b');
BEGIN
    INSERT INTO ctx VALUES ('sale_a1', pg_temp.sale(ca, 'A1000000-0000-4000-8000-000000000001', 'AAA010101AAA', 1000000)::text),
                           ('sale_a2', pg_temp.sale(ca, 'A1000000-0000-4000-8000-000000000002', 'AAA010101AAA', 2000000)::text),
                           ('sale_b1', pg_temp.sale(cb, 'B1000000-0000-4000-8000-000000000001', 'BBB020202BBB', 8000000)::text);
    RAISE NOTICE 'OK T0 fixtures: 2 sales for A, 1 for B, members of every role in A';
END $$;

-- T1. the two rows: exact values, every column --------------------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')) <> 2 THEN RAISE EXCEPTION 'FAIL T1 expected 2 rows'; END IF;
    IF NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'agri_sale_void' AND table_name = 'sp_agri_void_sale' AND primary_key = 'sale_id'
                     AND allowed_fields = '["sale_id","reason","actor_email"]'::jsonb AND allowed_ops = '{INSERT}'
                     AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'ADMIN' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                     AND is_global = false AND sp_requires_tenant = true AND default_filter IS NULL AND joins = '[]'::jsonb
                     AND schema_json = '{}'::jsonb AND hooks = '{"pre":[],"post":[]}'::jsonb) THEN
        RAISE EXCEPTION 'FAIL T1 agri_sale_void has other values';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'agri_sale_balance' AND table_name = 'sp_agri_sales_balance' AND primary_key = 'date_from'
                     AND allowed_fields = '["date_from","date_to","grain","plantation_id","lot_id","actor_email"]'::jsonb AND allowed_ops = '{INSERT}'
                     AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'ADMIN' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                     AND is_global = false AND sp_requires_tenant = true AND default_filter IS NULL AND joins = '[]'::jsonb
                     AND schema_json = '{}'::jsonb AND hooks = '{"pre":[],"post":[]}'::jsonb) THEN
        RAISE EXCEPTION 'FAIL T1 agri_sale_balance has other values';
    END IF;
    -- every column equals the expense models of M/081 except the identity, the names, the fields, the primary key and the roles (ADMIN only)
    IF EXISTS (SELECT 1 FROM crud_models n JOIN crud_models e ON (e.model_name, n.model_name) IN (('agri_void_expense', 'agri_sale_void'), ('agri_expense_balance', 'agri_sale_balance'))
                WHERE (to_jsonb(n) - 'id' - 'created_at' - 'model_name' - 'table_name' - 'primary_key' - 'allowed_fields' - 'allowed_roles_insert')
                      IS DISTINCT FROM (to_jsonb(e) - 'id' - 'created_at' - 'model_name' - 'table_name' - 'primary_key' - 'allowed_fields' - 'allowed_roles_insert')) THEN
        RAISE EXCEPTION 'FAIL T1 a column differs from the expense model it was copied from';
    END IF;
    RAISE NOTICE 'OK T1 both rows have the exact values; the other columns equal the 081 expense models';
END $$;

-- T2. role matrix: only ADMIN, only INSERT / call_sp ---------------------------------------------------------------------------------
DO $$
DECLARE m text; role_ text; op text;
BEGIN
    FOREACH m IN ARRAY ARRAY['agri_sale_void', 'agri_sale_balance'] LOOP
        FOREACH role_ IN ARRAY ARRAY['ADMIN', 'OWNER', 'EDITOR', 'CUSTOMER', 'GUEST'] LOOP
            FOREACH op IN ARRAY ARRAY['insert', 'call_sp'] LOOP
                IF pg_temp.can(m, op, role_) <> (role_ = 'ADMIN') THEN RAISE EXCEPTION 'FAIL T2 % % by %: must be ADMIN only', m, op, role_; END IF;
            END LOOP;
            FOREACH op IN ARRAY ARRAY['getall', 'getone', 'select', 'list', 'update', 'delete'] LOOP
                IF pg_temp.can(m, op, role_) THEN RAISE EXCEPTION 'FAIL T2 % % allowed for %: no other operation may exist', m, op, role_; END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'OK T2 role matrix ADMIN/OWNER/EDITOR/CUSTOMER/GUEST: only ADMIN, only insert / call_sp';
END $$;

-- T3. nothing else changed: every other crud_models row and the 104 procedures are identical to the snapshot ---------------------------
DO $$
BEGIN
    IF (SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') FROM crud_models c WHERE c.model_name NOT IN ('agri_sale_void', 'agri_sale_balance'))
       IS DISTINCT FROM (SELECT v FROM snap WHERE k = 'others_before') THEN
        RAISE EXCEPTION 'FAIL T3 another crud_models row changed';
    END IF;
    IF (SELECT md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.proname)) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('sp_agri_register_sale', 'sp_agri_void_sale', 'sp_agri_sales_balance'))
       IS DISTINCT FROM (SELECT v FROM snap WHERE k = 'm104_functions_before') THEN
        RAISE EXCEPTION 'FAIL T3 a 104 procedure changed';
    END IF;
    IF (SELECT count(*) FROM public.crud_models_backup_20261112_107) <> 0 THEN RAISE EXCEPTION 'FAIL T3 the backup must be empty on a first run (no previous rows)'; END IF;
    RAISE NOTICE 'OK T3 no other row and no procedure changed; the backup is empty (the rows are new)';
END $$;

-- T4. the procedures behind the models: signatures, one overload each, the model order matches the call order ---------------------------
DO $$
DECLARE v_n integer;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('sp_agri_void_sale', 'sp_agri_sales_balance');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL T4 expected exactly one procedure of each name (found % overloads)', v_n; END IF;
    IF (SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname = 'sp_agri_void_sale') <> 'p_tenant_id integer, p_actor_email text, p_sale_id uuid, p_reason text' THEN
        RAISE EXCEPTION 'FAIL T4 void signature'; END IF;
    IF (SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname = 'sp_agri_sales_balance')
       <> 'p_tenant_id integer, p_date_from date, p_date_to date, p_grain character varying, p_plantation_id uuid, p_lot_id uuid, p_actor_email character varying' THEN
        RAISE EXCEPTION 'FAIL T4 balance signature'; END IF;
    -- allowed_fields lists exactly the client-supplied arguments (the arguments of the procedure without the tenant, in the gateway order)
    IF (SELECT array_agg(f ORDER BY f) FROM jsonb_array_elements_text((SELECT allowed_fields FROM crud_models WHERE model_name = 'agri_sale_void')) f)
       <> ARRAY['actor_email', 'reason', 'sale_id'] THEN RAISE EXCEPTION 'FAIL T4 void fields'; END IF;
    IF (SELECT array_agg(f ORDER BY f) FROM jsonb_array_elements_text((SELECT allowed_fields FROM crud_models WHERE model_name = 'agri_sale_balance')) f)
       <> ARRAY['actor_email', 'date_from', 'date_to', 'grain', 'lot_id', 'plantation_id'] THEN RAISE EXCEPTION 'FAIL T4 balance fields'; END IF;
    RAISE NOTICE 'OK T4 one procedure per name with the expected signature; allowed_fields match the arguments';
END $$;

-- T5. the procedures answer as the gateway will call them (company from the header, actor from the token) --------------------------------
DO $$
DECLARE ca integer := (SELECT v FROM ctx WHERE k = 'a'); cb integer := (SELECT v FROM ctx WHERE k = 'b');
        a1 uuid := (SELECT v FROM ctx WHERE k = 'sale_a1')::uuid; b1 uuid := (SELECT v FROM ctx WHERE k = 'sale_b1')::uuid;
        r jsonb; r_foreign jsonb; r_unknown jsonb; actor text;
BEGIN
    -- only the ADMIN of the company voids; the other roles and an outsider are refused and nothing changes
    FOREACH actor IN ARRAY ARRAY['owner.a@example.invalid', 'editor.a@example.invalid', 'customer.a@example.invalid', 'guest.a@example.invalid', 'outsider@example.invalid', 'admin.b@example.invalid'] LOOP
        r := public.sp_agri_void_sale(ca, actor, a1, 'Voided by the test');
        IF r ->> 'status' <> 'FORBIDDEN' THEN RAISE EXCEPTION 'FAIL T5 % must be FORBIDDEN, got %', actor, r; END IF;
    END LOOP;
    IF (SELECT status FROM public.agri_sale_invoices WHERE id = a1) <> 'ACTIVE' THEN RAISE EXCEPTION 'FAIL T5 a refused call changed the sale'; END IF;
    -- reason limits
    IF public.sp_agri_void_sale(ca, 'admin.a@example.invalid', a1, 'abcd') ->> 'status' <> 'INVALID_REASON'
       OR public.sp_agri_void_sale(ca, 'admin.a@example.invalid', a1, repeat('x', 301)) ->> 'status' <> 'INVALID_REASON' THEN RAISE EXCEPTION 'FAIL T5 reason limits'; END IF;
    -- unknown id and another company's id answer the same
    r_unknown := public.sp_agri_void_sale(ca, 'admin.a@example.invalid', 'DEADBEEF-0000-4000-8000-000000000000'::uuid, 'Voided by the test');
    r_foreign := public.sp_agri_void_sale(ca, 'admin.a@example.invalid', b1, 'Voided by the test');
    IF r_unknown ->> 'status' <> 'NOT_FOUND' OR r_foreign ->> 'status' <> 'NOT_FOUND' OR r_unknown IS DISTINCT FROM r_foreign THEN
        RAISE EXCEPTION 'FAIL T5 unknown / foreign id: % / %', r_unknown, r_foreign;
    END IF;
    IF (SELECT status FROM public.agri_sale_invoices WHERE id = b1) <> 'ACTIVE' THEN RAISE EXCEPTION 'FAIL T5 the sale of B changed'; END IF;
    -- the void, then the repeat
    r := public.sp_agri_void_sale(ca, 'admin.a@example.invalid', a1, 'Voided by the test');
    IF r ->> 'status' <> 'OK' OR (r ->> 'sale_id')::uuid <> a1 OR r ? 'success' THEN RAISE EXCEPTION 'FAIL T5 void: %', r; END IF;
    IF (SELECT status || '|' || void_reason || '|' || voided_by_email FROM public.agri_sale_invoices WHERE id = a1) <> 'VOID|Voided by the test|admin.a@example.invalid' THEN RAISE EXCEPTION 'FAIL T5 void columns'; END IF;
    r := public.sp_agri_void_sale(ca, 'admin.a@example.invalid', a1, 'Another reason');
    IF r ->> 'status' <> 'ALREADY_VOID' OR (SELECT void_reason FROM public.agri_sale_invoices WHERE id = a1) <> 'Voided by the test' THEN RAISE EXCEPTION 'FAIL T5 repeat: %', r; END IF;
    -- balance: ADMIN reads, the rest raise P0084; the voided sale is excluded; the company is the argument, never the data of B
    r := public.sp_agri_sales_balance(ca, current_date - 30, current_date + 1, 'MONTH', NULL, NULL, 'admin.a@example.invalid');
    IF (r ->> 'success')::boolean IS NOT TRUE OR (r ->> 'sale_count')::int <> 1 OR (r ->> 'total_amount')::numeric <> 20000.00 THEN RAISE EXCEPTION 'FAIL T5 balance of A: %', r; END IF;
    r := public.sp_agri_sales_balance(cb, current_date - 30, current_date + 1, 'MONTH', NULL, NULL, 'admin.b@example.invalid');
    IF (r ->> 'sale_count')::int <> 1 OR (r ->> 'total_amount')::numeric <> 80000.00 THEN RAISE EXCEPTION 'FAIL T5 balance of B: %', r; END IF;
    FOREACH actor IN ARRAY ARRAY['owner.a@example.invalid', 'editor.a@example.invalid', 'customer.a@example.invalid', 'guest.a@example.invalid', 'outsider@example.invalid'] LOOP
        PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, current_date - 30, current_date, %L, NULL, NULL, %L)', ca, 'MONTH', actor), ARRAY['P0084']);
    END LOOP;
    PERFORM pg_temp.expect_err(format('SELECT public.sp_agri_sales_balance(%s, current_date - 30, current_date, %L, NULL, NULL, %L)', ca, 'MONTH', 'admin.b@example.invalid'), ARRAY['P0084']);
    RAISE NOTICE 'OK T5 void: ADMIN only, OK / ALREADY_VOID / NOT_FOUND (unknown = foreign) / INVALID_REASON / FORBIDDEN; balance: ADMIN only, no sale of B in A';
END $$;

-- T6. generic tenant-column rule over ALL models (report + assertion) ---------------------------------------------------------------------
-- The rule: every model whose table has an id_company / tenant_id column lists that column in allowed_fields. A call_sp model names a PROCEDURE
-- in table_name, so there is no table or view with that name and no column to list: the rule does not apply to it (it matches nothing in
-- information_schema.columns). The tenant of a call_sp model comes from sp_requires_tenant = true plus the verified header (the gateway entry
-- puts it first in the call) and the procedure checks the membership again. The two new models are therefore outside the rule; every other model still passes.
DO $$
DECLARE v_ic text; v_tn text; v_applies integer;
BEGIN
    SELECT count(*) INTO v_applies FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name IN ('id_company', 'tenant_id')
     WHERE m.model_name IN ('agri_sale_void', 'agri_sale_balance');
    IF v_applies <> 0 THEN RAISE EXCEPTION 'FAIL T6 the rule would apply to a new model (a relation named like the procedure exists)'; END IF;
    SELECT string_agg(DISTINCT m.model_name, ', ' ORDER BY m.model_name) INTO v_ic FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'id_company'
     WHERE NOT (m.allowed_fields ? 'id_company');
    SELECT string_agg(DISTINCT m.model_name, ', ' ORDER BY m.model_name) INTO v_tn FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name = 'tenant_id'
     WHERE NOT (m.allowed_fields ? 'tenant_id') AND NOT (m.allowed_fields ? 'id_company');
    RAISE NOTICE 'GENERIC TENANT CHECK: models over a table/view with id_company and without it in allowed_fields: %', coalesce(v_ic, '(none)');
    RAISE NOTICE 'GENERIC TENANT CHECK: models over a table/view with tenant_id and no tenant column in allowed_fields: %', coalesce(v_tn, '(none)');
    -- the two hotel models listed by migration 106 are tolerated when 106 is not applied in the scratch database (107 does not touch them)
    IF coalesce(v_ic, '') NOT IN ('', 'hotel_maintenance_tickets, hotel_rooms') OR v_tn IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL T6 a model does not list its tenant column: % / %', v_ic, v_tn;
    END IF;
    RAISE NOTICE 'OK T6 generic tenant rule passes for every model; it does not apply to the two procedure models (no table, so no tenant column)';
END $$;

-- T7. re-running the migration changes nothing (idempotent) ------------------------------------------------------------------------------
DO $$ BEGIN INSERT INTO snap SELECT 'rows_after_apply', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c WHERE c.model_name IN ('agri_sale_void', 'agri_sale_balance'); END $$;
\ir 107_agri_sale_gateway_sp.sql
DO $$
BEGIN
    IF (SELECT md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c WHERE c.model_name IN ('agri_sale_void', 'agri_sale_balance'))
       IS DISTINCT FROM (SELECT v FROM snap WHERE k = 'rows_after_apply') THEN RAISE EXCEPTION 'FAIL T7 a second apply changed the rows'; END IF;
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')) <> 2 THEN RAISE EXCEPTION 'FAIL T7 row count'; END IF;
    RAISE NOTICE 'OK T7 a second apply changes nothing';
END $$;

-- T8. the rollback disables exactly the two rows; a re-apply enables them again; nothing else moves --------------------------------------------
\ir 107_rollback.sql
DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance') AND cardinality(allowed_ops) = 0
          AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE') <> 2 THEN
        RAISE EXCEPTION 'FAIL T8 the rollback did not disable both rows';
    END IF;
    IF pg_temp.can('agri_sale_void', 'call_sp', 'ADMIN') OR pg_temp.can('agri_sale_balance', 'call_sp', 'ADMIN') OR pg_temp.can('agri_sale_void', 'insert', 'ADMIN') THEN
        RAISE EXCEPTION 'FAIL T8 a disabled model still allows an operation to ADMIN';
    END IF;
    IF (SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') FROM crud_models c WHERE c.model_name NOT IN ('agri_sale_void', 'agri_sale_balance'))
       IS DISTINCT FROM (SELECT v FROM snap WHERE k = 'others_before') THEN RAISE EXCEPTION 'FAIL T8 the rollback changed another row'; END IF;
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')) <> 2 THEN RAISE EXCEPTION 'FAIL T8 the rollback deleted a row'; END IF;
    RAISE NOTICE 'OK T8 rollback: both rows disabled (no operation, no role), none deleted, nothing else moved';
END $$;
\ir 107_agri_sale_gateway_sp.sql
DO $$
BEGIN
    IF (SELECT md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c WHERE c.model_name IN ('agri_sale_void', 'agri_sale_balance'))
       IS DISTINCT FROM (SELECT v FROM snap WHERE k = 'rows_after_apply') THEN RAISE EXCEPTION 'FAIL T8 the re-apply did not restore the rows'; END IF;
    IF NOT pg_temp.can('agri_sale_void', 'call_sp', 'ADMIN') OR pg_temp.can('agri_sale_void', 'call_sp', 'EDITOR') THEN RAISE EXCEPTION 'FAIL T8 the re-applied role rule'; END IF;
    RAISE NOTICE 'OK T8b re-apply after the rollback restores the exact rows';
END $$;

DO $$ BEGIN RAISE NOTICE 'ALL 107 TESTS OK'; END $$;
ROLLBACK;
\echo '*** 107 tests finished; everything rolled back ***'
