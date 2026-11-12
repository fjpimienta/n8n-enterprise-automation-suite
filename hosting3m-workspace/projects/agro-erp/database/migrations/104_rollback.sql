-- 104 ROLLBACK. No DROP / DELETE / TRUNCATE: the three public procedures keep their signatures and answer 'disabled'.
-- The tables, their rows, the guard triggers, the audit trail and the views stay (append-only records of what was registered).
-- Re-applying 104 restores the procedures and keeps the rows.
-- Usage: psql -v ON_ERROR_STOP=1 -f 104_rollback.sql (dry run) | -v apply=true (commit). Then 104_state_check.sql -v expect=rolled_back
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_agri_register_sale not found - 104 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_register_sale(
    p_tenant_id integer, p_actor_email text, p_parsed jsonb, p_sat_status text, p_original_path text, p_source_sha256 text
)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'El registro de ventas esta desactivado temporalmente (104 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_agri_void_sale(p_tenant_id integer, p_actor_email text, p_sale_id uuid, p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT jsonb_build_object('status', 'disabled', 'message', 'La anulacion de ventas esta desactivada temporalmente (104 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_agri_sales_balance(
    p_tenant_id integer, p_date_from date, p_date_to date, p_grain varchar, p_plantation_id uuid, p_lot_id uuid, p_actor_email varchar
)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('success', false, 'status', 'disabled', 'message', 'El balance de ventas esta desactivado temporalmente (104 revertida).')
$$;

\if :apply
COMMIT;
\echo '*** 104 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 104 rollback rolled back ***'
\endif
