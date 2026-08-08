-- Migration 037: Fixes two gaps in psg_licenses left by migration 014.
--
-- BUG 1: no `notes` column. Every other compliance/registry table added in this project
-- (leased_land_sites, ranch_management_protocols, brand_registrations,
-- herd_free_certificates) has one; psg_licenses was missed.
--
-- BUG 2: `issued_at` was declared NOT NULL, which directly contradicts
-- fn_psg_validity_status() — that function was written to handle issued_at IS NULL by
-- returning 'UNKNOWN' (see migration 014's own comment: "constancias do not print an
-- expiry date"), but the table never allowed that state to exist. Surfaced 2026-08-08
-- while loading Pedro's Tabasco PSG: the client confirmed the credential's issue date is
-- ambiguous between two printed dates and asked to leave it unset "por ahora" — a case
-- the function was designed for but the schema silently forbade.
BEGIN;

ALTER TABLE public.psg_licenses
    ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE public.psg_licenses
    ALTER COLUMN issued_at DROP NOT NULL;

COMMENT ON COLUMN public.psg_licenses.issued_at IS
    'Nullable on purpose: some credentials carry ambiguous or absent issue dates. fn_psg_validity_status() treats NULL as UNKNOWN, not as an error.';

COMMIT;
