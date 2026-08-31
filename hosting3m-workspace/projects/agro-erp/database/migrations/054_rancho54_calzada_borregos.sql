-- Migration 054: Lote de Rancho 54 (asignación retroactiva), Calzada, borregos, y alta
-- de un becerro sin arete de El Triunfo.
--
-- PRECONDICIÓN: requiere que las migraciones 050-052 (esquema de lotes) ya estén
-- aplicadas, y que 053_rancho54_nuevos.sql (salida de upsert_rancho54.py) ya haya
-- corrido — este archivo asume que los 3 lotes de UPP 54 y el registro corregido de
-- 0721391811 ya existen.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. lot_id retroactivo para los 24 animales de Rancho 54 ya cargados (migración 036,
--    entonces sin concepto de lote, asignados directo a production_unit_id). Estos 24 ya
--    tienen categoría y palpación correctas — este UPDATE solo agrega la ubicación fina.
-- ---------------------------------------------------------------------------
UPDATE public.cattle_livestock cl
   SET lot_id = lot.id
  FROM public.production_unit_lots lot
  JOIN public.production_units pu ON pu.id = lot.production_unit_id
 WHERE pu.id_company = 6 AND upper(lot.lot_name) = 'RANCHO 54'
   AND cl.rfid_siniiga IN (
     '2715700535','0722090640','2717447832','0721391909','2718676065',
     '0720053283','0722090696','0723039517','2718676070','0723039581',
     '0721391917','0722090699','2717494646','0722090618','2718918034',
     '0723039575','2718918033','0722090559','0722090736','2718026328',
     '2718026336','2718026331','2716583610','2716030126')
   AND cl.lot_id IS NULL;  -- nunca pisa una asignación previa si ya existiera

-- ---------------------------------------------------------------------------
-- 2. Calzada: 16 novillonas nuevas, sin dato de palpación ni linaje en el documento.
-- ---------------------------------------------------------------------------
INSERT INTO public.cattle_livestock
    (tenant_id, rfid_siniiga, category, business_model, current_status, species,
     current_weight_kg, brand_id, production_unit_id, lot_id, metadata)
SELECT 6, v.rfid, 'NOVILLONA', 'CRIA', 'ACTIVO', 'BOVINO', 0,
       (SELECT id FROM public.brand_registrations WHERE upper(brand_code) = 'R'),
       (SELECT id FROM public.production_units WHERE id_company = 6 AND is_active = true LIMIT 1),
       (SELECT l.id FROM public.production_unit_lots l
          JOIN public.production_units pu ON pu.id = l.production_unit_id
         WHERE pu.id_company = 6 AND upper(l.lot_name) = 'LA CALZADA' LIMIT 1),
       jsonb_build_object('edad_declarada', '01 año', 'raza', 'Bill Master', 'peso_no_registrado', true)
  FROM (VALUES
        ('0724019918'),('0724019837'),('0724019867'),('0724019909'),('0724019901'),
        ('0724019797'),('0724019877'),('0724019915'),('0724019923'),
        ('0723593032'),('0723593066'),('0723593029'),
        ('2718500308'),('2718500310'),('2718500311'),('2718727831')
       ) AS v(rfid)
 WHERE NOT EXISTS (SELECT 1 FROM public.cattle_livestock cl WHERE cl.rfid_siniiga = v.rfid);

-- ---------------------------------------------------------------------------
-- 3. Borregos de Rancho 54: 23 cabezas, sin arete individual.
-- Numeración global (row_number sobre todo el conjunto) para garantizar placeholders
-- únicos — un primer borrador de esta migración reutilizaba 1..N dentro de cada grupo,
-- lo que habría producido 'S/N-BORREGO-1' repetido tres veces. Corregido antes de aplicar.
-- ASUNCIÓN marcada explícitamente: "borregos chicos" se interpreta como BORREGO (macho);
-- si en realidad es un grupo mixto, corregir después — no se puede saber del documento.
-- ---------------------------------------------------------------------------
INSERT INTO public.cattle_livestock
    (tenant_id, rfid_siniiga, category, business_model, current_status, species,
     current_weight_kg, brand_id, production_unit_id, lot_id, metadata)
SELECT 6, 'S/N-BORREGO-' || row_number() OVER (), v.categoria, 'CRIA', 'ACTIVO', 'BORREGO', v.peso,
       (SELECT id FROM public.brand_registrations WHERE upper(brand_code) = 'R'),
       (SELECT id FROM public.production_units WHERE id_company = 6 AND is_active = true LIMIT 1),
       (SELECT l.id FROM public.production_unit_lots l
          JOIN public.production_units pu ON pu.id = l.production_unit_id
         WHERE pu.id_company = 6 AND upper(l.lot_name) = 'RANCHO 54' LIMIT 1),
       jsonb_build_object('edad_declarada', v.edad, 'grupo', v.grupo)
  FROM (
        SELECT 'BORREGO' AS categoria, 60 AS peso, '01 año y medio' AS edad, 'Semental' AS grupo
        UNION ALL SELECT 'BORREGA', 30, '01 año', 'Borrega criandera' FROM generate_series(1,11)
        UNION ALL SELECT 'BORREGA', 14, '02 meses', 'Borrega nueva' FROM generate_series(1,6)
        UNION ALL SELECT 'BORREGO', 12, '02 meses', 'Borrego chico' FROM generate_series(1,5)
       ) AS v;

-- ---------------------------------------------------------------------------
-- 4. Becerro Bill Master sin arete (El Triunfo) — alta nueva, sin madre identificada.
-- ---------------------------------------------------------------------------
INSERT INTO public.cattle_livestock
    (tenant_id, rfid_siniiga, category, business_model, current_status, species,
     current_weight_kg, brand_id, production_unit_id, lot_id, metadata)
SELECT 6, 'S/N-BECERRO-ELTRIUNFO-1', 'BECERRO', 'CRIA', 'ACTIVO', 'BOVINO', 152,
       (SELECT id FROM public.brand_registrations WHERE upper(brand_code) = 'R'),
       (SELECT id FROM public.production_units WHERE id_company = 6 AND is_active = true LIMIT 1),
       (SELECT l.id FROM public.production_unit_lots l
          JOIN public.production_units pu ON pu.id = l.production_unit_id
         WHERE pu.id_company = 6 AND upper(l.lot_name) = 'EL TRIUNFO' LIMIT 1),
       jsonb_build_object('raza', 'Bill Master', 'madre_no_identificada', true)
 WHERE NOT EXISTS (
        SELECT 1 FROM public.cattle_livestock
         WHERE rfid_siniiga = 'S/N-BECERRO-ELTRIUNFO-1');

COMMIT;
