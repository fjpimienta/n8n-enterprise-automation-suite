-- Migration 006: Catálogo GLOBAL (sin tenant_id) de estándares zootécnicos por raza
-- (Fase 0 de Etapas de Vida / Protocolo Sanitario). Pesos objetivo, % peso primer
-- servicio y días de gestación son estándar zootécnico, no varían por rancho.
-- especie sigue el mismo patrón que cattle_livestock.species/category: VARCHAR + CHECK,
-- no una FK a un catálogo de especies que no existe en el esquema.
BEGIN;

CREATE TABLE public.cattle_breed_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    especie character varying NOT NULL,
    raza_grupo character varying NOT NULL,
    raza_variante character varying,
    peso_adulto_hembra_kg numeric(10,2) NOT NULL,
    peso_adulto_macho_kg numeric(10,2) NOT NULL,
    pct_peso_primer_servicio numeric(5,2) NOT NULL DEFAULT 65.00,
    edad_min_pubertad_meses numeric(5,1),
    dias_gestacion_promedio integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT cattle_breed_catalog_especie_check
        CHECK (especie IN ('BOVINO','BUFALO','BORREGO')),
    CONSTRAINT cattle_breed_catalog_peso_hembra_check CHECK (peso_adulto_hembra_kg > 0),
    CONSTRAINT cattle_breed_catalog_peso_macho_check CHECK (peso_adulto_macho_kg > 0),
    CONSTRAINT cattle_breed_catalog_pct_servicio_check
        CHECK (pct_peso_primer_servicio > 0 AND pct_peso_primer_servicio <= 100),
    CONSTRAINT uq_breed_especie_grupo_variante UNIQUE (especie, raza_grupo, raza_variante)
);

-- Gotcha de Postgres: UNIQUE no detecta duplicados cuando raza_variante es NULL
-- (NULL <> NULL). Este índice parcial cubre el caso "raza sin subdivisión".
CREATE UNIQUE INDEX uq_breed_sin_variante
    ON public.cattle_breed_catalog (especie, raza_grupo)
    WHERE raza_variante IS NULL;

COMMENT ON TABLE public.cattle_breed_catalog IS 'Catálogo GLOBAL (sin tenant_id) de estándares zootécnicos por raza. Editable exclusivamente por ADMIN vía Meta-CRUD.';
COMMENT ON COLUMN public.cattle_breed_catalog.edad_min_pubertad_meses IS 'Orientativo, nunca determinante para decisiones automatizadas.';

COMMIT;
