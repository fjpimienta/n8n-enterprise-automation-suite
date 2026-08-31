-- Migration 056: Agrega lot_name a vw_cattle_kpi — la vista real que consume el
-- frontend, no cattle_livestock directamente.
--
-- CAUSA RAÍZ del problema "Sin lote" (2026-08-31): la migración 055 agregó el join
-- lot_name -> production_unit_lots al crud_models.joins del modelo 'cattle_livestock',
-- asumiendo (sin verificar) que el frontend consultaba esa tabla. La captura de Network
-- del navegador confirmó que en realidad consulta el modelo 'vw_cattle_kpi', una vista
-- con sus propios JOIN escritos directamente en el SQL — completamente al margen del
-- mecanismo declarativo de crud_models.joins. La migración 055 sigue siendo válida (por
-- si algún otro consumidor sí usa el modelo cattle_livestock directo), pero no resolvía
-- este caso. Esta es la corrección real.
--
-- Definición ORIGINAL verificada contra producción antes de escribir esto (pg_get_viewdef,
-- 2026-08-31) — se reproduce completa, columna por columna, en el mismo orden, y el campo
-- nuevo se agrega estrictamente al final. CREATE OR REPLACE VIEW exige que las columnas
-- existentes conserven nombre y posición (ver DATABASE_SCHEMA.md, nota de la migración
-- 004) — cualquier cliente (frontend, reportes) que lea por posición en vez de por nombre
-- se rompería si esto no se respeta.
BEGIN;

CREATE OR REPLACE VIEW public.vw_cattle_kpi AS
 SELECT cl.id,
        cl.tenant_id,
        cl.rfid_siniiga,
        cl.business_model,
        cl.category,
        cl.current_status,
        cl.birth_date,
        cl.current_weight_kg,
        cl.metadata,
        cl.created_at,
        cl.electronic_rfid,
        cl.numero_fuego,
        c.company_name AS tenant_name,
        round(cl.current_weight_kg / (CURRENT_DATE - cl.birth_date)::numeric, 2) AS adg_lifetime_kg,
        ( SELECT hl.medicines_json ->> 'resultado'::text
            FROM public.cattle_health_logs hl
           WHERE hl.livestock_id = cl.id AND hl.event_type::text = 'PALPACION'::text
           ORDER BY hl.event_date DESC
          LIMIT 1) AS last_palpation_result,
        ( SELECT (hl.medicines_json ->> 'dias_gestacion'::text)::integer AS int4
            FROM public.cattle_health_logs hl
           WHERE hl.livestock_id = cl.id AND hl.event_type::text = 'PALPACION'::text
           ORDER BY hl.event_date DESC
          LIMIT 1) AS current_gestation_days,
        cl.species,
        cl.upp_origen,
        cl.tb_test_date,
        cl.br_test_date,
        cl.production_unit_id,
        pu.upp_code,
        pu.ranch_name,
        -- NUEVO (migración 056): agregado estrictamente al final.
        lot.lot_name
   FROM public.cattle_livestock cl
     LEFT JOIN public.companys c ON cl.tenant_id = c.id_company
     LEFT JOIN public.production_units pu ON cl.production_unit_id = pu.id
     LEFT JOIN public.production_unit_lots lot ON cl.lot_id = lot.id;

COMMIT;

-- Verificación esperada tras aplicar:
-- SELECT rfid_siniiga, numero_fuego, lot_name FROM vw_cattle_kpi
--  WHERE rfid_siniiga = '0718436808';
-- Debe mostrar lot_name = 'Rancho 54' (el arete que ya vimos en la captura de pantalla
-- con "Fuego: 6808" mostrando "Sin lote" incorrectamente en la UI).
