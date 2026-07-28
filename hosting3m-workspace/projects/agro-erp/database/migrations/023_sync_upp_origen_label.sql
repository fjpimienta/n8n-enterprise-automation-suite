-- Migration 023: Syncs the legacy upp_origen label from production_unit_id.
--
-- PROBLEM: after migration 016 the system reports two contradictory figures for the same
-- herd. The main dashboard reads the legacy free-text column upp_origen (NULL for 209 of
-- 216 animals) while the compliance module reads the new FK production_unit_id (216 of 216).
-- Both are technically correct and impossible for a user to reconcile.
--
-- FIX: upp_origen becomes a denormalized label derived from the FK, not an independent
-- source of truth. The FK stays authoritative; this column exists only so legacy consumers
-- (dashboard, AI field agent, historico_movimientos snapshots) keep working.
--
-- The label uses companys.company_name because that is the convention already present in
-- the 7 pre-existing rows ('UPP La Bendición').
--
-- Sold animals are excluded: sp_procesar_salida_ganado deliberately nulls both columns on
-- exit, and re-populating upp_origen would resurrect a ranch assignment that no longer holds.
BEGIN;

UPDATE public.cattle_livestock cl
   SET upp_origen = c.company_name
  FROM public.production_units pu
  JOIN public.companys c ON c.id_company = pu.id_company
 WHERE cl.production_unit_id = pu.id
   AND cl.current_status <> 'VENDIDO'
   AND cl.upp_origen IS DISTINCT FROM c.company_name;

COMMENT ON COLUMN public.cattle_livestock.upp_origen IS
    'DENORMALIZED LABEL derived from production_unit_id (migration 023). Not a source of truth: never write it independently. Kept for legacy consumers and for the historical snapshot in historico_movimientos.upp_origen_anterior.';

COMMIT;
