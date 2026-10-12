-- 073_tests.sql — functional checks for migration 073. Run AFTER 073. Everything is rolled back.
-- Uses two synthetic companies (ids above the current max) and synthetic @example.test accounts;
-- no real company, user or membership is read or modified. Each check prints "Tn OK" or "Tn FAIL".
BEGIN;

DO $$
DECLARE
    v_a        integer;
    v_b        integer;
    v_hash_old text;
    v_res      jsonb;
    v_n        integer;
    a1 constant text := 't073-admin-a@example.test';
    a2 constant text := 't073-admin2-a@example.test';
    b1 constant text := 't073-admin-b@example.test';
    sh constant text := 't073-shared@example.test';    -- member of A and B (like real cross-company accounts)
    ex constant text := 't073-exclusive@example.test'; -- member of A only
    ed constant text := 't073-editor-a@example.test';  -- EDITOR of A
BEGIN
    SELECT coalesce(max(id_company), 0) + 1001 INTO v_a FROM companys;
    v_b := v_a + 1;
    INSERT INTO companys (id_company, company_name, is_active) VALUES (v_a, 'T073 Company A', true), (v_b, 'T073 Company B', true);

    INSERT INTO users (email, tenant_id, names, lastname, phone, password, role, is_active) VALUES
        (a1, v_a, 'Admin', 'A', NULL, encode(sha256(convert_to('admin-a-pass', 'UTF8')), 'hex'), 'ADMIN', true),
        (b1, v_b, 'Admin', 'B', NULL, encode(sha256(convert_to('admin-b-pass', 'UTF8')), 'hex'), 'ADMIN', true),
        (sh, v_a, 'Shared', 'Person', '9930000001', encode(sha256(convert_to('shared-pass', 'UTF8')), 'hex'), 'EDITOR', true),
        (ex, v_a, 'Exclusive', 'Person', '9930000002', encode(sha256(convert_to('excl-pass', 'UTF8')), 'hex'), 'EDITOR', true),
        (ed, v_a, 'Editor', 'A', NULL, encode(sha256(convert_to('editor-pass', 'UTF8')), 'hex'), 'EDITOR', true);
    INSERT INTO user_companies (email, id_company, role, is_active) VALUES
        (a1, v_a, 'ADMIN', true), (b1, v_b, 'ADMIN', true),
        (sh, v_a, 'EDITOR', true), (sh, v_b, 'EDITOR', true),
        (ex, v_a, 'EDITOR', true), (ed, v_a, 'EDITOR', true);

    -- T1: an EDITOR cannot add users (P0102)
    BEGIN
        PERFORM sp_access_add_user(v_a, 'x1@example.test', 'X', NULL, NULL, 'EDITOR', 'password123', ed);
        RAISE NOTICE 'T1 FAIL: EDITOR added a user';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T1 % (%): %', CASE WHEN SQLSTATE = 'P0102' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T2: malformed email (trailing "|") is rejected (P0103)
    BEGIN
        PERFORM sp_access_add_user(v_a, '12095038@gmail.com|', 'X', NULL, NULL, 'EDITOR', 'password123', a1);
        RAISE NOTICE 'T2 FAIL: malformed email accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T2 % (%): %', CASE WHEN SQLSTATE = 'P0103' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T3: new account is created with a normalized email, active membership and audit row
    v_res := sp_access_add_user(v_a, '  New.User@Example.TEST ', 'Nuevo', 'Usuario', '9930000003', 'customer', 'password123', upper(a1));
    RAISE NOTICE 'T3 %: %',
        CASE WHEN (v_res->>'created_account')::boolean
              AND EXISTS (SELECT 1 FROM users WHERE email = 'new.user@example.test'
                            AND password = encode(sha256(convert_to('password123', 'UTF8')), 'hex'))
              AND EXISTS (SELECT 1 FROM user_companies WHERE email = 'new.user@example.test' AND id_company = v_a
                            AND role = 'CUSTOMER' AND is_active IS TRUE)
              AND EXISTS (SELECT 1 FROM access_audit_log WHERE id_company = v_a AND target_email = 'new.user@example.test'
                            AND action = 'USER_ADDED' AND actor_email = a1)
             THEN 'OK' ELSE 'FAIL' END, v_res;

    -- T4 (F1): adding an EXISTING account to another company never touches its password/profile
    SELECT password INTO v_hash_old FROM users WHERE email = ex;
    v_res := sp_access_add_user(v_b, upper(ex), 'Hijacked', 'Name', '0000000000', 'ADMIN', 'attacker-pass', b1);
    RAISE NOTICE 'T4 %: %',
        CASE WHEN NOT (v_res->>'created_account')::boolean
              AND (SELECT password FROM users WHERE email = ex) = v_hash_old
              AND (SELECT names FROM users WHERE email = ex) = 'Exclusive'
              AND (SELECT role FROM users WHERE email = ex) = 'EDITOR'
              AND EXISTS (SELECT 1 FROM user_companies WHERE email = ex AND id_company = v_b AND role = 'ADMIN')
             THEN 'OK' ELSE 'FAIL' END, v_res;

    -- T5: adding the same person twice to the same company is rejected (P0107)
    BEGIN
        PERFORM sp_access_add_user(v_b, ex, 'X', NULL, NULL, 'EDITOR', NULL, b1);
        RAISE NOTICE 'T5 FAIL: duplicate membership accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T5 % (%): %', CASE WHEN SQLSTATE = 'P0107' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T6 (F2): admin of B cannot change the global profile of a person shared with A (P0112)
    BEGIN
        PERFORM sp_access_update_member(v_b, sh, 'Renamed', NULL, NULL, 'EDITOR', NULL, b1);
        RAISE NOTICE 'T6 FAIL: shared profile modified';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T6 % (%): %', CASE WHEN SQLSTATE = 'P0112' AND (SELECT names FROM users WHERE email = sh) = 'Shared'
                                     THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T7 (F2): admin of B cannot reset the password of a shared person (P0112)
    BEGIN
        PERFORM sp_access_update_member(v_b, sh, NULL, NULL, NULL, 'EDITOR', 'new-password-1', b1);
        RAISE NOTICE 'T7 FAIL: shared password reset';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T7 % (%): %', CASE WHEN SQLSTATE = 'P0112' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T8: admin of B CAN change the role of the shared person in B only; A and users.role untouched
    v_res := sp_access_update_member(v_b, sh, 'Shared', 'Person', '9930000001', 'CUSTOMER', '', b1);
    RAISE NOTICE 'T8 %: %',
        CASE WHEN (v_res->>'role_changed')::boolean AND NOT (v_res->>'profile_updated')::boolean
              AND (SELECT role FROM user_companies WHERE email = sh AND id_company = v_b) = 'CUSTOMER'
              AND (SELECT role FROM user_companies WHERE email = sh AND id_company = v_a) = 'EDITOR'
              AND (SELECT role FROM users WHERE email = sh) = 'EDITOR'
             THEN 'OK' ELSE 'FAIL' END, v_res;

    -- T9: exclusive member -> admin may update profile + password; audit keeps no hash or password
    v_res := sp_access_update_member(v_a, ed, 'Editor', 'Renamed', '', 'EDITOR', 'brand-new-pass', a1);
    RAISE NOTICE 'T9 %: %',
        CASE WHEN (v_res->>'profile_updated')::boolean
              AND (SELECT lastname FROM users WHERE email = ed) = 'Renamed'
              AND (SELECT password FROM users WHERE email = ed) = encode(sha256(convert_to('brand-new-pass', 'UTF8')), 'hex')
              AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE target_email = ed
                                AND (coalesce(new_value::text, '') LIKE '%brand-new-pass%'
                                  OR coalesce(new_value::text, '') LIKE '%' || encode(sha256(convert_to('brand-new-pass', 'UTF8')), 'hex') || '%'))
             THEN 'OK' ELSE 'FAIL' END, v_res;

    -- T10: exclusive member role change keeps legacy users.role in sync (WhatsApp reads it)
    PERFORM sp_access_update_member(v_a, ed, NULL, NULL, NULL, 'CUSTOMER', NULL, a1);
    RAISE NOTICE 'T10 %', CASE WHEN (SELECT role FROM users WHERE email = ed) = 'CUSTOMER' THEN 'OK' ELSE 'FAIL' END;

    -- T11: an ADMIN cannot demote themselves (P0109)
    BEGIN
        PERFORM sp_access_update_member(v_a, a1, NULL, NULL, NULL, 'EDITOR', NULL, a1);
        RAISE NOTICE 'T11 FAIL: self-demotion accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T11 % (%): %', CASE WHEN SQLSTATE = 'P0109' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T12: an ADMIN cannot deactivate themselves (P0109)
    BEGIN
        PERFORM sp_access_set_active(v_a, a1, false, a1);
        RAISE NOTICE 'T12 FAIL: self-deactivation accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T12 % (%): %', CASE WHEN SQLSTATE = 'P0109' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T13: with a second ADMIN, the first one can be demoted; company still has an active ADMIN
    PERFORM sp_access_add_user(v_a, a2, 'Admin', 'Dos', NULL, 'ADMIN', 'password123', a1);
    PERFORM sp_access_update_member(v_a, a1, NULL, NULL, NULL, 'EDITOR', NULL, a2);
    RAISE NOTICE 'T13 %', CASE WHEN fn_access_other_active_admins(v_a, a1::varchar) = 1
                                AND NOT fn_is_active_company_admin(a1, v_a) THEN 'OK' ELSE 'FAIL' END;

    -- T14: deactivate/reactivate only touches this company's membership, never users.is_active
    v_res := sp_access_set_active(v_b, sh, false, b1);
    RAISE NOTICE 'T14a %: %',
        CASE WHEN (v_res->>'changed')::boolean
              AND (SELECT is_active FROM user_companies WHERE email = sh AND id_company = v_b) IS FALSE
              AND (SELECT is_active FROM user_companies WHERE email = sh AND id_company = v_a) IS TRUE
              AND (SELECT is_active FROM users WHERE email = sh) IS TRUE
              AND EXISTS (SELECT 1 FROM access_audit_log WHERE target_email = sh AND action = 'USER_DEACTIVATED')
             THEN 'OK' ELSE 'FAIL' END, v_res;
    v_res := sp_access_set_active(v_b, sh, true, b1);
    RAISE NOTICE 'T14b %', CASE WHEN (SELECT is_active FROM user_companies WHERE email = sh AND id_company = v_b) IS TRUE
                                 AND EXISTS (SELECT 1 FROM access_audit_log WHERE target_email = sh AND action = 'USER_REACTIVATED')
                                THEN 'OK' ELSE 'FAIL' END;

    -- T15: an ADMIN of A cannot manage company B (cross-tenant, P0102)
    BEGIN
        PERFORM sp_access_set_active(v_b, sh, false, a2);
        RAISE NOTICE 'T15 FAIL: cross-company change accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T15 % (%): %', CASE WHEN SQLSTATE = 'P0102' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T16: target that is not a member of the company (P0108)
    BEGIN
        PERFORM sp_access_set_active(v_b, ed, false, b1);
        RAISE NOTICE 'T16 FAIL: non-member changed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T16 % (%): %', CASE WHEN SQLSTATE = 'P0108' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T17: NULL is_active membership = no access (actor with NULL is_active is not an admin)
    UPDATE user_companies SET is_active = NULL WHERE email = b1 AND id_company = v_b;
    BEGIN
        PERFORM sp_access_set_active(v_b, sh, false, b1);
        RAISE NOTICE 'T17 FAIL: NULL-active admin acted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T17 % (%): %', CASE WHEN SQLSTATE = 'P0102' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;
    UPDATE user_companies SET is_active = true WHERE email = b1 AND id_company = v_b;

    -- T18: password too short for a new account (P0106)
    BEGIN
        PERFORM sp_access_add_user(v_a, 'short@example.test', 'X', NULL, NULL, 'EDITOR', '1234', a2);
        RAISE NOTICE 'T18 FAIL: short password accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T18 % (%): %', CASE WHEN SQLSTATE = 'P0106' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T19: the audit log is append-only (P0120)
    BEGIN
        UPDATE access_audit_log SET action = 'ROLE_CHANGED' WHERE id_company = v_a;
        RAISE NOTICE 'T19 FAIL: audit row updated';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T19 % (%): %', CASE WHEN SQLSTATE = 'P0120' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T20: view never exposes password; shared vs exclusive flag; one company per row
    SELECT count(*) INTO v_n FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'vw_company_members' AND column_name = 'password';
    RAISE NOTICE 'T20 %',
        CASE WHEN v_n = 0
              AND (SELECT profile_managed_here FROM vw_company_members WHERE email = sh AND id_company = v_a) IS FALSE
              AND (SELECT profile_managed_here FROM vw_company_members WHERE email = a2 AND id_company = v_a) IS TRUE
              AND (SELECT count(*) FROM vw_company_members WHERE id_company = v_b AND email = a2) = 0
             THEN 'OK' ELSE 'FAIL' END;

    -- T21: gateway config after 073
    RAISE NOTICE 'T21 %',
        CASE WHEN (SELECT allowed_roles_select FROM crud_models WHERE model_name = 'users') = 'ADMIN'
              AND NOT (SELECT 'DELETE' = ANY (allowed_ops) FROM crud_models WHERE model_name = 'users')
              AND NOT (SELECT allowed_ops && ARRAY['INSERT', 'UPDATE', 'DELETE'] FROM crud_models WHERE model_name = 'user_companies')
              AND (SELECT count(*) FROM crud_models WHERE model_name IN
                     ('company_members', 'access_add_user', 'access_update_member', 'access_set_active')) = 4
             THEN 'OK' ELSE 'FAIL' END;
END $$;

ROLLBACK;
