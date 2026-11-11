-- 102_tests.sql
-- Tests for 102 (web panel livestock intake: sp_register_livestock_panel). LOCAL / throw-away database ONLY: it applies 099
-- (CREATE OR REPLACE, harmless if already there), then 102, its rollback and 102 again with \ir. Everything happens inside
-- ONE transaction that ends in ROLLBACK; nothing is kept. A final read-only block proves that nothing was left behind.
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 102_tests.sql
-- A failed assertion raises 'FAIL [label]' and stops the run (the open transaction is discarded with the connection).
-- NOT EXECUTED by the author of the file: run it and report the output (see 102_RUNBOOK.md).
-- Concurrency of two commits of the same ear tag is not testable in one transaction; the UNIQUE constraints are the last
-- line and the function answers a duplicate status on unique_violation (same design as 099_concurrency_check.sh).
\set ON_ERROR_STOP on

-- What the database looked like before this run (compared again after the ROLLBACK, outside the transaction).
SELECT (to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL) AS had_fn \gset
SELECT count(*) AS fixtures_before FROM companys WHERE id_company BETWEEN 9821 AND 9825 \gset
SELECT count(*) AS users_before FROM users WHERE email LIKE 't102-%@example.test' \gset
SELECT count(*) AS animals_before FROM cattle_livestock WHERE tenant_id BETWEEN 9821 AND 9825 \gset

BEGIN;

-- ---------------------------------------------------------------------------------------------
-- Helpers (session-local)
-- ---------------------------------------------------------------------------------------------
CREATE TEMP TABLE t102_res (label text);
CREATE TEMP TABLE t102_j (k text PRIMARY KEY, j jsonb);

CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL [%]', p_label;
    END IF;
    INSERT INTO t102_res VALUES (p_label);
    RAISE NOTICE 'PASS [%]', p_label;
END $$;

CREATE FUNCTION pg_temp.put(p_k text, p_j jsonb) RETURNS jsonb LANGUAGE sql AS $$
    INSERT INTO t102_j VALUES (p_k, p_j) ON CONFLICT (k) DO UPDATE SET j = EXCLUDED.j RETURNING j
$$;
CREATE FUNCTION pg_temp.j(p_k text) RETURNS jsonb LANGUAGE sql AS $$ SELECT j FROM t102_j WHERE k = p_k $$;

-- Issue of a need_info answer for one field (NULL when absent).
CREATE FUNCTION pg_temp.issue(p_j jsonb, p_field text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT e FROM jsonb_array_elements(coalesce(p_j->'issues', '[]'::jsonb)) e WHERE e->>'field' = p_field LIMIT 1
$$;
-- Warning of a preview by type (NULL when absent).
CREATE FUNCTION pg_temp.warn(p_j jsonb, p_type text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT e FROM jsonb_array_elements(coalesce(p_j->'warnings', '[]'::jsonb)) e WHERE e->>'type' = p_type LIMIT 1
$$;
CREATE FUNCTION pg_temp.n(p_tenant integer) RETURNS bigint LANGUAGE sql AS $$
    SELECT count(*) FROM cattle_livestock WHERE tenant_id = p_tenant
$$;
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql AS $$
    SELECT (now() AT TIME ZONE 'America/Mexico_City')::date
$$;

-- Panel call with defaults. p_confirmed = 'commit' runs preview + commit with the preview's hash.
CREATE FUNCTION pg_temp.p(
    p_tenant integer, p_email text, p_upp text DEFAULT NULL, p_lot text DEFAULT NULL, p_species text DEFAULT 'BOVINO',
    p_category text DEFAULT 'VACA', p_bm text DEFAULT 'CRIA', p_tag text DEFAULT NULL, p_fire text DEFAULT NULL,
    p_chip text DEFAULT NULL, p_weight text DEFAULT NULL, p_birth text DEFAULT NULL, p_origin text DEFAULT NULL,
    p_tb text DEFAULT NULL, p_br text DEFAULT NULL, p_notes text DEFAULT NULL, p_confirmed text DEFAULT 'false',
    p_hash text DEFAULT NULL, p_force text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v jsonb;
BEGIN
    IF p_confirmed = 'commit' THEN
        v := public.sp_register_livestock_panel(p_tenant, p_upp, p_lot, p_species, p_category, p_bm, p_tag, p_fire, p_chip,
                 p_weight, p_birth, p_origin, p_tb, p_br, p_notes, 'false', NULL, NULL, p_email);
        IF v->>'status' <> 'preview' THEN RETURN v; END IF;
        RETURN public.sp_register_livestock_panel(p_tenant, p_upp, p_lot, p_species, p_category, p_bm, p_tag, p_fire, p_chip,
                 p_weight, p_birth, p_origin, p_tb, p_br, p_notes, 'true', v->>'preview_hash', p_force, p_email);
    END IF;
    RETURN public.sp_register_livestock_panel(p_tenant, p_upp, p_lot, p_species, p_category, p_bm, p_tag, p_fire, p_chip,
             p_weight, p_birth, p_origin, p_tb, p_br, p_notes, p_confirmed, p_hash, p_force, p_email);
END $$;

-- ---------------------------------------------------------------------------------------------
-- Apply 099 only if its helpers are missing (a database that already has 099/100 is used as it is), fingerprint the functions 102 must not change, then apply 102
-- ---------------------------------------------------------------------------------------------
SELECT md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) AS md5_palm_before \gset
\set embedded 1
SELECT (to_regprocedure('public.fn_livestock_chat_ctx(text,text)') IS NULL) AS need099 \gset
\if :need099
\ir 099_livestock_regularization.sql
\endif
SELECT coalesce(md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)), 'none') AS fp_before
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND (p.proname LIKE 'fn\_livestock\_chat\_%'
        OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat', 'fn_reject_palm_company',
                         'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag', 'fn_is_herd_free',
                         'sp_procesar_salida_ganado')) \gset
\ir 102_panel_livestock_sp.sql

-- ---------------------------------------------------------------------------------------------
-- Fixtures (fake: companies 9821-9825, e-mails @example.test, tags 982x...)
-- ---------------------------------------------------------------------------------------------
INSERT INTO companys (id_company, company_name, industry, is_active) VALUES
    (9821, 'T102 Uno', 'ganaderia', true),
    (9822, 'T102 Multi', 'ganaderia', true),
    (9823, 'T102 Palma', 'agricultura', true),
    (9824, 'T102 Otra Empresa', 'ganaderia', true),
    (9825, 'T102 Sin UPP', 'ganaderia', true);
INSERT INTO users (email, names, password, role, is_active) VALUES
    ('t102-admin@example.test', 'T102 Admin', 'x', 'ADMIN', true),
    ('t102-editor@example.test', 'T102 Editor', 'x', 'EDITOR', true),
    ('t102-owner@example.test', 'T102 Owner', 'x', 'EDITOR', true),
    ('t102-customer@example.test', 'T102 Customer', 'x', 'EDITOR', true),
    ('t102-other@example.test', 'T102 Other', 'x', 'ADMIN', true);
INSERT INTO user_companies (email, id_company, role, is_active) VALUES
    ('t102-admin@example.test', 9821, 'ADMIN', true),
    ('t102-admin@example.test', 9822, 'ADMIN', true),
    ('t102-admin@example.test', 9823, 'ADMIN', true),
    ('t102-admin@example.test', 9825, 'ADMIN', true),
    ('t102-editor@example.test', 9821, 'EDITOR', true),
    ('t102-owner@example.test', 9821, 'OWNER', true),
    ('t102-customer@example.test', 9821, 'CUSTOMER', true),
    ('t102-other@example.test', 9824, 'ADMIN', true);
INSERT INTO production_units (id, id_company, upp_code, ranch_name, is_active) VALUES
    ('00000000-0000-4102-8000-000000000101', 9821, '99-821-0000-001', 'Finca Uno', true),
    ('00000000-0000-4102-8000-000000000201', 9822, '99-822-0000-001', 'Norte', true),
    ('00000000-0000-4102-8000-000000000202', 9822, '99-822-0000-002', 'Sur', true),
    ('00000000-0000-4102-8000-000000000401', 9824, '99-824-0000-001', 'Finca Ajena', true);
INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type, is_active) VALUES
    (9821, '00000000-0000-4102-8000-000000000101', 'Maceo', 'PROPIO', true),
    (9824, '00000000-0000-4102-8000-000000000401', 'Potrero Ajeno', 'PROPIO', true);
INSERT INTO cattle_lifestage_catalog (especie, categoria_origen, categoria_destino, edad_min_meses) VALUES
    ('BOVINO', 'BECERRA', 'NOVILLONA', 7), ('BOVINO', 'NOVILLONA', 'VACA', 19), ('BOVINO', 'BECERRO', 'NOVILLO', 7),
    ('BOVINO', 'NOVILLO', 'TORO', 19)
ON CONFLICT DO NOTHING;
INSERT INTO cattle_livestock (tenant_id, species, category, business_model, current_status, rfid_siniiga, electronic_rfid,
                              numero_fuego, production_unit_id) VALUES
    (9821, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9821000001', NULL, NULL, '00000000-0000-4102-8000-000000000101'),
    (9821, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9821000002', '982100000000002', 'F-100', '00000000-0000-4102-8000-000000000101'),
    (9821, 'BOVINO', 'BECERRO', 'CRIA', 'ACTIVO', '9821000003', NULL, NULL, NULL),
    (9824, 'BOVINO', 'VACA', 'CRIA', 'ACTIVO', '9824000001', NULL, NULL, '00000000-0000-4102-8000-000000000401');

-- ---------------------------------------------------------------------------------------------
-- F. A preview never writes (first, so a broken preview fails here)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.n(9821) AS n9821_before \gset
SELECT pg_temp.put('f1', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100001'));
SELECT pg_temp.ok(pg_temp.j('f1')->>'status' = 'preview' AND pg_temp.n(9821) = :n9821_before
                  AND pg_temp.j('f1')->>'preview_hash' ~ '^[0-9a-f]{32}$',
                  'F1 the preview writes nothing and returns a 32-hex preview_hash');

-- ---------------------------------------------------------------------------------------------
-- A. Session gate
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.p(NULL, 't102-admin@example.test')->>'status' = 'forbidden',
                  'A1 an empty tenant is forbidden');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-other@example.test', p_tag => '9821100002')->>'status' = 'forbidden'
                  AND pg_temp.p(9821, NULL, p_tag => '9821100002')->>'status' = 'forbidden',
                  'A2 a non-member (or no e-mail) is forbidden');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-customer@example.test', p_tag => '9821100002')->>'status' = 'forbidden',
                  'A3 CUSTOMER (read-only) is forbidden');
SELECT pg_temp.ok(pg_temp.p(9823, 't102-admin@example.test', p_tag => '9821100002')->>'status' = 'palm',
                  'A4 a palm company answers palm');
SELECT pg_temp.n(9824) AS n9824_before \gset
SELECT pg_temp.ok(pg_temp.p(9824, 't102-admin@example.test', p_tag => '9821100003', p_confirmed => 'commit')->>'status' = 'forbidden'
                  AND pg_temp.n(9824) = :n9824_before,
                  'A5 an actor of company 9821 cannot write into company 9824 (forbidden, nothing written)');
SELECT pg_temp.ok(pg_temp.p(9821, 'T102-OWNER@example.test', p_tag => '9821100002')->>'status' = 'preview'
                  AND pg_temp.p(9821, 't102-admin@example.test', p_tag => '9821100002')->>'status' = 'preview',
                  'A6 OWNER (e-mail in any case) and ADMIN are allowed');
SELECT pg_temp.ok(pg_temp.n(9821) = :n9821_before AND pg_temp.n(9824) = :n9824_before,
                  'A7 the gate checks wrote nothing');

-- ---------------------------------------------------------------------------------------------
-- B. Production unit (UPP) and lot
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('b1', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100004'));
SELECT pg_temp.ok(pg_temp.j('b1')->'preview'->>'upp_code' = '99-821-0000-001'
                  AND pg_temp.j('b1')->'preview'->>'empresa' = 'T102 Uno',
                  'B1 a single active UPP is used by default (preview shows company and UPP code)');
SELECT pg_temp.put('b2', pg_temp.p(9822, 't102-admin@example.test', p_tag => '9821100005'));
SELECT pg_temp.ok(pg_temp.j('b2')->>'status' = 'need_info'
                  AND pg_temp.issue(pg_temp.j('b2'), 'upp')->>'type' = 'ambiguous'
                  AND jsonb_array_length(pg_temp.issue(pg_temp.j('b2'), 'upp')->'options') = 2,
                  'B2 several UPP and none given: need_info with the options');
SELECT pg_temp.ok(pg_temp.p(9822, 't102-admin@example.test', p_upp => 'sur', p_tag => '9821100005')->'preview'->>'upp_code' = '99-822-0000-002',
                  'B3 a named UPP is resolved (case-insensitive exact match)');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_upp => 'Finca Ajena', p_tag => '9821100005'), 'upp')->>'type' = 'not_found',
                  'B4 the UPP of another company is not found');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9825, 't102-admin@example.test', p_tag => '9821100005'), 'upp')->>'type' = 'missing',
                  'B5 a company without active UPP: need_info missing');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_lot => 'Maceo', p_tag => '9821100006')->'preview'->>'lote' = 'Maceo'
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_lot => 'Potrero Ajeno', p_tag => '9821100006'), 'lot') IS NOT NULL,
                  'B6 a lot of the UPP is accepted, a lot of another company is an issue');

-- ---------------------------------------------------------------------------------------------
-- C. Confirmation
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('c1', pg_temp.p(9821, 't102-editor@example.test', p_tag => '07 2475 7014', p_fire => 'F-200', p_chip => '982 100 000 000 009',
                                    p_weight => '412.5 kg', p_birth => '2025-03-10', p_origin => 'UPP La Bendición',
                                    p_tb => (pg_temp.today() - 10)::text, p_br => (pg_temp.today() - 10)::text,
                                    p_lot => 'Maceo', p_notes => 'nota de prueba', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('c1')->>'status' = 'recorded' AND pg_temp.j('c1')->>'identificador' = '0724757014',
                  'C1 the commit records the animal (tag normalized)');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_livestock cl
                    WHERE cl.id = (pg_temp.j('c1')->>'livestock_id')::uuid AND cl.tenant_id = 9821 AND cl.species = 'BOVINO'
                      AND cl.category = 'VACA' AND cl.business_model = 'CRIA' AND cl.current_status = 'ACTIVO'
                      AND cl.rfid_siniiga = '0724757014' AND cl.numero_fuego = 'F-200' AND cl.electronic_rfid = '982100000000009'
                      AND cl.current_weight_kg = 412.5 AND cl.birth_date = DATE '2025-03-10'
                      AND cl.production_unit_id = '00000000-0000-4102-8000-000000000101' AND cl.lot_id IS NOT NULL
                      AND cl.upp_origen = 'UPP La Bendición' AND cl.tb_test_date = pg_temp.today() - 10
                      AND cl.br_test_date = pg_temp.today() - 10) = 1,
                  'C2 every field lands in its own column (UPP, lot, fire, chip, weight, birth, origin UPP, TB, BR)');
SELECT pg_temp.ok((SELECT cl.metadata->>'source' = 'PANEL_ALTA' AND cl.metadata->>'registered_by' = 't102-editor@example.test'
                          AND cl.metadata->>'channel' = 'PANEL_WEB' AND cl.metadata->>'migration' = '102'
                          AND cl.metadata->>'tool' = 'sp_register_livestock_panel' AND cl.metadata->>'notes' = 'nota de prueba'
                          AND NOT cl.metadata ? 'preview_hash' AND NOT cl.metadata ? 'no_official_tag'
                     FROM cattle_livestock cl WHERE cl.id = (pg_temp.j('c1')->>'livestock_id')::uuid),
                  'C3 metadata: source PANEL_ALTA, actor, channel, migration; no preview_hash; no no_official_tag for an official tag');
SELECT pg_temp.n(9821) AS n_c4 \gset
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100007', p_confirmed => 'true', p_hash => 'deadbeefdeadbeefdeadbeefdeadbeef')->>'status' = 'preview_required'
                  AND pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100007', p_confirmed => 'true')->>'status' = 'preview_required'
                  AND pg_temp.n(9821) = :n_c4,
                  'C4 an invalid or missing hash answers preview_required and writes nothing');
SELECT pg_temp.put('c5', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100007'));
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100007', p_weight => '300', p_confirmed => 'true',
                            p_hash => pg_temp.j('c5')->>'preview_hash')->>'status' = 'preview_required'
                  AND pg_temp.n(9821) = :n_c4,
                  'C5 changing any value after the preview invalidates the hash');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-admin@example.test', p_tag => '9821100007', p_confirmed => 'true',
                            p_hash => pg_temp.j('c5')->>'preview_hash')->>'status' = 'preview_required',
                  'C6 a hash of another actor does not confirm');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100007', p_confirmed => 'true',
                            p_hash => pg_temp.j('c5')->>'preview_hash')->>'status' = 'recorded',
                  'C7 the exact hash of the last preview records');

-- ---------------------------------------------------------------------------------------------
-- D. Duplicates
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.n(9821) AS n_d \gset
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821000001', p_confirmed => 'commit')->>'status' = 'duplicate'
                  AND pg_temp.n(9821) = :n_d,
                  'D1 a registered ear tag of the company is a duplicate (nothing written)');
SELECT pg_temp.put('d2', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9824000001'));
SELECT pg_temp.ok(pg_temp.j('d2')->>'status' = 'duplicate_other_company' AND pg_temp.j('d2')::text NOT LIKE '%Otra Empresa%',
                  'D2 a tag of another company is duplicate_other_company and never names that company');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100008', p_chip => '982100000000002')->>'status' = 'duplicate'
                  AND pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100008', p_chip => '982100000000002')->>'campo' = 'electronic_rfid',
                  'D3 a registered chip is a duplicate (field electronic_rfid)');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821000003')->>'status' = 'exists_without_upp',
                  'D4 an animal of the company without UPP answers exists_without_upp');

-- ---------------------------------------------------------------------------------------------
-- E. No ear tag / 'S/N'
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok((SELECT bool_and(r->>'status' = 'preview' AND (r->'preview'->>'sin_arete_oficial')::boolean
                                   AND pg_temp.warn(r, 'no_official_tag') IS NOT NULL AND r->'preview'->>'arete' IS NULL)
                     FROM (SELECT pg_temp.p(9821, 't102-editor@example.test', p_tag => t) AS r
                             FROM (VALUES (NULL), (''), ('S/N'), ('s/n'), ('SN'), ('sin arete')) v (t)) x),
                  'E1 empty, S/N, s/n, SN and "sin arete" are all "no tag" with the warning');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => 'S/N'), 'no_official_tag')->>'message' LIKE '%NO podrá venderse%',
                  'E2 a bovine without tag: the warning says it cannot be sold or leave until it has a 10-digit tag');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGO', p_tag => 'S/N'), 'no_official_tag')->>'message' NOT LIKE '%NO podrá venderse%',
                  'E3 another species: the warning does not claim the sale is blocked');
SELECT pg_temp.put('e4', pg_temp.p(9821, 't102-editor@example.test', p_tag => 'S/N', p_category => 'TORO', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('e4')->>'status' = 'recorded'
                  AND pg_temp.j('e4')->>'identificador' ~ '^S/N-9821-[0-9A-F]{10}$'
                  AND (SELECT rfid_siniiga FROM cattle_livestock WHERE id = (pg_temp.j('e4')->>'livestock_id')::uuid) = pg_temp.j('e4')->>'identificador'
                  AND (SELECT metadata->>'no_official_tag' FROM cattle_livestock WHERE id = (pg_temp.j('e4')->>'livestock_id')::uuid) = 'true',
                  'E4 "S/N" is never stored: the animal gets S/N-<company>-<10 hex> and metadata.no_official_tag');
SELECT pg_temp.n(9821) AS n_e \gset
SELECT pg_temp.put('e5', pg_temp.p(9821, 't102-editor@example.test', p_tag => 'S/N', p_category => 'TORO', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('e5')->>'status' = 'duplicate_recent' AND pg_temp.n(9821) = :n_e,
                  'E5 the same animal without tag registered again within 2 minutes needs a second confirmation');
SELECT pg_temp.put('e6', pg_temp.p(9821, 't102-editor@example.test', p_tag => 'S/N', p_category => 'TORO', p_confirmed => 'commit', p_force => 'true'));
SELECT pg_temp.ok(pg_temp.j('e6')->>'status' = 'recorded' AND pg_temp.j('e6')->>'identificador' <> pg_temp.j('e4')->>'identificador'
                  AND pg_temp.n(9821) = :n_e + 1,
                  'E6 forced: recorded again with a DIFFERENT identifier');
SELECT pg_temp.put('e7', pg_temp.p(9821, 't102-editor@example.test', p_tag => '', p_category => 'TORO', p_confirmed => 'commit', p_force => 'true'));
SELECT pg_temp.ok(pg_temp.j('e7')->>'status' = 'recorded'
                  AND (SELECT count(DISTINCT rfid_siniiga) FROM cattle_livestock WHERE tenant_id = 9821 AND rfid_siniiga LIKE 'S/N-%') = 3
                  AND NOT EXISTS (SELECT 1 FROM cattle_livestock WHERE rfid_siniiga IN ('S/N', 's/n')),
                  'E7 the same request repeated twice (forced) yields three distinct identifiers and never the literal S/N');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => 'S/N', p_category => 'NOVILLO', p_confirmed => 'commit')->>'status' = 'recorded',
                  'E8 a different animal without tag is not blocked by the recent-duplicate rule');
SELECT pg_temp.ok(pg_temp.p(9822, 't102-admin@example.test', p_upp => 'Norte', p_tag => '', p_category => 'TORO', p_confirmed => 'commit')->>'status' = 'recorded'
                  AND (SELECT rfid_siniiga FROM cattle_livestock WHERE tenant_id = 9822 AND rfid_siniiga LIKE 'S/N-%') ~ '^S/N-9822-',
                  'E9 the identifier carries the company of the animal');

-- ---------------------------------------------------------------------------------------------
-- G. Typed ear tag rules
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '12345'), 'ear_tag')->>'type' = 'invalid',
                  'G1 a bovine with a typed tag that is not 10 digits is an issue (use S/N instead)');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGO', p_tag => 'AB-12', p_confirmed => 'commit')->>'status' = 'recorded'
                  AND EXISTS (SELECT 1 FROM cattle_livestock WHERE tenant_id = 9821 AND rfid_siniiga = 'AB-12'),
                  'G2 another species keeps a typed tag as typed');

-- ---------------------------------------------------------------------------------------------
-- H. Weight (optional)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('h1', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100010', p_confirmed => 'commit'));
SELECT pg_temp.ok(pg_temp.j('h1')->>'status' = 'recorded'
                  AND (SELECT current_weight_kg IS NULL FROM cattle_livestock WHERE id = (pg_temp.j('h1')->>'livestock_id')::uuid)
                  AND NOT (pg_temp.j('h1')->'preview' ? 'peso_kg'),
                  'H1 the weight is optional: NULL when not given');
SELECT pg_temp.ok((SELECT bool_and(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100011', p_weight => w), 'weight_kg') IS NOT NULL)
                     FROM (VALUES ('0'), ('-5'), ('abc'), ('2500')) v (w)),
                  'H2 a weight of 0, negative, text or above 2000 is an issue');
SELECT pg_temp.ok((pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100011', p_weight => '450 kg')->'preview'->>'peso_kg')::numeric = 450,
                  'H3 "450 kg" is read as 450');

-- ---------------------------------------------------------------------------------------------
-- I. TB / BR (optional, with warnings)
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.put('i1', pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012'));
SELECT pg_temp.ok(pg_temp.warn(pg_temp.j('i1'), 'tb_missing_or_expired')->>'message' LIKE '%no registrada%'
                  AND pg_temp.warn(pg_temp.j('i1'), 'br_missing_or_expired')->>'message' LIKE '%no registrada%',
                  'I1 a bovine without TB / BR: both warnings (the exit would be blocked)');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_tb => (pg_temp.today() - 10)::text, p_br => (pg_temp.today() - 10)::text), 'tb_missing_or_expired') IS NULL
                  AND pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_tb => (pg_temp.today() - 60)::text, p_br => (pg_temp.today() - 60)::text), 'br_missing_or_expired') IS NULL,
                  'I2 TB / BR of 10 and exactly 60 days: no warning');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_tb => (pg_temp.today() - 61)::text, p_br => (pg_temp.today() - 61)::text), 'tb_missing_or_expired')->>'message' LIKE '%61 días%'
                  AND pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_tb => (pg_temp.today() - 61)::text, p_br => (pg_temp.today() - 61)::text), 'br_missing_or_expired')->>'message' LIKE '%61 días%',
                  'I3 TB / BR older than 60 days: warning with the age');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGO', p_tag => 'S/N'), 'tb_missing_or_expired') IS NULL
                  AND pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_species => 'BORREGO', p_category => 'BORREGO', p_tag => 'S/N'), 'br_missing_or_expired') IS NULL,
                  'I4 another species: no TB / BR warning (the exit rule does not apply)');
INSERT INTO herd_free_certificates (id_company, production_unit_id, disease, folio, issued_at, valid_until)
VALUES (9821, '00000000-0000-4102-8000-000000000101', 'TB', 'T102-TB', pg_temp.today() - 30, pg_temp.today() + 300);
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012'), 'tb_missing_or_expired') IS NULL
                  AND pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012'), 'br_missing_or_expired') IS NOT NULL,
                  'I5 a valid TB herd-free dictamen of the UPP removes only the TB warning');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_tb => (pg_temp.today() + 1)::text), 'tb_test_date') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_br => 'ayer'), 'br_test_date') IS NOT NULL,
                  'I6 a future or malformed TB / BR date is an issue');
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100012', p_confirmed => 'commit')->>'status' = 'recorded'
                  AND (SELECT tb_test_date IS NULL AND br_test_date IS NULL FROM cattle_livestock WHERE rfid_siniiga = '9821100012'),
                  'I7 TB / BR stay NULL when not given (warnings do not block the registration)');

-- ---------------------------------------------------------------------------------------------
-- J. Birth date (Mexico City) and other fields
-- ---------------------------------------------------------------------------------------------
SET LOCAL TIME ZONE 'Pacific/Kiritimati';
SELECT pg_temp.ok((pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013')->'preview'->>'fecha_nacimiento')::date = pg_temp.today(),
                  'J1 an empty birth date is today in Mexico City (session time zone UTC+14)');
SET LOCAL TIME ZONE 'UTC';
SELECT pg_temp.ok((pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013')->'preview'->>'fecha_nacimiento')::date = pg_temp.today(),
                  'J2 the same under UTC');
RESET TIME ZONE;
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_birth => (pg_temp.today() + 1)::text), 'birth_date') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_birth => '1950-01-01'), 'birth_date') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_birth => '10/03/2025'), 'birth_date') IS NOT NULL,
                  'J3 a future, a 40+ years old or a malformed birth date is an issue');
SELECT pg_temp.ok((pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_birth => '2025-03-10T08:00:00Z')->'preview'->>'fecha_nacimiento')::date = DATE '2025-03-10',
                  'J4 an animal born on the ranch: the date is taken as typed, never estimated');
SELECT pg_temp.ok(pg_temp.warn(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_fire => 'F-100'), 'fire_number_repeated') IS NOT NULL
                  AND pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100013', p_fire => 'F-100', p_confirmed => 'commit')->>'status' = 'recorded',
                  'J5 a repeated fire number is a warning, not a rejection');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100014', p_chip => '123'), 'electronic_rfid') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100014', p_fire => repeat('x', 51)), 'fire_number') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100014', p_origin => repeat('x', 101)), 'origin_upp') IS NOT NULL,
                  'J6 a chip that is not 15 digits and over-long fire number / origin UPP are issues');
SELECT pg_temp.ok((pg_temp.p(9821, 't102-editor@example.test', p_species => '', p_tag => '9821100014')->'preview'->>'especie') = 'BOVINO',
                  'J7 an empty species is BOVINO');
SELECT pg_temp.ok(pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100014', p_category => 'CABALLO'), 'category') IS NOT NULL
                  AND pg_temp.issue(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100014', p_bm => 'OTRO'), 'business_model') IS NOT NULL,
                  'J8 a category of another species and an unknown business model are issues');

-- ---------------------------------------------------------------------------------------------
-- K. Protections
-- ---------------------------------------------------------------------------------------------
SELECT pg_temp.ok(md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) = :'md5_palm_before',
                  'K1 fn_reject_palm_company is unchanged');
SELECT pg_temp.ok((SELECT coalesce(md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)), 'none')
                     FROM pg_proc p
                    WHERE p.pronamespace = 'public'::regnamespace
                      AND (p.proname LIKE 'fn\_livestock\_chat\_%'
                           OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat', 'fn_reject_palm_company',
                                            'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag', 'fn_is_herd_free',
                                            'sp_procesar_salida_ganado'))) = :'fp_before',
                  'K2 no 099/100 function (nor the exit procedure) changed by 102');
SELECT pg_temp.ok((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                     FROM pg_proc p WHERE p.oid = 'public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure),
                  'K3 PUBLIC has no EXECUTE on the new function');
SELECT pg_temp.ok((SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'fn\_livestock\_chat\_%') = 17,
                  'K4 102 added no fn_livestock_chat_* helper (099 can still be re-applied)');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '102' AND (production_unit_id IS NULL OR metadata ? 'preview_hash')) = 0,
                  'K5 every animal created through 102 has a production unit and no preview_hash in metadata');

-- ---------------------------------------------------------------------------------------------
-- L. State check, rollback, idempotence
-- ---------------------------------------------------------------------------------------------
\set expect_md5_palm :md5_palm_before
\set expect applied
\ir 102_state_check.sql
SELECT pg_temp.ok(true, 'L1 state check: applied');
\ir 102_panel_livestock_sp.sql
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100020')->>'status' = 'preview', 'L2 a second apply is harmless');
SELECT count(*) AS n102 FROM cattle_livestock WHERE metadata->>'migration' = '102' \gset
\ir 102_rollback.sql
SELECT pg_temp.ok(to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL,
                  'L3 the rollback removes the function');
SELECT pg_temp.ok((SELECT count(*) FROM cattle_livestock WHERE metadata->>'migration' = '102') = :n102,
                  'L4 the rollback keeps every animal already registered (no DELETE)');
\ir 102_rollback.sql
SELECT pg_temp.ok(true, 'L5 running the rollback twice is harmless');
SELECT pg_temp.ok((SELECT coalesce(md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)), 'none')
                     FROM pg_proc p
                    WHERE p.pronamespace = 'public'::regnamespace
                      AND (p.proname LIKE 'fn\_livestock\_chat\_%'
                           OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat', 'fn_reject_palm_company',
                                            'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag', 'fn_is_herd_free',
                                            'sp_procesar_salida_ganado'))) = :'fp_before',
                  'L6 after the rollback the 099/100 functions are still identical');
\set expect before
\ir 102_state_check.sql
SELECT pg_temp.ok(true, 'L7 state check: before');
\ir 102_panel_livestock_sp.sql
SELECT pg_temp.ok(pg_temp.p(9821, 't102-editor@example.test', p_tag => '9821100021', p_confirmed => 'commit')->>'status' = 'recorded',
                  'L8 re-applying after a rollback restores the function');

-- ---------------------------------------------------------------------------------------------
SELECT count(*) AS passed FROM t102_res \gset
\echo
\echo *** 102 TESTS: :passed assertions passed; rolling back, nothing is kept ***
ROLLBACK;

-- ---------------------------------------------------------------------------------------------
-- M. End of the run leaves no trace (outside the transaction, read-only)
-- ---------------------------------------------------------------------------------------------
BEGIN READ ONLY;
SELECT (SELECT count(*) FROM companys WHERE id_company BETWEEN 9821 AND 9825) = :fixtures_before
   AND (SELECT count(*) FROM users WHERE email LIKE 't102-%@example.test') = :users_before
   AND (SELECT count(*) FROM cattle_livestock WHERE tenant_id BETWEEN 9821 AND 9825) = :animals_before
   AND (to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL) = :'had_fn' AS no_trace \gset
COMMIT;
\if :no_trace
\echo *** 102 TESTS: no trace left (fixtures, users, animals and the function are as before the run) ***
\else
\echo *** 102 TESTS FAILED: the run left something behind ***
SELECT 1 / 0;
\endif
