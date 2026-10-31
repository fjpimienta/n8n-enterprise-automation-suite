-- 092 ROLLBACK. No DROP / DELETE / TRUNCATE: the three procedures keep their signatures and answer {"status":"disabled"}.
-- expense_invoice_drafts, its rows and triggers stay. Re-applying 092 restores the procedures and keeps the rows. 091 is untouched.
-- Usage: psql -v ON_ERROR_STOP=1 -f 092_rollback.sql (dry run) | -v apply=true (commit). Then 092_state_check.sql -v expect=rolled_back
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_expense_invoice_confirm(text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_expense_invoice_confirm not found - 092 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_expense_invoice_draft_create(
    p_tenant_id text, p_user_email text, p_channel text, p_invoice text, p_original_path text, p_sat_status text
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas esta desactivado temporalmente (092 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_expense_invoice_preview(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text, p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas esta desactivado temporalmente (092 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_expense_invoice_confirm(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text, p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas esta desactivado temporalmente (092 revertida).')
$$;

\if :apply
COMMIT;
\echo '*** 092 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 092 rollback rolled back ***'
\endif
