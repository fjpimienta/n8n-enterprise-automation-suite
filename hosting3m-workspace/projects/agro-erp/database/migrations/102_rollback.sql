-- 102 ROLLBACK. Removes ONLY what 102 created: the function sp_register_livestock_panel. No DELETE / UPDATE of data.
-- Animals already registered through the panel intake are real data and are NOT touched; they can be listed with
--   metadata->>'migration' = '102'  (and metadata->>'source' = 'PANEL_ALTA').
-- The 099/100 functions are not touched (the migration never changed them).
-- Order in production: first retire whatever calls the function (the gateway model and the panel, PR 2-4), then this file.
-- Re-applying 102_panel_livestock_sp.sql recreates the function.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 102_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 102_rollback.sql  -> commit
-- Then: 102_state_check.sql -v expect=before
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DROP FUNCTION IF EXISTS public.sp_register_livestock_panel(integer, text, text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_register_livestock_panel') THEN
        RAISE EXCEPTION '102 rollback: sp_register_livestock_panel is still there';
    END IF;
    RAISE NOTICE '102 rollback: OK (function dropped; animals and the 099/100 functions untouched)';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 102 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 102 rollback rolled back ***'
\endif
\endif
