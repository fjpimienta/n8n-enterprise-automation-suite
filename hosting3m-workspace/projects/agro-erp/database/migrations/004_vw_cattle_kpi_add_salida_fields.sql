-- Migration 004 (v2): vw_cattle_kpi no incluía upp_origen/tb_test_date/br_test_date
-- porque la vista lista columnas explícitas (no SELECT cl.*) y fue creada antes
-- de la Fase 1. CREATE OR REPLACE VIEW exige que las columnas existentes se
-- conserven en el mismo nombre/orden; las nuevas solo pueden agregarse al final.
--
-- v2: la v1 de esta migración fallaba con
--   ERROR: cannot change name of view column "species" to "upp_origen"
-- porque la vista en producción ya tenía una 17a columna (`species`) que esta
-- migración no contemplaba. Se verificó el orden real vía:
--   SELECT ordinal_position, column_name FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='vw_cattle_kpi' ORDER BY 1;
-- y se ajustó el SELECT list para preservar esas 17 columnas y anexar las 3
-- nuevas (upp_origen, tb_test_date, br_test_date) en las posiciones 18-20.
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
    round((cl.current_weight_kg / ((CURRENT_DATE - cl.birth_date))::numeric), 2) AS adg_lifetime_kg,
    ( SELECT (hl.medicines_json ->> 'resultado'::text)
           FROM public.cattle_health_logs hl
          WHERE ((hl.livestock_id = cl.id) AND ((hl.event_type)::text = 'PALPACION'::text))
          ORDER BY hl.event_date DESC
         LIMIT 1) AS last_palpation_result,
    ( SELECT ((hl.medicines_json ->> 'dias_gestacion'::text))::integer AS int4
           FROM public.cattle_health_logs hl
          WHERE ((hl.livestock_id = cl.id) AND ((hl.event_type)::text = 'PALPACION'::text))
          ORDER BY hl.event_date DESC
         LIMIT 1) AS current_gestation_days,
    cl.species,
    cl.upp_origen,
    cl.tb_test_date,
    cl.br_test_date
   FROM (public.cattle_livestock cl
     LEFT JOIN public.companys c ON ((cl.tenant_id = c.id_company)));

COMMIT;
