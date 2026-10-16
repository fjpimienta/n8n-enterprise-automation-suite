-- 074_rollback.sql — non-destructive rollback of migration 074 (sale orders). No DROP, no DELETE.
--   * sp_solicitar_venta_orden is replaced by a stub that always raises P0037 (feature disabled);
--     restore the previous MCP workflow too.
--   * 'sale_order_id' is removed from crud_models.pending_authorizations.allowed_fields.
-- KEPT on purpose:
--   * data: table sale_orders, pending_authorizations.sale_order_id and notified_at;
--   * the one-pending-request-per-animal rule (unique index + friendly trigger), a data-integrity rule
--     independent of sale orders. To relax it in an emergency: ALTER TABLE ... DISABLE TRIGGER (index stays).
-- Usage (dry run first):
--   psql -v ON_ERROR_STOP=1 -v apply=false -f 074_rollback.sql
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 074_rollback.sql
\set ON_ERROR_STOP on
BEGIN;

-- Requests already created by orders stay as they are (PENDIENTE ones still expire at 23:59 CDMX)
SELECT estado, count(*) AS solicitudes_con_orden
  FROM pending_authorizations WHERE sale_order_id IS NOT NULL GROUP BY 1 ORDER BY 1;

CREATE OR REPLACE FUNCTION public.sp_solicitar_venta_orden(
    p_items jsonb, p_solicitado_por_email varchar, p_fecha_evento date DEFAULT NULL,
    p_preview boolean DEFAULT true, p_channel varchar DEFAULT 'AGENTE')
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Las órdenes de venta están deshabilitadas temporalmente; solicita la venta animal por animal'
        USING ERRCODE = 'P0037';
END;
$$;

UPDATE crud_models
   SET allowed_fields = allowed_fields - 'sale_order_id'
 WHERE model_name = 'pending_authorizations';

DO $$
BEGIN
    BEGIN
        PERFORM public.sp_solicitar_venta_orden('[]'::jsonb, 'x', NULL, true, 'X');
        RAISE EXCEPTION '074 rollback: procedure still active';
    EXCEPTION WHEN SQLSTATE 'P0037' THEN NULL;
    END;
    IF (SELECT allowed_fields ? 'sale_order_id' FROM crud_models WHERE model_name = 'pending_authorizations') THEN
        RAISE EXCEPTION '074 rollback: crud_models not restored';
    END IF;
    RAISE NOTICE '074 rollback: OK (orders disabled; data and one-pending rule kept)';
END $$;

\if :apply
COMMIT;
\echo '*** 074 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
