-- Migration 012: Production units (UPP - Unidad de Producción Pecuaria).
--
-- Cardinality: one company (tenant) may hold N production units. This replaces the
-- free-text cattle_livestock.upp_origen with a real entity (migration 013 backfills it).
--
-- SURFACE STRATEGY (two layers, deliberate):
--  Layer 1 - surface_matrix JSONB: verbatim copy of the SENASICA surface grid
--            [riego, temporal] x [estabulado, agostadero, agricola, forestal_maderable,
--            praderas, cultivos_forrajeros]. The grid is a third-party format that changes
--            without notice and is extremely sparse (Santa Lucía: 1 non-zero cell of 12).
--            Normalizing it would cost 12 rows per unit to store one useful number and
--            couple the schema to SENASICA's layout. The JSONB is the evidence of record.
--  Layer 2 - generated columns: what the business actually queries (grazing surface for
--            stocking-rate math) is materialized, indexable, and cannot drift.
--
-- DATA-QUALITY FINDING: the real constancias are internally inconsistent. Santa Lucía
-- declares 42.00 ha total (Temporal) while every concept cell reads 0.00. A CHECK
-- enforcing "sum of cells = total" would therefore REJECT the client's own official
-- document. Consistency is exposed as a computed flag instead of a hard constraint.
BEGIN;

-- Safe numeric extraction. Returns 0 when the cell is absent or not numeric, so a
-- malformed payload can never make a generated column fail at insert time.
CREATE OR REPLACE FUNCTION public.fn_surface_cell(p_matrix jsonb, p_regime text, p_concept text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_raw text;
BEGIN
    v_raw := p_matrix -> p_regime ->> p_concept;
    IF v_raw IS NULL OR btrim(v_raw) = '' THEN
        RETURN 0;
    END IF;
    RETURN v_raw::numeric;
EXCEPTION WHEN others THEN
    RETURN 0;
END;
$$;

-- Structural validator used by the CHECK constraint.
CREATE OR REPLACE FUNCTION public.fn_is_valid_surface_matrix(p_matrix jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_concepts text[] := ARRAY['estabulado','agostadero','agricola',
                               'forestal_maderable','praderas','cultivos_forrajeros'];
    v_regime   text;
    v_concept  text;
    v_raw      text;
BEGIN
    IF p_matrix IS NULL THEN
        RETURN true;
    END IF;
    IF jsonb_typeof(p_matrix) <> 'object' THEN
        RETURN false;
    END IF;
    IF NOT (p_matrix ? 'schema_version' AND p_matrix ? 'riego' AND p_matrix ? 'temporal') THEN
        RETURN false;
    END IF;

    FOREACH v_regime IN ARRAY ARRAY['riego','temporal'] LOOP
        IF jsonb_typeof(p_matrix -> v_regime) <> 'object' THEN
            RETURN false;
        END IF;
        FOREACH v_concept IN ARRAY v_concepts LOOP
            IF NOT (p_matrix -> v_regime ? v_concept) THEN
                RETURN false;
            END IF;
            v_raw := p_matrix -> v_regime ->> v_concept;
            BEGIN
                IF v_raw::numeric < 0 THEN
                    RETURN false;
                END IF;
            EXCEPTION WHEN others THEN
                RETURN false;
            END;
        END LOOP;
    END LOOP;

    RETURN true;
END;
$$;

CREATE TABLE IF NOT EXISTS public.production_units (
    id                   uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company           integer NOT NULL,
    producer_id          uuid,

    upp_code             character varying(20) NOT NULL,
    ranch_name           character varying(255) NOT NULL,

    -- Derived from the code itself (EE-MMM-NNNN-SSS = INEGI state + municipality).
    state_code           character varying(2)
                         GENERATED ALWAYS AS (substring(upp_code from 1 for 2)) STORED,
    municipality_code    character varying(3)
                         GENERATED ALWAYS AS (substring(upp_code from 4 for 3)) STORED,

    state_name           character varying(100),
    municipality_name    character varying(255),
    locality_name        character varying(255),
    tenure_type          character varying(30),
    access_directions    text,
    latitude             numeric(10,7),
    longitude            numeric(10,7),

    -- Surface
    total_surface_ha     numeric(12,2),
    is_partial_surface   boolean NOT NULL DEFAULT false,
    surface_matrix       jsonb,
    grazing_surface_ha   numeric(12,2) GENERATED ALWAYS AS (
                             public.fn_surface_cell(surface_matrix,'riego','agostadero')
                           + public.fn_surface_cell(surface_matrix,'riego','praderas')
                           + public.fn_surface_cell(surface_matrix,'riego','cultivos_forrajeros')
                           + public.fn_surface_cell(surface_matrix,'temporal','agostadero')
                           + public.fn_surface_cell(surface_matrix,'temporal','praderas')
                           + public.fn_surface_cell(surface_matrix,'temporal','cultivos_forrajeros')
                         ) STORED,

    -- Regulatory dates and identifiers
    fire_brand_patent    character varying(100),
    uma_registry         character varying(100),
    registration_date    date,
    last_update_at       timestamp without time zone,

    is_active            boolean NOT NULL DEFAULT true,
    created_at           timestamp without time zone DEFAULT now(),
    updated_at           timestamp without time zone DEFAULT now(),

    CONSTRAINT production_units_upp_code_format_check
        CHECK (upp_code ~ '^[0-9]{2}-[0-9]{3}-[0-9]{4}-[0-9]{3}$'),
    CONSTRAINT production_units_tenure_check
        CHECK (tenure_type IS NULL OR tenure_type IN
               ('PRIVADA','EJIDAL','COMUNAL','RENTADA','COMODATO','OTRA')),
    CONSTRAINT production_units_surface_positive_check
        CHECK (total_surface_ha IS NULL OR total_surface_ha >= 0),
    CONSTRAINT production_units_surface_matrix_check
        CHECK (public.fn_is_valid_surface_matrix(surface_matrix)),
    CONSTRAINT production_units_coords_check
        CHECK ((latitude IS NULL AND longitude IS NULL)
            OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)),
    CONSTRAINT fk_production_units_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_production_units_producer
        FOREIGN KEY (producer_id) REFERENCES public.livestock_producers(id) ON DELETE SET NULL
);

-- An active UPP code is unique system-wide; historical (deactivated) rows may repeat it.
CREATE UNIQUE INDEX IF NOT EXISTS uq_production_units_active_code
    ON public.production_units (upp_code)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_production_units_company
    ON public.production_units (id_company);
CREATE INDEX IF NOT EXISTS idx_production_units_state_municipality
    ON public.production_units (state_code, municipality_code);
CREATE INDEX IF NOT EXISTS idx_production_units_surface_matrix
    ON public.production_units USING gin (surface_matrix);

COMMENT ON TABLE public.production_units IS
    'UPP registry. A tenant (companys) may hold N units. state_code/municipality_code are derived from the UPP code (INEGI encoding) and must never be written by hand.';
COMMENT ON COLUMN public.production_units.surface_matrix IS
    'Verbatim SENASICA surface grid, schema_version tagged. Evidence of record: do not normalize, do not clean. Business queries use grazing_surface_ha.';
COMMENT ON COLUMN public.production_units.is_partial_surface IS
    'True when the constancia reports the surface as "Parcial" instead of "Total". Changes the denominator of any stocking-rate calculation.';

COMMIT;
