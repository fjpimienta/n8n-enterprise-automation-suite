-- Migration 008: Catálogo GLOBAL (sin tenant_id) de transiciones de etapa de vida por
-- especie (Fase 1 de Etapas de Vida / Protocolo Sanitario). No implementa todavía la
-- lógica que dispare o valide transiciones reales contra cattle_livestock (fase futura).
-- especie/categoria_origen/categoria_destino siguen el mismo patrón VARCHAR+CHECK ya
-- usado en cattle_livestock.category/species y cattle_breed_catalog.especie.
BEGIN;

CREATE TABLE public.cattle_lifestage_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    especie character varying NOT NULL,
    categoria_origen character varying NOT NULL,
    categoria_destino character varying NOT NULL,
    edad_min_meses numeric(5,1) NOT NULL,
    requiere_validacion_peso boolean NOT NULL DEFAULT true,
    notas text,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT cattle_lifestage_catalog_especie_check
        CHECK (especie IN ('BOVINO','BUFALO','BORREGO')),
    CONSTRAINT cattle_lifestage_catalog_categoria_origen_check
        CHECK (categoria_origen IN ('VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO','BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA')),
    CONSTRAINT cattle_lifestage_catalog_categoria_destino_check
        CHECK (categoria_destino IN ('VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO','BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA')),
    CONSTRAINT cattle_lifestage_catalog_no_self_transition_check
        CHECK (categoria_origen <> categoria_destino),
    CONSTRAINT cattle_lifestage_catalog_edad_min_check CHECK (edad_min_meses > 0),
    CONSTRAINT uq_lifestage_especie_origen_destino UNIQUE (especie, categoria_origen, categoria_destino)
);

COMMENT ON TABLE public.cattle_lifestage_catalog IS 'Catálogo GLOBAL (sin tenant_id) de transiciones de etapa de vida por especie. edad_min_meses es orientativa: dispara revisión, nunca promueve la categoría por sí sola. Editable exclusivamente por ADMIN vía Meta-CRUD.';
COMMENT ON COLUMN public.cattle_lifestage_catalog.requiere_validacion_peso IS 'Si true, la transición real además exige que el peso del animal alcance pct_peso_primer_servicio de cattle_breed_catalog para su raza. Si false, la transición es solo por edad (ej. destete).';

-- Seed confirmado por el cliente. Solo BOVINO por ahora — Búfalo/Borrego NO se insertan
-- todavía (pendientes de confirmación), no se usan filas NULL de relleno.
INSERT INTO public.cattle_lifestage_catalog
    (especie, categoria_origen, categoria_destino, edad_min_meses, requiere_validacion_peso) VALUES
    ('BOVINO', 'BECERRA',   'NOVILLONA', 7,  false),
    ('BOVINO', 'NOVILLONA', 'VACA',      19, true),
    ('BOVINO', 'BECERRO',   'NOVILLO',   7,  false),
    ('BOVINO', 'NOVILLO',   'TORO',      19, true);

COMMIT;
