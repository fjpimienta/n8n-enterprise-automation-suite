-- Migration 060: Read-only combined event log for cattle audit (weight, health, birth).
--
-- Backs the new "Cattle Event Log" tab in main-dashboard (Agro ERP). Built from a live \d
-- against the LOCAL clone (n8n-enterprise-db, 2026-09-22), not from schema.sql (Regla 7 —
-- ese archivo se ha desactualizado tres veces).
--
-- Why a UNION view instead of exposing the 3 source tables directly:
--   - cattle_weight_logs / cattle_health_logs have NO tenant_id/id_company column at all.
--     Per Regla 9 (Build Query solo inyecta el filtro de tenant si allowed_fields trae
--     tenant_id/id_company), un GETALL desnudo de esos dos modelos hoy devolvería datos de
--     TODOS los tenants — confirmado leyendo crud_models.allowed_fields en vivo. Esta vista
--     resuelve tenant_id vía join a cattle_livestock (weight/health) o usa birth_events.id_company
--     directo, y lo expone como columna `tenant_id` para que el hotfix ya existente de
--     Build Query (modelHasTenantId/modelHasIdCompany) lo filtre automáticamente en
--     getall/getone, igual que ya hace con production_unit_lots.
--   - birth_events NO tiene columna livestock_id — tiene dam_id y calf_id, ambos nullable
--     (CHECK birth_events_dam_reference_check permite dam_id NULL si hay texto libre; calf_id
--     es NULL hasta que la cría se aretea, confirmado: 15/15 registros en LOCAL ya tienen
--     calf_id hoy, pero el diseño no puede asumir que siempre será así). Por eso un mismo
--     birth_events.id puede aportar hasta DOS filas al log combinado: una bajo la identidad
--     de la madre (evento PARTO, solo si dam_id ya está resuelto) y otra bajo la identidad de
--     la cría (evento NACIMIENTO, solo si calf_id ya está ligado) — nunca una fila con un
--     livestock_id inventado o ambiguo.
--   - El peso de la cría no vive en birth_events: si se capturó, está en cattle_weight_logs
--     con source_device = 'BIRTH_EVENT' y livestock_id = calf_id (confirmado: 15/15 birth
--     events en LOCAL tienen calf_id set, y BIRTH_EVENT es un source_device real observado en
--     cattle_weight_logs). Se resuelve aquí vía LATERAL join, tomando el primer registro
--     (el capturado junto con el parto), no el peso más reciente del animal.
--
-- id expuesto como TEXT (no uuid) porque las filas NACIMIENTO/PARTO derivadas del mismo
-- birth_events.id necesitan distinguirse ('<uuid>-dam' / '<uuid>-calf'); PESO/SALUD usan el
-- uuid nativo casteado a texto. Solo de lectura — sin allowed_ops de escritura.
BEGIN;

CREATE OR REPLACE VIEW public.vw_cattle_event_log AS
SELECT
    wl.id::text                    AS id,
    cl.tenant_id                   AS tenant_id,
    wl.livestock_id                AS livestock_id,
    cl.rfid_siniiga                AS rfid_siniiga,
    cl.numero_fuego                AS numero_fuego,
    'PESO'::text                   AS event_type,
    wl.log_date                    AS event_date,
    wl.weight_kg                   AS weight_kg,
    NULL::text                     AS health_event_type,
    NULL::text                     AS description,
    NULL::jsonb                    AS medicines_json,
    NULL::varchar(10)              AS calf_sex,
    NULL::date                     AS birth_date,
    NULL::numeric(10,2)            AS calf_weight_kg,
    wl.source_device               AS source_device,
    wl.created_at                  AS created_at
FROM public.cattle_weight_logs wl
JOIN public.cattle_livestock cl ON cl.id = wl.livestock_id

UNION ALL

SELECT
    hl.id::text,
    cl.tenant_id,
    hl.livestock_id,
    cl.rfid_siniiga,
    cl.numero_fuego,
    'SALUD',
    hl.event_date,
    NULL::numeric(10,2),
    hl.event_type,
    hl.description,
    hl.medicines_json,
    NULL::varchar(10),
    NULL::date,
    NULL::numeric(10,2),
    NULL::varchar(100),
    hl.created_at
FROM public.cattle_health_logs hl
JOIN public.cattle_livestock cl ON cl.id = hl.livestock_id

UNION ALL

-- Evento de parto bajo la identidad de la madre (solo si dam_id ya está resuelto).
SELECT
    be.id::text || '-dam',
    be.id_company,
    be.dam_id,
    dam.rfid_siniiga,
    dam.numero_fuego,
    'PARTO',
    be.birth_date::timestamp,
    NULL::numeric(10,2),
    NULL::text,
    be.notes,
    NULL::jsonb,
    be.calf_sex,
    be.birth_date,
    calf_w.weight_kg,
    be.source,
    be.created_at
FROM public.birth_events be
JOIN public.cattle_livestock dam ON dam.id = be.dam_id
LEFT JOIN LATERAL (
    SELECT w.weight_kg
      FROM public.cattle_weight_logs w
     WHERE w.livestock_id = be.calf_id
       AND w.source_device = 'BIRTH_EVENT'
     ORDER BY w.log_date ASC
     LIMIT 1
) calf_w ON be.calf_id IS NOT NULL
WHERE be.dam_id IS NOT NULL

UNION ALL

-- Evento de nacimiento bajo la identidad de la cría (solo si calf_id ya está ligado/aretado).
SELECT
    be.id::text || '-calf',
    be.id_company,
    be.calf_id,
    calf.rfid_siniiga,
    calf.numero_fuego,
    'NACIMIENTO',
    be.birth_date::timestamp,
    NULL::numeric(10,2),
    NULL::text,
    be.notes,
    NULL::jsonb,
    be.calf_sex,
    be.birth_date,
    calf_w2.weight_kg,
    be.source,
    be.created_at
FROM public.birth_events be
JOIN public.cattle_livestock calf ON calf.id = be.calf_id
LEFT JOIN LATERAL (
    SELECT w.weight_kg
      FROM public.cattle_weight_logs w
     WHERE w.livestock_id = be.calf_id
       AND w.source_device = 'BIRTH_EVENT'
     ORDER BY w.log_date ASC
     LIMIT 1
) calf_w2 ON true
WHERE be.calf_id IS NOT NULL;

COMMENT ON VIEW public.vw_cattle_event_log IS
    'Combined read-only audit log (weight/health/birth) for the "Cattle Event Log" tab in main-dashboard. tenant_id is resolved per branch (join to cattle_livestock, or birth_events.id_company directly) so the Build Query tenant hotfix (Regla 9) can filter getall/getone by it. A birth_events row can surface as up to two entries — PARTO under the dam, NACIMIENTO under the calf — never merged into one, because dam_id/calf_id are independently nullable in the source table.';

INSERT INTO public.crud_models
    (model_name, table_name, primary_key, allowed_fields, allowed_ops,
     allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
     schema_json)
SELECT 'cattle_event_log', 'vw_cattle_event_log', 'id',
       '["id","tenant_id","livestock_id","rfid_siniiga","numero_fuego","event_type",
         "event_date","weight_kg","health_event_type","description","medicines_json",
         "calf_sex","birth_date","calf_weight_kg","source_device","created_at"]'::jsonb,
       ARRAY['SELECT','GETONE','GETALL'],
       'ADMIN,EDITOR,CUSTOMER',
       'NONE',
       'NONE',
       'NONE',
       '{}'::jsonb
 WHERE NOT EXISTS (
        SELECT 1 FROM public.crud_models WHERE model_name = 'cattle_event_log');

COMMIT;
