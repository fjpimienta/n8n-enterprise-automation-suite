-- Migration 052 (corregida): Register production_unit_lots as a Meta-CRUD model.
--
-- CORRECCIÓN sobre el intento anterior (falló con "column allowed_fields is of type
-- jsonb but expression is of type text[]"): la primera versión de esta migración se
-- escribió contra un esquema de crud_models reconstruido de memoria, no verificado. El
-- \d crud_models real (2026-08-25) muestra tres diferencias:
--   1. primary_key es NOT NULL y no se incluía en absoluto en el intento anterior.
--   2. allowed_fields es jsonb, y debe cargarse como arreglo JSON ('["a","b"]'::jsonb),
--      no como text[] de Postgres.
--   3. allowed_roles_select/insert/update/delete son TEXT (cadena separada por comas,
--      ej. 'ADMIN,EDITOR,CUSTOMER'), no arreglos — se habían escrito con ARRAY[...].
--
-- RBAC sigue el mismo criterio que production_units: lectura amplia, escritura
-- restringida a ADMIN/OWNER a nivel de registro normativo.
BEGIN;

INSERT INTO public.crud_models
    (model_name, table_name, primary_key, allowed_fields, allowed_ops,
     allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
     schema_json)
SELECT 'production_unit_lots', 'production_unit_lots', 'id',
       '["id_company","production_unit_id","lot_name","tenure_type","lessor_name",
         "location_notes","is_active","notes"]'::jsonb,
       ARRAY['SELECT','INSERT','UPDATE','GETONE','GETALL'],
       'ADMIN,EDITOR,CUSTOMER',
       'ADMIN,OWNER',
       'ADMIN,OWNER',
       'ADMIN',
       '{"lot_name": {"type": "string", "required": true},
         "production_unit_id": {"type": "string", "required": true},
         "tenure_type": {"type": "string", "required": true}}'::jsonb
 WHERE NOT EXISTS (
        SELECT 1 FROM public.crud_models WHERE model_name = 'production_unit_lots');

COMMIT;
