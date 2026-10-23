-- 082_reject_palm_in_livestock_tools.sql
-- Palm phase 2b, stage 1: the livestock chat tools (v6/MCP Server Cattle) must never act on a palm company.
--
-- Incident (production, 2026-10-21): with company 10 (palm, test tenant) active, the Web Chat called
-- register_ranch_expense with tenant_id 10 and stored a palm expense in cattle_expenses. Company 7 (a real palm
-- client) was exposed to the same.
--
-- fn_reject_palm_company(p_tenant_id) raises P0094 with a clear Spanish message when the company is a palm
-- company (fn_company_business_domain, migration 081) and returns true otherwise (livestock, unknown domain,
-- NULL or a company that does not exist: those cases keep the tools' current behavior).
--
-- Every livestock tool calls it as the FIRST condition of the WHERE of the statement that runs the procedure,
-- the INSERT or the read, with the raw tenant parameter only (e.g. `WHERE fn_reject_palm_company($1::int) AND
-- EXISTS (...)`). With no column references and a STABLE function, Postgres plans it as a one-time filter
-- evaluated before any row is read or written (verified with EXPLAIN in 082_tests.sql and on every tool).
-- STABLE, not VOLATILE, on purpose: a volatile function would be evaluated per row and never run when the
-- query finds no rows (exactly the palm case), giving an empty answer instead of the message.
--
-- Error code: P0094 (P0090-P0093 are migration 081).
-- Rollback: 082_rollback.sql replaces the body with `RETURN true` (no DROP): the tools behave as before 082
-- without touching n8n. Re-applying 082 restores the check.
-- State:    082_state_check.sql -v expect=before|applied|rolled_back (read-only).
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 082_reject_palm_in_livestock_tools.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 082_reject_palm_in_livestock_tools.sql  -> commit
-- 082_tests.sql includes this file with `embedded` set (the tests own the transaction and roll it back).

\set ON_ERROR_STOP on
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
    IF to_regprocedure('public.fn_company_business_domain(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 081 (fn_company_business_domain) is not applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_reject_palm_company(p_tenant_id integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF public.fn_company_business_domain(p_tenant_id) = 'PALM' THEN
        RAISE EXCEPTION 'Esta empresa es de palma; usa el registro de palma. Las herramientas de ganadería no aplican a plantaciones.'
            USING ERRCODE = 'P0094';
    END IF;
    RETURN true;
END;
$$;
COMMENT ON FUNCTION public.fn_reject_palm_company(integer) IS
  'Guard of the livestock chat tools: raises P0094 for a palm company, true otherwise. Rolled back by 082_rollback.sql (body -> RETURN true).';

DO $$
BEGIN
    IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.fn_reject_palm_company(integer)'::regprocedure) <> 's' THEN
        RAISE EXCEPTION '082: fn_reject_palm_company must be STABLE';
    END IF;
    IF NOT public.fn_reject_palm_company(NULL) THEN
        RAISE EXCEPTION '082: NULL tenant must pass';
    END IF;
    RAISE NOTICE '082: OK';
END $$;

\if :{?embedded}
\echo '*** 082 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 082 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
