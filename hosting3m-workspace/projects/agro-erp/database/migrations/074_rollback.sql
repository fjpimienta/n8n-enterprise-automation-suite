-- 074_rollback.sql — non-destructive rollback of migration 074 (sale orders).
-- Disables the feature without deleting data:
--   * drops sp_solicitar_venta_orden (the MCP order tools then fail closed; restore the previous MCP workflow too)
--   * drops the unique pending-per-animal index
--   * removes 'sale_order_id' from crud_models.pending_authorizations.allowed_fields
-- KEPT on purpose (data preservation): table sale_orders, pending_authorizations.sale_order_id, notified_at.
-- Usage (dry run first):
--   psql -v ON_ERROR_STOP=1 -v apply=false -f 074_rollback.sql
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 074_rollback.sql
\set ON_ERROR_STOP on
BEGIN;

-- Requests already created by orders stay as they are (PENDIENTE ones still expire at 23:59 CDMX)
SELECT estado, count(*) AS solicitudes_con_orden
  FROM pending_authorizations WHERE sale_order_id IS NOT NULL GROUP BY 1 ORDER BY 1;

DROP FUNCTION IF EXISTS public.sp_solicitar_venta_orden(jsonb, varchar, date, boolean, varchar);
DROP INDEX IF EXISTS public.uq_pending_auth_one_pending_per_animal;

-- Remove only the field 074 added (the backup table stays as reference)
UPDATE crud_models
   SET allowed_fields = allowed_fields - 'sale_order_id'
 WHERE model_name = 'pending_authorizations';

DO $$
BEGIN
    IF to_regprocedure('public.sp_solicitar_venta_orden(jsonb, varchar, date, boolean, varchar)') IS NOT NULL THEN
        RAISE EXCEPTION '074 rollback: function still present';
    END IF;
    IF (SELECT allowed_fields ? 'sale_order_id' FROM crud_models WHERE model_name = 'pending_authorizations') THEN
        RAISE EXCEPTION '074 rollback: crud_models not restored';
    END IF;
    RAISE NOTICE '074 rollback: OK (sale_orders and sale_order_id kept)';
END $$;

\if :apply
COMMIT;
\echo '*** 074 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
