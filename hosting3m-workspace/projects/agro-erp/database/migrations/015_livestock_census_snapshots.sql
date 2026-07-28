-- Migration 015: Declared livestock census snapshots.
--
-- The head counts printed on a constancia (Santa Lucía: 128 vientres, 7 sementales,
-- 41 vaquillas, 3 novillos, 121 otras = 300 bovinos + 2 equinos) are a POINT-IN-TIME
-- DECLARATION, not an attribute of the UPP. Storing them on production_units would
-- overwrite history on every re-issue.
--
-- SCOPE: snapshot only. Automatic reconciliation against cattle_livestock is explicitly
-- OUT OF SCOPE (client decision): the declared figure and the biometric inventory diverge
-- for legitimate reasons (births, unregistered animals, capture lag), so a naive diff
-- would produce false alarms. Reconciliation gets its own validated ruleset later.
BEGIN;

CREATE TABLE IF NOT EXISTS public.livestock_census_snapshots (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid NOT NULL,
    certificate_id      uuid,

    snapshot_date       date NOT NULL,
    source              character varying(30) NOT NULL DEFAULT 'PGN_CERTIFICATE',

    -- Per-species breakdown exactly as declared, keyed by species.
    -- e.g. {"BOVINO": {"vientres":128, "crias":0, "sementales":7, ...}, "EQUIDO": {...}}
    species_counts      jsonb NOT NULL DEFAULT '{}'::jsonb,
    total_head          integer NOT NULL DEFAULT 0,
    breed_note          character varying(255),
    notes               text,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT livestock_census_source_check
        CHECK (source IN ('PGN_CERTIFICATE','MANUAL','FIELD_AGENT')),
    CONSTRAINT livestock_census_total_check
        CHECK (total_head >= 0),
    CONSTRAINT livestock_census_counts_object_check
        CHECK (jsonb_typeof(species_counts) = 'object'),
    CONSTRAINT fk_livestock_census_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_livestock_census_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE,
    CONSTRAINT fk_livestock_census_certificate
        FOREIGN KEY (certificate_id) REFERENCES public.compliance_certificates(id) ON DELETE SET NULL
);

-- One declared snapshot per unit per date; a correction is a new date, not an edit.
CREATE UNIQUE INDEX IF NOT EXISTS uq_livestock_census_unit_date_source
    ON public.livestock_census_snapshots (production_unit_id, snapshot_date, source);
CREATE INDEX IF NOT EXISTS idx_livestock_census_company
    ON public.livestock_census_snapshots (id_company);
CREATE INDEX IF NOT EXISTS idx_livestock_census_counts
    ON public.livestock_census_snapshots USING gin (species_counts);

COMMENT ON TABLE public.livestock_census_snapshots IS
    'Append-only declared census. Reconciliation against cattle_livestock is deliberately NOT implemented here.';

COMMIT;
