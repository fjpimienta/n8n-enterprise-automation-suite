-- 095_hotel_tickets_drop_default.sql: removes the DEFAULT 1 so a ticket can NEVER be created without an explicit company.
-- RUN ONLY after the patched v5 workflow is live and verified (it always sends the token's company).
-- Only ALTER COLUMN ... DROP DEFAULT (a default expression, not data, not a column). Rollback: 094_rollback.sql.
-- Usage: psql -v ON_ERROR_STOP=1 -f 095_hotel_tickets_drop_default.sql (dry run) | -v apply=true (commit). Then 094_state_check.sql -v expect=applied_095
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'hotel_maintenance_tickets' AND column_name = 'id_company') THEN
        RAISE EXCEPTION 'ABORT: 094 must be applied first.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.hotel_maintenance_tickets WHERE id_company IS NULL) THEN
        RAISE EXCEPTION 'ABORT: tickets without company found.';
    END IF;
END $$;
ALTER TABLE public.hotel_maintenance_tickets ALTER COLUMN id_company DROP DEFAULT;
-- @@FINALIZE
\if :apply
COMMIT;
\echo '095 APPLIED (default removed)'
\else
ROLLBACK;
\echo '095 DRY RUN: nothing changed.'
\endif
