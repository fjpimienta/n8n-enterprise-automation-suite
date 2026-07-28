-- Migration 018: Registers the regulatory-registry entities in the Meta-CRUD dictionary.
--
-- FINDING (pre-existing bug, fixed here): crud_models id 31 (cattle_livestock) still lists
-- the original 12 allowed_fields. species (migration 1.6.0), upp_origen, tb_test_date and
-- br_test_date (migration 001) were never added, so the n8n gateway has been silently
-- unable to write the very fields sp_procesar_salida_ganado validates against. Any TB/BR
-- date in production got there by direct SQL, not through the gateway.
--
-- allowed_fields is the injection whitelist, so an unlisted column is not a soft failure —
-- it is dropped from the payload without complaint.
BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Fix cattle_livestock whitelist + expose the new production unit FK
-- ---------------------------------------------------------------------------
UPDATE public.crud_models
   SET allowed_fields = '["id","tenant_id","rfid_siniiga","numero_fuego","electronic_rfid","business_model","category","current_status","birth_date","current_weight_kg","metadata","created_at","species","upp_origen","tb_test_date","br_test_date","production_unit_id"]'::jsonb,
       schema_json = schema_json
           || '{"species": {"type":"text","required":false},
                "upp_origen": {"type":"text","required":false},
                "tb_test_date": {"type":"text","required":false},
                "br_test_date": {"type":"text","required":false},
                "production_unit_id": {"type":"text","required":false}}'::jsonb
 WHERE model_name = 'cattle_livestock';

-- ---------------------------------------------------------------------------
-- 1. Producer PII write path (the raw table is never writable through the gateway)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sp_upsert_producer_pii(
    p_producer_id uuid,
    p_curp text DEFAULT NULL,
    p_rfc text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_company integer;
BEGIN
    SELECT id_company INTO v_company
      FROM public.livestock_producers
     WHERE id = p_producer_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producer % not found', p_producer_id USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.livestock_producers
       SET curp_enc  = COALESCE(public.fn_encrypt_pii(p_curp),  curp_enc),
           curp_hash = COALESCE(public.fn_hash_pii(p_curp),     curp_hash),
           rfc_enc   = COALESCE(public.fn_encrypt_pii(p_rfc),   rfc_enc),
           rfc_hash  = COALESCE(public.fn_hash_pii(p_rfc),      rfc_hash),
           updated_at = now()
     WHERE id = p_producer_id;

    RETURN jsonb_build_object('success', true, 'producer_id', p_producer_id, 'id_company', v_company);
END;
$$;

COMMENT ON FUNCTION public.sp_upsert_producer_pii(uuid, text, text) IS
    'Only supported write path for producer CURP/RFC. Callers never handle the encryption key. NULL arguments leave the stored value untouched.';

-- ---------------------------------------------------------------------------
-- 2. Model registration
-- ---------------------------------------------------------------------------
INSERT INTO public.crud_models (
    model_name, table_name, primary_key,
    allowed_fields, schema_json, allowed_ops,
    allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
    joins, hooks, is_global
) VALUES

-- 2.1 Producers WITHOUT PII. Non-sensitive attributes only.
('livestock_producers',
 'livestock_producers',
 'id',
 '["id","id_company","full_name","producer_role","contact_email","contact_phone","address_street","address_number","address_colony","address_locality","address_municipality","address_state","address_postal_code","is_active","created_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"full_name":{"type":"text","required":true},"producer_role":{"type":"text","required":false},"contact_email":{"type":"text","required":false},"contact_phone":{"type":"text","required":false},"address_street":{"type":"text","required":false},"address_number":{"type":"text","required":false},"address_colony":{"type":"text","required":false},"address_locality":{"type":"text","required":false},"address_municipality":{"type":"text","required":false},"address_state":{"type":"text","required":false},"address_postal_code":{"type":"text","required":false},"is_active":{"type":"boolean","required":false}}'::jsonb,
 '{SELECT,INSERT,UPDATE,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR', 'ADMIN,OWNER', 'ADMIN,OWNER', 'ADMIN',
 '[{"table":"companys","fields":{"company_name":"tenant_name"},"own_col":"id_company","foreign_col":"id_company"}]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.2 Producers WITH PII. Read-only, ADMIN/OWNER only, served from the decrypting view.
('livestock_producers_pii',
 'vw_livestock_producers',
 'id',
 '["id","id_company","full_name","producer_role","curp","rfc","contact_email","contact_phone","is_active"]'::jsonb,
 '{"id":{"type":"text","required":false}}'::jsonb,
 '{SELECT,GETONE}'::text[],
 'ADMIN,OWNER', 'NONE', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.3 Production units (UPP)
('production_units',
 'production_units',
 'id',
 '["id","id_company","producer_id","upp_code","ranch_name","state_name","municipality_name","locality_name","tenure_type","access_directions","latitude","longitude","total_surface_ha","is_partial_surface","surface_matrix","fire_brand_patent","uma_registry","registration_date","last_update_at","is_active","created_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"producer_id":{"type":"text","required":false},"upp_code":{"type":"text","required":true},"ranch_name":{"type":"text","required":true},"state_name":{"type":"text","required":false},"municipality_name":{"type":"text","required":false},"locality_name":{"type":"text","required":false},"tenure_type":{"type":"text","required":false},"access_directions":{"type":"text","required":false},"latitude":{"type":"number","required":false},"longitude":{"type":"number","required":false},"total_surface_ha":{"type":"number","required":false},"is_partial_surface":{"type":"boolean","required":false},"surface_matrix":{"type":"jsonb","required":false},"fire_brand_patent":{"type":"text","required":false},"uma_registry":{"type":"text","required":false},"registration_date":{"type":"text","required":false},"last_update_at":{"type":"text","required":false},"is_active":{"type":"boolean","required":false}}'::jsonb,
 '{SELECT,INSERT,UPDATE,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'ADMIN,OWNER', 'ADMIN,OWNER', 'ADMIN',
 '[{"table":"companys","fields":{"company_name":"tenant_name"},"own_col":"id_company","foreign_col":"id_company"}]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.4 PSG licenses
('psg_licenses',
 'psg_licenses',
 'id',
 '["id","id_company","producer_id","psg_code","state_name","municipality_name","issuing_window","issued_at","expires_at","is_active","created_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"producer_id":{"type":"text","required":false},"psg_code":{"type":"text","required":true},"state_name":{"type":"text","required":false},"municipality_name":{"type":"text","required":false},"issuing_window":{"type":"text","required":false},"issued_at":{"type":"text","required":true},"expires_at":{"type":"text","required":false},"is_active":{"type":"boolean","required":false}}'::jsonb,
 '{SELECT,INSERT,UPDATE,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'ADMIN,OWNER', 'ADMIN,OWNER', 'ADMIN',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.5 Certificates. No UPDATE, no DELETE: append-only by contract.
('compliance_certificates',
 'compliance_certificates',
 'id',
 '["id","id_company","production_unit_id","psg_license_id","certificate_type","folio","issued_at","issuing_window","issuing_officer","source_url","notes","created_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"production_unit_id":{"type":"text","required":false},"psg_license_id":{"type":"text","required":false},"certificate_type":{"type":"text","required":true},"folio":{"type":"text","required":true},"issued_at":{"type":"text","required":true},"issuing_window":{"type":"text","required":false},"issuing_officer":{"type":"text","required":false},"source_url":{"type":"text","required":false},"notes":{"type":"text","required":false}}'::jsonb,
 '{SELECT,INSERT,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'ADMIN,EDITOR', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.6 Document custody. Append-only for the same audit reason.
('compliance_documents',
 'compliance_documents',
 'id',
 '["id","id_company","entity_type","entity_id","storage_key","original_name","mime_type","size_bytes","sha256_hash","uploaded_by","uploaded_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"entity_type":{"type":"text","required":true},"entity_id":{"type":"text","required":true},"storage_key":{"type":"text","required":true},"original_name":{"type":"text","required":false},"mime_type":{"type":"text","required":true},"size_bytes":{"type":"number","required":false},"sha256_hash":{"type":"text","required":true},"uploaded_by":{"type":"text","required":false}}'::jsonb,
 '{SELECT,INSERT,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'ADMIN,EDITOR', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.7 Declared census snapshots
('livestock_census_snapshots',
 'livestock_census_snapshots',
 'id',
 '["id","id_company","production_unit_id","certificate_id","snapshot_date","source","species_counts","total_head","breed_note","notes","created_at"]'::jsonb,
 '{"id":{"type":"text","required":false},"id_company":{"type":"number","required":true},"production_unit_id":{"type":"text","required":true},"certificate_id":{"type":"text","required":false},"snapshot_date":{"type":"text","required":true},"source":{"type":"text","required":false},"species_counts":{"type":"jsonb","required":false},"total_head":{"type":"number","required":true},"breed_note":{"type":"text","required":false},"notes":{"type":"text","required":false}}'::jsonb,
 '{SELECT,INSERT,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'ADMIN,EDITOR', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.8 Read-only dashboard feeds
('upp_compliance_status',
 'vw_upp_compliance_status',
 'production_unit_id',
 '["production_unit_id","id_company","company_name","upp_code","ranch_name","state_name","municipality_name","total_surface_ha","is_partial_surface","grazing_surface_ha","has_surface_inconsistency","registration_date","last_update_at","days_since_update","update_status","last_declared_head","last_census_date","active_head_in_system","is_active"]'::jsonb,
 '{}'::jsonb,
 '{SELECT,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'NONE', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

('psg_compliance_status',
 'vw_psg_compliance_status',
 'psg_license_id',
 '["psg_license_id","id_company","company_name","psg_code","state_code","municipality_code","state_name","municipality_name","issuing_window","issued_at","expires_at","effective_expires_at","validity_status","producer_name","is_active"]'::jsonb,
 '{}'::jsonb,
 '{SELECT,GETONE,GETALL}'::text[],
 'ADMIN,EDITOR,CUSTOMER', 'NONE', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false),

-- 2.9 PII write routine, exposed the same way salida_ganado is (function as table_name)
('producer_pii',
 'sp_upsert_producer_pii',
 'p_producer_id',
 '["p_producer_id","p_curp","p_rfc"]'::jsonb,
 '{"p_producer_id":{"type":"text","required":true},"p_curp":{"type":"text","required":false},"p_rfc":{"type":"text","required":false}}'::jsonb,
 '{INSERT}'::text[],
 'ADMIN,OWNER', 'ADMIN,OWNER', 'NONE', 'NONE',
 '[]'::jsonb,
 '{"pre": [], "post": []}'::jsonb, false)

ON CONFLICT (model_name) DO NOTHING;

COMMIT;
