-- 103_tests.sql
-- Tests for 103 (gateway model of the panel livestock intake). LOCAL / throw-away database ONLY. Everything happens inside ONE
-- transaction that ends in ROLLBACK; nothing is kept. If migration 102 (and its 099 helpers) are missing, they are applied
-- first inside the same transaction. A final read-only block proves that nothing was left behind.
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 103_tests.sql
-- A failed assertion raises 'FAIL [label]' and stops the run (the open transaction is discarded with the connection).
-- NOT EXECUTED by the author of the file: run it and report the output (see 103_RUNBOOK.md).
-- The gateway itself (n8n) is not exercised here: the role check of the "Security Validation" node is reproduced with the same
-- string logic (split on commas, trim, upper-case, membership) to prove what the row grants.
\set ON_ERROR_STOP on

-- What the database looked like before this run (compared again after the ROLLBACK, outside the transaction).
SELECT count(*) AS models_before FROM crud_models \gset
SELECT count(*) AS panel_rows_before FROM crud_models WHERE model_name = 'register_livestock_panel' \gset
SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS others_before
  FROM crud_models c WHERE c.model_name <> 'register_livestock_panel' \gset

BEGIN;

CREATE TEMP TABLE t103_res (label text);
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL [%]', p_label;
    END IF;
    INSERT INTO t103_res VALUES (p_label);
    RAISE NOTICE 'PASS [%]', p_label;
END $$;

-- The role check of Security Validation for call_sp (validated as INSERT): the role must be in allowed_roles_insert.
CREATE FUNCTION pg_temp.role_allowed(p_role text) RETURNS boolean LANGUAGE sql AS $$
    SELECT upper(p_role) = ANY (SELECT upper(btrim(r)) FROM unnest(string_to_array(m.allowed_roles_insert, ',')) r)
      FROM crud_models m
     WHERE m.model_name = 'register_livestock_panel' AND 'insert' = ANY (SELECT lower(o) FROM unnest(m.allowed_ops) o)
$$;

-- ---------------------------------------------------------------------------------------------
-- Prerequisites: 102 (and 099) only if missing, then start from "before" whatever the database had
-- ---------------------------------------------------------------------------------------------
\set embedded 1
SELECT (to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL) AS need102 \gset
SELECT (to_regprocedure('public.fn_livestock_chat_ctx(text,text)') IS NULL) AS need099 \gset
\if :need102
\if :need099
\ir 099_livestock_regularization.sql
\endif
\ir 102_panel_livestock_sp.sql
\endif
\ir 103_rollback.sql
SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS others_start
  FROM crud_models c WHERE c.model_name <> 'register_livestock_panel' \gset
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 0, 'A1 the test starts without the model');

-- ---------------------------------------------------------------------------------------------
-- B. Apply
-- ---------------------------------------------------------------------------------------------
\set expect before
\ir 103_state_check.sql
SELECT pg_temp.ok(true, 'B1 state check: before');
\ir 103_panel_livestock_gateway_model.sql
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 1, 'B2 exactly one model row');
SELECT pg_temp.ok((SELECT table_name = 'sp_register_livestock_panel' AND primary_key = 'ear_tag'
                          AND allowed_ops = '{INSERT}'::text[] AND hooks = '{"pre":[],"post":[]}'::jsonb
                          AND schema_json = '{}'::jsonb AND joins = '[]'::jsonb AND default_filter IS NULL
                     FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'B3 table_name, only INSERT, no hooks, empty schema_json, no joins');
SELECT pg_temp.ok((SELECT allowed_roles_select = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                          AND allowed_roles_insert = 'ADMIN,EDITOR'
                     FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'B4 roles: insert ADMIN,EDITOR; select / update / delete NONE');
SELECT pg_temp.ok((SELECT is_global = false AND sp_requires_tenant = true FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'B5 not global and the tenant is required');
SELECT pg_temp.ok((SELECT allowed_fields = '["upp","lot","species","category","business_model","ear_tag","fire_number","electronic_rfid","weight_kg","birth_date","origin_upp","tb_test_date","br_test_date","notes","confirmed","preview_hash","force_duplicate","actor_email"]'::jsonb
                     FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'B6 allowed_fields: the 18 arguments in signature order (confirmed, preview_hash and force_duplicate included)');
SELECT pg_temp.ok((SELECT NOT (allowed_fields ? 'id') AND NOT (allowed_fields ? 'tenant_id') AND NOT (allowed_fields ? 'id_company')
                     FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'B7 the model never accepts id, tenant_id or id_company from the client');
SELECT pg_temp.ok((SELECT count(*) FROM crud_models) = :models_before - :panel_rows_before + 1, 'B8 one row added, none removed');
SELECT pg_temp.ok((SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
                     FROM crud_models c WHERE c.model_name <> 'register_livestock_panel') = :'others_start',
                  'B9 every other crud_models row is identical');

-- ---------------------------------------------------------------------------------------------
-- C. What the row grants (same string logic as Security Validation)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.role_allowed('ADMIN') AND pg_temp.role_allowed('editor'), 'C1 ADMIN and EDITOR (any case) are allowed');
SELECT pg_temp.ok(NOT coalesce(pg_temp.role_allowed('OWNER'), false) AND NOT coalesce(pg_temp.role_allowed('CUSTOMER'), false)
                  AND NOT coalesce(pg_temp.role_allowed('VIEWER'), false) AND NOT coalesce(pg_temp.role_allowed(''), false),
                  'C2 OWNER (not widened), CUSTOMER and unknown roles are refused');
SELECT pg_temp.ok((SELECT NOT ('select' = ANY (SELECT lower(o) FROM unnest(allowed_ops) o))
                          AND NOT ('update' = ANY (SELECT lower(o) FROM unnest(allowed_ops) o))
                          AND NOT ('delete' = ANY (SELECT lower(o) FROM unnest(allowed_ops) o))
                          AND NOT ('getall' = ANY (SELECT lower(o) FROM unnest(allowed_ops) o))
                     FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'C3 the model cannot be read, updated or deleted through the gateway');
SELECT pg_temp.ok((SELECT ('insert' = ANY (SELECT lower(o) FROM unnest(allowed_ops) o)) FROM crud_models WHERE model_name = 'register_livestock_panel'),
                  'C4 insert is allowed (call_sp is validated as insert)');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM crud_models WHERE sp_requires_tenant IS NOT TRUE AND model_name = 'register_livestock_panel'),
                  'C5 the tenant is required (fail-closed)');

-- ---------------------------------------------------------------------------------------------
-- D. State check, idempotence
-- ---------------------------------------------------------------------------------------------
\set expect applied
\ir 103_state_check.sql
SELECT pg_temp.ok(true, 'D1 state check: applied');
SELECT row_to_json(c)::text AS row_after_first FROM crud_models c WHERE model_name = 'register_livestock_panel' \gset
\ir 103_panel_livestock_gateway_model.sql
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 1
                  AND (SELECT row_to_json(c)::text FROM crud_models c WHERE model_name = 'register_livestock_panel') = :'row_after_first',
                  'D2 a second apply is harmless (one row, same values, same id)');

-- ---------------------------------------------------------------------------------------------
-- E. Preconditions (each refusal is provoked inside a savepoint and undone). psql's ERROR variable is true when the last SQL
--    statement of the included file failed: with the precondition refusing, the rest of the file fails inside the aborted
--    transaction; if the precondition did NOT refuse, the last statement (the final check) would succeed and ERROR stays false.
-- ---------------------------------------------------------------------------------------------
\set ON_ERROR_STOP off
SAVEPOINT s_nofn;
DROP FUNCTION public.sp_register_livestock_panel(integer, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text);
DELETE FROM crud_models WHERE model_name = 'register_livestock_panel';
\ir 103_panel_livestock_gateway_model.sql
\set refused_nofn :ERROR
ROLLBACK TO SAVEPOINT s_nofn;
\set ON_ERROR_STOP on
SELECT pg_temp.ok(:refused_nofn, 'E1 without the function of 102 the migration refuses to run');
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 1
                  AND to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL,
                  'E2 the savepoint restored the function and the row');

\set ON_ERROR_STOP off
SAVEPOINT s_conflict;
UPDATE crud_models SET table_name = 'something_else' WHERE model_name = 'register_livestock_panel';
\ir 103_panel_livestock_gateway_model.sql
\set refused_conflict :ERROR
ROLLBACK TO SAVEPOINT s_conflict;
\set ON_ERROR_STOP on
SELECT pg_temp.ok(:refused_conflict, 'E3 a model with this name that points elsewhere is refused (not overwritten)');
SELECT pg_temp.ok((SELECT table_name FROM crud_models WHERE model_name = 'register_livestock_panel') = 'sp_register_livestock_panel',
                  'E4 the savepoint restored the row');

-- ---------------------------------------------------------------------------------------------
-- F. Rollback
-- ---------------------------------------------------------------------------------------------
\ir 103_rollback.sql
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 0, 'F1 the rollback removes the row');
SELECT pg_temp.ok((SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
                     FROM crud_models c WHERE c.model_name <> 'register_livestock_panel') = :'others_start',
                  'F2 the rollback touched no other row');
SELECT pg_temp.ok(to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL,
                  'F3 the rollback keeps the function of 102');
\ir 103_rollback.sql
SELECT pg_temp.ok(true, 'F4 running the rollback twice is harmless');
\set expect before
\ir 103_state_check.sql
SELECT pg_temp.ok(true, 'F5 state check: before');
\ir 103_panel_livestock_gateway_model.sql
SELECT pg_temp.ok((SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = 1
                  AND pg_temp.role_allowed('EDITOR'), 'F6 re-applying after the rollback restores the model');

-- ---------------------------------------------------------------------------------------------
SELECT count(*) AS passed FROM t103_res \gset
\echo
\echo *** 103 TESTS: :passed assertions passed; rolling back, nothing is kept ***
ROLLBACK;

-- ---------------------------------------------------------------------------------------------
-- G. End of the run leaves no trace (outside the transaction, read-only)
-- ---------------------------------------------------------------------------------------------
BEGIN READ ONLY;
SELECT (SELECT count(*) FROM crud_models) = :models_before
   AND (SELECT count(*) FROM crud_models WHERE model_name = 'register_livestock_panel') = :panel_rows_before
   AND (SELECT coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty')
          FROM crud_models c WHERE c.model_name <> 'register_livestock_panel') = :'others_before' AS no_trace \gset
COMMIT;
\if :no_trace
\echo *** 103 TESTS: no trace left (crud_models is as before the run) ***
\else
\echo *** 103 TESTS FAILED: the run left something behind ***
SELECT 1 / 0;
\endif
