-- Migration 057 (redefinida): asigna lote a los 5 registros NOVILLO que quedaron sin
-- resolver — reemplaza el plan original de baja lógica.
--
-- CAMBIO DE DIRECCIÓN (2026-08-31): el cliente había dicho "novillo no hay... se puede
-- dar de baja" para estos 5 aretes (sin origen confirmado en ninguna libreta real). La
-- instrucción que reemplaza esa dirección es: no dar de baja, asignarles lote —
-- 4 a Rancho 54, y 0721391943 a El Triunfo. Se aplica tal cual se indicó. category y
-- current_status NO se tocan en esta migración — siguen como NOVILLO/VACÍA. Si en algún
-- momento se confirma que también necesitan corrección de categoría (mismo patrón que
-- los otros 16 del lote original), es un ajuste aparte, no asumido aquí.
--
-- No se ejecutó ninguna versión previa de la migración 057 — no hay nada que revertir.
BEGIN;

UPDATE public.cattle_livestock cl
   SET lot_id = lot.id
  FROM public.production_unit_lots lot
  JOIN public.production_units pu ON pu.id = lot.production_unit_id
 WHERE pu.id_company = 6 AND upper(lot.lot_name) = 'RANCHO 54'
   AND cl.rfid_siniiga IN ('0723639517','0723639581','0722690736','0723090699')
   AND cl.lot_id IS NULL;

UPDATE public.cattle_livestock cl
   SET lot_id = lot.id
  FROM public.production_unit_lots lot
  JOIN public.production_units pu ON pu.id = lot.production_unit_id
 WHERE pu.id_company = 6 AND upper(lot.lot_name) = 'EL TRIUNFO'
   AND cl.rfid_siniiga = '0721391943'
   AND cl.lot_id IS NULL;

COMMIT;

-- Verificación esperada tras aplicar:
-- SELECT cl.rfid_siniiga, lot.lot_name FROM cattle_livestock cl
--   JOIN production_unit_lots lot ON lot.id = cl.lot_id
--  WHERE cl.rfid_siniiga IN ('0723639517','0723639581','0722690736','0721391943','0723090699')
--  ORDER BY cl.rfid_siniiga;
-- Las 4 primeras -> Rancho 54. 0721391943 -> El Triunfo.
