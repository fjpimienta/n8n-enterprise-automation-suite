-- 080_qa_palm_tenant_seed.sql — QA tenant for the palm domain. NOT part of migration 080.
-- Creates the company "Plantación de Pruebas" (industry "Agricultura de Precisión", so the frontend treats it
-- as palm domain) and an active ADMIN membership for fjpimienta@gmail.com. Everything under this company is
-- TEST DATA (same convention as company 3, "Rancho El Palomar"). Company 7 ("Plantación Palma Real") is a
-- real client and must never be used for QA.
--
-- Idempotent: the company is found by name + metadata.qa_tenant = true; the membership is created or
-- reactivated as ADMIN. Aborts if a company with the same name exists WITHOUT the QA flag (never takes over
-- a real company). Membership changes are recorded in access_audit_log (same table as sp_access_*).
--
-- Dry run is the default and writes NOTHING (not even a sequence value): it only reports what it would do.
--   psql -v ON_ERROR_STOP=1 -f 080_qa_palm_tenant_seed.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 080_qa_palm_tenant_seed.sql   -> commit
-- Independent of 080 (only companys / user_companies / access_audit_log), but meant to be run after it.

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SELECT set_config('t080qa.apply', :'apply', true) AS apply;

DO $$
DECLARE
    c_name      constant text := 'Plantación de Pruebas';
    c_industry  constant text := 'Agricultura de Precisión';
    c_email     constant text := 'fjpimienta@gmail.com';
    v_apply     boolean := current_setting('t080qa.apply')::boolean;
    v_company   integer;
    v_member    record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE lower(email) = c_email AND is_active IS NOT FALSE) THEN
        RAISE EXCEPTION 'ABORT: user % does not exist or is inactive.', c_email;
    END IF;

    IF EXISTS (SELECT 1 FROM companys WHERE lower(btrim(company_name)) = lower(c_name)
                AND coalesce(metadata->>'qa_tenant', 'false') <> 'true') THEN
        RAISE EXCEPTION 'ABORT: a company named "%" exists without metadata.qa_tenant = true. Not touching it.', c_name;
    END IF;

    SELECT id_company INTO v_company FROM companys
     WHERE lower(btrim(company_name)) = lower(c_name) AND metadata->>'qa_tenant' = 'true'
     ORDER BY id_company LIMIT 1;

    IF v_company IS NULL THEN
        IF NOT v_apply THEN
            RAISE NOTICE 'DRY RUN: would create company "%" (industry "%") and an ADMIN membership for %.',
                c_name, c_industry, c_email;
            RETURN;
        END IF;
        INSERT INTO companys (company_name, industry, relation_type, is_active, notes, metadata)
        VALUES (c_name, c_industry, 'Pruebas', true,
                'Empresa de PRUEBAS del dominio palma (QA). Todo lo que cuelga de ella es dato de prueba.',
                jsonb_build_object('qa_tenant', true, 'domain', 'PALMA',
                                   'created_by_script', '080_qa_palm_tenant_seed.sql'))
        RETURNING id_company INTO v_company;
        RAISE NOTICE 'Created QA company % (id_company %).', c_name, v_company;
    ELSE
        RAISE NOTICE 'QA company already exists: id_company %.', v_company;
    END IF;

    SELECT role, is_active INTO v_member FROM user_companies
     WHERE lower(email) = c_email AND id_company = v_company;

    IF FOUND AND upper(v_member.role) = 'ADMIN' AND v_member.is_active THEN
        RAISE NOTICE 'Membership already ADMIN and active: nothing to do.';
        RETURN;
    END IF;

    IF NOT v_apply THEN
        RAISE NOTICE 'DRY RUN: would % the membership of % in company % as ADMIN (current: %).',
            CASE WHEN FOUND THEN 'update' ELSE 'create' END, c_email, v_company,
            CASE WHEN FOUND THEN v_member.role || '/' || CASE WHEN v_member.is_active THEN 'active' ELSE 'inactive' END
                 ELSE 'none' END;
        RETURN;
    END IF;

    INSERT INTO user_companies (email, id_company, role, is_active)
    VALUES (c_email, v_company, 'ADMIN', true)
    ON CONFLICT (email, id_company) DO UPDATE SET role = 'ADMIN', is_active = true;

    INSERT INTO access_audit_log (id_company, actor_email, is_platform_admin, target_email, action, old_value, new_value)
    VALUES (v_company, c_email, true, c_email,
            CASE WHEN v_member IS NULL THEN 'USER_ADDED'
                 WHEN NOT v_member.is_active THEN 'USER_REACTIVATED'
                 ELSE 'ROLE_CHANGED' END,
            CASE WHEN v_member IS NULL THEN NULL
                 ELSE jsonb_build_object('role', v_member.role, 'is_active', v_member.is_active) END,
            jsonb_build_object('role', 'ADMIN', 'is_active', true, 'source', '080_qa_palm_tenant_seed.sql'));
    RAISE NOTICE 'Membership of % in company % set to ADMIN (active).', c_email, v_company;
END $$;

SELECT c.id_company, c.company_name, c.industry, c.metadata->>'qa_tenant' AS qa_tenant,
       uc.role, uc.is_active AS membership_active
  FROM companys c
  LEFT JOIN user_companies uc ON uc.id_company = c.id_company AND lower(uc.email) = 'fjpimienta@gmail.com'
 WHERE c.metadata->>'qa_tenant' = 'true';

\if :apply
COMMIT;
\echo '*** QA palm tenant seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: nothing written ***'
\endif
