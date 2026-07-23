-- Migration 007: Registra el modelo 'cattle_breed_catalog' en crud_models para exponerlo
-- a través del gateway Meta-CRUD (archivo separado del DDL, mismo patrón que
-- 003_crud_models_salida_ganado.sql registró 'salida_ganado' aparte de su tabla).
-- ADMIN exclusivo en las 4 operaciones de escritura/lectura: catálogo de configuración,
-- no dato operativo de campo.
BEGIN;

INSERT INTO public.crud_models (
    model_name, table_name, primary_key,
    allowed_fields, schema_json, allowed_ops,
    allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
    joins, hooks
) VALUES (
    'cattle_breed_catalog',
    'cattle_breed_catalog',
    'id',
    '["id","especie","raza_grupo","raza_variante","peso_adulto_hembra_kg","peso_adulto_macho_kg","pct_peso_primer_servicio","edad_min_pubertad_meses","dias_gestacion_promedio","created_at"]'::jsonb,
    '{"id": {"type":"text","required":false}, "especie": {"type":"text","required":true}, "raza_grupo": {"type":"text","required":true}, "raza_variante": {"type":"text","required":false}, "peso_adulto_hembra_kg": {"type":"number","required":true}, "peso_adulto_macho_kg": {"type":"number","required":true}, "pct_peso_primer_servicio": {"type":"number","required":false}, "edad_min_pubertad_meses": {"type":"number","required":false}, "dias_gestacion_promedio": {"type":"number","required":true}}'::jsonb,
    '{SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL}'::text[],
    'ADMIN', 'ADMIN', 'ADMIN', 'ADMIN',
    '[]'::jsonb,
    '{"pre": [], "post": []}'::jsonb
);

COMMIT;
