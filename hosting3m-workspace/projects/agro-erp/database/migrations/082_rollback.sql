-- 082 ROLLBACK. No DROP: fn_reject_palm_company keeps its name and signature (the n8n tools still call it) but
-- its body becomes `RETURN true`, so every livestock tool behaves exactly as before 082 without touching n8n.
-- Re-applying 082 restores the check.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 082_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 082_rollback.sql  -> commit
-- Then: 082_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.fn_reject_palm_company(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: fn_reject_palm_company not found - 082 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_reject_palm_company(p_tenant_id integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- 082 rolled back: the palm check is disabled (re-apply 082_reject_palm_in_livestock_tools.sql to restore it).
    RETURN true;
END;
$$;
COMMENT ON FUNCTION public.fn_reject_palm_company(integer) IS
  'ROLLED BACK (082_rollback.sql): always true. Re-apply 082 to restore the palm check.';

SELECT public.fn_reject_palm_company(10) AS company_10_passes;

\if :apply
COMMIT;
\echo '*** 082 ROLLBACK COMMITTED - verify with 082_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 082 ROLLBACK DRY RUN: nothing changed ***'
\endif
