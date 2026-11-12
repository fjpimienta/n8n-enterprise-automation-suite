-- 106 ROLLBACK. No DROP, no DELETE, no TRUNCATE.
--   * Restores allowed_fields of the two rows (hotel_rooms, hotel_maintenance_tickets) from crud_models_backup_20261112_106.
--     Nothing else is touched: every other column of the two rows and every other crud_models row stay as they are.
--   * The backup table stays (a re-apply of 106 keeps the original copy).
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 106_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 106_rollback.sql  -> commit
-- Then: 106_state_check.sql -v expect=rolled_back

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
    IF to_regclass('public.crud_models_backup_20261112_106') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models_backup_20261112_106 not found - 106 was never applied here.';
    END IF;
    IF (SELECT count(*) FROM public.crud_models_backup_20261112_106 WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')) <> 2 THEN
        RAISE EXCEPTION 'ABORT: the backup does not hold exactly the two rows.';
    END IF;
END $$;

UPDATE crud_models c
   SET allowed_fields = b.allowed_fields
  FROM crud_models_backup_20261112_106 b
 WHERE c.model_name = b.model_name
   AND c.model_name IN ('hotel_rooms', 'hotel_maintenance_tickets');

DO $$
BEGIN
    IF (SELECT count(*) FROM public.crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')) <> 2 THEN
        RAISE EXCEPTION '106 rollback: both rows must exist';
    END IF;
    IF EXISTS (SELECT 1 FROM public.crud_models c JOIN public.crud_models_backup_20261112_106 b ON b.model_name = c.model_name
                WHERE (to_jsonb(c)) IS DISTINCT FROM (to_jsonb(b) - 'backed_up_at')) THEN
        RAISE EXCEPTION '106 rollback: a row is not equal to its backup';
    END IF;
    RAISE NOTICE '106 rollback: OK';
END $$;

SELECT model_name, table_name, allowed_ops, allowed_fields
  FROM crud_models WHERE model_name IN ('hotel_maintenance_tickets', 'hotel_rooms') ORDER BY model_name;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 106 ROLLBACK COMMITTED - verify with 106_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 106 ROLLBACK DRY RUN: nothing changed ***'
\endif
\endif
