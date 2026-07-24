-- Migration 003: Registra el modelo 'salida_ganado' en crud_models para exponer
-- sp_procesar_salida_ganado a través del gateway genérico (case 'call_sp' en Build Query).
-- Ya ejecutada manualmente (id=46). Este archivo documenta el cambio para mantener
-- el repo en sync con el estado real de la base de datos.
BEGIN;

INSERT INTO public.crud_models (
    model_name, table_name, primary_key,
    allowed_fields, schema_json, allowed_ops,
    allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
    joins, hooks
) VALUES (
    'salida_ganado',
    'sp_procesar_salida_ganado',
    'electronic_rfid',
    '["electronic_rfid"]'::jsonb,
    '{"electronic_rfid": {"type": "text", "required": true}}'::jsonb,
    '{INSERT}'::text[],
    'ADMIN,EDITOR',
    'ADMIN,EDITOR',
    'ADMIN',
    'ADMIN',
    '[]'::jsonb,
    '{"pre": [], "post": []}'::jsonb
);

COMMIT;
