-- Migration 044: Movement compliance documents (REEMO, CZM, GBG, state permit, ownership letter)
--
-- Confirmed by Alejandro/Pedro with real document examples (Aug 2026):
--   - The screwworm (GBG) requirement is a real, separate, mandatory
--     document (constancia de tratamiento y/o inspección para GBG),
--     required as a PREREQUISITE before SENASICA/OIRSA-accredited officials
--     can issue the CZM (Certificado Zoosanitario de Movilización). It is
--     NOT embedded within the CZM itself, and it is NOT what OIRSA issues
--     directly -- OIRSA accredits the officials/organization that issues
--     the CZM more broadly. Independently verified: DOF published the
--     DINESA expansion covering this Dec 2, 2025, and SENASICA explicitly
--     lists Chiapas and Tabasco as maximum-risk zones.
--   - The "Cesión de Derechos" / ownership-transfer letter is used for
--     same-owner UPP-to-UPP interstate movements, to accredit possession
--     under state civil/administrative authority even where a March 2026
--     SCJN ruling (Controversia Constitucional 216/2025) invalidated some
--     state-level movement PERMITS as federal-authority overreach. Note:
--     that ruling was specifically against a Nayarit law; whether it has
--     general binding effect on other states (including Chiapas/Tabasco)
--     is a legal question outside this migration's scope.
--   - The state "Permiso de Internación" is confirmed still required by
--     Alejandro/Pedro in current practice for interstate movements,
--     independent of the SCJN ruling's legal reach -- no change needed to
--     the requires_introduction_permit values already stored in 042.
--
-- Real document chain observed for an interstate movement (4 documents):
--   1. Guía de Tránsito (REEMO) -- issued by the origin state's local
--      cattle association. Own folio + REEMO number.
--   2. Certificado Zoosanitario de Movilización (CZM) -- issued by a
--      SENASICA/OIRSA-accredited certifying body. Own SADER folio;
--      references TB/BR test folios internally.
--   3. Permiso de Internación -- issued by the DESTINATION state's
--      Dirección de Sanidad. Own authorization number and validity window.
--   4. Cesión de Derechos / carta de traslado -- used for same-owner
--      interstate UPP-to-UPP movements to accredit possession.
--
-- This migration extends compliance_certificates (013) to link a
-- certificate to the specific movement it supports, and adds an
-- expiration field since every one of the real documents above carries
-- its own short validity window (typically 5 days).

BEGIN;

-- Column rename for accuracy: the confirmed required document is the GBG
-- (Gusano Barrenador del Ganado) treatment/inspection constancia, not
-- something issued by OIRSA directly.
ALTER TABLE cattle_movement_rules
    RENAME COLUMN requires_oirsa_certificate TO requires_gbg_certificate;

COMMENT ON COLUMN cattle_movement_rules.requires_gbg_certificate IS
    'Whether a GBG (Gusano Barrenador del Ganado) treatment/inspection constancia is required -- a prerequisite for CZM issuance under the DINESA emergency measures (DOF, Dec 2, 2025). Confirmed applicable to interstate movements in/through Chiapas and Tabasco, both listed by SENASICA as maximum-risk zones. Not the same as OIRSA accreditation of the CZM-issuing body.';

ALTER TABLE compliance_certificates
    ADD COLUMN movement_event_id UUID REFERENCES cattle_movement_events(id),
    ADD COLUMN expires_at TIMESTAMPTZ;

CREATE INDEX idx_compliance_certificates_movement_event ON compliance_certificates(movement_event_id);

ALTER TABLE compliance_certificates
    DROP CONSTRAINT IF EXISTS compliance_certificates_type_check;

ALTER TABLE compliance_certificates
    ADD CONSTRAINT compliance_certificates_type_check CHECK (
        certificate_type IN (
            'PGN_UPP_REGISTRATION',
            'PGN_UPP_UPDATE',
            'PGN_PSG_UPDATE',
            'REEMO_TRANSIT_GUIDE',
            'CZM_MOVEMENT_CERTIFICATE',
            'GBG_TREATMENT_CERTIFICATE',
            'STATE_INTRODUCTION_PERMIT',
            'OWNERSHIP_TRANSFER_LETTER'
        )
    );

COMMENT ON COLUMN compliance_certificates.movement_event_id IS
    'Links this certificate to the specific movement it supports, when applicable. Nullable: certificates issued for a production_unit or psg_license in general (not tied to one movement) leave this null.';
COMMENT ON COLUMN compliance_certificates.expires_at IS
    'Validity end date, when the certificate type carries one. All movement-related document types observed in real examples (REEMO guide, CZM, state introduction permit) carry a short validity window, typically 5 days from issuance.';
COMMENT ON CONSTRAINT compliance_certificates_type_check ON compliance_certificates IS
    'REEMO_TRANSIT_GUIDE: origin-state local cattle association transit guide. CZM_MOVEMENT_CERTIFICATE: SENASICA/OIRSA-accredited zoosanitary movement certificate; internally references TB/BR test folios. GBG_TREATMENT_CERTIFICATE: screwworm treatment/inspection constancia, prerequisite for CZM issuance. STATE_INTRODUCTION_PERMIT: destination state Dirección de Sanidad authorization. OWNERSHIP_TRANSFER_LETTER: same-owner interstate UPP-to-UPP possession accreditation (cesión de derechos).';

COMMIT;
