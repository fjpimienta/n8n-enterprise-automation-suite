-- 108 ROLLBACK. No DROP, no DELETE, no TRUNCATE (same 073 pattern as 106 / 107).
--   * The two models (vw_palpation_events, vw_palpation_herd) are disabled: allowed_ops '{}' and every role 'NONE'. The rows stay registered.
--   * The two views stay in place: they are read-only definitions over existing tables, nothing reads them once the models are disabled.
--   * Every other crud_models row and every other object is untouched.
-- Re-enabling the models is a decision of the owner and a separate, reviewed change: 108_palpation_views.sql aborts when the views or models exist.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 108_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_rollback.sql  -> commit
-- Then: 108_state_check.sql -v expect=rolled_back

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
    IF (SELECT count(*) FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')) <> 2 THEN
        RAISE EXCEPTION 'ABORT: the two palpation models are not both registered - 108 was not applied here.';
    END IF;
END $$;

UPDATE public.crud_models
   SET allowed_ops = '{}',
       allowed_roles_select = 'NONE', allowed_roles_insert = 'NONE',
       allowed_roles_update = 'NONE', allowed_roles_delete = 'NONE'
 WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd');

SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
  FROM public.crud_models
 WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
 ORDER BY 1;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 108 ROLLBACK COMMITTED - verify with 108_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 108 ROLLBACK DRY RUN: nothing changed ***'
\endif
\endif
