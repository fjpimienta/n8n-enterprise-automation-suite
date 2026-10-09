-- 067_event_log_cdmx_timezone.sql
-- ALREADY APPLIED in LOCAL and PRODUCTION on 2026-10-08. Versioned retroactively.
-- (Labelled "065" during the session; renumbered because 065/066 already existed.)
-- Display-layer timezone fix: vw_cattle_event_log renders America/Mexico_City wall-clock time.
-- Convention: timestamp (without tz) columns written via CURRENT_TIMESTAMP/now() hold UTC
-- (server TimeZone = Etc/UTC). Exact-midnight values are date-only entries (local calendar date).
-- Column names/types of the view are unchanged; no data is modified.
-- Rollback: /backups/vw_cattle_event_log_pre065.sql on the VPS.
BEGIN;
CREATE OR REPLACE FUNCTION public.fn_utc_to_cdmx(p_ts timestamp without time zone)
 RETURNS timestamp without time zone
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (p_ts AT TIME ZONE 'UTC') AT TIME ZONE 'America/Mexico_City';
$function$

;
CREATE OR REPLACE FUNCTION public.fn_event_ts_cdmx(p_event timestamp without time zone, p_created_utc timestamp without time zone)
 RETURNS timestamp without time zone
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN p_event IS NULL
      THEN public.fn_utc_to_cdmx(p_created_utc)
    WHEN p_event <> date_trunc('day', p_event)
      THEN public.fn_utc_to_cdmx(p_event)
    WHEN p_created_utc IS NOT NULL
     AND public.fn_utc_to_cdmx(p_created_utc)::date = p_event::date
      THEN public.fn_utc_to_cdmx(p_created_utc)
    ELSE p_event
  END;
$function$

;
CREATE OR REPLACE VIEW public.vw_cattle_event_log AS  SELECT wl.id::text AS id,
    cl.tenant_id,
    wl.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'PESO'::text AS event_type,
    fn_event_ts_cdmx(wl.log_date, wl.created_at) AS event_date,
    wl.weight_kg,
    NULL::text AS health_event_type,
    NULL::text AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    wl.source_device,
    fn_utc_to_cdmx(wl.created_at) AS created_at,
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
    fn_event_ts_cdmx(hl.event_date, hl.created_at) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    hl.event_type AS health_event_type,
    hl.description,
    hl.medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    fn_utc_to_cdmx(hl.created_at) AS created_at,
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
    fn_event_ts_cdmx(be.birth_date::timestamp without time zone, be.created_at) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    be.notes AS description,
    NULL::jsonb AS medicines_json,
    be.calf_sex,
    be.birth_date,
    calf_w.weight_kg AS calf_weight_kg,
    be.source AS source_device,
    fn_utc_to_cdmx(be.created_at) AS created_at,
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
    fn_event_ts_cdmx(be.birth_date::timestamp without time zone, be.created_at) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    be.notes AS description,
    NULL::jsonb AS medicines_json,
    be.calf_sex,
    be.birth_date,
    calf_w2.weight_kg AS calf_weight_kg,
    be.source AS source_device,
    fn_utc_to_cdmx(be.created_at) AS created_at,
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
    fn_event_ts_cdmx((cl.metadata ->> 'purchase_date'::text)::timestamp without time zone, cl.created_at) AS event_date,
    cl.current_weight_kg AS weight_kg,
    NULL::text AS health_event_type,
    concat('Comprado a ', COALESCE(cl.metadata ->> 'seller_name'::text, 'vendedor no registrado'::text), ' por $', COALESCE(cl.metadata ->> 'purchase_price'::text, 'N/D'::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    fn_utc_to_cdmx(cl.created_at) AS created_at,
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
    fn_event_ts_cdmx(we.weaning_date::timestamp without time zone, we.created_at) AS event_date,
    wgt.weight_kg,
    we.weaning_method AS health_event_type,
    we.notes AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    fn_utc_to_cdmx(we.created_at) AS created_at,
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
    fn_utc_to_cdmx(pa.fecha_solicitud) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    pa.estado AS health_event_type,
    concat('Estado: ', pa.estado,
        CASE
            WHEN (pa.payload ->> 'causa_mortandad'::text) IS NOT NULL THEN ' | Causa: '::text || (pa.payload ->> 'causa_mortandad'::text)
            ELSE ''::text
        END,
        CASE
            WHEN pa.fecha_resolucion IS NOT NULL THEN ((' | Resuelto: '::text || to_char(fn_utc_to_cdmx(pa.fecha_resolucion), 'DD/MM/YYYY HH24:MI'::text)) || ' por '::text) || COALESCE(pa.resuelto_por_email, 'N/D'::character varying)::text
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
    fn_utc_to_cdmx(pa.fecha_solicitud) AS created_at,
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
    fn_event_ts_cdmx(be.breeding_date::timestamp without time zone, (be.created_at AT TIME ZONE 'UTC'::text)) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    be.method::text AS health_event_type,
    concat_ws(' — '::text, initcap(replace(be.method::text, '_'::text, ' '::text)), 'Semental: '::text || NULLIF(be.sire_identifier::text, ''::text), 'Parto estimado: '::text || to_char(be.estimated_due_date::timestamp without time zone, 'DD/MM/YYYY'::text), NULLIF(be.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    (be.created_at AT TIME ZONE 'America/Mexico_City'::text) AS created_at,
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
    fn_event_ts_cdmx(de.application_date::timestamp without time zone, (de.created_at AT TIME ZONE 'UTC'::text)) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text, de.product::text, 'Dosis: '::text || NULLIF(de.dose::text, ''::text), 'Refuerzo: '::text || to_char(de.next_application_date::timestamp without time zone, 'DD/MM/YYYY'::text), NULLIF(de.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    (de.created_at AT TIME ZONE 'America/Mexico_City'::text) AS created_at,
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
    fn_event_ts_cdmx(ce.castration_date::timestamp without time zone, (ce.created_at AT TIME ZONE 'UTC'::text)) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text, (('Categoría: '::text || COALESCE(ce.previous_category, '?'::character varying)::text) || ' → '::text) || ce.new_category::text, NULLIF(ce.method::text, ''::text), NULLIF(ce.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    (ce.created_at AT TIME ZONE 'America/Mexico_City'::text) AS created_at,
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
    fn_utc_to_cdmx(hm.fecha_registro) AS event_date,
    NULL::numeric(10,2) AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text, 'Origen: '::text || COALESCE(NULLIF(hm.lot_origen_anterior::text, ''::text), NULLIF(hm.upp_origen_anterior::text, ''::text)), NULLIF(hm.notes, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    fn_utc_to_cdmx(hm.fecha_registro) AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM historico_movimientos hm
     JOIN cattle_livestock cl ON cl.id = hm.livestock_id
  WHERE hm.tipo_movimiento::text = ANY (ARRAY['TRASLADO'::text, 'CAMBIO_ARETE'::text]);
COMMIT;
