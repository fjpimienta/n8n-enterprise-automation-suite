-- 103 ROLLBACK. Deletes ONLY the crud_models row 'register_livestock_panel' (table_name sp_register_livestock_panel) created by
-- 103. No other row, no function, no animal is touched. The function of migration 102 stays (use 102_rollback.sql for that,
-- AFTER this file: first retire the gateway model, then the function).
-- Re-applying 103_panel_livestock_gateway_model.sql recreates the row.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 103_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 103_rollback.sql  -> commit
-- Then: 103_state_check.sql -v expect=before
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

DELETE FROM public.crud_models
 WHERE model_name = 'register_livestock_panel' AND table_name = 'sp_register_livestock_panel';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = 'register_livestock_panel') THEN
        RAISE EXCEPTION '103 rollback: the model row is still there (it points at another table; not touched)';
    END IF;
    RAISE NOTICE '103 rollback: OK (only the register_livestock_panel row was removed)';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 103 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 103 rollback rolled back ***'
\endif
\endif
