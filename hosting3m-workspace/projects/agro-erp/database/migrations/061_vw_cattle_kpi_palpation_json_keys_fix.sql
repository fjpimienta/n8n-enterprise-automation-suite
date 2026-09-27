-- 061_vw_cattle_kpi_palpation_json_keys_fix.sql
-- Fix: last_palpation_result / current_gestation_days in vw_cattle_kpi read
-- medicines_json ->> 'resultado' / 'dias_gestacion', but cattle_health_logs
-- stores these keys in English ('result' / 'gestation_days'). Both columns
-- always returned NULL. Already applied directly in production on 2026-09-25;
-- this migration documents the change and replays it on other environments.

CREATE OR REPLACE VIEW vw_cattle_kpi AS
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
    round(cl.current_weight_kg / NULLIF(CURRENT_DATE - cl.birth_date, 0)::numeric, 2) AS adg_lifetime_kg,
    ( SELECT hl.medicines_json ->> 'result'::text
           FROM cattle_health_logs hl
          WHERE hl.livestock_id = cl.id AND hl.event_type::text = 'PALPACION'::text
          ORDER BY hl.event_date DESC
         LIMIT 1) AS last_palpation_result,
    ( SELECT (hl.medicines_json ->> 'gestation_days'::text)::integer AS int4
           FROM cattle_health_logs hl
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
    lot.lot_name
   FROM cattle_livestock cl
     LEFT JOIN companys c ON cl.tenant_id = c.id_company
     LEFT JOIN production_units pu ON cl.production_unit_id = pu.id
     LEFT JOIN production_unit_lots lot ON cl.lot_id = lot.id;