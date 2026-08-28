-- Migration 040: Seed UPP 54's three lotes, migrate El Triunfo out of leased_land_sites.
--
-- Confirmed by client (2026-08-25): UPP 54 (Puyacatengo, Jalapa, Tabasco) has three
-- physically distinct parcels — "El Triunfo" (rentada, arrendador Eladio Alejandro
-- Navarro Ble — already loaded via migration 031 as a leased_land_sites row, now that its
-- UPP is confirmed it belongs as a lot instead), "Rancho 54" (propio), "La Calzada"
-- (propio). All three in R/A Puyacatengo Sur, Jalapa, Tabasco.
--
-- leased_land_sites.'Rancho El Triunfo' is marked is_active = false rather than deleted —
-- same never-delete discipline used for cattle_tenants (migration 010). Its animals
-- (loaded in migration 033, corrected in migration 036) move from leased_site_id to
-- production_unit_id (Puyacatengo) + lot_id (El Triunfo), matching how every other
-- UPP-54 animal is already stored.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Seed the three lots
-- ---------------------------------------------------------------------------
INSERT INTO public.production_unit_lots
    (id_company, production_unit_id, lot_name, tenure_type, lessor_name, location_notes)
SELECT 6, pu.id, v.lot_name, v.tenure_type, v.lessor_name, 'R/A Puyacatengo Sur, Jalapa, Tabasco'
  FROM public.production_units pu
  CROSS JOIN (VALUES
        ('El Triunfo', 'RENTADA', 'Eladio Alejandro Navarro Ble'),
        ('Rancho 54',  'PROPIO',  NULL),
        ('La Calzada', 'PROPIO',  NULL)
       ) AS v(lot_name, tenure_type, lessor_name)
 WHERE pu.id_company = 6 AND pu.is_active = true
   AND NOT EXISTS (
        SELECT 1 FROM public.production_unit_lots l
         WHERE l.production_unit_id = pu.id AND upper(l.lot_name) = upper(v.lot_name));

-- ---------------------------------------------------------------------------
-- 2. Migrate El Triunfo's animals: leased_site_id -> production_unit_id + lot_id
-- ---------------------------------------------------------------------------
UPDATE public.cattle_livestock cl
   SET production_unit_id = pu.id,
       lot_id = lot.id,
       leased_site_id = NULL
  FROM public.leased_land_sites ls
  JOIN public.production_units pu ON pu.id_company = 6 AND pu.is_active = true
  JOIN public.production_unit_lots lot
       ON lot.production_unit_id = pu.id AND upper(lot.lot_name) = 'EL TRIUNFO'
 WHERE cl.leased_site_id = ls.id
   AND upper(ls.site_name) = 'RANCHO EL TRIUNFO';

-- ---------------------------------------------------------------------------
-- 3. Deprecate the old leased_land_sites row (never delete)
-- ---------------------------------------------------------------------------
UPDATE public.leased_land_sites
   SET is_active = false,
       notes = COALESCE(notes || ' | ', '')
            || 'SUPERADO por migración 040 (2026-08-25): reclasificado como lote '
            || '"El Triunfo" de UPP 54 (production_unit_lots), ya que su UPP quedó '
            || 'confirmada. Fila conservada solo para auditoría histórica.'
 WHERE upper(site_name) = 'RANCHO EL TRIUNFO' AND id_company = 6;

COMMIT;
