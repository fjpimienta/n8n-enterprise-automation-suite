-- Migration 038: Alta of 3 breeding bulls arriving at La Bendición (San José y La Pita)
-- via interstate Guía de Tránsito (Tenosique, Tabasco -> Palenque, Chiapas).
--
-- SOURCE: Guía de Tránsito folio 10879, REEMO 1941589, Asociación Ganadera Local
-- "20 de Noviembre" (Tenosique). Motivo: reproducción, pie de cría. Origin UPP
-- 27-017-1621-001 ("Cocotero y San Jorge", Raúl Gustavo Gutiérrez Cortés). This is the
-- first real interstate movement document seen in this project — useful evidence for the
-- still-open cattle_movement_rules design (migration 020), not acted on here: this
-- migration only registers the animals, it does not model the movement itself.
--
-- numero_fuego: client confirmed the printed control numbers (377/375/383) are the
-- animals' quemado, following the same internal bull-numbering convention already seen
-- in migration 034 ("Toro 12" for Ganado Rojo — a separate sequence used only for bulls).
--
-- birth_date: APPROXIMATE. The guía gives age in months at time of transit (27-28 meses),
-- not a birth date. Client explicitly asked to derive it from the month only ("tomar en
-- relación al mes, no tanto la fecha exacta"), so it is computed as first-of-month
-- arithmetic from August 2026 and flagged in metadata as approximate — never presented as
-- an exact date the client didn't provide.
--
-- current_weight_kg: not given on the guía (only age, not weight). Same NOT NULL
-- workaround used throughout this project: 0 + metadata.peso_no_registrado = true.
--
-- brand: 'aR' (Alejandro's own title), confirmed by the client — distinct from most of
-- the recently-loaded batches, which used 'R' (rancho brand).
--
-- Provenance (guía folio, REEMO, seller, origin UPP) is stored in metadata rather than
-- forcing it into historico_movimientos, which is schema-shaped for OUTBOUND exits via
-- sp_procesar_salida_ganado and snapshots upp_origen_anterior on departure — not a fit
-- for an inbound arrival from a third party. A proper movements/arrivals table is exactly
-- what cattle_movement_rules is meant to formalize once its design questions are answered.
BEGIN;

INSERT INTO public.cattle_livestock
    (tenant_id, rfid_siniiga, numero_fuego, category, business_model, current_status,
     species, birth_date, current_weight_kg, brand_id, production_unit_id, metadata)
SELECT 5, v.rfid, v.fuego, 'TORO', 'REPRODUCCION', 'ACTIVO', 'BOVINO',
       v.birth_date::date, 0,
       (SELECT id FROM public.brand_registrations WHERE upper(brand_code) = 'AR'),
       (SELECT id FROM public.production_units
         WHERE upp_code = '07-065-8727-001' AND is_active = true LIMIT 1),
       jsonb_build_object(
           'raza', v.raza,
           'edad_declarada_meses', v.meses,
           'birth_date_aproximado', true,
           'peso_no_registrado', true,
           'procedencia', jsonb_build_object(
               'guia_folio', '10879',
               'reemo', '1941589',
               'upp_origen', '27-017-1621-001',
               'rancho_origen', 'Cocotero y San Jorge',
               'vendedor', 'Raul Gustavo Gutierrez Cortes',
               'motivo', 'Reproduccion, pie de cria',
               'fecha_movimiento_aproximada', '2026-08',
               'municipio_origen', 'Tenosique, Tabasco',
               'municipio_destino', 'Palenque, Chiapas'
           )
       )
  FROM (VALUES
        ('2718122037', '383', 'Droughtmaster', 28, '2024-04-01'),
        ('2718122060', '377', 'Brahman Rojo',  27, '2024-05-01'),
        ('2718122062', '375', 'Brahman Rojo',  28, '2024-04-01')
       ) AS v(rfid, fuego, raza, meses, birth_date)
 WHERE NOT EXISTS (
        SELECT 1 FROM public.cattle_livestock cl WHERE cl.rfid_siniiga = v.rfid);

COMMIT;
