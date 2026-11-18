-- 108_palpation_views.sql
-- Read-only palpation report data: two views and their two gateway models. Database only: no table, function, trigger or data is changed.
-- REQUIRES 086 (palpation_repro_details, repro_condition_codes) and 028 (brand_registrations). Aborts if missing.
--
-- What it creates
--   vw_palpation_events  one row per PALPACION event of cattle_health_logs, tenant column id_company (from cattle_livestock.tenant_id)
--   vw_palpation_herd    one row per animal of the company (including never palpated), last counted palpation and palpation count
--   crud_models rows vw_palpation_events (PK health_log_id) and vw_palpation_herd (PK livestock_id):
--     allowed_ops {SELECT}, allowed_roles_select ADMIN,EDITOR, insert / update / delete NONE, joins [], is_global false, sp_requires_tenant true,
--     no default filter, no hooks. allowed_fields = exactly the view columns, WITH id_company and created_at.
--
-- Why the models carry id_company: v6/CRUD ("Build Query") injects the verified x-tenant-id header as a filter ONLY when id_company or tenant_id is
-- in allowed_fields. Without it the query has no company filter at all (it would return every company). The migration therefore ABORTS if
-- id_company is missing from either model. created_at is required too: without sort_by the gateway orders by <table>.created_at.
-- allowed_ops {SELECT}: the gateway authorises getall AND getone as "select"; getone is also filtered by company because id_company is allowed.
-- Views are owned by the migration user (a superuser in this suite): no ACL or security_invoker protects them. The gateway model is the control.
--
-- Data rules (agreed with the owner)
--   * result            = palpation_repro_details.result, else derived from medicines_json (result / resultado; PRENADA -> PREÑADA, VACIA -> VACÍA)
--   * gestation_days    = medicines_json gestation_days / dias_gestacion, only if ^[0-9]{1,3}$ and 1..320
--   * is_historical_load= JSON has key 'resultado' and NOT key 'result' (the 2023 bulk load)
--   * technician        = medicines_json->>'technician_name' (NULL in the historical load). description, notes and metadata are never selected.
--   * ranch_term        = upper(btrim(raw_code)) when it is NR, RP, NO APTO or MATRIZ OCUPADA (from the code itself, not from the meaning enum);
--                         NULL for an UNMAPPED code. code_meaning is forced to NULL when mapping_status = 'UNMAPPED'.
--   * counts_as_palpation = ranch_term is not NR (an unexamined animal is not a palpated animal)
--   * is_clinical_result  = no ranch term and a result exists (only these enter the clinical percentages)
--   * brand_code        = brand_registrations.brand_code only (R / aR); the owner_* columns are never selected.
--   * event_date is timestamp WITHOUT time zone: it is cast to date, no time-zone arithmetic.
--
-- Rollback: 108_rollback.sql disables ONLY the two models (no operation, no role); nothing is dropped or deleted.
-- State:    108_state_check.sql -v expect=before|applied|rolled_back (read-only). Tests: 108_tests.sql. Static check: 108_static_check.sh.
-- Usage:    psql -X -v ON_ERROR_STOP=1 -f 108_palpation_views.sql                (dry run)
--           psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_palpation_views.sql  (commit)

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions: abort if anything is missing, or if the views / models already exist ----------------------------------------------------

DO $$
DECLARE
    v_t text;
BEGIN
    FOREACH v_t IN ARRAY ARRAY['crud_models', 'cattle_health_logs', 'cattle_livestock', 'palpation_repro_details', 'repro_condition_codes', 'brand_registrations'] LOOP
        IF to_regclass('public.' || v_t) IS NULL THEN
            RAISE EXCEPTION 'ABORT: table % does not exist (086 and 028 are required).', v_t;
        END IF;
    END LOOP;
    -- Columns the views read.
    IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND
          (table_name, column_name) IN (('palpation_repro_details','health_log_id'), ('palpation_repro_details','result'), ('palpation_repro_details','raw_code'),
                                        ('palpation_repro_details','repro_condition'), ('palpation_repro_details','mapping_status'), ('palpation_repro_details','id_company'),
                                        ('repro_condition_codes','id_company'), ('repro_condition_codes','code'), ('repro_condition_codes','meaning'),
                                        ('brand_registrations','brand_code'), ('cattle_livestock','brand_id'), ('cattle_livestock','tenant_id'),
                                        ('cattle_health_logs','medicines_json'), ('cattle_health_logs','event_date'), ('cattle_health_logs','created_at'))) <> 15 THEN
        RAISE EXCEPTION 'ABORT: a column the views need is missing (is migration 090 applied? repro_condition_codes.meaning).';
    END IF;
    -- The simple LEFT JOIN on repro_condition_codes is only duplicate-free if (id_company, code) is its primary key.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = to_regclass('public.repro_condition_codes') AND contype = 'p'
                      AND pg_get_constraintdef(oid) = 'PRIMARY KEY (id_company, code)') THEN
        RAISE EXCEPTION 'ABORT: repro_condition_codes must have PRIMARY KEY (id_company, code).';
    END IF;
    IF to_regclass('public.vw_palpation_events') IS NOT NULL OR to_regclass('public.vw_palpation_herd') IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT: vw_palpation_events or vw_palpation_herd already exists. Not touching it.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
                                                   OR table_name IN ('vw_palpation_events', 'vw_palpation_herd')) THEN
        RAISE EXCEPTION 'ABORT: a crud_models row for vw_palpation_events / vw_palpation_herd already exists. Not touching it.';
    END IF;
END $$;

-- 1) Views ----------------------------------------------------------------------------------------------------------------------------------

CREATE VIEW public.vw_palpation_events AS
SELECT
    l.tenant_id                                   AS id_company,
    h.id                                          AS health_log_id,
    h.livestock_id,
    h.event_date::date                            AS event_date,
    coalesce(d.result, x.derived_result)          AS result,
    x.gestation_days,
    (jj.j ? 'resultado' AND NOT (jj.j ? 'result')) AS is_historical_load,
    NULLIF(btrim(jj.j ->> 'technician_name'), '') AS technician,
    d.mapping_status,
    d.repro_condition,
    left(d.raw_code, 40)                          AS raw_code,
    CASE WHEN d.mapping_status = 'UNMAPPED' THEN NULL ELSE c.meaning END AS code_meaning,
    r.ranch_term,
    (r.ranch_term IS DISTINCT FROM 'NR')          AS counts_as_palpation,
    (r.ranch_term IS NULL AND coalesce(d.result, x.derived_result) IS NOT NULL) AS is_clinical_result,
    h.created_at
  FROM public.cattle_health_logs h
  JOIN public.cattle_livestock l ON l.id = h.livestock_id
 CROSS JOIN LATERAL (SELECT CASE WHEN jsonb_typeof(h.medicines_json) = 'object' THEN h.medicines_json ELSE '{}'::jsonb END AS j) jj
 CROSS JOIN LATERAL (SELECT NULLIF(btrim(coalesce(jj.j ->> 'gestation_days', jj.j ->> 'dias_gestacion')), '') AS v) g
 CROSS JOIN LATERAL (
        SELECT CASE upper(translate(btrim(coalesce(jj.j ->> 'result', jj.j ->> 'resultado', '')), 'ÍíÑñ', 'IiNn'))
                    WHEN 'VACIA' THEN 'VACÍA' WHEN 'PRENADA' THEN 'PREÑADA' END AS derived_result,
               CASE WHEN g.v ~ '^[0-9]{1,3}$' THEN CASE WHEN g.v::integer BETWEEN 1 AND 320 THEN g.v::integer END END AS gestation_days
        ) x
  LEFT JOIN public.palpation_repro_details d ON d.health_log_id = h.id AND d.id_company = l.tenant_id
  LEFT JOIN public.repro_condition_codes c ON c.id_company = l.tenant_id AND c.code = upper(btrim(d.raw_code))
 CROSS JOIN LATERAL (
        SELECT CASE WHEN d.mapping_status = 'UNMAPPED' THEN NULL
                    WHEN upper(btrim(d.raw_code)) IN ('NR', 'RP', 'NO APTO', 'MATRIZ OCUPADA') THEN upper(btrim(d.raw_code)) END AS ranch_term
        ) r
 WHERE upper(translate(h.event_type, 'Óó', 'Oo')) = 'PALPACION';

COMMENT ON VIEW public.vw_palpation_events IS '108: one row per PALPACION event, tenant column id_company. Read through the gateway model vw_palpation_events (id_company in allowed_fields). Never selects description, notes or metadata.';

CREATE VIEW public.vw_palpation_herd AS
SELECT
    l.tenant_id                AS id_company,
    l.id                       AS livestock_id,
    l.rfid_siniiga,
    l.numero_fuego,
    b.brand_code,
    l.current_status,
    e.event_date               AS last_event_date,
    e.result                   AS last_result,
    e.is_historical_load       AS last_is_historical,
    e.repro_condition          AS last_repro_condition,
    e.mapping_status           AS last_mapping_status,
    e.ranch_term               AS last_ranch_term,
    coalesce(n.cnt, 0)::integer AS palpation_count,
    l.created_at
  FROM public.cattle_livestock l
  LEFT JOIN public.brand_registrations b ON b.id = l.brand_id
  LEFT JOIN LATERAL (
        SELECT ev.event_date, ev.result, ev.is_historical_load, ev.repro_condition, ev.mapping_status, ev.ranch_term
          FROM public.vw_palpation_events ev
         WHERE ev.livestock_id = l.id AND ev.id_company = l.tenant_id AND ev.counts_as_palpation
         ORDER BY ev.event_date DESC, ev.created_at DESC, ev.health_log_id DESC
         LIMIT 1) e ON true
  LEFT JOIN LATERAL (
        SELECT count(*) AS cnt
          FROM public.vw_palpation_events ev
         WHERE ev.livestock_id = l.id AND ev.id_company = l.tenant_id AND ev.counts_as_palpation) n ON true;

COMMENT ON VIEW public.vw_palpation_herd IS '108: one row per animal of the company (including never palpated). From brand_registrations only brand_code. Read through the gateway model vw_palpation_herd.';

-- 2) Gateway models (plain INSERT: the preconditions guarantee that they do not exist) -----------------------------------------------------------

INSERT INTO public.crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json,
                                allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                                allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  ('vw_palpation_events', 'vw_palpation_events', 'health_log_id',
   '["id_company","health_log_id","livestock_id","event_date","result","gestation_days","is_historical_load","technician","mapping_status","repro_condition","raw_code","code_meaning","ranch_term","counts_as_palpation","is_clinical_result","created_at"]',
   NULL, '{}', '{SELECT}', '{"pre":[],"post":[]}',
   'ADMIN,EDITOR', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('vw_palpation_herd', 'vw_palpation_herd', 'livestock_id',
   '["id_company","livestock_id","rfid_siniiga","numero_fuego","brand_code","current_status","last_event_date","last_result","last_is_historical","last_repro_condition","last_mapping_status","last_ranch_term","palpation_count","created_at"]',
   NULL, '{}', '{SELECT}', '{"pre":[],"post":[]}',
   'ADMIN,EDITOR', 'NONE', 'NONE', 'NONE', '[]', false, true);

-- 3) Static checks: fail closed ---------------------------------------------------------------------------------------------------------------------

DO $$
DECLARE
    m record;
    v_cols jsonb;
BEGIN
    IF (SELECT count(*) FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')) <> 2 THEN
        RAISE EXCEPTION '108: expected 2 model rows';
    END IF;
    FOR m IN SELECT model_name, table_name, allowed_fields, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                    allowed_roles_delete, joins, is_global, sp_requires_tenant, default_filter
               FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd') LOOP
        -- id_company is what makes the gateway filter by company; without it the model would be readable across companies.
        IF NOT (m.allowed_fields ? 'id_company') THEN
            RAISE EXCEPTION '108: ABORT: id_company is missing from allowed_fields of % (the gateway would not filter by company)', m.model_name;
        END IF;
        IF NOT (m.allowed_fields ? 'created_at') THEN
            RAISE EXCEPTION '108: ABORT: created_at is missing from allowed_fields of % (the gateway sorts by it by default)', m.model_name;
        END IF;
        IF m.allowed_fields ?| ARRAY['description', 'notes', 'metadata', 'medicines_json', 'owner_name', 'owner_curp_enc', 'owner_curp_hash', 'password'] THEN
            RAISE EXCEPTION '108: ABORT: % exposes a forbidden field', m.model_name;
        END IF;
        -- allowed_fields must be exactly the columns of the view.
        SELECT jsonb_agg(column_name::text ORDER BY column_name) INTO v_cols
          FROM information_schema.columns WHERE table_schema = 'public' AND table_name = m.table_name;
        IF v_cols IS DISTINCT FROM (SELECT jsonb_agg(f ORDER BY f) FROM jsonb_array_elements_text(m.allowed_fields) f) THEN
            RAISE EXCEPTION '108: ABORT: allowed_fields of % differ from the columns of the view (%)', m.model_name, v_cols;
        END IF;
        IF m.allowed_ops <> '{SELECT}' OR m.allowed_roles_select <> 'ADMIN,EDITOR' OR m.allowed_roles_insert <> 'NONE'
           OR m.allowed_roles_update <> 'NONE' OR m.allowed_roles_delete <> 'NONE' OR m.joins <> '[]'::jsonb
           OR m.is_global OR NOT m.sp_requires_tenant OR m.default_filter IS NOT NULL THEN
            RAISE EXCEPTION '108: % does not have the expected configuration', m.model_name;
        END IF;
    END LOOP;
    RAISE NOTICE '108: OK';
END $$;

-- 4) Fingerprints (record them in the runbook; compare with the production run) ---------------------------------------------------------------

SELECT 'view vw_palpation_events' AS fingerprint, md5(pg_get_viewdef('public.vw_palpation_events'::regclass)) AS md5
UNION ALL SELECT 'view vw_palpation_herd', md5(pg_get_viewdef('public.vw_palpation_herd'::regclass))
UNION ALL SELECT 'model vw_palpation_events', md5(row_to_json(c)::text) FROM (SELECT model_name, table_name, primary_key, allowed_fields, default_filter, schema_json, allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins, is_global, sp_requires_tenant FROM public.crud_models WHERE model_name = 'vw_palpation_events') c
UNION ALL SELECT 'model vw_palpation_herd', md5(row_to_json(c)::text) FROM (SELECT model_name, table_name, primary_key, allowed_fields, default_filter, schema_json, allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins, is_global, sp_requires_tenant FROM public.crud_models WHERE model_name = 'vw_palpation_herd') c;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 108 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 108 rolled back ***'
\endif
\endif
