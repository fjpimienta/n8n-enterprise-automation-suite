-- 111 ROLLBACK. No DROP, no DELETE, no TRUNCATE: the four procedures are REPLACED by a fail-closed stub with the same signatures, so a caller
-- that already uses them always receives {status: disabled} and nothing is written. Tables, helper functions and the void trigger stay: the link
-- table keeps its rows, and voiding an invoice-backed expense still voids its link. Re-applying 111_palm_expense_invoices.sql restores the procedures.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 111_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_rollback.sql  -> commit
-- Then: 111_state_check.sql -v expect=rolled_back

\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
BEGIN
    IF to_regprocedure('public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111 rollback: sp_agri_expense_invoice_register not found - 111 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_draft_create(
    p_tenant_id text, p_user_email text, p_channel text, p_invoice text, p_original_path text, p_sat_status text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    -- 111 palm expense invoice (rolled back)
    RETURN jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas como gasto esta desactivado.');
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_preview(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL, p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    -- 111 palm expense invoice (rolled back)
    RETURN jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas como gasto esta desactivado.');
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_confirm(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL, p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    -- 111 palm expense invoice (rolled back)
    RETURN jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas como gasto esta desactivado.');
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_register(
    p_tenant_id text, p_user_email text, p_invoice text, p_original_path text, p_sat_status text,
    p_category text DEFAULT NULL, p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL,
    p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL, p_confirmed text DEFAULT 'false'
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    -- 111 palm expense invoice (rolled back)
    RETURN jsonb_build_object('status', 'disabled', 'message', 'El registro de facturas como gasto esta desactivado.');
END $$;

DO $$
BEGIN
    IF public.sp_agri_expense_invoice_register('0', 'x', '{}', 'x', 'x') ->> 'status' IS DISTINCT FROM 'disabled'
       OR public.sp_agri_expense_invoice_preview('0', 'x', 'x', 'x') ->> 'status' IS DISTINCT FROM 'disabled'
       OR public.sp_agri_expense_invoice_confirm('0', 'x', 'x', 'x') ->> 'status' IS DISTINCT FROM 'disabled'
       OR public.sp_agri_expense_invoice_draft_create('0', 'x', 'x', '{}', 'x', 'x') ->> 'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '111 rollback: the stubs are not in place';
    END IF;
    RAISE NOTICE '111 rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 111 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 111 rollback rolled back ***'
\endif
\endif
