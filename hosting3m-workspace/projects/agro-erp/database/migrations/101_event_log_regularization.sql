-- 101_event_log_regularization.sql
-- Adds ONE branch ('REGULARIZACION') to public.vw_cattle_event_log so the Bitacora shows the animals registered by the
-- livestock regularization tool of migration 099 (cattle_livestock.metadata->>'source' = 'REGULARIZACION_PADRON').
-- The view definition is the one of 067_event_log_cdmx_timezone.sql (the last one that defines it) plus the new branch, which
-- mirrors the COMPRA branch: same columns and types, event date through fn_event_ts_cdmx, creation time through fn_utc_to_cdmx.
-- The description is built with concat_ws from the 099 metadata keys: guide_folio, origin_upp_code, reported_age_months,
-- category_reported, channel and notes. It never includes preview_hash or the email of the person who registered the animal.
--
-- Changes ONE view (CREATE OR REPLACE VIEW). No table, function, trigger, index or crud_models row is touched; no data is
-- modified. The ACL of the view is kept by CREATE OR REPLACE. The Bitacora stays ADMIN-only (migration 064, crud_models).
-- Idempotent: if the view already has the branch, it exits with a NOTICE and changes nothing.
-- Precondition: the current definition must be the 067 one (whitespace-normalized md5 726fdf2e20ca6848deb0b1d7cfef66b9, PostgreSQL 15.4 deparse;
-- another PostgreSQL major version can deparse differently: compare by hand in that case, see the runbook).
--
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 101_event_log_regularization.sql                 (dry run: ROLLBACK)
--        psql -X -v ON_ERROR_STOP=1 -v apply=true -f 101_event_log_regularization.sql   (COMMIT)
-- Rollback: 101_rollback.sql. State: 101_state_check.sql.
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- ---------------------------------------------------------------------------------------------
-- 0. Preconditions.
-- ---------------------------------------------------------------------------------------------
SELECT to_regclass('public.vw_cattle_event_log') IS NULL AS no_view \gset
\if :no_view
\echo 'ABORT: public.vw_cattle_event_log does not exist (apply 060-067 first).'
DO $$ BEGIN RAISE EXCEPTION 'ABORT: public.vw_cattle_event_log does not exist (apply 060-067 first).'; END $$;
\endif
SELECT pg_get_viewdef('public.vw_cattle_event_log'::regclass, true) LIKE '%''REGULARIZACION''::text AS event_type%' AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE '101: the view already has the REGULARIZACION branch - nothing to change'; END $$;
\else
DO $$
DECLARE
    v_def  text := pg_get_viewdef('public.vw_cattle_event_log'::regclass, true);
    v_md5  text := md5(regexp_replace(v_def, '\s+', ' ', 'g'));
    v_cols text := (SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
           FROM pg_attribute a WHERE a.attrelid = 'public.vw_cattle_event_log'::regclass AND a.attnum > 0 AND NOT a.attisdropped);
BEGIN
    IF v_cols IS DISTINCT FROM 'id:text,tenant_id:integer,livestock_id:uuid,rfid_siniiga:character varying(100),numero_fuego:character varying(50),event_type:text,event_date:timestamp without time zone,weight_kg:numeric(10,2),health_event_type:text,description:text,medicines_json:jsonb,calf_sex:character varying(10),birth_date:date,calf_weight_kg:numeric(10,2),source_device:character varying,created_at:timestamp without time zone,calf_category:character varying(50),dam_identifier:text' THEN
        RAISE EXCEPTION 'ABORT: the columns of vw_cattle_event_log are not the expected 18 (got %)', v_cols;
    END IF;
    IF v_md5 <> '726fdf2e20ca6848deb0b1d7cfef66b9' THEN
        RAISE EXCEPTION 'ABORT: the current vw_cattle_event_log is not the 067 definition (normalized md5 %, expected 726fdf2e20ca6848deb0b1d7cfef66b9). Compare with 067_event_log_cdmx_timezone.sql before continuing.', v_md5;
    END IF;
    IF to_regprocedure('public.fn_event_ts_cdmx(timestamp without time zone, timestamp without time zone)') IS NULL
       OR to_regprocedure('public.fn_utc_to_cdmx(timestamp without time zone)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: fn_event_ts_cdmx / fn_utc_to_cdmx are missing (067 not applied).';
    END IF;
    RAISE NOTICE '101: preconditions OK';
END $$;

-- ---------------------------------------------------------------------------------------------
-- 1. The view: 067 definition + the REGULARIZACION branch (placed right after COMPRA).
-- ---------------------------------------------------------------------------------------------
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
 SELECT cl.id::text AS id,
    cl.tenant_id,
    cl.id AS livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'REGULARIZACION'::text AS event_type,
    fn_event_ts_cdmx(NULL::timestamp without time zone, cl.created_at) AS event_date,
    cl.current_weight_kg AS weight_kg,
    NULL::text AS health_event_type,
    concat_ws(' — '::text, 'Alta por regularización de padrón'::text, 'Guía: '::text || NULLIF(cl.metadata ->> 'guide_folio'::text, ''::text), 'UPP origen de la guía: '::text || NULLIF(cl.metadata ->> 'origin_upp_code'::text, ''::text), (('Edad aproximada: '::text || NULLIF(cl.metadata ->> 'reported_age_months'::text, ''::text)) || ' meses'::text), 'Categoría dictada: '::text || NULLIF(cl.metadata ->> 'category_reported'::text, ''::text), 'Canal: '::text || NULLIF(cl.metadata ->> 'channel'::text, ''::text), NULLIF(cl.metadata ->> 'notes'::text, ''::text)) AS description,
    NULL::jsonb AS medicines_json,
    NULL::character varying(10) AS calf_sex,
    NULL::date AS birth_date,
    NULL::numeric(10,2) AS calf_weight_kg,
    NULL::character varying(100) AS source_device,
    fn_utc_to_cdmx(cl.created_at) AS created_at,
    NULL::character varying(50) AS calf_category,
    NULL::text AS dam_identifier
   FROM cattle_livestock cl
  WHERE (cl.metadata ->> 'source'::text) = 'REGULARIZACION_PADRON'::text
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

DO $$
DECLARE
    v_def  text := pg_get_viewdef('public.vw_cattle_event_log'::regclass, true);
    v_cols text := (SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
           FROM pg_attribute a WHERE a.attrelid = 'public.vw_cattle_event_log'::regclass AND a.attnum > 0 AND NOT a.attisdropped);
BEGIN
    IF v_cols IS DISTINCT FROM 'id:text,tenant_id:integer,livestock_id:uuid,rfid_siniiga:character varying(100),numero_fuego:character varying(50),event_type:text,event_date:timestamp without time zone,weight_kg:numeric(10,2),health_event_type:text,description:text,medicines_json:jsonb,calf_sex:character varying(10),birth_date:date,calf_weight_kg:numeric(10,2),source_device:character varying,created_at:timestamp without time zone,calf_category:character varying(50),dam_identifier:text' THEN
        RAISE EXCEPTION '101: the columns of the view changed (got %)', v_cols;
    END IF;
    IF v_def NOT LIKE '%''REGULARIZACION''::text AS event_type%' OR v_def NOT LIKE '%''COMPRA''::text AS event_type%' THEN
        RAISE EXCEPTION '101: the view does not have both the COMPRA and REGULARIZACION branches';
    END IF;
    IF v_def LIKE '%preview_hash%' OR v_def LIKE '%registered_by%' THEN
        RAISE EXCEPTION '101: the view must not read preview_hash or registered_by';
    END IF;
    RAISE NOTICE '101: OK';
END $$;
\endif

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 101 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 101 rolled back ***'
\endif
\endif
