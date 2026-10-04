-- Migration 063: New event types in vw_cattle_event_log (Cattle Event Log / Bitácora).
--
-- Appends four UNION ALL branches; the existing eight branches (PESO, SALUD, PARTO, NACIMIENTO,
-- COMPRA, DESTETE, SOLICITUD_BAJA/SOLICITUD_VENTA) are copied verbatim from
-- pg_get_viewdef('vw_cattle_event_log', true) — md5 a6977b7a9260cb8228a98ba7014ba983, identical in
-- LOCAL (restored 2026-10-04 07:08) and PRODUCTION (checked 2026-10-04), i.e. the 062 definition.
--
-- New event_type values:
--   REPRODUCCION    <- cattle_breeding_events   (breeding_date)
--   DESPARASITACION <- cattle_deworming_events  (application_date)
--   CASTRACION      <- cattle_castration_events (castration_date)
--   TRASLADO / CAMBIO_ARETE <- historico_movimientos (fecha_registro) — ONLY these two values.
--     VENTA / BAJA_MORTANDAD / REVERSION rows of historico_movimientos stay out on purpose: they
--     may duplicate the SOLICITUD_* rows from pending_authorizations (separate product decision).
--
-- Shape: the view keeps its 18 typed columns; the frontend maps event_type to its label and renders
-- `description`, so the human-readable detail is built here into `description` (CONCAT_WS skips
-- NULLs). rfid_siniiga / numero_fuego stay raw — 'Sin arete' / 'S/N' are applied in the frontend.
--
-- Voids: rows of the three new event tables are hidden when event_voids has a matching
-- (event_table, event_id) for the SAME tenant (fail-closed: a void row from another tenant can never
-- hide an event). historico_movimientos is not void-filtered (not in the task scope).
--
-- created_at of the new tables is timestamptz; cast to timestamp to keep the view column type
-- Optional text fields are wrapped in NULLIF(..., '') because concat_ws skips NULL but not ''.
-- (server TimeZone is Etc/UTC in LOCAL and PRODUCTION, same as the other branches' now()).
--
-- Safety: CREATE OR REPLACE VIEW only (never DROP): keeps grants and the crud_models registration.
-- No column added, renamed or retyped — only rows. Rollback = re-apply 062 via CREATE OR REPLACE
-- (valid, since the column list is unchanged).
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
     JOIN cattle_livestock cl ON cl.id = pa.livestock_id
UNION ALL
 SELECT be.id::text AS id,
    be.tenant_id,
    be.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'REPRODUCCION'::text AS event_type,
    be.breeding_date::timestamp without time zone AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    be.method::text AS health_event_type,
    concat_ws(' — '::text,
        initcap(replace(be.method::text, '_'::text, ' '::text)),
        'Semental: '::text || NULLIF(be.sire_identifier::text, ''::text),
        'Parto estimado: '::text || to_char(be.estimated_due_date::timestamp without time zone, 'DD/MM/YYYY'::text),
        NULLIF(be.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    be.created_at::timestamp without time zone AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_breeding_events be
     JOIN cattle_livestock cl ON cl.id = be.livestock_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM event_voids ev
          WHERE ev.event_table::text = 'cattle_breeding_events'::text AND ev.event_id = be.id AND ev.tenant_id = be.tenant_id))
UNION ALL
 SELECT de.id::text AS id,
    de.tenant_id,
    de.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'DESPARASITACION'::text AS event_type,
    de.application_date::timestamp without time zone AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text,
        de.product::text,
        'Dosis: '::text || NULLIF(de.dose::text, ''::text),
        'Refuerzo: '::text || to_char(de.next_application_date::timestamp without time zone, 'DD/MM/YYYY'::text),
        NULLIF(de.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    de.created_at::timestamp without time zone AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_deworming_events de
     JOIN cattle_livestock cl ON cl.id = de.livestock_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM event_voids ev
          WHERE ev.event_table::text = 'cattle_deworming_events'::text AND ev.event_id = de.id AND ev.tenant_id = de.tenant_id))
UNION ALL
 SELECT ce.id::text AS id,
    ce.tenant_id,
    ce.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'CASTRACION'::text AS event_type,
    ce.castration_date::timestamp without time zone AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text,
        (('Categoría: '::text || COALESCE(ce.previous_category, '?'::character varying)::text) || ' → '::text) || ce.new_category::text,
        NULLIF(ce.method::text, ''::text),
        NULLIF(ce.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    ce.created_at::timestamp without time zone AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_castration_events ce
     JOIN cattle_livestock cl ON cl.id = ce.livestock_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM event_voids ev
          WHERE ev.event_table::text = 'cattle_castration_events'::text AND ev.event_id = ce.id AND ev.tenant_id = ce.tenant_id))
UNION ALL
 SELECT hm.id::text AS id,
    hm.tenant_id,
    hm.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    hm.tipo_movimiento::text AS event_type,
    hm.fecha_registro AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text,
        'Origen: '::text || COALESCE(NULLIF(hm.lot_origen_anterior::text, ''::text), NULLIF(hm.upp_origen_anterior::text, ''::text)),
        NULLIF(hm.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    hm.fecha_registro AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM historico_movimientos hm
     JOIN cattle_livestock cl ON cl.id = hm.livestock_id
  WHERE hm.tipo_movimiento::text = ANY (ARRAY['TRASLADO'::text, 'CAMBIO_ARETE'::text]);

COMMENT ON VIEW public.vw_cattle_event_log IS
    'Combined read-only audit log (weight/health/birth/purchase/weaning/authorization requests/breeding/deworming/castration/transfer/tag change) for the "Cattle Event Log" tab in main-dashboard. tenant_id is resolved per branch (join to cattle_livestock, or the source table''s tenant column directly) so the Build Query tenant hotfix (Regla 9) can filter getall/getone by it. A birth_events row can surface as up to two entries — PARTO under the dam, NACIMIENTO under the calf. calf_category/dam_identifier (migration 062) are populated only on NACIMIENTO rows. Breeding/deworming/castration rows voided in event_voids (same tenant) are excluded (migration 063).';

COMMIT;
