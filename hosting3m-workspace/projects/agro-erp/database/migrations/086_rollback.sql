-- 086 ROLLBACK. No DROP / DELETE / TRUNCATE: the 5 phase-3 procedures keep their names and signatures (the n8n tools
-- still call them) but their bodies become a constant answer {"status":"disabled", ...}: nothing is read, nothing is
-- written, and the agent tells the user the function is off.
-- LEFT IN PLACE on purpose: the tables repro_condition_codes and palpation_repro_details with all their rows and triggers
-- (the details are append-only records of what staff reported, and the only copy), and the helpers fn_repro_norm_code,
-- fn_uterine_split, fn_parse_uterine_code, fn_repro_palpations, fn_trg_palp_details_tenant.
-- 086 never touched an existing table, column, trigger, crud_models, a pre-existing function (sp_log_palpation_event
-- included) or any existing row, so there is nothing to restore. The existing log_palpation_event and
-- log_palpation_event_batch tools keep working exactly as before, with or without 086.
-- Re-applying 086 (CREATE OR REPLACE / IF NOT EXISTS) restores the tools and keeps the rows.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 086_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 086_rollback.sql  -> commit
-- Then: 086_state_check.sql -v expect=rolled_back
-- The seed (086_seed_tenant5_uterine_codes.sql) is separate: this rollback does not remove the mapping rows.

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_list_palpation_due(text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_repro_list_palpation_due not found - 086 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_repro_log_palpation_batch(
    p_tenant_id text, p_user_email text, p_items text, p_palpation_date text DEFAULT NULL, p_technician_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'El registro de palpaciones con condicion uterina esta desactivado temporalmente (086 revertida). Usa log_palpation_event_batch.')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_palpation_due(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de palpacion pendiente estan desactivadas temporalmente (086 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_upcoming_calvings(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos proximos estan desactivadas temporalmente (086 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_unmapped_uterine_codes(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'La lista de codigos uterinos sin confirmar esta desactivada temporalmente (086 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_condition_code_set(
    p_tenant_id text, p_user_email text, p_code text, p_repro_condition text, p_source text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'La confirmacion de codigos uterinos esta desactivada temporalmente (086 revertida).')
$$;

DO $$
BEGIN
    IF public.sp_repro_list_palpation_due('0', 'nobody@example.test')->>'status' IS DISTINCT FROM 'disabled'
       OR public.sp_repro_log_palpation_batch('0', 'nobody@example.test', '[]')->>'status' IS DISTINCT FROM 'disabled'
       OR public.sp_repro_condition_code_set('0', 'nobody@example.test', 'x', 'OTRO')->>'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '086 rollback: a tool is not disabled';
    END IF;
    RAISE NOTICE '086 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 086 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
