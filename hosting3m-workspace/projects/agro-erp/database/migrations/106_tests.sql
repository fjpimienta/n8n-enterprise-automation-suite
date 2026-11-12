-- 106_tests.sql: LOCAL / throwaway database ONLY (the name must contain "test" or "rehearsal"). Everything runs inside ONE transaction that is rolled back.
-- psql -X -v ON_ERROR_STOP=1 -f 106_tests.sql
-- The two rows are rebuilt inside the transaction with their pre-106 configuration, so the result does not depend on the state of the database.
\set ON_ERROR_STOP on
SELECT current_database() ~ '(test|rehearsal)' AS scratch_ok \gset
\if :scratch_ok
\else
\echo 'ABORT: run this only against a throwaway database (name must contain test or rehearsal).'
\quit
\endif
BEGIN;
\set embedded true

-- Fixtures: the two rows as they are before 106, plus a probe row that 106 must never touch --------------------------------------------
DELETE FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets', 'zz_106_probe');
DROP TABLE IF EXISTS public.crud_models_backup_20261112_106;
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json, allowed_ops, hooks,
                         allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  ('hotel_rooms', 'hotel_rooms', 'id',
   '["id","room_number","type","status","price_night","description","cleaning_status","is_active"]', NULL, '{}',
   '{SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL}', '{"pre": [], "post": []}',
   'ADMIN,EDITOR,CUSTOMER', 'ADMIN,EDITOR', 'ADMIN,EDITOR,HOUSEKEEPING', 'ADMIN', '[]', false, true),
  ('hotel_maintenance_tickets', 'hotel_maintenance_tickets', 'id',
   '["id","room_id","inspection_id","expense_id","issue_type","description","status","priority","resolved_at","created_at","room_number","solution_details"]',
   'hotel_maintenance_tickets.status != ''DELETED''', '{}',
   '{SELECT,INSERT,UPDATE,GETALL,GETONE}', '{"pre": [], "post": []}',
   'ADMIN,EDITOR,HOUSEKEEPING', 'ADMIN,EDITOR,HOUSEKEEPING', 'ADMIN,EDITOR', 'ADMIN',
   '[{"alias": "room_data", "table": "hotel_rooms", "select": ["room_number"], "own_col": "room_id", "foreign_col": "id"}]', false, true),
  ('zz_106_probe', 'agri_unit_catalog', 'id', '["id","full_name"]', NULL, '{}', '{SELECT}', '{"pre": [], "post": []}', 'ADMIN', 'NONE', 'NONE', 'NONE', '[]', false, true);

CREATE TEMP TABLE snap ON COMMIT DROP AS
    SELECT model_name, to_jsonb(c) AS row_json FROM crud_models c WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets');
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text) ON COMMIT DROP;
INSERT INTO ctx SELECT 'others_md5', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name))
  FROM crud_models c WHERE c.model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets');
INSERT INTO ctx SELECT 'others_n', count(*)::text FROM crud_models WHERE model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets');

\ir 106_align_hotel_models_tenant_field.sql

-- T1. both rows list id_company ------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets') AND allowed_fields ? 'id_company') <> 2 THEN
        RAISE EXCEPTION 'FAIL T1 both rows must list id_company';
    END IF;
    RAISE NOTICE 'OK T1 hotel_rooms and hotel_maintenance_tickets list id_company';
END $$;

-- T2. nothing else changed in the two rows: every other column, operations, roles, joins, hooks, primary key, other allowed fields -------------
DO $$
DECLARE t text; a jsonb; s jsonb;
BEGIN
    FOREACH t IN ARRAY ARRAY['hotel_rooms', 'hotel_maintenance_tickets'] LOOP
        SELECT to_jsonb(c) INTO a FROM crud_models c WHERE model_name = t;
        SELECT row_json INTO s FROM snap WHERE model_name = t;
        IF (a - 'allowed_fields') IS DISTINCT FROM (s - 'allowed_fields') THEN RAISE EXCEPTION 'FAIL T2 % : a column other than allowed_fields changed', t; END IF;
        IF (a -> 'allowed_fields') - 'id_company' IS DISTINCT FROM (s -> 'allowed_fields') THEN RAISE EXCEPTION 'FAIL T2 % : the other allowed fields changed', t; END IF;
        IF jsonb_array_length(a -> 'allowed_fields') <> jsonb_array_length(s -> 'allowed_fields') + 1 THEN RAISE EXCEPTION 'FAIL T2 % : exactly one field must be added', t; END IF;
        IF (a -> 'allowed_fields') ->> (jsonb_array_length(a -> 'allowed_fields') - 1) <> 'id_company' THEN RAISE EXCEPTION 'FAIL T2 % : id_company must be appended at the end', t; END IF;
    END LOOP;
    -- explicit values (not only "equal to the snapshot")
    IF NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'hotel_rooms' AND primary_key = 'id' AND allowed_ops = '{SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL}'
                     AND allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER' AND allowed_roles_insert = 'ADMIN,EDITOR' AND allowed_roles_update = 'ADMIN,EDITOR,HOUSEKEEPING'
                     AND allowed_roles_delete = 'ADMIN' AND joins = '[]'::jsonb AND hooks = '{"pre": [], "post": []}'::jsonb AND default_filter IS NULL) THEN
        RAISE EXCEPTION 'FAIL T2 hotel_rooms operations / roles / joins / hooks';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'hotel_maintenance_tickets' AND primary_key = 'id' AND allowed_ops = '{SELECT,INSERT,UPDATE,GETALL,GETONE}'
                     AND allowed_roles_select = 'ADMIN,EDITOR,HOUSEKEEPING' AND allowed_roles_insert = 'ADMIN,EDITOR,HOUSEKEEPING' AND allowed_roles_update = 'ADMIN,EDITOR'
                     AND allowed_roles_delete = 'ADMIN' AND joins -> 0 ->> 'table' = 'hotel_rooms' AND hooks = '{"pre": [], "post": []}'::jsonb
                     AND default_filter = 'hotel_maintenance_tickets.status != ''DELETED''') THEN
        RAISE EXCEPTION 'FAIL T2 hotel_maintenance_tickets operations / roles / joins / hooks';
    END IF;
    RAISE NOTICE 'OK T2 operations, roles, joins, hooks, primary key and the other allowed fields are unchanged';
END $$;

-- T3. no other crud_models row changed -----------------------------------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c WHERE c.model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets'))
       IS DISTINCT FROM (SELECT v FROM ctx WHERE k = 'others_md5') THEN RAISE EXCEPTION 'FAIL T3 another crud_models row changed'; END IF;
    IF (SELECT count(*) FROM crud_models WHERE model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets'))::text <> (SELECT v FROM ctx WHERE k = 'others_n') THEN
        RAISE EXCEPTION 'FAIL T3 the number of other rows changed';
    END IF;
    IF (SELECT allowed_fields FROM crud_models WHERE model_name = 'zz_106_probe') <> '["id","full_name"]'::jsonb THEN RAISE EXCEPTION 'FAIL T3 the probe row changed'; END IF;
    RAISE NOTICE 'OK T3 no other crud_models row changed (including a probe row)';
END $$;

-- T4. the backup holds exactly the two original rows ----------------------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models_backup_20261112_106) <> 2
       OR EXISTS (SELECT 1 FROM crud_models_backup_20261112_106 b JOIN snap s ON s.model_name = b.model_name WHERE (to_jsonb(b) - 'backed_up_at') IS DISTINCT FROM s.row_json) THEN
        RAISE EXCEPTION 'FAIL T4 the backup is not the original two rows';
    END IF;
    RAISE NOTICE 'OK T4 the backup holds exactly the two original rows';
END $$;

-- T5. idempotent re-run ---------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE after_first ON COMMIT DROP AS SELECT model_name, to_jsonb(c) AS row_json FROM crud_models c;
\ir 106_align_hotel_models_tenant_field.sql
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM crud_models c JOIN after_first a ON a.model_name = c.model_name WHERE to_jsonb(c) IS DISTINCT FROM a.row_json)
       OR (SELECT count(*) FROM crud_models) <> (SELECT count(*) FROM after_first) THEN
        RAISE EXCEPTION 'FAIL T5 a second run changed something';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')
                AND (SELECT count(*) FROM jsonb_array_elements_text(allowed_fields) e WHERE e = 'id_company') <> 1) THEN
        RAISE EXCEPTION 'FAIL T5 id_company is listed more than once';
    END IF;
    IF (SELECT count(*) FROM crud_models_backup_20261112_106 WHERE allowed_fields ? 'id_company') <> 0 THEN RAISE EXCEPTION 'FAIL T5 the backup was overwritten by the second run'; END IF;
    RAISE NOTICE 'OK T5 a second run changes nothing';
END $$;

-- T6. the rollback restores the exact previous rows --------------------------------------------------------------------------------------------
\ir 106_rollback.sql
DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')) <> 2 THEN RAISE EXCEPTION 'FAIL T6 both rows must still exist after the rollback'; END IF;
    IF EXISTS (SELECT 1 FROM crud_models c JOIN snap s ON s.model_name = c.model_name WHERE to_jsonb(c) IS DISTINCT FROM s.row_json) THEN
        RAISE EXCEPTION 'FAIL T6 the rollback did not restore the exact previous rows';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets') AND allowed_fields ? 'id_company') THEN RAISE EXCEPTION 'FAIL T6 id_company is still listed'; END IF;
    IF (SELECT md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c WHERE c.model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets'))
       IS DISTINCT FROM (SELECT v FROM ctx WHERE k = 'others_md5') THEN RAISE EXCEPTION 'FAIL T6 the rollback touched another row'; END IF;
    RAISE NOTICE 'OK T6 the rollback restores the exact previous allowed_fields; no other row touched';
END $$;
\ir 106_align_hotel_models_tenant_field.sql

-- T7. generic assertion over ALL models: a model over a table / view that has id_company or tenant_id lists that column in allowed_fields -------
DO $$
DECLARE v_names text; v_total integer;
BEGIN
    SELECT count(DISTINCT m.model_name) INTO v_total FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name IN ('id_company', 'tenant_id');
    SELECT string_agg(DISTINCT m.model_name, ', ' ORDER BY m.model_name) INTO v_names FROM crud_models m
      JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name IN ('id_company', 'tenant_id')
     WHERE NOT (m.allowed_fields ? c.column_name);
    RAISE NOTICE 'GENERIC TENANT CHECK: % model(s) over a table/view with id_company or tenant_id; not listing it: %', v_total, coalesce(v_names, '(none)');
    IF v_names IS NOT NULL THEN RAISE EXCEPTION 'FAIL T7 models that do not list their tenant column: %', v_names; END IF;
    RAISE NOTICE 'OK T7 every model over a table with a tenant column lists it in allowed_fields';
END $$;

DO $$ BEGIN RAISE NOTICE 'ALL 106 TESTS OK'; END $$;
ROLLBACK;
\echo '*** 106 tests finished; everything rolled back ***'
