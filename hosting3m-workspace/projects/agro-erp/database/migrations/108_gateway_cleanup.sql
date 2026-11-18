-- 108_gateway_cleanup.sql: removes the synthetic fixtures of 108_gateway_setup.sql and the synthetic bulk events of 108_gateway_tests.py. LOCAL ONLY.
-- psql -X -v ON_ERROR_STOP=1 -v i_am_local=yes [-v remove_108=yes] -f 108_gateway_cleanup.sql
-- Only rows that belong to the two GW108 companies (or carry the gw108_bulk marker inside them) are touched. With remove_108=yes it also removes the two
-- gateway models and the two views of migration 108 from THIS LOCAL database (to leave it as it was before testing). Never run this against production.
\set ON_ERROR_STOP on
\if :{?i_am_local}
\else
\echo 'ABORT: pass -v i_am_local=yes (LOCAL databases only).'
\quit
\endif
BEGIN;
CREATE TEMP TABLE c AS SELECT id_company id FROM companys WHERE company_name LIKE 'GW108 Company %';
DELETE FROM cattle_health_logs h USING cattle_livestock l WHERE l.id = h.livestock_id AND l.tenant_id IN (SELECT id FROM c);
DELETE FROM cattle_livestock WHERE tenant_id IN (SELECT id FROM c);
DELETE FROM user_companies WHERE email LIKE 'gw108-%@example.invalid' AND id_company IN (SELECT id FROM c);
DELETE FROM users WHERE email LIKE 'gw108-%@example.invalid';
DELETE FROM companys WHERE id_company IN (SELECT id FROM c);
\if :{?remove_108}
DELETE FROM crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd');
DROP VIEW IF EXISTS public.vw_palpation_herd;
DROP VIEW IF EXISTS public.vw_palpation_events;
\endif
COMMIT;
SELECT (SELECT count(*) FROM companys WHERE company_name LIKE 'GW108%') AS gw108_companies_left,
       (SELECT count(*) FROM users WHERE email LIKE 'gw108-%') AS gw108_users_left,
       (SELECT count(*) FROM cattle_livestock WHERE rfid_siniiga ~ '^999[89]' AND tenant_id NOT IN (SELECT id_company FROM companys)) AS orphan_animals;
