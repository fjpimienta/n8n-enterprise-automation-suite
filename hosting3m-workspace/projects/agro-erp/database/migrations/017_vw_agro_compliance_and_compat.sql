-- Migration 017: BI layer for the regulatory registry (Server-Side BI, zero client compute)
-- plus naming-compatibility views.
--
-- NAMING: the codebase carries two names for the same tenant key — tenant_id
-- (cattle_*, users, agriculture_telemetry) and id_company (customers, ph_*, user_companies).
-- Renaming columns in live tables would require Postgres + n8n + Angular to deploy in the
-- same window, and a lag produces a silent failure (missing column -> HTTP 200 with
-- error:true, exactly what the MetaCRUD Silent Error Shield swallows). Instead: all NEW
-- tables use id_company, and these views expose BOTH names for the legacy ones. When the
-- last consumer stops reading tenant_id, the rename becomes one small migration.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. UPP compliance / re-update alerting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_upp_compliance_status AS
 SELECT pu.id                                   AS production_unit_id,
        pu.id_company,
        c.company_name,
        pu.upp_code,
        pu.ranch_name,
        pu.state_name,
        pu.municipality_name,
        pu.total_surface_ha,
        pu.is_partial_surface,
        pu.grazing_surface_ha,
        -- Declared surface vs the sum of the grid. The real constancias disagree with
        -- themselves (Santa Lucía: 42.00 ha total, every concept cell 0.00), so this is
        -- surfaced as a reviewable flag, never as a blocking constraint.
        (pu.total_surface_ha IS NOT NULL
         AND pu.is_partial_surface = false
         AND pu.total_surface_ha <> (
              public.fn_surface_cell(pu.surface_matrix,'riego','estabulado')
            + public.fn_surface_cell(pu.surface_matrix,'riego','agostadero')
            + public.fn_surface_cell(pu.surface_matrix,'riego','agricola')
            + public.fn_surface_cell(pu.surface_matrix,'riego','forestal_maderable')
            + public.fn_surface_cell(pu.surface_matrix,'riego','praderas')
            + public.fn_surface_cell(pu.surface_matrix,'riego','cultivos_forrajeros')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','estabulado')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','agostadero')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','agricola')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','forestal_maderable')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','praderas')
            + public.fn_surface_cell(pu.surface_matrix,'temporal','cultivos_forrajeros')
         )) AS has_surface_inconsistency,
        pu.registration_date,
        pu.last_update_at,
        (CURRENT_DATE - pu.last_update_at::date) AS days_since_update,
        CASE
            WHEN pu.last_update_at IS NULL THEN 'UNKNOWN'
            WHEN (CURRENT_DATE - pu.last_update_at::date)
                 > COALESCE((c.metadata ->> 'upp_update_expired_days')::integer, 365)
                 THEN 'EXPIRED'
            WHEN (CURRENT_DATE - pu.last_update_at::date)
                 > COALESCE((c.metadata ->> 'upp_update_warning_days')::integer, 300)
                 THEN 'WARNING'
            ELSE 'OK'
        END AS update_status,
        -- Latest declared head count, for dashboard context only.
        ( SELECT lcs.total_head
            FROM public.livestock_census_snapshots lcs
           WHERE lcs.production_unit_id = pu.id
           ORDER BY lcs.snapshot_date DESC
           LIMIT 1) AS last_declared_head,
        ( SELECT lcs.snapshot_date
            FROM public.livestock_census_snapshots lcs
           WHERE lcs.production_unit_id = pu.id
           ORDER BY lcs.snapshot_date DESC
           LIMIT 1) AS last_census_date,
        ( SELECT count(*)
            FROM public.cattle_livestock cl
           WHERE cl.production_unit_id = pu.id
             AND cl.current_status NOT IN ('VENDIDO','BAJA_MORTANDAD')) AS active_head_in_system,
        pu.is_active
   FROM public.production_units pu
   JOIN public.companys c ON c.id_company = pu.id_company;

COMMENT ON VIEW public.vw_upp_compliance_status IS
    'UPP dashboard feed. Alert thresholds are per-tenant via companys.metadata (upp_update_warning_days / upp_update_expired_days), defaulting to 300 / 365 days.';

-- ---------------------------------------------------------------------------
-- 2. PSG validity
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_psg_compliance_status AS
 SELECT pl.id            AS psg_license_id,
        pl.id_company,
        c.company_name,
        pl.psg_code,
        pl.state_code,
        pl.municipality_code,
        pl.state_name,
        pl.municipality_name,
        pl.issuing_window,
        pl.issued_at,
        pl.expires_at,
        COALESCE(pl.expires_at,
                 (pl.issued_at + (COALESCE((c.metadata ->> 'psg_validity_months')::integer, 12)
                  || ' months')::interval)::date) AS effective_expires_at,
        public.fn_psg_validity_status(
            pl.issued_at,
            pl.expires_at,
            COALESCE((c.metadata ->> 'psg_validity_months')::integer, 12)
        ) AS validity_status,
        p.full_name      AS producer_name,
        pl.is_active
   FROM public.psg_licenses pl
   JOIN public.companys c ON c.id_company = pl.id_company
   LEFT JOIN public.livestock_producers p ON p.id = pl.producer_id;

-- ---------------------------------------------------------------------------
-- 3. Naming-compatibility views (tenant_id AND id_company exposed side by side)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_cattle_livestock_std AS
 SELECT cl.*, cl.tenant_id AS id_company
   FROM public.cattle_livestock cl;

CREATE OR REPLACE VIEW public.vw_cattle_expenses_std AS
 SELECT ce.*, ce.tenant_id AS id_company
   FROM public.cattle_expenses ce;

CREATE OR REPLACE VIEW public.vw_historico_movimientos_std AS
 SELECT hm.*, hm.tenant_id AS id_company
   FROM public.historico_movimientos hm;

COMMENT ON VIEW public.vw_cattle_livestock_std IS
    'Compatibility shim: exposes the legacy tenant_id alongside the canonical id_company. Transitional — drop once no consumer reads tenant_id.';

-- ---------------------------------------------------------------------------
-- 4. vw_cattle_kpi: append production unit context.
-- CREATE OR REPLACE VIEW requires existing columns to keep name AND position; new columns
-- may only be appended. Positions 1-20 below are byte-identical to migration 004.
-- ---------------------------------------------------------------------------
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
    cl.br_test_date,
    cl.production_unit_id,
    pu.upp_code,
    pu.ranch_name
   FROM ((public.cattle_livestock cl
     LEFT JOIN public.companys c ON ((cl.tenant_id = c.id_company)))
     LEFT JOIN public.production_units pu ON ((cl.production_unit_id = pu.id)));

COMMIT;
