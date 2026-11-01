-- 094_rollback.sql: returns hotel_maintenance_tickets to the 094 state (id_company NOT NULL DEFAULT 1), i.e. exactly what the OLD v5 workflow needs.
-- Use it if 095 (drop default) was applied and the old v5 workflow has to come back.
-- The column, FK and index stay: they are inert for the old workflow. Physically removing the column is a separate manual decision (not scripted, no DROP here).
-- Usage: psql -v ON_ERROR_STOP=1 -f 094_rollback.sql (dry run) | -v apply=true (commit). Then 094_state_check.sql -v expect=applied_094
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
        RAISE EXCEPTION 'ABORT: 094 is not applied; nothing to roll back.';
    END IF;
END $$;
ALTER TABLE public.hotel_maintenance_tickets ALTER COLUMN id_company SET DEFAULT 1;
-- @@FINALIZE
\if :apply
COMMIT;
\echo '094 ROLLBACK APPLIED (default 1 restored; column kept)'
\else
ROLLBACK;
\echo '094 ROLLBACK DRY RUN: nothing changed.'
\endif
