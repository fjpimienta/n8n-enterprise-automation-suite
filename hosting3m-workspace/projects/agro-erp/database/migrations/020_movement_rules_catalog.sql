-- Migration 020: Movement rule matrix (UPP <-> PSG).
--
-- ⚠️ THIS MIGRATION IS A PROPOSAL, NOT A RULESET. It creates the catalog structure and
-- seeds it with a DRAFT matrix flagged is_confirmed = false. Nothing enforces these rules:
-- no movement transaction table is created and sp_procesar_salida_ganado is untouched.
--
-- Reason: the client stated "hay reglas definidas para eso" but the rules themselves were
-- not supplied. Six questions remain open (valid origin/destination pairs, PSG validity at
-- movement date vs capture date, interstate scope, atomic vs multi-state transit with
-- destination acknowledgement, individual animal vs batch, and whether a movement may cross
-- tenants). Guessing them would produce a compliance engine that is confidently wrong —
-- worse than none. Run this migration only after the matrix below has been reviewed.
BEGIN;

CREATE TABLE IF NOT EXISTS public.cattle_movement_rules (
    id                        uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    origin_type               character varying(20) NOT NULL,
    destination_type          character varying(20) NOT NULL,
    is_allowed                boolean NOT NULL DEFAULT true,
    requires_valid_psg        boolean NOT NULL DEFAULT true,
    requires_health_tests     boolean NOT NULL DEFAULT true,
    allows_interstate         boolean NOT NULL DEFAULT false,
    requires_destination_ack  boolean NOT NULL DEFAULT true,
    is_confirmed              boolean NOT NULL DEFAULT false,
    notes                     text,
    created_at                timestamp without time zone DEFAULT now(),

    CONSTRAINT cattle_movement_rules_origin_check
        CHECK (origin_type IN ('UPP','PSG')),
    CONSTRAINT cattle_movement_rules_destination_check
        CHECK (destination_type IN ('UPP','PSG','RASTRO','EXPORTACION')),
    CONSTRAINT uq_movement_rules_pair UNIQUE (origin_type, destination_type)
);

COMMENT ON TABLE public.cattle_movement_rules IS
    'GLOBAL catalog (no tenant_id) of permitted livestock movements. DRAFT: every row ships with is_confirmed=false and MUST be validated by the client before any enforcement layer reads it.';
COMMENT ON COLUMN public.cattle_movement_rules.is_confirmed IS
    'Fail-closed switch. Any future enforcement layer must treat is_confirmed=false as "rule unavailable" and refuse the movement, never as an implicit allow.';

INSERT INTO public.cattle_movement_rules
    (origin_type, destination_type, is_allowed, requires_valid_psg,
     requires_health_tests, allows_interstate, requires_destination_ack, is_confirmed, notes)
VALUES
    ('UPP','UPP',        true,  true,  true,  false, true,  false,
     'DRAFT: ranch-to-ranch transfer. Interstate defaulted to false pending confirmation of whether a PSG is required at both ends.'),
    ('UPP','PSG',        true,  true,  true,  false, true,  false,
     'DRAFT: entry into a service provider (collection centre / feedlot).'),
    ('PSG','PSG',        true,  true,  true,  false, true,  false,
     'DRAFT: transfer between service providers.'),
    ('PSG','UPP',        true,  true,  true,  false, true,  false,
     'DRAFT: return to a production unit.'),
    ('UPP','RASTRO',     true,  true,  true,  true,  false, false,
     'DRAFT: definitive exit to slaughter. No destination acknowledgement: the animal leaves the traceability chain. Currently handled by sp_procesar_salida_ganado as VENTA.'),
    ('PSG','RASTRO',     true,  true,  true,  true,  false, false,
     'DRAFT: definitive exit to slaughter from a service provider.'),
    ('UPP','EXPORTACION',true,  true,  true,  true,  false, false,
     'DRAFT: export. Almost certainly needs additional federal documentation not modelled here.'),
    ('PSG','EXPORTACION',true,  true,  true,  true,  false, false,
     'DRAFT: export from a service provider.')
ON CONFLICT (origin_type, destination_type) DO NOTHING;

COMMIT;
