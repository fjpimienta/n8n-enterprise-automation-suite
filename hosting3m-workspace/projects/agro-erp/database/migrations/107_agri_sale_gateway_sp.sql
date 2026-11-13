-- 107_agri_sale_gateway_sp.sql
-- Gateway models for the two palm-sale procedures of migration 104: the void of a sale (sp_agri_void_sale) and the sales balance
-- (sp_agri_sales_balance). Two crud_models rows, ADMIN only. Database only: no table, view, function, trigger or data is changed.
-- REQUIRES 104 (both procedures, with the exact signatures below). Aborts if missing.
--
-- What it registers (idempotent upsert on model_name; every column copied from the existing rows agri_void_expense / agri_expense_balance of M/081)
--   agri_sale_void     procedure sp_agri_void_sale     primary_key sale_id    allowed_fields sale_id, reason, actor_email
--   agri_sale_balance  procedure sp_agri_sales_balance primary_key date_from  allowed_fields date_from, date_to, grain, plantation_id, lot_id, actor_email
--   both: allowed_ops {INSERT} (the gateway validates call_sp as an insert), allowed_roles_insert ADMIN, select / update / delete NONE,
--         is_global false, sp_requires_tenant true, no default filter, no joins, no hooks.
-- The company and the actor e-mail are never part of the client payload: the gateway takes the company from the verified header and the
-- e-mail from the verified token (gateway entries added by the same pull request); the procedures check the ADMIN role again.
-- Nothing calls the new models until the gateway entries are published (Part 2 of the runbook).
--
-- Rollback: 107_rollback.sql disables ONLY the two rows (no operation, no role); nothing is deleted.
-- State:    107_state_check.sql -v expect=before|applied|rolled_back (read-only). Tests: 107_tests.sql. Static check: 107_static_check.sh.
-- Usage:    psql -X -v ON_ERROR_STOP=1 -f 107_agri_sale_gateway_sp.sql                (dry run)
--           psql -X -v ON_ERROR_STOP=1 -v apply=true -f 107_agri_sale_gateway_sp.sql  (commit)

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions and backup ---------------------------------------------------------------------------

DO $$
DECLARE
    v_sig text;
BEGIN
    IF to_regclass('public.crud_models') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models does not exist.';
    END IF;
    -- Exactly one procedure of each name, with the expected arguments and result (pg_proc).
    SELECT string_agg(pg_get_function_identity_arguments(p.oid), ' | ') INTO v_sig
      FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_agri_void_sale';
    IF v_sig IS DISTINCT FROM 'p_tenant_id integer, p_actor_email text, p_sale_id uuid, p_reason text' THEN
        RAISE EXCEPTION 'ABORT: sp_agri_void_sale is missing or has other arguments (found: %). Migration 104 is required.', coalesce(v_sig, 'none');
    END IF;
    SELECT string_agg(pg_get_function_identity_arguments(p.oid), ' | ') INTO v_sig
      FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_agri_sales_balance';
    IF v_sig IS DISTINCT FROM 'p_tenant_id integer, p_date_from date, p_date_to date, p_grain character varying, p_plantation_id uuid, p_lot_id uuid, p_actor_email character varying' THEN
        RAISE EXCEPTION 'ABORT: sp_agri_sales_balance is missing or has other arguments (found: %). Migration 104 is required.', coalesce(v_sig, 'none');
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('sp_agri_void_sale', 'sp_agri_sales_balance')
                  AND p.prorettype <> 'jsonb'::regtype) THEN
        RAISE EXCEPTION 'ABORT: the procedures must return jsonb.';
    END IF;
    -- A model with one of these names must not already point somewhere else (it would be overwritten).
    IF EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'agri_sale_void' AND table_name <> 'sp_agri_void_sale')
       OR EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'agri_sale_balance' AND table_name <> 'sp_agri_sales_balance') THEN
        RAISE EXCEPTION 'ABORT: a model with one of these names already points at another object. Not touching it.';
    END IF;
    -- A different model name must not already serve the same procedures.
    IF EXISTS (SELECT 1 FROM public.crud_models
                WHERE (table_name = 'sp_agri_void_sale' AND model_name <> 'agri_sale_void')
                   OR (table_name = 'sp_agri_sales_balance' AND model_name <> 'agri_sale_balance')) THEN
        RAISE EXCEPTION 'ABORT: another model already serves one of these procedures. Review it first.';
    END IF;
END $$;

-- Backup of the rows this migration may overwrite (first run only: a re-apply after the rollback keeps the original state).
CREATE TABLE IF NOT EXISTS crud_models_backup_20261112_107 AS
SELECT m.*, now() AS backed_up_at
  FROM crud_models m
 WHERE m.model_name IN ('agri_sale_void', 'agri_sale_balance');

-- 1) Models (idempotent upsert) ---------------------------------------------------------------------------------

INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json,
                         allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                         allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  ('agri_sale_void', 'sp_agri_void_sale', 'sale_id',
   '["sale_id","reason","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN', 'NONE', 'NONE', '[]', false, true),
  -- A read, but call_sp is validated as INSERT by the gateway.
  ('agri_sale_balance', 'sp_agri_sales_balance', 'date_from',
   '["date_from","date_to","grain","plantation_id","lot_id","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN', 'NONE', 'NONE', '[]', false, true)
ON CONFLICT (model_name) DO UPDATE SET
    table_name = EXCLUDED.table_name, primary_key = EXCLUDED.primary_key,
    allowed_fields = EXCLUDED.allowed_fields, default_filter = EXCLUDED.default_filter,
    schema_json = EXCLUDED.schema_json, allowed_ops = EXCLUDED.allowed_ops, hooks = EXCLUDED.hooks,
    allowed_roles_select = EXCLUDED.allowed_roles_select, allowed_roles_insert = EXCLUDED.allowed_roles_insert,
    allowed_roles_update = EXCLUDED.allowed_roles_update, allowed_roles_delete = EXCLUDED.allowed_roles_delete,
    joins = EXCLUDED.joins, is_global = EXCLUDED.is_global, sp_requires_tenant = EXCLUDED.sp_requires_tenant;

-- 2) Checks -------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance')) <> 2 THEN
        RAISE EXCEPTION '107: expected 2 model rows';
    END IF;
    IF (SELECT count(*) FROM crud_models
         WHERE ((model_name = 'agri_sale_void' AND table_name = 'sp_agri_void_sale' AND primary_key = 'sale_id'
                 AND allowed_fields = '["sale_id","reason","actor_email"]'::jsonb)
             OR (model_name = 'agri_sale_balance' AND table_name = 'sp_agri_sales_balance' AND primary_key = 'date_from'
                 AND allowed_fields = '["date_from","date_to","grain","plantation_id","lot_id","actor_email"]'::jsonb))
           AND allowed_ops = '{INSERT}' AND allowed_roles_insert = 'ADMIN' AND allowed_roles_select = 'NONE'
           AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE' AND is_global = false AND sp_requires_tenant = true
           AND default_filter IS NULL AND joins = '[]'::jsonb AND schema_json = '{}'::jsonb AND hooks = '{"pre":[],"post":[]}'::jsonb) <> 2 THEN
        RAISE EXCEPTION '107: the two models do not have the expected values';
    END IF;
    RAISE NOTICE '107: OK';
END $$;

SELECT model_name, table_name, allowed_ops, allowed_roles_insert, allowed_fields
  FROM crud_models WHERE model_name IN ('agri_sale_void', 'agri_sale_balance') ORDER BY model_name;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 107 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 107 rolled back ***'
\endif
\endif
