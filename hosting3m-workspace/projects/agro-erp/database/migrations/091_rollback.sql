-- 091 ROLLBACK. No DROP / DELETE / TRUNCATE: both functions keep their signatures and answer {"status":"disabled"}.
-- company_tax_ids, expense_invoices, their rows and triggers stay (append-only records of what was registered; cattle_expenses rows
-- created by the procedure are untouched). Re-applying 091 restores the functions and keeps the rows.
-- Usage: psql -v ON_ERROR_STOP=1 -f 091_rollback.sql (dry run) | -v apply=true (commit). Then 091_state_check.sql -v expect=rolled_back
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_expense_invoice_register not found - 091 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_company_tax_id_set(
    p_tenant_id text, p_user_email text, p_rfc text, p_label text DEFAULT NULL, p_active text DEFAULT 'true'
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de RFC esta desactivado temporalmente (091 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_expense_invoice_register(
    p_tenant_id text, p_user_email text, p_invoice text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL,
    p_original_path text DEFAULT NULL, p_sat_status text DEFAULT NULL, p_confirmed text DEFAULT 'false'
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas esta desactivado temporalmente (091 revertida).')
$$;

\if :apply
COMMIT;
\echo '*** 091 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 091 rollback rolled back ***'
\endif
