-- Migration 014: PSG licenses (Prestador de Servicios Ganaderos).
--
-- A PSG belongs to the PERSON, not to a predio: hanging it off production_units would be a
-- domain error. It is operational, not merely documentary — it gates livestock movements —
-- so validity window and territorial scope are first-class columns.
--
-- Territorial scope is derived from the code (EE-MMM-NNNN-Pnn), same INEGI encoding as UPP.
-- The Chiapas Norte constancia prints no expiry date, so expires_at is NULLABLE and its
-- semantics are configured per tenant (see fn_psg_validity_status).
BEGIN;

CREATE TABLE IF NOT EXISTS public.psg_licenses (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    producer_id         uuid,

    psg_code            character varying(20) NOT NULL,

    state_code          character varying(2)
                        GENERATED ALWAYS AS (substring(psg_code from 1 for 2)) STORED,
    municipality_code   character varying(3)
                        GENERATED ALWAYS AS (substring(psg_code from 4 for 3)) STORED,

    state_name          character varying(100),
    municipality_name   character varying(255),
    issuing_window      character varying(255),

    issued_at           date NOT NULL,
    expires_at          date,

    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamp without time zone DEFAULT now(),
    updated_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT psg_licenses_code_format_check
        CHECK (psg_code ~ '^[0-9]{2}-[0-9]{3}-[0-9]{4}-P[0-9]{2}$'),
    CONSTRAINT psg_licenses_dates_check
        CHECK (expires_at IS NULL OR expires_at > issued_at),
    CONSTRAINT fk_psg_licenses_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_psg_licenses_producer
        FOREIGN KEY (producer_id) REFERENCES public.livestock_producers(id) ON DELETE SET NULL
);

-- Scoped per tenant, NOT globally: the same person operating two tenants legitimately
-- needs the same PSG replicated, mirroring the producer replication decision.
CREATE UNIQUE INDEX IF NOT EXISTS uq_psg_licenses_active_code_per_company
    ON public.psg_licenses (id_company, psg_code)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_psg_licenses_company
    ON public.psg_licenses (id_company);
CREATE INDEX IF NOT EXISTS idx_psg_licenses_territory
    ON public.psg_licenses (state_code, municipality_code);

COMMENT ON TABLE public.psg_licenses IS
    'PSG licenses. Operational: gates livestock movements. Belongs to the producer, replicated per tenant.';

-- Deferred FK from migration 013 (psg_licenses did not exist yet at that point).
ALTER TABLE public.compliance_certificates
    DROP CONSTRAINT IF EXISTS fk_compliance_certificates_psg;
ALTER TABLE public.compliance_certificates
    ADD CONSTRAINT fk_compliance_certificates_psg
    FOREIGN KEY (psg_license_id) REFERENCES public.psg_licenses(id) ON DELETE CASCADE;

-- Validity resolver. p_default_validity_months applies only when expires_at is NULL,
-- which is the real-world case: the constancias do not print an expiry date.
CREATE OR REPLACE FUNCTION public.fn_psg_validity_status(
    p_issued_at date,
    p_expires_at date,
    p_default_validity_months integer DEFAULT 12,
    p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_issued_at IS NULL THEN 'UNKNOWN'
        WHEN COALESCE(p_expires_at,
                      (p_issued_at + (p_default_validity_months || ' months')::interval)::date)
             < p_reference_date THEN 'EXPIRED'
        WHEN COALESCE(p_expires_at,
                      (p_issued_at + (p_default_validity_months || ' months')::interval)::date)
             < (p_reference_date + 30) THEN 'EXPIRING_SOON'
        ELSE 'VALID'
    END;
$$;

COMMENT ON FUNCTION public.fn_psg_validity_status(date, date, integer, date) IS
    'Resolves PSG validity. ASSUMPTION PENDING CLIENT CONFIRMATION: 12-month default validity when the constancia prints no expiry date. Override per tenant via companys.metadata->>psg_validity_months.';

COMMIT;
