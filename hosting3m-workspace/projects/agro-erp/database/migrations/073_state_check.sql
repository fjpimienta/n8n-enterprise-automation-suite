-- 073_state_check.sql — READ-ONLY state assertions for migration 073 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with
-- ON_ERROR_STOP) when any assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      < 073_state_check.sql   -- only prints fingerprints
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     < 073_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back < 073_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 073 -> applied -> rollback -> rolled_back -> 073 -> applied.
-- The FINGERPRINT lines must be identical at every step: they cover everything 073 and its rollback
-- must never touch (every other crud_models row, the untouched columns of users/user_companies
-- models, and the users / user_companies data; password excluded).

BEGIN READ ONLY;

SELECT set_config('t073.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'other_crud_models' AS fingerprint,
       md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5
  FROM crud_models c
 WHERE c.model_name NOT IN ('users', 'user_companies', 'company_members', 'access_add_user',
                            'access_update_member', 'access_set_active')
UNION ALL
SELECT 'users_user_companies_untouched_columns',
       md5(string_agg(concat_ws('|', c.model_name, c.table_name, c.primary_key, c.allowed_fields::text,
                                c.default_filter, c.schema_json::text, c.hooks::text, c.allowed_roles_insert,
                                c.allowed_roles_update, c.allowed_roles_delete, c.joins::text,
                                c.is_global::text, c.sp_requires_tenant::text), '#' ORDER BY c.model_name))
  FROM crud_models c
 WHERE c.model_name IN ('users', 'user_companies')
UNION ALL
SELECT 'users_data_without_password',
       md5(string_agg(concat_ws('|', u.email, u.tenant_id::text, u.names, u.lastname, u.phone, u.role,
                                u.is_active::text, u.created_at::text), '#' ORDER BY u.email))
  FROM users u
UNION ALL
SELECT 'user_companies_data',
       md5(string_agg(concat_ws('|', uc.email, uc.id_company::text, uc.role, uc.is_active::text,
                                uc.created_at::text), '#' ORDER BY uc.email, uc.id_company))
  FROM user_companies uc;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect   text := current_setting('t073.expect');
    v_failures integer := 0;
    r          record;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got "%")', v_expect;
    END IF;
    IF v_expect = 'before' THEN
        RAISE NOTICE 'expect=before: fingerprints only, no assertions.';
        RETURN;
    END IF;
    IF to_regclass('public.crud_models_backup_20261012_073') IS NULL THEN
        RAISE EXCEPTION 'crud_models_backup_20261012_073 not found: 073 was never applied here.';
    END IF;

    IF v_expect = 'applied' THEN
        -- The four 073 models carry exactly the intended config
        FOR r IN
            SELECT t.model_name,
                   c.model_name IS NOT NULL
                   AND c.table_name = t.table_name
                   AND c.primary_key = t.primary_key
                   AND c.allowed_fields = t.allowed_fields::jsonb
                   AND c.default_filter IS NULL
                   AND c.schema_json = t.schema_json::jsonb
                   AND c.allowed_ops = t.allowed_ops::text[]
                   AND c.allowed_roles_select = t.sel AND c.allowed_roles_insert = t.ins
                   AND c.allowed_roles_update = 'NONE' AND c.allowed_roles_delete = 'NONE'
                   AND c.joins = '[]'::jsonb AND c.is_global IS FALSE
                   AND c.sp_requires_tenant = t.sp_tenant AS ok
              FROM (VALUES
                ('company_members', 'vw_company_members', 'email, id_company',
                 '["id_company","email","names","lastname","phone","role","is_active","account_is_active","profile_managed_here","created_at"]',
                 '{}', '{SELECT}', 'ADMIN', 'NONE', false),
                ('access_add_user', 'sp_access_add_user', 'email',
                 '["email","names","lastname","phone","role","password","actor_email"]',
                 '{"email": {"type": "text", "required": true}, "role": {"type": "text", "required": true}}',
                 '{INSERT}', 'NONE', 'ADMIN', true),
                ('access_update_member', 'sp_access_update_member', 'email',
                 '["email","names","lastname","phone","role","password","actor_email"]',
                 '{"email": {"type": "text", "required": true}, "role": {"type": "text", "required": true}}',
                 '{INSERT}', 'NONE', 'ADMIN', true),
                ('access_set_active', 'sp_access_set_active', 'email',
                 '["email","is_active","actor_email"]',
                 '{"email": {"type": "text", "required": true}, "is_active": {"type": "boolean", "required": true}}',
                 '{INSERT}', 'NONE', 'ADMIN', true)
              ) AS t(model_name, table_name, primary_key, allowed_fields, schema_json, allowed_ops, sel, ins, sp_tenant)
              LEFT JOIN crud_models c ON c.model_name = t.model_name
        LOOP
            RAISE NOTICE '% %: 073 config', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END, r.model_name;
            IF NOT r.ok THEN v_failures := v_failures + 1; END IF;
        END LOOP;

        -- users: SELECT ADMIN only, DELETE removed, everything else as before 073
        SELECT (c.allowed_roles_select = 'ADMIN' AND c.allowed_ops = array_remove(b.allowed_ops, 'DELETE')) AS ok
          INTO r
          FROM crud_models c JOIN crud_models_backup_20261012_073 b USING (model_name)
         WHERE c.model_name = 'users';
        RAISE NOTICE '% users: SELECT=ADMIN, no DELETE', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END;
        IF NOT coalesce(r.ok, false) THEN v_failures := v_failures + 1; END IF;

        -- user_companies: no INSERT/UPDATE/DELETE, SELECT roles unchanged
        SELECT (c.allowed_roles_select = b.allowed_roles_select
                AND c.allowed_ops = ARRAY(SELECT op FROM unnest(b.allowed_ops) AS op
                                           WHERE op NOT IN ('INSERT', 'UPDATE', 'DELETE'))) AS ok
          INTO r
          FROM crud_models c JOIN crud_models_backup_20261012_073 b USING (model_name)
         WHERE c.model_name = 'user_companies';
        RAISE NOTICE '% user_companies: read-only through the gateway', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END;
        IF NOT coalesce(r.ok, false) THEN v_failures := v_failures + 1; END IF;

        SELECT to_regclass('public.vw_company_members') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                                WHERE table_schema = 'public' AND table_name = 'vw_company_members'
                                  AND column_name = 'password') AS ok INTO r;
        RAISE NOTICE '% vw_company_members exists without password', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END;
        IF NOT r.ok THEN v_failures := v_failures + 1; END IF;

    ELSE -- rolled_back
        FOR r IN
            SELECT c.model_name,
                   (c.allowed_ops = b.allowed_ops AND c.allowed_roles_select = b.allowed_roles_select) AS ok
              FROM crud_models c JOIN crud_models_backup_20261012_073 b USING (model_name)
             WHERE c.model_name IN ('users', 'user_companies')
        LOOP
            RAISE NOTICE '% %: pre-073 allowed_ops/allowed_roles_select', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END, r.model_name;
            IF NOT r.ok THEN v_failures := v_failures + 1; END IF;
        END LOOP;

        FOR r IN
            SELECT c.model_name,
                   (c.allowed_ops = '{}'::text[] AND c.allowed_roles_select = 'NONE' AND c.allowed_roles_insert = 'NONE'
                    AND c.allowed_roles_update = 'NONE' AND c.allowed_roles_delete = 'NONE') AS ok
              FROM crud_models c
             WHERE c.model_name IN ('company_members', 'access_add_user', 'access_update_member', 'access_set_active')
               AND NOT EXISTS (SELECT 1 FROM crud_models_backup_20261012_073 b WHERE b.model_name = c.model_name)
        LOOP
            RAISE NOTICE '% %: disabled', CASE WHEN r.ok THEN 'OK  ' ELSE 'FAIL' END, r.model_name;
            IF NOT r.ok THEN v_failures := v_failures + 1; END IF;
        END LOOP;
    END IF;

    IF v_failures > 0 THEN
        RAISE EXCEPTION '073 state check (%): % assertion(s) failed', v_expect, v_failures;
    END IF;
    RAISE NOTICE '073 state check (%): all assertions passed', v_expect;
END $$;

ROLLBACK;
