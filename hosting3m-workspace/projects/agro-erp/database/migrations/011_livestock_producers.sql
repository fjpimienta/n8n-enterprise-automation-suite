-- Migration 011: Producer registry (holder of the UPP / PSG before SENASICA-SINIIGA).
--
-- Design decisions:
--  * REPLICATED PER TENANT (id_company NOT NULL). The same physical person may appear in
--    several tenants with a different role (TITULAR in one, SOCIO in another). A single
--    global producer row shared across tenants would be a cross-tenant leak by design.
--  * CURP is personal data under LFPDPPP. It is stored encrypted (pgcrypto), following the
--    precedent already in production: employee_credentials.curp_enc + nss_hash. A SHA-256
--    hash column enables equality lookups without decrypting.
--  * The producer's fiscal address is NOT the location of the ranch. Predio location lives
--    in production_units (migration 012).
--
-- TECH DEBT flagged: view_employee_credentials hardcodes the pgcrypto symmetric key in the
-- view body, so anyone with \d+ on the view can read it. This migration reuses the same key
-- for consistency but centralizes it in fn_pii_key() so a future rotation is a one-line
-- change instead of a schema-wide hunt. Moving the key to a GUC / external KMS is tracked
-- separately and is NOT solved here.
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_pii_key()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT '6nbXOSu79Vjx6g2ySP80I46imAqNToZ/NDVWJsc9AV1d/D82KHcPFfbFYFIrTgqy'::text;
$$;

COMMENT ON FUNCTION public.fn_pii_key() IS
    'Single source of truth for the pgcrypto symmetric key used by PII columns. TECH DEBT: key is embedded in the function body, mirroring the pre-existing view_employee_credentials pattern. Migrate to a GUC or external KMS.';

CREATE TABLE IF NOT EXISTS public.livestock_producers (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    full_name           character varying(255) NOT NULL,
    producer_role       character varying(20) NOT NULL DEFAULT 'TITULAR',

    -- Encrypted PII
    curp_enc            bytea,
    curp_hash           text,
    rfc_enc             bytea,
    rfc_hash            text,

    -- Contact
    contact_email       character varying(255),
    contact_phone       character varying(50),

    -- Fiscal address of the PERSON (not the ranch)
    address_street      character varying(255),
    address_number      character varying(50),
    address_colony      character varying(255),
    address_locality    character varying(255),
    address_municipality character varying(255),
    address_state       character varying(100),
    address_postal_code character varying(10),

    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamp without time zone DEFAULT now(),
    updated_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT livestock_producers_role_check
        CHECK (producer_role IN ('TITULAR', 'SOCIO', 'REPRESENTANTE')),
    CONSTRAINT fk_livestock_producers_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE
);

-- Exactly one TITULAR per tenant. SOCIO / REPRESENTANTE are unbounded.
CREATE UNIQUE INDEX IF NOT EXISTS uq_livestock_producers_single_titular
    ON public.livestock_producers (id_company)
    WHERE producer_role = 'TITULAR' AND is_active = true;

-- Same person cannot be registered twice inside the same tenant.
CREATE UNIQUE INDEX IF NOT EXISTS uq_livestock_producers_curp_per_company
    ON public.livestock_producers (id_company, curp_hash)
    WHERE curp_hash IS NOT NULL AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_livestock_producers_company
    ON public.livestock_producers (id_company);

COMMENT ON TABLE public.livestock_producers IS
    'Producer / holder registry before SENASICA-SINIIGA. Replicated per tenant on purpose: the same person in two tenants is two rows, preventing cross-tenant PII exposure.';
COMMENT ON COLUMN public.livestock_producers.curp_hash IS
    'SHA-256 of the uppercase CURP. Enables equality lookup and duplicate detection without decrypting.';

-- Helper: writes the encrypted pair (value + hash) in one call, so callers never handle the key.
CREATE OR REPLACE FUNCTION public.fn_encrypt_pii(p_plain text)
RETURNS bytea
LANGUAGE sql
VOLATILE
AS $$
    SELECT CASE
        WHEN p_plain IS NULL OR btrim(p_plain) = '' THEN NULL
        ELSE public.pgp_sym_encrypt(upper(btrim(p_plain)), public.fn_pii_key())
    END;
$$;

CREATE OR REPLACE FUNCTION public.fn_hash_pii(p_plain text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_plain IS NULL OR btrim(p_plain) = '' THEN NULL
        ELSE encode(public.digest(upper(btrim(p_plain)), 'sha256'), 'hex')
    END;
$$;

-- Decrypting view. Exposed to ADMIN / OWNER only (see migration 017); the raw table is
-- never registered in crud_models, so the generic gateway cannot return ciphertext either.
CREATE OR REPLACE VIEW public.vw_livestock_producers AS
 SELECT p.id,
        p.id_company,
        p.full_name,
        p.producer_role,
        CASE WHEN p.curp_enc IS NULL THEN NULL
             ELSE public.pgp_sym_decrypt(p.curp_enc, public.fn_pii_key()) END AS curp,
        CASE WHEN p.rfc_enc IS NULL THEN NULL
             ELSE public.pgp_sym_decrypt(p.rfc_enc, public.fn_pii_key()) END AS rfc,
        p.contact_email,
        p.contact_phone,
        p.address_street,
        p.address_number,
        p.address_colony,
        p.address_locality,
        p.address_municipality,
        p.address_state,
        p.address_postal_code,
        p.is_active,
        p.created_at,
        p.updated_at
   FROM public.livestock_producers p;

COMMIT;
