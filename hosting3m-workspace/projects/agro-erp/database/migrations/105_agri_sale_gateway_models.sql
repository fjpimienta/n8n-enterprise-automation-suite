-- 105_agri_sale_gateway_models.sql
-- Gateway models for the palm sales (migration 104): two read-only, ADMIN-only models for the dashboard and four restricted models for the
-- sale tables themselves. Database only: no n8n workflow, no gateway code and no frontend change; nothing calls the new models yet.
-- REQUIRES 104 (agri_sale_invoices, vw_agri_sale_summary). Aborts if missing. No table, function, trigger or data is changed.
--
-- What it creates
--   vw_agri_sale_ui_list   the browser view of the sales of a company (CREATE OR REPLACE VIEW). It carries only what the dashboard shows:
--                          id, id_company, folio, sale_date, buyer_name, quantity, unit_code, unit_price, total_amount, payment_method,
--                          ticket_ref, ticket_warning, plantation / lot ids, codes and names, status, void_reason, voided_at, is_test,
--                          created_at. It has no voucher UUID, buyer tax id, SAT state, e-mail, file path or hash. It does not filter by
--                          company itself: the gateway adds id_company = the verified company (the model lists id_company in allowed_fields).
--   crud_models rows (idempotent upsert on model_name, all with id_company in allowed_fields):
--     agri_sales             over vw_agri_sale_ui_list   ops {SELECT,GETONE,GETALL}, select ADMIN, insert/update/delete NONE
--     agri_sale_summary      over vw_agri_sale_summary   ops {SELECT,GETONE,GETALL}, select ADMIN, insert/update/delete NONE (active sales only)
--     agri_sale_invoices, agri_sale_audit, company_flags, company_issuer_rfcs
--                            restricted models: registered with no operation and no role; the procedures and the platform seeds
--                            remain the only writers.
-- Pattern: M/081_agri_expenses.sql (upsert, backup first) and the ADMIN-only reads of M/071 and M/073.
-- Not touched: every other crud_models row, the procedures and tables of migration 104, workflows, the gateway code and the frontend.
--
-- Rollback: 105_rollback.sql disables ONLY the two read models (no operation, no role); the browser view and the four restricted models stay.
-- State:    105_state_check.sql -v expect=before|applied|rolled_back (read-only). Tests: 105_tests.sql.
-- Usage:    psql -X -v ON_ERROR_STOP=1 -f 105_agri_sale_gateway_models.sql                (dry run)
--           psql -X -v ON_ERROR_STOP=1 -v apply=true -f 105_agri_sale_gateway_models.sql  (commit)

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
BEGIN
    IF to_regclass('public.crud_models') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models does not exist.';
    END IF;
    IF to_regclass('public.agri_sale_invoices') IS NULL OR to_regclass('public.agri_sale_audit') IS NULL
       OR to_regclass('public.company_flags') IS NULL OR to_regclass('public.company_issuer_rfcs') IS NULL
       OR to_regclass('public.vw_agri_sale_summary') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 104 is not applied here.';
    END IF;
    -- A model with one of these names must not already point somewhere else (it would be overwritten).
    IF EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'agri_sales' AND table_name <> 'vw_agri_sale_ui_list')
       OR EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'agri_sale_summary' AND table_name <> 'vw_agri_sale_summary')
       OR EXISTS (SELECT 1 FROM public.crud_models WHERE model_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
                                                         AND table_name <> model_name) THEN
        RAISE EXCEPTION 'ABORT: a model with one of these names already points at another table. Not touching it.';
    END IF;
    -- A different model name must not already serve the same view or tables.
    IF EXISTS (SELECT 1 FROM public.crud_models
                WHERE (table_name = 'vw_agri_sale_ui_list' AND model_name <> 'agri_sales')
                   OR (table_name = 'vw_agri_sale_summary' AND model_name <> 'agri_sale_summary')
                   OR (table_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs') AND model_name <> table_name)) THEN
        RAISE EXCEPTION 'ABORT: another model already serves one of these views or tables. Review it first.';
    END IF;
END $$;

-- Backup of the rows this migration may overwrite (first run only: a re-apply after the rollback keeps the original state).
CREATE TABLE IF NOT EXISTS crud_models_backup_20261112_105 AS
SELECT m.*, now() AS backed_up_at
  FROM crud_models m
 WHERE m.model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs');

-- 1) Browser view -------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.vw_agri_sale_ui_list AS
SELECT
    s.id,
    s.id_company,
    coalesce(s.serie, '') || coalesce(s.folio, '') AS folio,
    s.issued_at::date AS sale_date,
    s.buyer_name,
    s.quantity,
    s.unit_code,
    s.unit_price,
    s.total_cents::numeric / 100 AS total_amount,
    s.payment_method,
    s.ticket_ref,
    s.ticket_warning,
    s.plantation_id,
    p.plantation_code,
    p.plantation_name,
    s.lot_id,
    l.lot_code,
    l.lot_name,
    s.status,
    s.void_reason,
    s.voided_at,
    s.is_test,
    s.created_at
FROM public.agri_sale_invoices s
LEFT JOIN public.agri_plantations p ON p.id = s.plantation_id AND p.id_company = s.id_company
LEFT JOIN public.agri_lots l ON l.id = s.lot_id AND l.id_company = s.id_company;
COMMENT ON VIEW public.vw_agri_sale_ui_list IS
  '105: sales of the dashboard (voided sales included with their status). Reduced column set; id_company is filtered by the gateway (ADMIN-only read model agri_sales).';

-- 2) Models (idempotent upsert; id_company is in allowed_fields of every row) --------------------------------

INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json,
                         allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                         allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  -- Read models for the dashboard: ADMIN only, no write operation of any kind.
  ('agri_sales', 'vw_agri_sale_ui_list', 'id',
   '["id_company","sale_date","status","plantation_id","lot_id","ticket_ref"]', NULL, '{}',
   '{SELECT,GETONE,GETALL}', '{"pre":[],"post":[]}',
   'ADMIN', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('agri_sale_summary', 'vw_agri_sale_summary', 'id',
   '["id_company","grain","period_start","plantation_id","lot_id"]', NULL, '{}',
   '{SELECT,GETONE,GETALL}', '{"pre":[],"post":[]}',
   'ADMIN', 'NONE', 'NONE', 'NONE', '[]', false, true),
  -- Restricted models: the four tables of migration 104 are registered with no operation and no role.
  ('agri_sale_invoices', 'agri_sale_invoices', 'id', '["id_company"]', NULL, '{}',
   '{}', '{"pre":[],"post":[]}', 'NONE', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('agri_sale_audit', 'agri_sale_audit', 'id', '["id_company"]', NULL, '{}',
   '{}', '{"pre":[],"post":[]}', 'NONE', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('company_flags', 'company_flags', 'id_company', '["id_company"]', NULL, '{}',
   '{}', '{"pre":[],"post":[]}', 'NONE', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('company_issuer_rfcs', 'company_issuer_rfcs', 'id', '["id_company"]', NULL, '{}',
   '{}', '{"pre":[],"post":[]}', 'NONE', 'NONE', 'NONE', 'NONE', '[]', false, true)
ON CONFLICT (model_name) DO UPDATE SET
    table_name = EXCLUDED.table_name, primary_key = EXCLUDED.primary_key,
    allowed_fields = EXCLUDED.allowed_fields, default_filter = EXCLUDED.default_filter,
    schema_json = EXCLUDED.schema_json, allowed_ops = EXCLUDED.allowed_ops, hooks = EXCLUDED.hooks,
    allowed_roles_select = EXCLUDED.allowed_roles_select, allowed_roles_insert = EXCLUDED.allowed_roles_insert,
    allowed_roles_update = EXCLUDED.allowed_roles_update, allowed_roles_delete = EXCLUDED.allowed_roles_delete,
    joins = EXCLUDED.joins, is_global = EXCLUDED.is_global, sp_requires_tenant = EXCLUDED.sp_requires_tenant;

-- 3) Checks -------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_cols text;
BEGIN
    IF (SELECT count(*) FROM crud_models WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')) <> 6 THEN
        RAISE EXCEPTION '105: expected 6 model rows';
    END IF;
    IF EXISTS (SELECT 1 FROM crud_models
                WHERE model_name IN ('agri_sales', 'agri_sale_summary', 'agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs')
                  AND NOT (allowed_fields ? 'id_company')) THEN
        RAISE EXCEPTION '105: every model must list id_company in allowed_fields';
    END IF;
    IF (SELECT count(*) FROM crud_models
         WHERE model_name IN ('agri_sales', 'agri_sale_summary') AND allowed_ops = '{SELECT,GETONE,GETALL}'
           AND allowed_roles_select = 'ADMIN' AND allowed_roles_insert = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
           AND NOT (allowed_fields ? 'id')) <> 2 THEN
        RAISE EXCEPTION '105: the read models do not have the expected operations / roles';
    END IF;
    IF (SELECT count(*) FROM crud_models
         WHERE model_name IN ('agri_sale_invoices', 'agri_sale_audit', 'company_flags', 'company_issuer_rfcs') AND table_name = model_name
           AND cardinality(allowed_ops) = 0 AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE'
           AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE') <> 4 THEN
        RAISE EXCEPTION '105: the restricted models must have no operation and no role';
    END IF;
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols
      FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';
    IF v_cols <> 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at' THEN
        RAISE EXCEPTION '105: unexpected columns in vw_agri_sale_ui_list: %', v_cols;
    END IF;
    RAISE NOTICE '105: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 105 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 105 rolled back ***'
\endif
\endif
