-- Migration 055: Hidrata lot_name en el modelo Meta-CRUD de cattle_livestock.
--
-- Formato de "joins" confirmado directamente contra producción antes de escribir esto
-- (después de dos correcciones fallidas en la migración 052 por adivinar el esquema de
-- crud_models de memoria — esta vez se verificó primero):
--   [{"table": "companys", "fields": {"company_name": "tenant_name"},
--     "own_col": "tenant_id", "foreign_col": "id_company"}]
--
-- Se agrega un segundo elemento al arreglo (no se reemplaza el existente): hidrata
-- production_unit_lots.lot_name -> lot_name, uniendo por cattle_livestock.lot_id contra
-- production_unit_lots.id. Necesario para que el frontend (brief entregado
-- 2026-08-28) pueda mostrar la columna "Lote" sin una llamada adicional a la API.
BEGIN;

UPDATE public.crud_models
   SET joins = joins || '[{"table": "production_unit_lots", "fields": {"lot_name": "lot_name"}, "own_col": "lot_id", "foreign_col": "id"}]'::jsonb
 WHERE model_name = 'cattle_livestock'
   AND NOT (joins @> '[{"table": "production_unit_lots"}]'::jsonb);

-- Verificación esperada tras aplicar:
-- SELECT joins FROM crud_models WHERE model_name = 'cattle_livestock';
-- Debe mostrar DOS elementos en el arreglo: el join a companys (sin tocar) + el nuevo a
-- production_unit_lots.

COMMIT;
