-- 084 ROLLBACK. No DROP / DELETE: the 5 reproduction tool functions keep their names and signatures (the n8n tools
-- still call them) but their bodies become a constant answer {"status":"disabled", ...}: nothing is read, nothing is
-- written, and the agent tells the user the query is off. The parser (fn_fire_number_shape,
-- fn_estimate_birth_from_fire_number, fn_is_placeholder_birth_date), the helpers (fn_repro_*), the type
-- fire_number_estimate and the view vw_animal_effective_birth are left in place: they are read-only, harmless and are
-- replaced by a re-apply. 084 never touched a table, a column, a trigger, crud_models or any pre-existing function, so
-- there is no data to restore. Re-applying 084 restores the tools.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 084_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 084_rollback.sql  -> commit
-- Then: 084_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_list_births(text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_repro_list_births not found - 084 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_births(
    p_tenant_id text, p_user_email text, p_date_from text DEFAULT NULL, p_date_to text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las consultas de reproduccion estan desactivadas temporalmente (084 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_dam_birth_history(
    p_tenant_id text, p_user_email text, p_identifier text
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las consultas de reproduccion estan desactivadas temporalmente (084 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_summary(
    p_tenant_id text, p_user_email text, p_group_by text DEFAULT NULL, p_date_from text DEFAULT NULL, p_date_to text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las consultas de reproduccion estan desactivadas temporalmente (084 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_unregistered_historical_births(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las consultas de reproduccion estan desactivadas temporalmente (084 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_identifier_quality_report(
    p_tenant_id text, p_user_email text
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las consultas de reproduccion estan desactivadas temporalmente (084 revertida).')
$$;

DO $$
BEGIN
    IF public.sp_repro_list_births('0', 'nobody@example.test')->>'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '084 rollback: sp_repro_list_births is not disabled';
    END IF;
    RAISE NOTICE '084 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 084 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
