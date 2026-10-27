-- 085 ROLLBACK. No DROP / DELETE / TRUNCATE: the 8 empadre tool functions keep their names and signatures (the n8n
-- tools still call them) but their bodies become a constant answer {"status":"disabled", ...}: nothing is read, nothing
-- is written, and the agent tells the user the function is off.
-- The three tables (repro_empadre_config, repro_empadre_entries, repro_empadre_voids), their rows, triggers and the
-- internal helpers (fn_repro_today, fn_repro_member_role, fn_repro_empadre_cfg, fn_repro_resolve_animal,
-- fn_repro_empadre_eval, fn_repro_empadre_check_item, fn_repro_empadre_date) are LEFT IN PLACE on purpose: the entries are
-- append-only records of what staff reported, and they are the only copy. 085 never touched an existing table, column,
-- trigger, crud_models, a pre-existing function or any existing row, so there is nothing to restore.
-- Re-applying 085 (CREATE OR REPLACE / IF NOT EXISTS) restores the tools and keeps the rows.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 085_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 085_rollback.sql  -> commit
-- Then: 085_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_list_open_cows(text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_repro_list_open_cows not found - 085 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_repro_empadre_get_config(
    p_tenant_id text, p_user_email text
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_empadre_set_config(
    p_tenant_id text, p_user_email text, p_min_age_months text DEFAULT NULL, p_min_weight_kg text DEFAULT NULL, p_weight_stale_days text DEFAULT NULL, p_empadre_window_days text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_heifers_eligible_for_empadre(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_log_empadre_entry(
    p_tenant_id text, p_user_email text, p_heifer_identifier text, p_bull_identifier text DEFAULT NULL, p_entry_date text DEFAULT NULL, p_method text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_log_empadre_entry_batch(
    p_tenant_id text, p_user_email text, p_items text, p_entry_date text DEFAULT NULL, p_bull_identifier text DEFAULT NULL, p_method text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_void_empadre_entry(
    p_tenant_id text, p_user_email text, p_entry_id text, p_reason text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_empadre_entries(
    p_tenant_id text, p_user_email text, p_heifer_identifier text DEFAULT NULL, p_include_voided text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_open_cows(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de empadre estan desactivadas temporalmente (085 revertida).')
$$;

DO $$
BEGIN
    IF public.sp_repro_list_open_cows('0', 'nobody@example.test')->>'status' IS DISTINCT FROM 'disabled'
       OR public.sp_repro_log_empadre_entry('0', 'nobody@example.test', 'x')->>'status' IS DISTINCT FROM 'disabled'
       OR public.sp_void_empadre_entry('0', 'nobody@example.test', 'x', 'x')->>'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '085 rollback: a tool is not disabled';
    END IF;
    RAISE NOTICE '085 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 085 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
