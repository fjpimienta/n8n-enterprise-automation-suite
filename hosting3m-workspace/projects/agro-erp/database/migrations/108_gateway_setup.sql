-- 108_gateway_setup.sql: synthetic fixtures for 108_gateway_tests.py. LOCAL ONLY.
-- psql -X -v ON_ERROR_STOP=1 -v i_am_local=yes -f 108_gateway_setup.sql
-- Creates two fictitious companies (GW108 Company A / B), four fictitious users (password SHA-256 of a synthetic string), their memberships,
-- 3 + 2 fictitious animals (identifiers 9999... / 9998..., no real INEGI state code) and one PALPACION event each. No palpation_repro_details
-- rows (that table is append-only). Remove everything with 108_gateway_cleanup.sql. Never run this against production.
\set ON_ERROR_STOP on
\if :{?i_am_local}
\else
\echo 'ABORT: pass -v i_am_local=yes (LOCAL databases only).'
\quit
\endif
BEGIN;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM companys WHERE company_name LIKE 'GW108%') THEN RAISE EXCEPTION 'ABORT: GW108 fixtures already exist. Run 108_gateway_cleanup.sql first.'; END IF;
END $$;
INSERT INTO companys (company_name, industry) VALUES ('GW108 Company A', 'Ganaderia'), ('GW108 Company B', 'Ganaderia');
CREATE TEMP TABLE c AS SELECT company_name n, id_company id FROM companys WHERE company_name IN ('GW108 Company A', 'GW108 Company B');
INSERT INTO users (email, names, password, role)
SELECT e, 'GW108 ' || e, encode(sha256(convert_to('SyntheticPw-108', 'UTF8')), 'hex'), 'ADMIN'
  FROM unnest(ARRAY['gw108-admin-a@example.invalid', 'gw108-editor-a@example.invalid', 'gw108-cust-a@example.invalid', 'gw108-admin-b@example.invalid']) e;
INSERT INTO user_companies (email, id_company, role)
SELECT 'gw108-admin-a@example.invalid', id, 'ADMIN' FROM c WHERE n = 'GW108 Company A'
UNION ALL SELECT 'gw108-editor-a@example.invalid', id, 'EDITOR' FROM c WHERE n = 'GW108 Company A'
UNION ALL SELECT 'gw108-cust-a@example.invalid', id, 'CUSTOMER' FROM c WHERE n = 'GW108 Company A'
UNION ALL SELECT 'gw108-admin-b@example.invalid', id, 'ADMIN' FROM c WHERE n = 'GW108 Company B';
INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status)
SELECT c.id, '9999' || lpad(g::text, 6, '8'), 'CRIA', 'VACA', 'ACTIVO' FROM c, generate_series(1, 3) g WHERE c.n = 'GW108 Company A';
INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status)
SELECT c.id, '9998' || lpad(g::text, 6, '7'), 'CRIA', 'VACA', 'ACTIVO' FROM c, generate_series(1, 2) g WHERE c.n = 'GW108 Company B';
INSERT INTO cattle_health_logs (livestock_id, event_type, event_date, medicines_json)
SELECT l.id, 'PALPACION', '2026-11-10 08:00', '{"result":"PRENADA","gestation_days":"90"}'::jsonb
  FROM cattle_livestock l JOIN c ON c.id = l.tenant_id;
COMMIT;
SELECT n AS company, id AS id_company FROM c;
