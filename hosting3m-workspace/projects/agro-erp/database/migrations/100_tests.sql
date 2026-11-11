-- 100_tests.sql
-- Tests for 100 (guide folio normalization). LOCAL / throw-away schema ONLY. Everything happens inside ONE transaction that
-- ends in ROLLBACK; nothing is kept. Usage: psql -X -v ON_ERROR_STOP=1 -f 100_tests.sql
-- It is 099_tests.sql (same helpers, same synthetic companies 9811-9816 and fixtures) with 100 applied right after 099, so
-- every 099 assertion runs against the 100 version of the tool, plus section N (folio cases) and section I100 (no back-fill,
-- rollback to the 099 function, re-apply). 099_tests.sql itself is unchanged and still tests 099 alone.
-- A failed assertion raises 'FAIL [label]' and stops the run.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------------------------
-- Helpers (session-local)
-- ---------------------------------------------------------------------------------------------
CREATE TEMP TABLE t099_res (label text);
CREATE TEMP TABLE t099_j (k text PRIMARY KEY, j jsonb);

CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL [%]', p_label;
    END IF;
    INSERT INTO t099_res VALUES (p_label);
    RAISE NOTICE 'PASS [%]', p_label;
END $$;

CREATE FUNCTION pg_temp.put(p_k text, p_j jsonb) RETURNS jsonb LANGUAGE sql AS $$
    INSERT INTO t099_j VALUES (p_k, p_j) ON CONFLICT (k) DO UPDATE SET j = EXCLUDED.j RETURNING j
$$;
CREATE FUNCTION pg_temp.j(p_k text) RETURNS jsonb LANGUAGE sql AS $$ SELECT j FROM t099_j WHERE k = p_k $$;

-- Issue of a need_info answer for one field (NULL when absent).
CREATE FUNCTION pg_temp.issue(p_j jsonb, p_field text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT e FROM jsonb_array_elements(coalesce(p_j->'issues', '[]'::jsonb)) e WHERE e->>'field' = p_field LIMIT 1
$$;

CREATE FUNCTION pg_temp.n(p_tenant integer) RETURNS bigint LANGUAGE sql AS $$
    SELECT count(*) FROM cattle_livestock WHERE tenant_id = p_tenant
$$;

-- Regularization call with defaults. p_confirmed = 'commit' runs preview + commit with the preview's hash.
CREATE FUNCTION pg_temp.reg(
    p_tenant text, p_email text, p_upp text DEFAULT NULL, p_lot text DEFAULT NULL, p_species text DEFAULT 'BOVINO',
    p_category text DEFAULT 'BECERRO', p_bm text DEFAULT 'CRIA', p_age text DEFAULT '8', p_tag text DEFAULT NULL,
    p_folio text DEFAULT 'G-0001', p_origin text DEFAULT NULL, p_notes text DEFAULT NULL, p_confirmed text DEFAULT 'false',
    p_hash text DEFAULT NULL, p_force text DEFAULT NULL, p_channel text DEFAULT 'CHAT_WEB')
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v jsonb;
BEGIN
    IF p_confirmed = 'commit' THEN
        v := public.sp_register_livestock_regularization(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
                 p_bm, p_age, p_tag, p_folio, p_origin, p_notes, 'false', NULL, NULL);
        IF v->>'status' <> 'preview' THEN RETURN v; END IF;
        RETURN public.sp_register_livestock_regularization(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
                 p_bm, p_age, p_tag, p_folio, p_origin, p_notes, 'true', v->>'preview_hash', p_force);
    END IF;
    RETURN public.sp_register_livestock_regularization(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
             p_bm, p_age, p_tag, p_folio, p_origin, p_notes, p_confirmed, p_hash, p_force);
END $$;

-- Purchase call with defaults (same 'commit' convention).
CREATE FUNCTION pg_temp.buy(
    p_tenant text, p_email text, p_upp text DEFAULT NULL, p_lot text DEFAULT NULL, p_species text DEFAULT 'BOVINO',
    p_category text DEFAULT 'BECERRO', p_bm text DEFAULT 'CRIA', p_tag text DEFAULT NULL, p_birth text DEFAULT NULL,
    p_weight text DEFAULT NULL, p_price text DEFAULT '15000', p_seller text DEFAULT 'Juan Ejemplo',
    p_pdate text DEFAULT NULL, p_notes text DEFAULT NULL, p_confirmed text DEFAULT 'false', p_hash text DEFAULT NULL,
    p_force text DEFAULT NULL, p_channel text DEFAULT 'WHATSAPP')
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v jsonb;
BEGIN
    IF p_confirmed = 'commit' THEN
        v := public.sp_register_livestock_purchase_chat(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
                 p_bm, p_tag, p_birth, p_weight, p_price, p_seller, p_pdate, p_notes, 'false', NULL, NULL);
        IF v->>'status' <> 'preview' THEN RETURN v; END IF;
        RETURN public.sp_register_livestock_purchase_chat(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
                 p_bm, p_tag, p_birth, p_weight, p_price, p_seller, p_pdate, p_notes, 'true', v->>'preview_hash', p_force);
    END IF;
    RETURN public.sp_register_livestock_purchase_chat(p_tenant, p_email, p_channel, p_upp, p_lot, p_species, p_category,
             p_bm, p_tag, p_birth, p_weight, p_price, p_seller, p_pdate, p_notes, p_confirmed, p_hash, p_force);
END $$;

SELECT md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) AS md5_palm_before \gset
\echo fn_reject_palm_company md5 before 099 :md5_palm_before

-- ---------------------------------------------------------------------------------------------
-- Apply 099, then 100, inside the test transaction
-- ---------------------------------------------------------------------------------------------
\set embedded 1
\ir 099_livestock_regularization.sql
SELECT md5(pg_get_functiondef('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)) AS md5_sp_099 \gset
\ir 100_livestock_folio_normalization.sql

-- ---------------------------------------------------------------------------------------------
-- Fixtures (fake: companies 9811-9816, e-mails @example.test, tags 98xx...)
-- ---------------------------------------------------------------------------------------------
INSERT INTO companys (id_company, company_name, industry, is_active) VALUES
    (9811, 'T099 Uno', 'ganaderia', true),
    (9812, 'T099 Multi', 'ganaderia', true),
    (9813, 'T099 Palma', 'agricultura', true),
    (9814, 'T099 Otra Empresa', 'ganaderia', true),
    (9815, 'T099 Sin UPP', 'ganaderia', true),
    (9816, 'T099 Inactiva', 'ganaderia', false);
INSERT INTO users (email, names, password, role, is_active) VALUES
    ('t099-admin@example.test', 'T099 Admin', 'x', 'ADMIN', true),
    ('t099-editor@example.test', 'T099 Editor', 'x', 'EDITOR', true),
    ('t099-owner@example.test', 'T099 Owner', 'x', 'EDITOR', true),
    ('t099-customer@example.test', 'T099 Customer', 'x', 'EDITOR', true),
    ('t099-gone@example.test', 'T099 Gone', 'x', 'EDITOR', true),
    ('t099-other@example.test', 'T099 Other', 'x', 'ADMIN', true);
INSERT INTO user_companies (email, id_company, role, is_active) VALUES
    ('t099-admin@example.test', 9811, 'ADMIN', true),
    ('t099-admin@example.test', 9812, 'ADMIN', true),
    ('t099-admin@example.test', 9813, 'ADMIN', true),
    ('t099-admin@example.test', 9815, 'ADMIN', true),
    ('t099-admin@example.test', 9816, 'ADMIN', true),
    ('t099-editor@example.test', 9811, 'EDITOR', true),
    ('t099-editor@example.test', 9812, 'EDITOR', true),
    ('t099-owner@example.test', 9811, 'OWNER', true),
    ('t099-customer@example.test', 9811, 'CUSTOMER', true),
    ('t099-gone@example.test', 9811, 'EDITOR', false),
    ('t099-other@example.test', 9814, 'ADMIN', true);
INSERT INTO production_units (id, id_company, upp_code, ranch_name, is_active) VALUES
    ('00000000-0000-4099-8000-000000000101', 9811, '99-811-0000-001', 'La Bendición – San José', true),
    ('00000000-0000-4099-8000-000000000201', 9812, '99-812-0000-001', 'Norte', true),
    ('00000000-0000-4099-8000-000000000202', 9812, '99-812-0000-002', 'Sur', true),
    ('00000000-0000-4099-8000-000000000203', 9812, '99-812-0000-003', 'Viejo', false),
    ('00000000-0000-4099-8000-000000000401', 9814, '99-814-0000-001', 'Otra Finca', true),
    ('00000000-0000-4099-8000-000000000601', 9816, '99-816-0000-001', 'Finca Inactiva', true);
INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type, is_active) VALUES
    (9811, '00000000-0000-4099-8000-000000000101', 'Maceo', 'PROPIO', true),
    (9811, '00000000-0000-4099-8000-000000000101', 'Cerrado', 'PROPIO', false),
    (9812, '00000000-0000-4099-8000-000000000201', 'Norte Uno', 'PROPIO', true),
    (9812, '00000000-0000-4099-8000-000000000202', 'Maceo Sur', 'PROPIO', true),
    (9814, '00000000-0000-4099-8000-000000000401', 'Potrero Ajeno', 'PROPIO', true);
INSERT INTO leased_land_sites (id, id_company, site_name) VALUES
    ('00000000-0000-4099-8000-000000000901', 9811, 'T099 Rentado');
-- Production catalog content for BOVINO (2026-11-05); a local schema-only copy has no rows.
INSERT INTO cattle_lifestage_catalog (especie, categoria_origen, categoria_destino, edad_min_meses) VALUES
    ('BOVINO', 'BECERRA', 'NOVILLONA', 7), ('BOVINO', 'NOVILLONA', 'VACA', 19), ('BOVINO', 'BECERRO', 'NOVILLO', 7),
    ('BOVINO', 'NOVILLO', 'TORO', 19), ('BOVINO', 'BECERRO_TORETE', 'TORO', 16)
ON CONFLICT DO NOTHING;
INSERT INTO cattle_livestock (tenant_id, species, category, business_model, current_status, rfid_siniiga, electronic_rfid,
                              numero_fuego, production_unit_id, leased_site_id) VALUES
    (9811, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9811000001', NULL, NULL, '00000000-0000-4099-8000-000000000101', NULL),
    (9811, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', NULL, '9811000002', NULL, '00000000-0000-4099-8000-000000000101', NULL),
    (9811, 'BOVINO', 'BECERRO', 'CRIA', 'ACTIVO', '9811000003', NULL, NULL, NULL, NULL),
    (9811, 'BOVINO', 'BECERRO', 'CRIA', 'VENDIDO', '9811000004', NULL, NULL, NULL, NULL),
    (9811, 'BOVINO', 'BECERRO', 'CRIA', 'ACTIVO', '9811000005', NULL, NULL, NULL, '00000000-0000-4099-8000-000000000901'),
    (9811, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', NULL, NULL, '9811000006', '00000000-0000-4099-8000-000000000101', NULL),
    (9814, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9814000001', NULL, NULL, '00000000-0000-4099-8000-000000000401', NULL),
    (9814, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', NULL, NULL, '9811000007', '00000000-0000-4099-8000-000000000401', NULL);

-- ---------------------------------------------------------------------------------------------
-- F1 first (mutation M5 must fail here): a preview never writes
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.n(9811) AS n9811_before \gset
SELECT pg_temp.put('f1', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100001', p_folio => '7130001'));
SELECT pg_temp.ok(pg_temp.j('f1')->>'status' = 'preview' AND pg_temp.n(9811) = :n9811_before
                  AND length(pg_temp.j('f1')->>'preview_hash') = 32,
                  'F1 regularization preview writes nothing and returns a preview_hash');
SELECT pg_temp.ok(pg_temp.buy('9811', 't099-editor@example.test')->>'status' = 'preview' AND pg_temp.n(9811) = :n9811_before,
                  'F1b purchase preview writes nothing');

-- ---------------------------------------------------------------------------------------------
-- A. Session gate
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.reg('98x1', 't099-admin@example.test')->>'status' = 'forbidden'
                  AND pg_temp.reg(NULL, 't099-admin@example.test')->>'status' = 'forbidden',
                  'A1 malformed or empty tenant is forbidden');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-other@example.test', p_tag => '9811100002')->>'status' = 'forbidden'
                  AND pg_temp.buy('9811', 't099-other@example.test')->>'status' = 'forbidden'
                  AND pg_temp.reg('9811', NULL, p_tag => '9811100002')->>'status' = 'forbidden',
                  'A2 a non-member (or no e-mail) is forbidden in both tools');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-customer@example.test', p_tag => '9811100002')->>'status' = 'forbidden'
                  AND pg_temp.buy('9811', 't099-customer@example.test')->>'status' = 'forbidden',
                  'A3 CUSTOMER (read-only) is forbidden in both tools');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-gone@example.test', p_tag => '9811100002')->>'status' = 'forbidden',
                  'A4 an inactive membership is forbidden');
SELECT pg_temp.ok(pg_temp.reg('9813', 't099-admin@example.test', p_tag => '9811100002')->>'status' = 'palm'
                  AND pg_temp.buy('9813', 't099-admin@example.test', p_price => '0')->>'status' = 'palm',
                  'A5 a palm company answers status palm in both tools');
SELECT pg_temp.ok(pg_temp.reg('9811', 'T099-OWNER@example.test', p_tag => '9811100002')->>'status' = 'preview'
                  AND pg_temp.reg('9811', 't099-admin@example.test', p_tag => '9811100002')->>'status' = 'preview',
                  'A6 OWNER (e-mail in any case) and ADMIN are allowed');
SELECT pg_temp.ok(pg_temp.reg('9816', 't099-admin@example.test', p_tag => '9811100002')->>'status' = 'forbidden',
                  'A7 an inactive company is forbidden');

-- ---------------------------------------------------------------------------------------------
-- B. Production unit
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('b1', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002'));
SELECT pg_temp.ok(pg_temp.j('b1')->'preview'->>'upp_code' = '99-811-0000-001'
                  AND pg_temp.j('b1')->'preview'->>'empresa' = 'T099 Uno',
                  'B1 a single active UPP is used when no name is given (preview shows company and UPP)');
SELECT pg_temp.put('b2', pg_temp.reg('9812', 't099-editor@example.test', p_tag => '9811100002'));
SELECT pg_temp.ok(pg_temp.j('b2')->>'status' = 'need_info'
                  AND pg_temp.issue(pg_temp.j('b2'), 'upp')->>'type' = 'ambiguous'
                  AND pg_temp.issue(pg_temp.j('b2'), 'upp')->>'code' = 'P0114'
                  AND jsonb_array_length(pg_temp.issue(pg_temp.j('b2'), 'upp')->'options') = 2
                  AND pg_temp.issue(pg_temp.j('b2'), 'upp')::text NOT LIKE '%Viejo%',
                  'B2 several UPP without a name: need_info ambiguous with the 2 active options (inactive one hidden)');
SELECT pg_temp.ok(pg_temp.reg('9812', 't099-editor@example.test', p_upp => '  SUR ', p_tag => '9811100002')->'preview'->>'upp_code' = '99-812-0000-002',
                  'B3 exact normalized name (case and spaces) resolves');
SELECT pg_temp.ok(pg_temp.reg('9812', 't099-editor@example.test', p_upp => '998120000001', p_tag => '9811100002')->'preview'->>'upp' = 'Norte'
                  AND pg_temp.reg('9812', 't099-editor@example.test', p_upp => '99-812-0000-001', p_tag => '9811100002')->'preview'->>'upp' = 'Norte'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_upp => 'la bendicion – san jose', p_tag => '9811100002')->>'status' = 'preview',
                  'B4 UPP by code with or without dashes, and by name without accents');
SELECT pg_temp.put('b5', pg_temp.reg('9811', 't099-editor@example.test', p_upp => '99-814-0000-001', p_tag => '9811100002'));
SELECT pg_temp.ok(pg_temp.issue(pg_temp.j('b5'), 'upp')->>'type' = 'not_found'
                  AND pg_temp.j('b5')::text NOT LIKE '%Otra Finca%'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_upp => 'Otra Finca', p_tag => '9811100002')->>'status' = 'need_info',
                  'B5 a UPP of another company (by code or name) is not_found and never named');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9812', 't099-editor@example.test', p_upp => 'Viejo', p_tag => '9811100002'), 'upp')->>'type' = 'not_found',
                  'B6 an inactive UPP is not_found');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9815', 't099-admin@example.test', p_tag => '9811100002'), 'upp')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.buy('9815', 't099-admin@example.test'), 'upp')->>'code' = 'P0114',
                  'B7 a company without active UPP: missing P0114 in both tools');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9812', 't099-editor@example.test', p_upp => 'Su', p_tag => '9811100002'), 'upp')->>'type' = 'not_found',
                  'B8 a partial name never matches');

-- ---------------------------------------------------------------------------------------------
-- C. Lot
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_lot => ' maceo ', p_tag => '9811100002')->'preview'->>'lote' = 'Maceo',
                  'C1 exact normalized lot inside the UPP resolves');
SELECT pg_temp.put('c2', pg_temp.reg('9812', 't099-editor@example.test', p_upp => 'Norte', p_lot => 'Maceo Sur', p_tag => '9811100002'));
SELECT pg_temp.ok(pg_temp.issue(pg_temp.j('c2'), 'lot')->>'type' = 'not_found'
                  AND pg_temp.issue(pg_temp.j('c2'), 'lot')->>'code' = 'P0115'
                  AND pg_temp.issue(pg_temp.j('c2'), 'lot')->>'message' LIKE '%otra UPP de la empresa (Sur)%',
                  'C2 a lot of another UPP of the same company is rejected and the right UPP is named');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_lot => 'Cerrado', p_tag => '9811100002'), 'lot')->>'type' = 'not_found',
                  'C3 an inactive lot is not_found');
SELECT pg_temp.put('c4', pg_temp.reg('9811', 't099-editor@example.test', p_lot => 'Potrero Ajeno', p_tag => '9811100002'));
SELECT pg_temp.ok(pg_temp.issue(pg_temp.j('c4'), 'lot')->>'type' = 'not_found' AND pg_temp.j('c4')::text NOT LIKE '%Otra Finca%',
                  'C4 a lot of another company is not_found and its UPP is never named');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_lot => 'Mace', p_tag => '9811100002'), 'lot')->>'type' = 'not_found',
                  'C5 a partial lot name never matches');

-- ---------------------------------------------------------------------------------------------
-- D. Regularization fields
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test'), 'ear_tag')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test'), 'ear_tag')->>'code' = 'P0118'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_species => NULL), 'ear_tag')->>'type' = 'missing',
                  'D1 a bovine (or unknown species) without ear tag: missing P0118');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '981110000'), 'ear_tag')->>'type' = 'invalid',
                  'D2 a bovine ear tag that is not 10 digits is invalid');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_folio => NULL), 'guide_folio')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_folio => 'desconocido'), 'guide_folio')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_folio => 'N/A'), 'guide_folio')->>'type' = 'invalid',
                  'D3 a bovine without guide folio, or with a placeholder folio, is rejected');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'oveja', p_category => 'borrega', p_folio => NULL)->>'status' = 'preview'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_species => 'EQUINO', p_category => 'yegua', p_age => '60', p_folio => NULL)->>'status' = 'preview',
                  'D4 other species: ear tag and guide folio are optional');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => '241'), 'age_months')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => '-1'), 'age_months')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => 'ocho'), 'age_months')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => NULL), 'age_months')->>'type' = 'missing'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => '240')->>'status' = 'preview'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => '0')->>'status' = 'preview',
                  'D5 approximate age: 0 and 240 accepted; 241, -1, text and empty rejected');
SELECT pg_temp.ok((pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_age => '8 meses')->'preview'->>'fecha_nacimiento_estimada')::date
                      = fn_livestock_chat_today() - 244,
                  'D5b "8 meses" estimates the birth date as today minus 244 days');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_bm => NULL), 'business_model')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_bm => 'LECHE'), 'business_model')->>'type' = 'invalid'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_bm => 'reproducción')->'preview'->>'modelo_negocio' = 'REPRODUCCION',
                  'D6 business model is asked (no default) and validated');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_category => 'Vaquilla')->'preview'->>'categoria' = 'NOVILLONA'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_category => 'becerro torete')->'preview'->>'categoria' = 'BECERRO_TORETE'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BUFALO', p_category => 'NOVILLO', p_folio => NULL), 'category')->>'type' = 'invalid'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_species => 'búfalo', p_category => 'Búfala', p_folio => NULL)->'preview'->>'categoria' = 'BUFALA'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BUFALO', p_category => 'BUCERRO', p_folio => NULL)->>'status' = 'preview'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_species => 'EQUIDO', p_category => 'caballo castrado', p_folio => NULL)->'preview'->>'categoria' = 'CABALLO_CASTRADO'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BORREGO', p_category => 'VACA', p_folio => NULL), 'category')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_category => 'BUCERRO'), 'category')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'cabra', p_folio => NULL), 'species')->>'type' = 'invalid',
                  'D7 categories: VAQUILLA = NOVILLONA, BOVINO by catalog, fixed lists for BUFALO / EQUIDO / BORREGO (BUFALO + NOVILLO rejected)');
SELECT pg_temp.put('d8', pg_temp.reg('9812', 't099-editor@example.test', p_category => NULL, p_bm => NULL, p_age => NULL, p_folio => NULL));
SELECT pg_temp.ok(pg_temp.j('d8')->>'status' = 'need_info'
                  AND (SELECT array_agg(e->>'field' ORDER BY e->>'field') FROM jsonb_array_elements(pg_temp.j('d8')->'issues') e)
                      = ARRAY['age_months', 'business_model', 'category', 'ear_tag', 'guide_folio', 'upp'],
                  'D8 all the problems come back in ONE need_info answer');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_origin => '07 065 6515 001')->'preview'->>'upp_origen_guia' = '07-065-6515-001'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002', p_origin => 'ABC-1')->'preview'->>'upp_origen_guia' = 'ABC-1',
                  'D9 the origin UPP code of the guide is normalized when possible and never blocks');

-- ---------------------------------------------------------------------------------------------
-- E. Ear tag conflicts (rfid_siniiga / electronic_rfid reject; numero_fuego warns)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000001')->>'status' = 'duplicate'
                  AND pg_temp.buy('9811', 't099-editor@example.test', p_tag => '9811000001')->>'status' = 'duplicate',
                  'E1 rfid_siniiga of an animal of the same company: duplicate in both tools');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000002')->>'status' = 'duplicate',
                  'E2 electronic_rfid of an animal of the same company: duplicate');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000003')->>'status' = 'exists_without_upp'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000003')->>'code' = 'P0116'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000004')->>'status' = 'duplicate',
                  'E3 active animal without UPP: exists_without_upp; a sold one: duplicate');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000005')->>'status' = 'duplicate',
                  'E4 an animal on a leased site (no UPP by design) is a duplicate, not exists_without_upp');
SELECT pg_temp.put('e5', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9814000001'));
SELECT pg_temp.ok(pg_temp.j('e5')->>'status' = 'duplicate_other_company'
                  AND pg_temp.j('e5')::text NOT LIKE '%9814%Otra%' AND pg_temp.j('e5')::text NOT LIKE '%T099 Otra Empresa%'
                  AND pg_temp.j('e5')::text NOT LIKE '%Otra Finca%',
                  'E5 a tag of another company: duplicate_other_company, without naming it');
SELECT pg_temp.put('e6', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000006'));
SELECT pg_temp.ok(pg_temp.j('e6')->>'status' = 'preview'
                  AND pg_temp.j('e6')->'warnings'->0->>'type' = 'fire_number_match',
                  'E6 a numero_fuego match in the same company is a warning in the preview, not a rejection');
SELECT pg_temp.ok(NOT (pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811000007') ? 'warnings')
                  AND NOT (pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100002') ? 'warnings'),
                  'E7 a fire number of another company (or no match) gives no warning');

-- ---------------------------------------------------------------------------------------------
-- F. Preview / commit
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100003', p_confirmed => 'true')->>'status' = 'preview_required'
                  AND pg_temp.buy('9811', 't099-editor@example.test', p_confirmed => 'true')->>'status' = 'preview_required'
                  AND pg_temp.n(9811) = :n9811_before,
                  'F2 a commit without preview_hash answers preview_required and writes nothing (both tools)');
SELECT pg_temp.put('f3', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100003'));
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-admin@example.test', p_tag => '9811100003', p_confirmed => 'true',
                              p_hash => pg_temp.j('f3')->>'preview_hash')->>'status' = 'preview_required'
                  AND pg_temp.reg('9812', 't099-editor@example.test', p_upp => 'Sur', p_tag => '9811100003', p_confirmed => 'true',
                                  p_hash => pg_temp.j('f3')->>'preview_hash')->>'status' = 'preview_required'
                  AND pg_temp.n(9811) = :n9811_before AND pg_temp.n(9812) = 0,
                  'F3 a preview_hash of another actor or another company is refused');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100003', p_lot => 'Maceo', p_confirmed => 'true',
                              p_hash => pg_temp.j('f3')->>'preview_hash')->>'status' = 'preview_required'
                  AND pg_temp.n(9811) = :n9811_before,
                  'F4 data changed after the preview: preview_required');
SELECT pg_temp.put('f5', pg_temp.reg('9811', 'T099-Editor@example.test', p_lot => 'Maceo', p_tag => '9811100003', p_folio => '7130005',
                                     p_origin => '070656515001', p_age => '8', p_notes => 'nota de prueba', p_confirmed => 'commit',
                                     p_channel => 'WHATSAPP'));
SELECT pg_temp.ok(pg_temp.j('f5')->>'status' = 'recorded' AND pg_temp.n(9811) = :n9811_before + 1
                  AND (SELECT tenant_id = 9811 AND species = 'BOVINO' AND category = 'BECERRO' AND business_model = 'CRIA'
                              AND current_status = 'ACTIVO' AND rfid_siniiga = '9811100003' AND current_weight_kg IS NULL
                              AND birth_date = fn_livestock_chat_today() - 244
                              AND production_unit_id = '00000000-0000-4099-8000-000000000101'
                              AND lot_id = (SELECT id FROM production_unit_lots WHERE id_company = 9811 AND lot_name = 'Maceo')
                              AND metadata->>'source' = 'REGULARIZACION_PADRON' AND metadata->>'guide_folio' = '7130005'
                              AND metadata->>'origin_upp_code' = '07-065-6515-001' AND (metadata->>'origin_upp_code_valid')::boolean
                              AND (metadata->>'birth_date_estimated')::boolean AND (metadata->>'reported_age_months')::numeric = 8
                              AND metadata->>'registered_by' = 't099-editor@example.test' AND metadata->>'channel' = 'WHATSAPP'
                              AND metadata->>'migration' = '099' AND metadata->>'notes' = 'nota de prueba'
                              AND NOT metadata ? 'purchase_price' AND NOT metadata ? 'seller_name' AND NOT metadata ? 'purchase_date'
                         FROM cattle_livestock WHERE id = (pg_temp.j('f5')->>'livestock_id')::uuid),
                  'F5 commit with the preview_hash records the animal with UPP, lot, estimated birth date and full metadata (no purchase data)');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_lot => 'Maceo', p_tag => '9811100003', p_folio => '7130005',
                              p_origin => '070656515001', p_age => '8', p_notes => 'nota de prueba',
                              p_confirmed => 'commit')->>'status' = 'duplicate'
                  AND pg_temp.n(9811) = :n9811_before + 1,
                  'F6 a second commit of the same tagged animal is a duplicate (no second row)');
-- p_force_duplicate: the database honours it only to skip the 2-minute duplicate_recent check of an UNTAGGED animal.
-- It cannot know whether the user confirmed twice: the prompt (part c) must send it as true ONLY after a duplicate_recent
-- answer AND a second explicit confirmation of the user. F7-F10 document that contract.
SELECT pg_temp.put('f7a', pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGA',
                                      p_age => '5', p_folio => NULL, p_confirmed => 'commit'));
SELECT pg_temp.put('f7b', pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGA',
                                      p_age => '5', p_folio => NULL, p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('f7a')->>'status' = 'recorded' AND pg_temp.j('f7b')->>'status' = 'duplicate_recent'
                  AND pg_temp.j('f7b')->>'livestock_id' = pg_temp.j('f7a')->>'livestock_id'
                  AND pg_temp.n(9811) = :n9811_before + 2,
                  'F7 a repeated "Sí" for an untagged animal within 2 minutes answers duplicate_recent and writes nothing');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGA',
                              p_age => '5', p_folio => NULL, p_confirmed => 'commit', p_force => 'true')->>'status' = 'recorded'
                  AND pg_temp.n(9811) = :n9811_before + 3,
                  'F8 after duplicate_recent (and the second explicit confirmation the prompt requires), p_force_duplicate=true records it');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100003', p_force => 'true', p_confirmed => 'commit')->>'status' = 'duplicate'
                  AND pg_temp.buy('9811', 't099-editor@example.test', p_seller => 'desconocido', p_force => 'true', p_confirmed => 'commit')->>'status' = 'need_info'
                  AND pg_temp.reg('9811', 't099-customer@example.test', p_species => 'BORREGO', p_category => 'BORREGA', p_folio => NULL,
                                  p_force => 'true', p_confirmed => 'commit')->>'status' = 'forbidden'
                  AND pg_temp.n(9811) = :n9811_before + 3,
                  'F9 p_force_duplicate never bypasses tag duplicates, data validation or the role gate');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGO',
                              p_age => '7', p_folio => NULL, p_confirmed => 'commit', p_force => 'true')->>'status' = 'recorded'
                  AND pg_temp.n(9811) = :n9811_before + 4,
                  'F10 (contract) the database does not check that duplicate_recent came first: the prompt rule is the guard');
-- (Store the answer first: a volatile call inside a WHERE would run once per scanned row.)
SELECT pg_temp.put('f11', pg_temp.reg('9811', 't099-editor@example.test', p_species => 'EQUIDO', p_category => 'YEGUA',
                                      p_age => '30', p_folio => NULL, p_confirmed => 'commit', p_channel => 'EVIL'));
SELECT pg_temp.ok((SELECT metadata->>'channel' FROM cattle_livestock
                    WHERE id = (pg_temp.j('f11')->>'livestock_id')::uuid) = 'DESCONOCIDO',
                  'F11 an unknown channel is stored as DESCONOCIDO');

-- ---------------------------------------------------------------------------------------------
-- G. Purchase (hardened)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_price => '0'), 'purchase_price')->>'code' = 'P0117'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_price => '-5'), 'purchase_price')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_price => 'mucho'), 'purchase_price')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_price => NULL), 'purchase_price')->>'type' = 'missing',
                  'G1 purchase price 0, negative, text or missing is rejected (P0117)');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_seller => 'desconocido'), 'seller_name')->>'code' = 'P0117'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_seller => 'No sé'), 'seller_name')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_seller => ' - '), 'seller_name')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_seller => 'null'), 'seller_name')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_seller => ''), 'seller_name')->>'type' = 'missing',
                  'G2 seller missing, "desconocido", "No sé", "-" or "null" is rejected');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.buy('9812', 't099-editor@example.test'), 'upp')->>'type' = 'ambiguous'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_upp => '070656515001'), 'upp')->>'type' = 'not_found',
                  'G3 the purchase UPP must resolve: several UPP without a name, or an origin code as UPP, never create an animal without UPP');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_pdate => (fn_livestock_chat_today() + 1)::text), 'purchase_date')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_birth => '2030-01-01'), 'birth_date')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_weight => 'abc'), 'weight_kg')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.buy('9811', 't099-editor@example.test', p_weight => '0'), 'weight_kg')->>'type' = 'invalid',
                  'G4 future purchase or birth dates and invalid weights are rejected');
SELECT pg_temp.put('g5', pg_temp.buy('9812', 't099-editor@example.test', p_upp => '99-812-0000-002', p_lot => 'maceo sur',
                                     p_category => 'Vaquilla', p_tag => '9812100001', p_weight => '120 kg', p_price => '$1,300.50',
                                     p_seller => 'Rancho Ejemplo', p_pdate => '2026-10-01', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('g5')->>'status' = 'recorded'
                  AND (SELECT category = 'NOVILLONA' AND current_weight_kg = 120 AND rfid_siniiga = '9812100001'
                              AND production_unit_id = '00000000-0000-4099-8000-000000000202' AND lot_id IS NOT NULL
                              AND metadata->>'source' = 'COMPRA' AND (metadata->>'purchase_price')::numeric = 1300.50
                              AND metadata->>'seller_name' = 'Rancho Ejemplo' AND metadata->>'purchase_date' = '2026-10-01'
                              AND metadata->>'category_reported' = 'VAQUILLA' AND metadata->>'channel' = 'WHATSAPP'
                              AND metadata->>'registered_by' = 't099-editor@example.test'
                         FROM cattle_livestock WHERE id = (pg_temp.j('g5')->>'livestock_id')::uuid),
                  'G5 a valid purchase is recorded with UPP, lot and the metadata keys of the Bitácora');
SELECT pg_temp.put('g6', pg_temp.buy('9811', 't099-admin@example.test', p_species => 'EQUIDO', p_category => 'POTRO',
                                     p_seller => 'Feria Regional', p_confirmed => 'commit'));
SELECT pg_temp.ok((SELECT metadata->>'purchase_date' FROM cattle_livestock
                    WHERE id = (pg_temp.j('g6')->>'livestock_id')::uuid) = fn_livestock_chat_today()::text,
                  'G6 the purchase date defaults to today (Mexico City) when the user did not say it');
\if :{?skip_view}
\else
SELECT to_regclass('public.vw_cattle_event_log') IS NOT NULL AS has_event_log \gset
\if :has_event_log
SELECT pg_temp.ok((SELECT count(*) FROM vw_cattle_event_log
                    WHERE livestock_id = (pg_temp.j('g5')->>'livestock_id')::uuid AND event_type = 'COMPRA'
                      AND description = 'Comprado a Rancho Ejemplo por $1300.50') = 1,
                  'G7 the purchase appears in the Bitácora (vw_cattle_event_log) with seller and price');
SELECT pg_temp.ok((SELECT count(*) FROM vw_cattle_event_log WHERE livestock_id = (pg_temp.j('f5')->>'livestock_id')::uuid) = 0,
                  'G8 (debt, documented) a regularization does not appear in the Bitácora');
\endif
\endif

-- ---------------------------------------------------------------------------------------------
-- H. Protections
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) = :'md5_palm_before',
                  'H1 fn_reject_palm_company is unchanged');
SELECT pg_temp.ok((SELECT bool_and(p.proacl IS NOT NULL
                                   AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0))
                     FROM pg_proc p
                    WHERE p.oid IN ('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure,
                                    'public.sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)),
                  'H2 PUBLIC has no EXECUTE on the two tool functions');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '099' AND production_unit_id IS NULL) = 0
                  AND (SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '099') = 7,
                  'H3 every animal created through 099 has a production unit');

-- ---------------------------------------------------------------------------------------------
-- N. 100: guide folio normalization (upper case, inner white space collapsed, hyphens kept)
--    Every animal created here also carries metadata.migration = '099' (the tool body is the 099 one), which is why this
--    section runs after H3 counted them.
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('n1', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200001', p_folio => '  g-0042 ', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('n1')->>'status' = 'recorded'
                  AND pg_temp.j('n1')->'preview'->>'guia_transito' = 'G-0042'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE id = (pg_temp.j('n1')->>'livestock_id')::uuid) = 'G-0042',
                  'N1 a lower-case folio is stored (and previewed) in upper case');
SELECT pg_temp.put('n2', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200002', p_folio => 'Ab-12 xY', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('n2')->>'status' = 'recorded'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE id = (pg_temp.j('n2')->>'livestock_id')::uuid) = 'AB-12 XY',
                  'N2 a mixed-case folio is stored in upper case');
SELECT pg_temp.put('n3', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200003', p_folio => E'gt   55 \t a', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('n3')->>'status' = 'recorded'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE id = (pg_temp.j('n3')->>'livestock_id')::uuid) = 'GT 55 A',
                  'N3 repeated inner white space (spaces and tabs) collapses to one space');
SELECT pg_temp.put('n4', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200004', p_folio => 'prueba-1', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('n4')->>'status' = 'recorded'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE id = (pg_temp.j('n4')->>'livestock_id')::uuid) = 'PRUEBA-1'
                  AND public.fn_livestock_chat_folio('A--B - C') = 'A--B - C'
                  AND public.fn_livestock_chat_folio('7130001') = '7130001',
                  'N4 hyphens (and digits) are kept as typed');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => 'prueba-1')->>'preview_hash'
                  = pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => 'PRUEBA-1')->>'preview_hash'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => 'PRUEBA-1')->>'preview_hash'
                  = pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => '  Prueba-1 ')->>'preview_hash'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => 'PRUEBA-1')->>'preview_hash'
                  <> pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200005', p_folio => 'PRUEBA-2')->>'preview_hash',
                  'N5 prueba-1 and PRUEBA-1 give the same preview_hash; a different folio gives another');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200006', p_folio => 'desconocido'), 'guide_folio')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200006', p_folio => 'DESCONOCIDO'), 'guide_folio')->>'type' = 'invalid'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200006', p_folio => 'n/a'), 'guide_folio')->>'type' = 'invalid'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200006', p_folio => 'desconocido', p_confirmed => 'commit')->>'status' = 'need_info',
                  'N6 a placeholder folio is still rejected (any case) and nothing is written');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200007', p_folio => NULL), 'guide_folio')->>'code' = 'P0118'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200007', p_folio => NULL), 'guide_folio')->>'type' = 'missing'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200007', p_folio => 'null'), 'guide_folio')->>'code' = 'P0118'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200007', p_folio => '   '), 'guide_folio')->>'code' = 'P0118',
                  'N7 a bovine with a NULL / empty folio still gets P0118 missing');
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200008', p_folio => repeat('a', 61))->>'status' = 'need_info'
                  AND pg_temp.issue(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200008', p_folio => repeat('a', 61)), 'guide_folio')->>'type' = 'invalid'
                  AND pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811200008', p_folio => repeat('a', 60))->>'status' = 'preview',
                  'N8 a folio of 61 characters is still rejected; 60 is accepted');
SELECT pg_temp.n(9814) AS n9814_before \gset
SELECT pg_temp.ok(pg_temp.reg('9814', 't099-editor@example.test', p_tag => '9814200001', p_folio => 'iso-1', p_confirmed => 'commit')->>'status' = 'forbidden'
                  AND pg_temp.reg('9811', 't099-other@example.test', p_tag => '9814200001', p_folio => 'iso-1', p_confirmed => 'commit')->>'status' = 'forbidden'
                  AND pg_temp.n(9814) = :n9814_before,
                  'N9 tenant isolation: a user of another company is refused and nothing is written');
SELECT pg_temp.put('n9b', pg_temp.reg('9814', 't099-other@example.test', p_tag => '9814200001', p_folio => 'iso-1', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('n9b')->>'status' = 'recorded'
                  AND (SELECT tenant_id = 9814 AND metadata->>'guide_folio' = 'ISO-1' FROM cattle_livestock WHERE id = (pg_temp.j('n9b')->>'livestock_id')::uuid)
                  AND (SELECT count(*) FROM cattle_livestock WHERE tenant_id = 9811 AND metadata->>'guide_folio' = 'ISO-1') = 0,
                  'N9b the same folio typed in another company is recorded only in that company');
SELECT pg_temp.ok((SELECT provolatile = 'i' FROM pg_proc WHERE oid = 'public.fn_livestock_chat_folio(text)'::regprocedure)
                  AND public.fn_livestock_chat_folio(NULL) IS NULL AND public.fn_livestock_chat_folio('undefined') IS NULL
                  AND public.fn_livestock_chat_folio('  Ñandú 1 ') = 'ÑANDÚ 1',
                  'N10 the helper is IMMUTABLE, returns NULL where fn_livestock_chat_txt does, and keeps accented letters');

-- ---------------------------------------------------------------------------------------------
-- I. Rollback and re-apply
-- ---------------------------------------------------------------------------------------------
SELECT count(*) AS n099 FROM cattle_livestock WHERE metadata->>'migration' = '099' \gset
-- Order of a full rollback: 100 first (it drops the helper that 099's own precondition would reject), then 099.
\ir 100_rollback.sql
SELECT pg_temp.ok(md5(pg_get_functiondef('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)) = :'md5_sp_099'
                  AND to_regprocedure('public.fn_livestock_chat_folio(text)') IS NULL
                  AND (SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '099') = :n099,
                  'I0 the 100 rollback restores the exact 099 function, drops the helper and keeps every animal');
\ir 099_rollback.sql
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100009', p_confirmed => 'commit')->>'status' = 'disabled'
                  AND pg_temp.buy('9811', 't099-editor@example.test', p_confirmed => 'commit')->>'status' = 'disabled',
                  'I1 after the rollback both tools answer disabled');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '099') = :n099,
                  'I2 the rollback keeps every animal already registered (no DELETE)');
\ir 099_rollback.sql
SELECT pg_temp.ok(true, 'I3 running the rollback twice is harmless');
\ir 099_livestock_regularization.sql
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811100009')->>'status' = 'preview'
                  AND md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) = :'md5_palm_before',
                  'I4 re-applying 099 after a rollback restores the tools');

-- ---------------------------------------------------------------------------------------------
-- I100. 100 on top of the re-applied 099: no back-fill, rollback restores 099, re-apply
-- ---------------------------------------------------------------------------------------------
INSERT INTO cattle_livestock (tenant_id, species, category, business_model, current_status, rfid_siniiga, production_unit_id, metadata)
VALUES (9811, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9811300001', '00000000-0000-4099-8000-000000000101',
        '{"guide_folio": "abc-1  x", "source": "REGULARIZACION_PADRON"}'::jsonb);
\ir 100_livestock_folio_normalization.sql
SELECT pg_temp.ok((SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE rfid_siniiga = '9811300001') = 'abc-1  x',
                  'I5 applying 100 does not rewrite the folio of an existing animal (no back-fill)');
-- (Store the answer first: a volatile call and a read of its row in one statement see the same snapshot.)
SELECT pg_temp.put('i6', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811300002', p_folio => 'zz  9', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('i6')->>'status' = 'recorded'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE rfid_siniiga = '9811300002') = 'ZZ 9',
                  'I6 re-applying 100 after a 099 re-apply normalizes again');
\ir 100_rollback.sql
SELECT pg_temp.ok(md5(pg_get_functiondef('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)) = :'md5_sp_099'
                  AND to_regprocedure('public.fn_livestock_chat_folio(text)') IS NULL,
                  'I7 the 100 rollback restores the exact 099 function and drops the helper');
SELECT pg_temp.ok((SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE rfid_siniiga = '9811300002') = 'ZZ 9'
                  AND (SELECT metadata->>'guide_folio' FROM cattle_livestock WHERE rfid_siniiga = '9811300001') = 'abc-1  x'
                  AND NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(
                        (SELECT proacl FROM pg_proc WHERE oid = 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure),
                        acldefault('f', (SELECT proowner FROM pg_proc WHERE oid = 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)))) a WHERE a.grantee = 0),
                  'I8 the 100 rollback keeps the data and keeps PUBLIC without EXECUTE');
SELECT pg_temp.put('i9', pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811300003', p_folio => 'low-1'));
SELECT pg_temp.ok(pg_temp.j('i9')->'preview'->>'guia_transito' = 'low-1',
                  'I9 after the 100 rollback the folio is stored as typed again (099 behaviour)');
\ir 100_rollback.sql
SELECT pg_temp.ok(true, 'I10 running the 100 rollback twice is harmless');
\ir 100_livestock_folio_normalization.sql
SELECT pg_temp.ok(pg_temp.reg('9811', 't099-editor@example.test', p_tag => '9811300003', p_folio => 'low-1')->'preview'->>'guia_transito' = 'LOW-1',
                  'I11 100 can be applied again after its rollback');

-- ---------------------------------------------------------------------------------------------
SELECT count(*) AS passed FROM t099_res \gset
\echo
\echo *** 100 TESTS (includes the 099 assertions): :passed assertions passed; rolling back, nothing is kept ***
ROLLBACK;
