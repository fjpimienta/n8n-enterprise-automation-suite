-- Migration 062: Birth detail columns for vw_cattle_event_log (NACIMIENTO rows).
--
-- Adds two columns, strictly appended at the end (positions 17-18), so the "Cattle Event Log"
-- widget can render "Nació <sexo>, categoría <categoría>, madre <identificador>":
--   - calf_category  : cattle_livestock.category of the calf (birth_events.calf_id).
--   - dam_identifier : COALESCE(dam.rfid_siniiga, dam.numero_fuego, be.dam_ear_tag,
--                      be.dam_fire_number) — falls back to the free-text dam reference that
--                      birth_events_dam_reference_check allows when dam_id is not linked yet.
-- Both are populated only in the NACIMIENTO branch; every other branch returns NULL.
--
-- Base definition: taken verbatim from pg_get_viewdef('vw_cattle_event_log', true) against the
-- LOCAL clone restored from the VPS on 2026-09-30 07:08 (Regla 7). This includes the v1.15.0
-- COMPRA / DESTETE / SOLICITUD_* branches that were applied directly to Postgres without a
-- versioned migration — this file is now the first versioned copy of the full view.
--
-- Safety:
--   - CREATE OR REPLACE VIEW only (never DROP + CREATE): keeps grants (n8n_user,
--     backup_readonly_user) and the crud_models registration untouched. Postgres itself rejects
--     the statement if any of the 16 existing columns changes name, type or order.
--   - The dam is a LEFT JOIN: a birth without dam_id must keep its NACIMIENTO row, as today.
--   - crud_models is NOT modified: the gateway Build Query selects `vw_cattle_event_log.*`, so
--     the new columns reach the frontend without touching allowed_fields.
--   - No other consumer of this view exists (repo, n8n_db workflows, pg_depend — 2026-09-30).
--
-- Rollback: re-apply the pre-change pg_get_viewdef snapshot via CREATE OR REPLACE is NOT
-- possible (a view cannot drop trailing columns that way); rollback requires DROP VIEW +
-- CREATE from the snapshot + re-GRANT, so only do it with explicit approval.
BEGIN;

CREATE OR REPLACE VIEW public.vw_cattle_event_log AS
 SELECT wl.id::text AS id,
    cl.tenant_id,
    wl.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'PESO'::text AS event_type,
    wl.log_date AS event_date,
    wl.weight_kg,
    NULL::text AS health_event_type,
    NULL::text AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    wl.source_device,
    wl.created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_weight_logs wl
     JOIN cattle_livestock cl ON cl.id = wl.livestock_id
UNION ALL
 SELECT hl.id::text AS id,
    cl.tenant_id,
    hl.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'SALUD'::text AS event_type,
    hl.event_date,
    NULL::numeric(10,2) AS weight_kg,
    hl.event_type AS health_event_type,
    hl.description,
    hl.medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    hl.created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_health_logs hl
     JOIN cattle_livestock cl ON cl.id = hl.livestock_id
UNION ALL
 SELECT be.id::text || '-dam'::text AS id,
    be.id_company AS tenant_id,
    be.dam_id AS livestock_id,
    dam.rfid_siniiga,
    dam.numero_fuego,
    'PARTO'::text AS event_type,
    be.birth_date::timestamp without time zone AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    be.notes AS description,
    NULL::jsonb AS medicines_json,
    be.calf_sex,
    be.birth_date,
    calf_w.weight_kg AS calf_weight_kg,
    be.source AS source_device,
    be.created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM birth_events be
     JOIN cattle_livestock dam ON dam.id = be.dam_id
     LEFT JOIN LATERAL ( SELECT w.weight_kg
           FROM cattle_weight_logs w
          WHERE w.livestock_id = be.calf_id AND w.source_device::text = 'BIRTH_EVENT'::text
          ORDER BY w.log_date
         LIMIT 1) calf_w ON be.calf_id IS NOT NULL
  WHERE be.dam_id IS NOT NULL
UNION ALL
 SELECT be.id::text || '-calf'::text AS id,
    be.id_company AS tenant_id,
    be.calf_id AS livestock_id,
    calf.rfid_siniiga,
    calf.numero_fuego,
    'NACIMIENTO'::text AS event_type,
    be.birth_date::timestamp without time zone AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    be.notes AS description,
    NULL::jsonb AS medicines_json,
    be.calf_sex,
    be.birth_date,
    calf_w2.weight_kg AS calf_weight_kg,
    be.source AS source_device,
    be.created_at,
    calf.category AS calf_category,
    COALESCE(dam.rfid_siniiga, dam.numero_fuego, be.dam_ear_tag, be.dam_fire_number)::text AS dam_identifier
   FROM birth_events be
     JOIN cattle_livestock calf ON calf.id = be.calf_id
     LEFT JOIN cattle_livestock dam ON dam.id = be.dam_id
     LEFT JOIN LATERAL ( SELECT w.weight_kg
           FROM cattle_weight_logs w
          WHERE w.livestock_id = be.calf_id AND w.source_device::text = 'BIRTH_EVENT'::text
          ORDER BY w.log_date
         LIMIT 1) calf_w2 ON true
  WHERE be.calf_id IS NOT NULL
UNION ALL
 SELECT cl.id::text AS id,
    cl.tenant_id,
    cl.id AS livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'COMPRA'::text AS event_type,
    COALESCE((cl.metadata ->> 'purchase_date'::text)::timestamp without time zone, cl.created_at) AS event_date,
    cl.current_weight_kg AS weight_kg,
    NULL::text AS health_event_type,
    concat('Comprado a ', COALESCE(cl.metadata ->> 'seller_name'::text, 'vendedor no registrado'::text), ' por $', COALESCE(cl.metadata ->> 'purchase_price'::text, 'N/D'::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    cl.created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_livestock cl
  WHERE (cl.metadata ->> 'source'::text) = 'COMPRA'::text
UNION ALL
 SELECT we.id::text AS id,
    we.id_company AS tenant_id,
    we.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'DESTETE'::text AS event_type,
    we.weaning_date::timestamp without time zone AS event_date,
    wgt.weight_kg,
    we.weaning_method AS health_event_type,
    we.notes AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    we.created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM weaning_events we
     JOIN cattle_livestock cl ON cl.id = we.livestock_id
     LEFT JOIN cattle_weight_logs wgt ON wgt.id = we.weight_log_id
UNION ALL
 SELECT pa.id::text AS id,
    pa.id_company AS tenant_id,
    pa.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
        CASE pa.tipo_evento
            WHEN 'BAJA_MORTANDAD'::text THEN 'SOLICITUD_BAJA'::text
            WHEN 'VENTA'::text THEN 'SOLICITUD_VENTA'::text
            ELSE NULL::text
        END AS event_type,
    pa.fecha_solicitud AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    pa.estado AS health_event_type,
    concat('Estado: ', pa.estado,
        CASE
            WHEN (pa.payload ->> 'causa_mortandad'::text) IS NOT NULL THEN ' | Causa: '::text || (pa.payload ->> 'causa_mortandad'::text)
            ELSE ''::text
        END,
        CASE
            WHEN pa.fecha_resolucion IS NOT NULL THEN ((' | Resuelto: '::text || to_char(pa.fecha_resolucion, 'DD/MM/YYYY HH24:MI'::text)) || ' por '::text) || COALESCE(pa.resuelto_por_email, 'N/D'::character varying)::text
            ELSE ''::text
        END,
        CASE
            WHEN pa.notas_resolucion IS NOT NULL THEN ' | Notas: '::text || pa.notas_resolucion
            ELSE ''::text
        END) AS description,
    pa.payload AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    pa.fecha_solicitud AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM pending_authorizations pa
     JOIN cattle_livestock cl ON cl.id = pa.livestock_id;

COMMENT ON VIEW public.vw_cattle_event_log IS
    'Combined read-only audit log (weight/health/birth/purchase/weaning/authorization requests) for the "Cattle Event Log" tab in main-dashboard. tenant_id is resolved per branch (join to cattle_livestock, or the source table''s id_company directly) so the Build Query tenant hotfix (Regla 9) can filter getall/getone by it. A birth_events row can surface as up to two entries — PARTO under the dam, NACIMIENTO under the calf — never merged into one, because dam_id/calf_id are independently nullable in the source table. calf_category/dam_identifier (migration 062) are populated only on NACIMIENTO rows.';

COMMIT;
