-- Migration 026: Padrón corrections from documents supplied on 2026-07-28/29.
--
-- WHAT CHANGED IN OUR UNDERSTANDING
--   * "UPP 54" is the rancho name; "El Puyacatengo" is the ranchería. Same unit.
--     Its key is 27-009-4146-002, in Jalapa TABASCO — the database had it as
--     Catazajá, Chiapas, which would have made every movement to/from it look
--     intrastate when it is in fact interstate.
--   * Its titular is PEDRO Aguilar Reséndez (the "Dr"), NOT Alejandro. Two holders
--     operate across the same set of predios.
--   * Santa Lucía is currently "bloqueada" per the client. That is a registry state,
--     not is_active = false: the unit exists and its history must stay queryable.
--
-- STILL MISSING (not handled here)
--   * UPP 07-065-6515-001 (La Bendición de Dios, Pedro) — constancia not yet supplied.
--   * Company 5 is named "UPP La Bendición" but the client calls that predio "San José".
--     Its own constancia reads "LA BENDICION DE DIOS ( SAN JOSE Y LA PITA )", and the
--     Dr's separate unit is ALSO called La Bendición de Dios. Renaming is deliberately
--     NOT done here: company_name is denormalized into cattle_livestock.upp_origen for
--     216 animals (migration 023), so a rename must be paired with a re-sync, and the
--     correct name is still ambiguous. Flagged for the client.
--   * The exact meaning of "bloqueada" (SENASICA suspension vs voluntary hold).
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Registry status on production units
-- ---------------------------------------------------------------------------
ALTER TABLE public.production_units
    ADD COLUMN IF NOT EXISTS registry_status character varying(20) NOT NULL DEFAULT 'ACTIVA';

ALTER TABLE public.production_units
    DROP CONSTRAINT IF EXISTS production_units_registry_status_check;

ALTER TABLE public.production_units
    ADD CONSTRAINT production_units_registry_status_check
    CHECK (registry_status IN ('ACTIVA', 'BLOQUEADA', 'SUSPENDIDA', 'BAJA'));

COMMENT ON COLUMN public.production_units.registry_status IS
    'Status before SENASICA. Distinct from is_active: a BLOQUEADA unit still exists and keeps its history, it simply cannot move livestock. is_active = false means the row is retired from our own system.';

-- ---------------------------------------------------------------------------
-- 2. Tenant relocation: UPP 54 is in Jalapa, Tabasco
-- ---------------------------------------------------------------------------
UPDATE public.companys
   SET location = 'Jalapa, Tabasco, México',
       notes    = COALESCE(notes, '') ||
                  ' Rancho "Las 54", ranchería Ría Puyacatengo, Jalapa, Tabasco. UPP 27-009-4146-002, titular Pedro Aguilar Reséndez. Corregido en migración 026: la ubicación previa (Catazajá, Chiapas) era incorrecta.'
 WHERE company_name = 'UPP 54'
   AND location <> 'Jalapa, Tabasco, México';

-- ---------------------------------------------------------------------------
-- 3. Producer: Pedro Aguilar Reséndez (titular of UPP 54)
-- ---------------------------------------------------------------------------
INSERT INTO public.livestock_producers
    (id_company, full_name, producer_role, contact_email, contact_phone,
     address_street, address_number, address_colony, address_locality,
     address_municipality, address_state, address_postal_code)
SELECT c.id_company,
       'PEDRO AGUILAR RESENDEZ',
       'TITULAR',
       'odontologiaintegral@msn.com',
       '9933200341',
       'CALLE 5', '47', 'FRACC NANCE II', 'VILLAHERMOSA',
       'Centro', 'Tabasco', NULL
  FROM public.companys c
 WHERE c.company_name = 'UPP 54'
   AND NOT EXISTS (
        SELECT 1 FROM public.livestock_producers p
         WHERE p.id_company = c.id_company
           AND p.full_name = 'PEDRO AGUILAR RESENDEZ');

SELECT public.sp_upsert_producer_pii(p.id, 'AURP630925HTCGSD05', NULL)
  FROM public.livestock_producers p
 WHERE p.full_name = 'PEDRO AGUILAR RESENDEZ'
   AND p.curp_hash IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Production unit 27-009-4146-002 (El Puyacatengo / Las 54)
-- ---------------------------------------------------------------------------
-- Surface grid transcribed verbatim: the constancia declares 65.78 ha Parcial with
-- every concept cell at 0.00, the same internal inconsistency already seen in Santa Lucía.
INSERT INTO public.production_units
    (id_company, producer_id, upp_code, ranch_name, state_name, municipality_name,
     locality_name, tenure_type, access_directions, total_surface_ha, is_partial_surface,
     surface_matrix, fire_brand_patent, uma_registry, registration_date, last_update_at,
     registry_status)
SELECT c.id_company,
       p.id,
       '27-009-4146-002',
       'EL PUYACATENGO',
       'Tabasco',
       'Jalapa',
       'RIA PUYACATENGO',
       'RENTADA',
       'CARRETERA VILLAHERMOSA - TEAPA HASTA AGAVE, MANO IZQUIERDA RANCHERIA PUYACATENGO, MANO DERECHA A 300 METROS',
       65.78,
       true,
       '{"schema_version": 1,
         "riego":    {"estabulado": 0, "agostadero": 0, "agricola": 0,
                      "forestal_maderable": 0, "praderas": 0, "cultivos_forrajeros": 0},
         "temporal": {"estabulado": 0, "agostadero": 0, "agricola": 0,
                      "forestal_maderable": 0, "praderas": 0, "cultivos_forrajeros": 0},
         "source_note": "Constancia F-887211 declares 65.78 ha Parcial (Temporal) with all concept cells at 0.00. Transcribed as printed."}'::jsonb,
       '155',
       '155',
       DATE '2019-07-08',
       TIMESTAMP '2026-06-22 14:06:24',
       'ACTIVA'
  FROM public.companys c
  LEFT JOIN public.livestock_producers p
         ON p.id_company = c.id_company AND p.producer_role = 'TITULAR'
 WHERE c.company_name = 'UPP 54'
   AND NOT EXISTS (
        SELECT 1 FROM public.production_units pu WHERE pu.upp_code = '27-009-4146-002');

-- ---------------------------------------------------------------------------
-- 5. Certificate F-887211
-- ---------------------------------------------------------------------------
INSERT INTO public.compliance_certificates
    (id_company, production_unit_id, certificate_type, folio, issued_at,
     issuing_window, issuing_officer)
SELECT pu.id_company, pu.id, 'PGN_UPP_UPDATE', 'F-887211', DATE '2026-06-22',
       'VENTANILLA AUTORIZADA SINIIGA TABASCO', 'EDDY GUZMAN LEON'
  FROM public.production_units pu
 WHERE pu.upp_code = '27-009-4146-002'
   AND NOT EXISTS (
        SELECT 1 FROM public.compliance_certificates cc
         WHERE cc.production_unit_id = pu.id AND cc.folio = 'F-887211');

-- ---------------------------------------------------------------------------
-- 6. Declared census
-- ---------------------------------------------------------------------------
-- NOTE: the constancia declares 102 bovines while the system holds 54 buffalo for this
-- tenant. Buffalo may not be counted as BOVINO on the form, or the census predates the
-- current inventory. Recorded as declared; no reconciliation attempted.
INSERT INTO public.livestock_census_snapshots
    (id_company, production_unit_id, certificate_id, snapshot_date, source,
     species_counts, total_head, breed_note, notes)
SELECT pu.id_company,
       pu.id,
       cc.id,
       DATE '2026-06-22',
       'PGN_CERTIFICATE',
       '{"BOVINO": {"vientres": 52, "crias": 18, "sementales": 1, "vaquillas": 6,
                    "novillos": 8, "engorda": 0, "otras": 17, "total": 102},
         "EQUIDO": {"caballos": 9, "burros": 0, "mulas_machos": 0, "yeguas": 0,
                    "sementales": 0, "otros": 0, "total": 9},
         "OVINO": {"total": 0}, "CAPRINO": {"total": 0}, "PORCINO": {"total": 0},
         "AVES": {"total": 0}, "CONEJOS": {"total": 0}, "COLMENAS": {"total": 0}}'::jsonb,
       111,
       'Cruza Europeo/Cebú (bovino) · Criollo (equino)',
       'total_head = 102 bovinos + 9 equinos. Finalidad zootécnica declarada: carne (bovinos), trabajo (équidos).'
  FROM public.production_units pu
  JOIN public.compliance_certificates cc
    ON cc.production_unit_id = pu.id AND cc.folio = 'F-887211'
 WHERE pu.upp_code = '27-009-4146-002'
   AND NOT EXISTS (
        SELECT 1 FROM public.livestock_census_snapshots lcs
         WHERE lcs.production_unit_id = pu.id
           AND lcs.snapshot_date = DATE '2026-06-22');

-- ---------------------------------------------------------------------------
-- 7. Santa Lucía is currently blocked
-- ---------------------------------------------------------------------------
UPDATE public.production_units
   SET registry_status = 'BLOQUEADA'
 WHERE upp_code = '07-065-8643-001'
   AND registry_status <> 'BLOQUEADA';

-- ---------------------------------------------------------------------------
-- 8. Link the 54 head of UPP 54 to their production unit
-- ---------------------------------------------------------------------------
UPDATE public.cattle_livestock cl
   SET production_unit_id = pu.id,
       upp_origen         = c.company_name
  FROM public.production_units pu
  JOIN public.companys c ON c.id_company = pu.id_company
 WHERE pu.upp_code = '27-009-4146-002'
   AND cl.tenant_id = pu.id_company
   AND cl.production_unit_id IS NULL
   AND cl.current_status <> 'VENDIDO';

COMMIT;
