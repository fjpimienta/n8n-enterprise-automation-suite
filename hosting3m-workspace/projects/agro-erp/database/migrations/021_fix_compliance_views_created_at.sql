-- Migration 021: Adds created_at to the compliance views.
--
-- The n8n Meta-CRUD gateway assumes every model exposes created_at (it is used for the
-- default ORDER BY on getall). Both views omitted it, so getall failed at runtime with:
--   {"error":true,"message":"column vw_upp_compliance_status.created_at does not exist"}
--
-- This is a contract of the Meta-CRUD engine, not an optional convenience: any view
-- registered in crud_models MUST expose created_at.
--
-- CREATE OR REPLACE VIEW requires existing columns to keep their name and position, so the
-- new column is appended at the end of each select list (position 20 for UPP, 16 for PSG).
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. UPP compliance (positions 1-19 unchanged, created_at appended at 20)
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
        pu.is_active,
        pu.created_at
   FROM public.production_units pu
   JOIN public.companys c ON c.id_company = pu.id_company;

COMMENT ON VIEW public.vw_upp_compliance_status IS
    'UPP dashboard feed. Alert thresholds are per-tenant via companys.metadata (upp_update_warning_days / upp_update_expired_days), defaulting to 300 / 365 days. created_at is required by the Meta-CRUD gateway.';

-- ---------------------------------------------------------------------------
-- 2. PSG compliance (positions 1-15 unchanged, created_at appended at 16)
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
        pl.is_active,
        pl.created_at
   FROM public.psg_licenses pl
   JOIN public.companys c ON c.id_company = pl.id_company
   LEFT JOIN public.livestock_producers p ON p.id = pl.producer_id;

-- ---------------------------------------------------------------------------
-- 3. Whitelist sync (idempotent: does not duplicate the entry on re-run)
-- ---------------------------------------------------------------------------
UPDATE public.crud_models
   SET allowed_fields = allowed_fields || '["created_at"]'::jsonb
 WHERE model_name IN ('upp_compliance_status','psg_compliance_status')
   AND NOT (allowed_fields @> '["created_at"]'::jsonb);

COMMIT;
