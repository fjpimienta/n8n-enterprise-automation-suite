-- Migration 009: Registra el modelo 'cattle_lifestage_catalog' en crud_models (archivo
-- separado del DDL, mismo patrón que 007_crud_models_breed_catalog.sql). ADMIN exclusivo
-- en las 4 operaciones: catálogo de configuración, no dato operativo de campo.
BEGIN;

INSERT INTO public.crud_models (
    model_name, table_name, primary_key,
    allowed_fields, schema_json, allowed_ops,
    allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
    joins, hooks
) VALUES (
    'cattle_lifestage_catalog',
    'cattle_lifestage_catalog',
    'id',
    '["id","especie","categoria_origen","categoria_destino","edad_min_meses","requiere_validacion_peso","notas","created_at"]'::jsonb,
    '{"id": {"type":"text","required":false}, "especie": {"type":"text","required":true}, "categoria_origen": {"type":"text","required":true}, "categoria_destino": {"type":"text","required":true}, "edad_min_meses": {"type":"number","required":true}, "requiere_validacion_peso": {"type":"boolean","required":false}, "notas": {"type":"text","required":false}}'::jsonb,
    '{SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL}'::text[],
    'ADMIN', 'ADMIN', 'ADMIN', 'ADMIN',
    '[]'::jsonb,
    '{"pre": [], "post": []}'::jsonb
);

COMMIT;
