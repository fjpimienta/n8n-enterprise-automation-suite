-- Migration 013: Certificate history (folios) and audit-grade document custody.
--
-- Why a separate certificates table: hologram folios change on every re-issue
-- (E-882100, F-273464, F-433185, F-591164). Holding "the current folio" as a column on
-- production_units destroys the audit trail on the second re-issue. This table is
-- APPEND-ONLY by convention and by Meta-CRUD permissions (no UPDATE/DELETE ops).
--
-- Document custody: files are NOT stored as bytea. Storing PDFs in-row inflates every
-- pg_dump and forces the n8n gateway to paginate blobs. What gives the record probative
-- value is sha256_hash: it proves the file served today is bit-for-bit the one filed.
BEGIN;

CREATE TABLE IF NOT EXISTS public.compliance_certificates (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid,
    psg_license_id      uuid,          -- FK added in migration 014 (table does not exist yet)

    certificate_type    character varying(40) NOT NULL,
    folio               character varying(50) NOT NULL,
    issued_at           date NOT NULL,
    issuing_window      character varying(255),
    issuing_officer     character varying(255),
    source_url          text,
    notes               text,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT compliance_certificates_type_check
        CHECK (certificate_type IN (
            'PGN_UPP_REGISTRATION',   -- alta de UPP en el Padrón Ganadero Nacional
            'PGN_UPP_UPDATE',         -- constancia de actualización de UPP
            'PGN_PSG_UPDATE'          -- constancia de actualización de PSG
        )),
    -- Every certificate belongs to exactly one subject: a UPP or a PSG, never both.
    CONSTRAINT compliance_certificates_single_subject_check
        CHECK (num_nonnulls(production_unit_id, psg_license_id) = 1),
    CONSTRAINT fk_compliance_certificates_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_compliance_certificates_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_compliance_certificates_folio
    ON public.compliance_certificates (id_company, certificate_type, folio);
CREATE INDEX IF NOT EXISTS idx_compliance_certificates_unit
    ON public.compliance_certificates (production_unit_id);
CREATE INDEX IF NOT EXISTS idx_compliance_certificates_company_issued
    ON public.compliance_certificates (id_company, issued_at DESC);

COMMENT ON TABLE public.compliance_certificates IS
    'Append-only history of SENASICA-SINIIGA constancias. Never update a row: a re-issued constancia is a NEW row.';


CREATE TABLE IF NOT EXISTS public.compliance_documents (
    id              uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company      integer NOT NULL,

    -- Polymorphic on purpose: one Meta-CRUD model instead of one table per subject.
    -- entity_id is intentionally NOT a FK; integrity is enforced by the write path.
    entity_type     character varying(40) NOT NULL,
    entity_id       uuid NOT NULL,

    storage_key     text NOT NULL,
    original_name   character varying(255),
    mime_type       character varying(100) NOT NULL,
    size_bytes      bigint,
    sha256_hash     character varying(64) NOT NULL,

    uploaded_by     character varying(255),
    uploaded_at     timestamp without time zone DEFAULT now(),

    CONSTRAINT compliance_documents_entity_type_check
        CHECK (entity_type IN ('COMPLIANCE_CERTIFICATE','PRODUCTION_UNIT','PSG_LICENSE')),
    CONSTRAINT compliance_documents_hash_format_check
        CHECK (sha256_hash ~ '^[a-f0-9]{64}$'),
    CONSTRAINT compliance_documents_size_check
        CHECK (size_bytes IS NULL OR size_bytes > 0),
    CONSTRAINT fk_compliance_documents_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_compliance_documents_uploader
        FOREIGN KEY (uploaded_by) REFERENCES public.users(email) ON DELETE SET NULL
);

-- The same physical file filed twice against the same subject is a duplicate, not a version.
CREATE UNIQUE INDEX IF NOT EXISTS uq_compliance_documents_hash_per_entity
    ON public.compliance_documents (entity_type, entity_id, sha256_hash);
CREATE INDEX IF NOT EXISTS idx_compliance_documents_entity
    ON public.compliance_documents (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_compliance_documents_company
    ON public.compliance_documents (id_company);

COMMENT ON TABLE public.compliance_documents IS
    'Custody of original PDF/JPEG evidence. Files live outside the DB and outside the web root; storage_key is resolved by an authenticated endpoint that validates id_company against user_companies. A guessable public path is a cross-tenant leak no interceptor can catch.';
COMMENT ON COLUMN public.compliance_documents.sha256_hash IS
    'Integrity proof. Recompute on download and compare: a mismatch means the artifact was altered after filing.';

COMMIT;
