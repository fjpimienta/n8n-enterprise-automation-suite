-- Migration 019: Seeds the registry with the client's real SENASICA-SINIIGA documents.
-- Fully idempotent: safe to re-run.
--
-- SOURCE DOCUMENTS
--   Upp_2025_Nh_Santa_Luci_a_.pdf  -> UPP 07-065-8643-001, folio F-273464
--   WhatsApp_Image_2026-07-26.jpeg -> UPP 07-065-8727-001, folio E-882100
--   Psg_y_upp_2025_san_pedro.pdf   -> UPP 27-009-0514-001, folio 441740 + PSG 27-009-0562-P14, folio F-433185
--   Psg_playas_NH_2026.pdf         -> PSG 07-016-0053-P02, folio F-591164
--
-- ASSUMPTIONS PENDING CLIENT CONFIRMATION (marked ASSUMPTION below):
--   A1. New tenants 'UPP Santa Lucía y Anexo Nuevo Horizonte 2' and 'UPP San Pedro' inherit
--       the attributes of the existing livestock tenants (size, revenue band, priority).
--   A2. Alejandro Aguilar Reséndez is registered as TITULAR in all three tenants. The
--       TITULAR/SOCIO split per tenant was not supplied and must be corrected once known.
--   A3. PSG territorial assignment follows the state of the predio: the Chiapas Norte PSG
--       is replicated to both Chiapas tenants, the Tabasco PSG to the Tabasco tenant.
--   A4. The producer's RFC is not legible on the constancia (the field overlaps the CURP),
--       so only the CURP is stored.
BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Sequence repair. The 7 pre-existing companies were inserted with explicit
-- id_company values, leaving companys_id_company_seq behind max(id_company).
-- The first INSERT without an explicit id therefore collides on the primary key.
-- setval only moves the counter: no row is read, written or deleted.
-- ---------------------------------------------------------------------------
SELECT setval('public.companys_id_company_seq',
              GREATEST((SELECT max(id_company) FROM public.companys), 1),
              true);

-- ---------------------------------------------------------------------------
-- 1. Tenants
-- ---------------------------------------------------------------------------
INSERT INTO public.companys
    (company_name, relation_type, industry, company_size, location, employees,
     annual_revenue, priority_level, registration_date, notes, is_default, is_active, org_type)
SELECT v.company_name, 'Cliente', 'Ganadería de Precisión', 'Pequeña', v.location, 10,
       'Menos de $1M USD', 'Alta', v.registration_date, v.notes, false, true, 'GANADERO'
  FROM (VALUES
        ('UPP Santa Lucía y Anexo Nuevo Horizonte 2', 'Palenque, Chiapas, México',
         DATE '2022-02-10', 'Unidad de producción pecuaria registrada ante SENASICA (UPP 07-065-8643-001). ASSUMPTION A1.'),
        ('UPP San Pedro', 'Jalapa, Tabasco, México',
         DATE '2015-01-01', 'Centro de Producción Agropecuaria registrado ante SENASICA (UPP 27-009-0514-001). ASSUMPTION A1.')
       ) AS v(company_name, location, registration_date, notes)
 WHERE NOT EXISTS (
        SELECT 1 FROM public.companys c WHERE c.company_name = v.company_name);

-- ---------------------------------------------------------------------------
-- 2. Producer (replicated per tenant - deliberate, see migration 011)
-- ---------------------------------------------------------------------------
INSERT INTO public.livestock_producers
    (id_company, full_name, producer_role, contact_email, contact_phone,
     address_street, address_number, address_colony, address_locality,
     address_municipality, address_state, address_postal_code)
SELECT c.id_company,
       'ALEJANDRO AGUILAR RESENDEZ',
       'TITULAR',                              -- ASSUMPTION A2
       'aguilar.resendez@hotmail.com',
       '9933113526',
       'C CREPUSCULO', '114 INT 5', 'JOSE MARIA PINO SUAREZ', 'CENTRO',
       'Centro', 'Tabasco', '86029'
  FROM public.companys c
 WHERE c.company_name IN ('UPP La Bendición',
                          'UPP Santa Lucía y Anexo Nuevo Horizonte 2',
                          'UPP San Pedro')
   AND NOT EXISTS (
        SELECT 1 FROM public.livestock_producers p
         WHERE p.id_company = c.id_company
           AND p.full_name = 'ALEJANDRO AGUILAR RESENDEZ');

-- CURP is written through the encrypting routine, never as plaintext into the table.
SELECT public.sp_upsert_producer_pii(p.id, 'AURA720829HTCGSL05', NULL)
  FROM public.livestock_producers p
 WHERE p.full_name = 'ALEJANDRO AGUILAR RESENDEZ'
   AND p.curp_hash IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Production units (UPP)
-- ---------------------------------------------------------------------------
INSERT INTO public.production_units
    (id_company, producer_id, upp_code, ranch_name, state_name, municipality_name,
     locality_name, tenure_type, access_directions, total_surface_ha, is_partial_surface,
     surface_matrix, registration_date, last_update_at)
SELECT c.id_company,
       p.id,
       v.upp_code, v.ranch_name, v.state_name, v.municipality_name, v.locality_name,
       v.tenure_type, v.access_directions, v.total_surface_ha, v.is_partial_surface,
       v.surface_matrix, v.registration_date, v.last_update_at
  FROM (VALUES
        -- La Bendición de Dios. Surface grid was not legible on the scanned image, so the
        -- matrix stays NULL rather than being invented; only the header total is recorded.
        ('UPP La Bendición',
         '07-065-8727-001',
         'LA BENDICION DE DIOS (SAN JOSE Y LA PITA)',
         'Chiapas', 'Palenque', 'POBLADO RAYMUNDO ENRIQUEZ', 'PRIVADA',
         'CARRETERA PALENQUE - CRUCERO CATAZAJA - HACIA ZAPATA - ENTRADA A LA DERECHA KM 124.5 - LA BENDICION DE DIOS (SAN JOSE Y LA PITA)',
         144.36::numeric, true,
         NULL::jsonb,
         DATE '2022-07-14', TIMESTAMP '2024-10-04 12:11:35'),

        -- Santa Lucía. The constancia declares 42.00 ha (Temporal / Total) while every
        -- concept cell reads 0.00. Transcribed verbatim: has_surface_inconsistency will
        -- flag it in vw_upp_compliance_status. Do not "fix" the source document here.
        ('UPP Santa Lucía y Anexo Nuevo Horizonte 2',
         '07-065-8643-001',
         'SANTA LUCIA Y ANEXO NUEVO HORIZONTE 2',
         'Chiapas', 'Palenque', 'PALENQUE', 'PRIVADA',
         'CARRETERA PALENQUE - EMILIANO ZAPATA KM. 123.5, ENTRADA POR RAYMUNDO ENRIQUEZ SAN FRANCISCO SANTA LUCIA',
         42.00::numeric, false,
         '{"schema_version": 1,
           "riego":    {"estabulado": 0, "agostadero": 0, "agricola": 0,
                        "forestal_maderable": 0, "praderas": 0, "cultivos_forrajeros": 0},
           "temporal": {"estabulado": 0, "agostadero": 0, "agricola": 0,
                        "forestal_maderable": 0, "praderas": 0, "cultivos_forrajeros": 0},
           "source_note": "Constancia declares 42.00 ha total (Temporal) with all concept cells at 0.00. Transcribed as printed."}'::jsonb,
         DATE '2022-02-10', TIMESTAMP '2025-02-06 09:19:27'),

        -- San Pedro. The registration certificate carries no surface grid.
        ('UPP San Pedro',
         '27-009-0514-001',
         'SAN PEDRO CENTRO DE PRODUCCION AGROPECUARIA',
         'Tabasco', 'Jalapa', NULL, NULL,
         NULL,
         NULL::numeric, false,
         NULL::jsonb,
         DATE '2015-01-01', NULL::timestamp)
       ) AS v(company_name, upp_code, ranch_name, state_name, municipality_name,
              locality_name, tenure_type, access_directions, total_surface_ha,
              is_partial_surface, surface_matrix, registration_date, last_update_at)
  JOIN public.companys c ON c.company_name = v.company_name
  LEFT JOIN public.livestock_producers p
         ON p.id_company = c.id_company AND p.producer_role = 'TITULAR'
 WHERE NOT EXISTS (
        SELECT 1 FROM public.production_units pu WHERE pu.upp_code = v.upp_code);

-- ---------------------------------------------------------------------------
-- 4. PSG licenses (ASSUMPTION A3: assigned by state of operation)
-- ---------------------------------------------------------------------------
INSERT INTO public.psg_licenses
    (id_company, producer_id, psg_code, state_name, municipality_name,
     issuing_window, issued_at)
SELECT c.id_company, p.id, v.psg_code, v.state_name, v.municipality_name,
       v.issuing_window, v.issued_at
  FROM (VALUES
        ('UPP La Bendición',                        '07-016-0053-P02', 'Chiapas', 'Catazajá',
         'VENTANILLA AUTORIZADA SINIIGA CHIAPAS NORTE', DATE '2026-05-29'),
        ('UPP Santa Lucía y Anexo Nuevo Horizonte 2','07-016-0053-P02', 'Chiapas', 'Catazajá',
         'VENTANILLA AUTORIZADA SINIIGA CHIAPAS NORTE', DATE '2026-05-29'),
        ('UPP San Pedro',                           '27-009-0562-P14', 'Tabasco', 'Jalapa',
         'VENTANILLA AUTORIZADA SINIIGA TABASCO',       DATE '2025-02-12')
       ) AS v(company_name, psg_code, state_name, municipality_name, issuing_window, issued_at)
  JOIN public.companys c ON c.company_name = v.company_name
  LEFT JOIN public.livestock_producers p
         ON p.id_company = c.id_company AND p.producer_role = 'TITULAR'
 WHERE NOT EXISTS (
        SELECT 1 FROM public.psg_licenses pl
         WHERE pl.id_company = c.id_company AND pl.psg_code = v.psg_code);

-- ---------------------------------------------------------------------------
-- 5. Certificates (hologram folio history)
-- ---------------------------------------------------------------------------
INSERT INTO public.compliance_certificates
    (id_company, production_unit_id, certificate_type, folio, issued_at,
     issuing_window, issuing_officer, source_url)
SELECT pu.id_company, pu.id, v.certificate_type, v.folio, v.issued_at,
       v.issuing_window, v.issuing_officer, v.source_url
  FROM (VALUES
        ('07-065-8727-001', 'PGN_UPP_UPDATE',       'E-882100', DATE '2024-10-04',
         NULL, NULL, 'https://sinidasiniiga.senasica.gob.mx/programacion/reporte-pgnact.php'),
        ('07-065-8643-001', 'PGN_UPP_UPDATE',       'F-273464', DATE '2025-02-06',
         'CSI PALENQUE', 'DIANA JAZMIN DIAZ RODRIGUEZ',
         'https://sinidasiniiga.senasica.gob.mx/programacion/reporte-pgnact.php'),
        ('27-009-0514-001', 'PGN_UPP_REGISTRATION', '441740',   DATE '2025-02-12',
         'VENTANILLA AUTORIZADA SINIIGA TABASCO', 'YURY BAUTISTA OLMEDO',
         'https://sinidasiniiga.senasica.gob.mx/programacion/constancia.php?id_upp=270090514001&folio=441740')
       ) AS v(upp_code, certificate_type, folio, issued_at, issuing_window, issuing_officer, source_url)
  JOIN public.production_units pu ON pu.upp_code = v.upp_code
 WHERE NOT EXISTS (
        SELECT 1 FROM public.compliance_certificates cc
         WHERE cc.production_unit_id = pu.id AND cc.folio = v.folio);

INSERT INTO public.compliance_certificates
    (id_company, psg_license_id, certificate_type, folio, issued_at,
     issuing_window, issuing_officer, source_url)
SELECT pl.id_company, pl.id, 'PGN_PSG_UPDATE', v.folio, v.issued_at,
       v.issuing_window, v.issuing_officer, v.source_url
  FROM (VALUES
        ('07-016-0053-P02', 'F-591164', DATE '2026-05-29',
         'VENTANILLA AUTORIZADA SINIIGA CHIAPAS NORTE', 'FRANCISCA DEL CARMEN GONZALEZ ORTIZ',
         'https://sinidasiniiga.senasica.gob.mx/programacion/constanciaActualPSG.php?opcion=1'),
        ('27-009-0562-P14', 'F-433185', DATE '2025-02-12',
         'VENTANILLA AUTORIZADA SINIIGA TABASCO', 'YURY BAUTISTA OLMEDO',
         'https://sinidasiniiga.senasica.gob.mx/programacion/constanciaActualPSG.php?opcion=1')
       ) AS v(psg_code, folio, issued_at, issuing_window, issuing_officer, source_url)
  JOIN public.psg_licenses pl ON pl.psg_code = v.psg_code
 WHERE NOT EXISTS (
        SELECT 1 FROM public.compliance_certificates cc
         WHERE cc.psg_license_id = pl.id AND cc.folio = v.folio);

-- ---------------------------------------------------------------------------
-- 6. Declared census (Santa Lucía is the only constancia carrying head counts)
-- ---------------------------------------------------------------------------
INSERT INTO public.livestock_census_snapshots
    (id_company, production_unit_id, certificate_id, snapshot_date, source,
     species_counts, total_head, breed_note, notes)
SELECT pu.id_company,
       pu.id,
       cc.id,
       DATE '2025-02-06',
       'PGN_CERTIFICATE',
       '{"BOVINO": {"vientres": 128, "crias": 0, "sementales": 7, "vaquillas": 41,
                    "novillos": 3, "engorda": 0, "otras": 121, "total": 300},
         "EQUIDO": {"caballos": 2, "burros": 0, "mulas_machos": 0, "yeguas": 0,
                    "sementales": 0, "otros": 0, "total": 2},
         "OVINO": {"total": 0}, "CAPRINO": {"total": 0}, "PORCINO": {"total": 0},
         "AVES": {"total": 0}, "CONEJOS": {"total": 0}, "COLMENAS": {"total": 0}}'::jsonb,
       302,
       'Cruza Europeo/Cebú',
       'total_head is the sum of all declared species (300 bovine + 2 equine). The bovine subtotal alone is 300.'
  FROM public.production_units pu
  JOIN public.compliance_certificates cc
    ON cc.production_unit_id = pu.id AND cc.folio = 'F-273464'
 WHERE pu.upp_code = '07-065-8643-001'
   AND NOT EXISTS (
        SELECT 1 FROM public.livestock_census_snapshots lcs
         WHERE lcs.production_unit_id = pu.id
           AND lcs.snapshot_date = DATE '2025-02-06'
           AND lcs.source = 'PGN_CERTIFICATE');

COMMIT;
