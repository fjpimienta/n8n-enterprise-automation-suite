-- 089_tests.sql — functional checks for migration 089 (THROWAWAY / LOCAL database only). EVERYTHING is rolled back.
--
-- It needs 085 applied or loads 084 and 085 itself (embedded), then runs 089 and 089_rollback inside this transaction. The throwaway
-- database is a schema-only copy, so crud_models may be empty: the test then INSERTS a fixture row with id 70 (model nacimiento) and
-- fixture neighbours (ids 7001, 7002); if row 70 already exists with the right names it is used as it is; if id 70 belongs to another
-- model the test stops.
--
-- Run (the test files must be INSIDE the container):
--   docker exec n8n-enterprise-db rm -rf /tmp/m089
--   docker cp database/migrations n8n-enterprise-db:/tmp/m089
--   docker exec -w /tmp/m089 -i n8n-enterprise-db psql -U n8n_user -d <THROWAWAY_DB> -v ON_ERROR_STOP=1 -f /tmp/m089/089_tests.sql

\set ON_ERROR_STOP on
\set embedded true
BEGIN;
\ir 084_repro_births_age.sql
\ir 085_repro_empadre.sql

CREATE TEMP TABLE t_result (n serial, test text, ok boolean, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_test text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO t_result (test, ok, detail) VALUES (p_test, coalesce(p_ok, false), p_detail) $$;
CREATE FUNCTION pg_temp.raises(p_sql text, p_state text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN false;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE = p_state;
END $$;

-- fixture rows (only when the schema-only copy has none)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM crud_models WHERE id = 70 AND (model_name <> 'nacimiento' OR table_name <> 'sp_register_birth_event')) THEN
        RAISE EXCEPTION '089 tests: crud_models id 70 is another model in this database; use a schema-only copy.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM crud_models WHERE id = 70) THEN
        INSERT INTO crud_models (id, model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops,
                                 allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins, sp_requires_tenant)
        VALUES (70, 'nacimiento', 'sp_register_birth_event', 'id', '["calf_sex","species","dam_id"]'::jsonb, '{}'::jsonb, ARRAY['INSERT']::text[],
                'ADMIN', 'ADMIN,EDITOR', 'ADMIN', 'ADMIN', '[]'::jsonb, true);
    END IF;
    INSERT INTO crud_models (id, model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops,
                             allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins)
    SELECT v.id, v.n, v.n, 'id', '[]'::jsonb, '{}'::jsonb, ARRAY['SELECT', 'INSERT']::text[], 'ADMIN', 'ADMIN,EDITOR', 'ADMIN', 'ADMIN', '[]'::jsonb
      FROM (VALUES (7001, 'T089_other_model_1'), (7002, 'T089_other_model_2')) AS v (id, n)
     WHERE NOT EXISTS (SELECT 1 FROM crud_models c WHERE c.id = v.id);
END $$;

CREATE TEMP TABLE t_before ON COMMIT DROP AS
SELECT (SELECT to_jsonb(c) FROM crud_models c WHERE c.id = 70) AS row70,
       (SELECT md5(coalesce(string_agg(row_to_json(c)::text, '|' ORDER BY c.id), '')) FROM crud_models c WHERE c.id <> 70) AS others,
       (SELECT count(*) FROM crud_models) AS n_models;

\ir 089_disable_nacimiento_gateway.sql

SELECT pg_temp.ok('A row 70 is DISABLED: allowed_ops empty and the four roles NONE; the row still EXISTS (never deleted, so the auto-register path stays closed)',
    (SELECT cardinality(allowed_ops) = 0 AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
       FROM crud_models WHERE id = 70)
    AND (SELECT count(*) FROM crud_models WHERE model_name = 'nacimiento') = 1);
SELECT pg_temp.ok('A the gateway''s own check (Security Validation: the operation must be in allowed_ops) rejects INSERT, SELECT, UPDATE, DELETE and call_sp for the model',
    (SELECT bool_and(NOT (op = ANY (SELECT lower(x) FROM unnest(c.allowed_ops) x)))
       FROM crud_models c, unnest(ARRAY['select', 'insert', 'update', 'delete']) op WHERE c.id = 70));
SELECT pg_temp.ok('A ONLY row 70 changed: every other model is byte-identical, no model was added or removed, and only the five columns of row 70 differ',
    (SELECT md5(coalesce(string_agg(row_to_json(c)::text, '|' ORDER BY c.id), '')) FROM crud_models c WHERE c.id <> 70) = (SELECT others FROM t_before)
    AND (SELECT count(*) FROM crud_models) = (SELECT n_models FROM t_before)
    AND ((SELECT to_jsonb(c) FROM crud_models c WHERE c.id = 70) - 'allowed_ops' - 'allowed_roles_select' - 'allowed_roles_insert' - 'allowed_roles_update' - 'allowed_roles_delete')
        = ((SELECT row70 FROM t_before) - 'allowed_ops' - 'allowed_roles_select' - 'allowed_roles_insert' - 'allowed_roles_update' - 'allowed_roles_delete'));
SELECT pg_temp.ok('A the ORIGINAL row is in the backup, whole, as a DISABLE entry',
    (SELECT count(*) = 1 AND bool_and(row_data = (SELECT row70 FROM t_before)) FROM crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE'));
SELECT pg_temp.ok('A the backup table is append-only: UPDATE, DELETE and TRUNCATE raise P0095',
    pg_temp.raises('UPDATE crud_models_backup_089 SET model_name = ''x''', 'P0095') AND pg_temp.raises('DELETE FROM crud_models_backup_089', 'P0095')
    AND pg_temp.raises('TRUNCATE crud_models_backup_089', 'P0095'));

\ir 089_disable_nacimiento_gateway.sql
SELECT pg_temp.ok('B applying it AGAIN is idempotent: no second backup is taken (the backup must keep the original) and nothing changes',
    (SELECT count(*) FROM crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE') = 1
    AND (SELECT allowed_roles_insert FROM crud_models WHERE id = 70) = 'NONE');

\ir 089_rollback.sql
SELECT pg_temp.ok('C the rollback restores row 70 EXACTLY: the whole row equals the original; a RESTORE entry is recorded; the DISABLE entry is still there',
    (SELECT to_jsonb(c) FROM crud_models c WHERE c.id = 70) = (SELECT row70 FROM t_before)
    AND (SELECT count(*) FROM crud_models_backup_089 WHERE action = 'RESTORE') = 1 AND (SELECT count(*) FROM crud_models_backup_089 WHERE action = 'DISABLE') = 1
    AND (SELECT md5(coalesce(string_agg(row_to_json(c)::text, '|' ORDER BY c.id), '')) FROM crud_models c WHERE c.id <> 70) = (SELECT others FROM t_before));
\ir 089_rollback.sql
SELECT pg_temp.ok('C rolling back again when the row is not disabled does nothing (no second RESTORE entry)',
    (SELECT count(*) FROM crud_models_backup_089 WHERE action = 'RESTORE') = 1 AND (SELECT to_jsonb(c) FROM crud_models c WHERE c.id = 70) = (SELECT row70 FROM t_before));

\ir 089_disable_nacimiento_gateway.sql
SELECT pg_temp.ok('D re-applying after a rollback disables again and takes a NEW backup of the restored original (2 DISABLE entries, both equal to the original)',
    (SELECT allowed_roles_insert FROM crud_models WHERE id = 70) = 'NONE'
    AND (SELECT count(*) = 2 AND bool_and(row_data = (SELECT row70 FROM t_before)) FROM crud_models_backup_089 WHERE action = 'DISABLE'));

-- a hand-disabled row without a backup must never be adopted: simulate in a sub-transaction-like way with a second fixture
DO $$
BEGIN
    UPDATE crud_models SET allowed_ops = ARRAY[]::text[], allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE', allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
     WHERE id = 7001;
END $$;
SELECT pg_temp.ok('D a model other than id 70 (even one disabled by hand) is never touched or backed up by 089',
    (SELECT count(*) FROM crud_models_backup_089 WHERE crud_model_id <> 70) = 0
    AND (SELECT allowed_roles_insert FROM crud_models WHERE id = 7002) = 'ADMIN,EDITOR');

\echo === RESULTS
SELECT n, CASE WHEN ok THEN 'OK  ' ELSE 'FAIL' END AS result, test, CASE WHEN ok THEN NULL ELSE left(detail, 400) END AS detail FROM t_result ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM t_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_result WHERE NOT ok) THEN
        RAISE EXCEPTION '089 tests: % failure(s)', (SELECT count(*) FROM t_result WHERE NOT ok);
    END IF;
END $$;

ROLLBACK;
\echo '*** 089 tests: everything rolled back ***'
