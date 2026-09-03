-- Migration 058: Alta de 11 equinos (El Triunfo, Rancho 54, Calzada) — UPP 54.
--
-- CORRIGE una versión previa del script (nunca aplicada) que tenía dos errores
-- críticos: tenant_id=1 (debía ser 6, el tenant de Pedro/UPP 54 — hubiera violado el
-- aislamiento multi-tenant) y ningún production_unit_id/lot_id (habrían quedado
-- huérfanos exactamente como los novillos y búfalos que se corrigieron hoy mismo).
--
-- Conteos y categorías verificados contra las libretas originales (El Triunfo:
-- "01 yegua con cría (potrillo de 1 mes), 01 yegua preñada de 11 meses"; Rancho 54:
-- lista de 7 equinos; Calzada: "01 potro de raza criolla") — 3+7+1=11, coincide.
--
-- species = 'EQUIDO' (no 'EQUINO'): consistente con cattle_breed_catalog y
-- cattle_lifestage_catalog (migración 029), que ya usan ese valor exacto.
--
-- rfid_siniiga con convención S/N-<tipo>-<consecutivo>, igual que el resto del
-- proyecto (borregos, becerros sin arete) — así cualquier reporte que filtre por
-- 'S/N-%' los encuentra igual que a los demás.
BEGIN;

INSERT INTO public.cattle_livestock (
    tenant_id, rfid_siniiga, business_model, category, current_status,
    current_weight_kg, species, brand_id, production_unit_id, lot_id, metadata
)
SELECT 6, v.rfid, 'CRIA', v.categoria, v.estado, 0, 'EQUIDO',
       (SELECT id FROM public.brand_registrations WHERE upper(brand_code) = 'R'),
       (SELECT id FROM public.production_units WHERE id_company = 6 AND is_active = true LIMIT 1),
       (SELECT l.id FROM public.production_unit_lots l
          JOIN public.production_units pu ON pu.id = l.production_unit_id
         WHERE pu.id_company = 6 AND upper(l.lot_name) = upper(v.lote) LIMIT 1),
       v.metadata || jsonb_build_object('peso_no_registrado', true)
  FROM (VALUES
        -- El Triunfo (3)
        ('S/N-EQUIDO-TRI-001', 'YEGUA',    'ACTIVO',  'El Triunfo',
         '{"raza": "No especificada", "edad_descripcion": "Adulta", "observaciones": "Con cria: potrillo de 1 mes"}'::jsonb),
        ('S/N-EQUIDO-TRI-002', 'POTRO',    'ACTIVO',  'El Triunfo',
         '{"raza": "No especificada", "edad_descripcion": "01 mes", "observaciones": "Cria de yegua del mismo predio (ver S/N-EQUIDO-TRI-001)"}'::jsonb),
        ('S/N-EQUIDO-TRI-003', 'YEGUA',    'PREÑADA', 'El Triunfo',
         '{"raza": "No especificada", "edad_descripcion": "Adulta", "gestacion_meses": 11}'::jsonb),
        -- Rancho 54 (7)
        ('S/N-EQUIDO-R54-001', 'CABALLO',  'ACTIVO',  'Rancho 54',
         '{"raza": "Criollo", "edad_descripcion": "Adulto"}'::jsonb),
        ('S/N-EQUIDO-R54-002', 'YEGUA',    'ACTIVO',  'Rancho 54',
         '{"raza": "Appaloosa", "edad_descripcion": "Adulta", "observaciones": "Escrito originalmente como apaluz. Estado reproductivo no mencionado en la libreta - no se asume vacia ni preñada."}'::jsonb),
        ('S/N-EQUIDO-R54-003', 'CABALLO',  'ACTIVO',  'Rancho 54',
         '{"raza": "No especificada", "edad_descripcion": "Adulto", "caracteristicas": "Color blanco"}'::jsonb),
        ('S/N-EQUIDO-R54-004', 'POTRO',    'ACTIVO',  'Rancho 54',
         '{"raza": "No especificada", "edad_descripcion": "1 año 2 meses"}'::jsonb),
        ('S/N-EQUIDO-R54-005', 'POTRANCA', 'ACTIVO',  'Rancho 54',
         '{"raza": "No especificada", "edad_descripcion": "6 meses"}'::jsonb),
        ('S/N-EQUIDO-R54-006', 'CABALLO',  'ACTIVO',  'Rancho 54',
         '{"raza": "Criollo", "edad_descripcion": "Adulto", "observaciones": "Caballo adicional"}'::jsonb),
        ('S/N-EQUIDO-R54-007', 'POTRO',    'ACTIVO',  'Rancho 54',
         '{"raza": "Cuarto de Milla", "edad_descripcion": "Año y medio"}'::jsonb),
        -- Calzada (1)
        ('S/N-EQUIDO-CAL-001', 'POTRO',    'ACTIVO',  'La Calzada',
         '{"raza": "Criollo"}'::jsonb)
       ) AS v(rfid, categoria, estado, lote, metadata)
 WHERE NOT EXISTS (SELECT 1 FROM public.cattle_livestock cl WHERE cl.rfid_siniiga = v.rfid);

COMMIT;

-- Verificación esperada tras aplicar:
-- SELECT category, count(*), count(*) FILTER (WHERE lot_id IS NOT NULL) AS con_lote
--   FROM cattle_livestock WHERE species = 'EQUIDO' GROUP BY 1;
-- Debe sumar 11 en total, con con_lote = count en cada fila (ninguno huérfano).
