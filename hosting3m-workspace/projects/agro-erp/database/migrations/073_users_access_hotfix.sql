-- 073_users_access_hotfix.sql
-- Security hotfix for the shared `users` / `user_companies` gateway models (F1-F3 of the
-- "Users & Access" Step 0 report, 2026-10-12). Additive and idempotent. Rollback:
-- 073_users_access_hotfix_rollback.sql. Functional tests: 073_tests.sql.
--
-- FINDINGS (repo export of v6/CRUD synced from production on 2026-10-08/10; crud_models
-- confirmed against PRODUCTION by the project owner on 2026-10-12):
--   F1  `users` INSERT is `INSERT ... ON CONFLICT (email) DO UPDATE SET names, password, role,
--       tenant_id ...`: the ADMIN of company A "creating" an email that already belongs to
--       company B overwrote that account's password and profile -> account takeover. Real
--       cross-company accounts exist in production (members of 2-5 companies each).
--   F2  `users` UPDATE/DELETE carry no tenant scope (`WHERE email = $x` only): any company ADMIN
--       could rewrite or globally deactivate (gateway soft-delete) any account of the platform.
--   F3  `users` SELECT/GETALL/GETONE are allowed to ADMIN,EDITOR,CUSTOMER and select `users.*`.
--       Normalize Data strips `password` from responses since 2026-10-08, but the hash still
--       reaches n8n (execution data) and EDITOR/CUSTOMER can list every member's PII.
--
-- WHAT THIS MIGRATION DOES
--   1) access_audit_log (append-only) - first table of the Users & Access module.
--   2) vw_company_members - membership list of ONE company, never exposes `password`, never
--      reveals in WHICH other companies a person is a member (only `profile_managed_here`).
--   3) sp_access_add_user / sp_access_update_member / sp_access_set_active - the only write path
--      for memberships. Caller must be an active ADMIN of the company (actor email always comes
--      from the verified JWT, injected by the gateway). Rules enforced here, not in the UI:
--        * email trimmed + lowercased, malformed emails rejected;
--        * an existing account is NEVER modified when added to another company (closes F1);
--        * names/lastname/phone/password of a person who also belongs to another company can
--          only be changed by that person (platform admin: migration 074);
--        * an ADMIN cannot change their own role or deactivate themselves; the last active
--          ADMIN of a company cannot be demoted or deactivated;
--        * memberships are deactivated/reactivated, never deleted; users.is_active is never
--          touched (it is global).
--   4) crud_models: registers the view (SELECT, ADMIN) and the 3 procedures (call_sp, ADMIN);
--      `users` SELECT -> ADMIN only and DELETE removed; `user_companies` INSERT/UPDATE/DELETE
--      removed (writes only through the procedures).
--
-- Re-applying after 073_users_access_hotfix_rollback.sql restores the full 073 config (upsert).
-- Verify with 073_state_check.sql (apply -> rollback -> apply procedure in that file).
--
-- REQUIRES the matching v6/CRUD Build Query patch (spConfigByModel entries for the 3 procedures
-- + `users` guards). Deploy in ONE window: backup -> this migration -> n8n patch -> agro-erp
-- frontend. Between this migration and the frontend deploy the old Personal UPP screen cannot
-- create/edit/delete (fails closed).
--
-- NOT IN SCOPE: platform_admins, user_scope, fn_user_can_access (074+); scope enforcement in
-- n8n/MCP/WhatsApp (Phase 3); jwt-service exact-case email match.

BEGIN;

-- 0) Backup of every gateway row this migration edits or creates, taken on the FIRST apply only
--    (IF NOT EXISTS: a re-apply never overwrites the pre-073 snapshot). Rows absent from the backup
--    are the ones 073 created; the rollback only disables those.
CREATE TABLE IF NOT EXISTS crud_models_backup_20261012_073 AS
SELECT * FROM crud_models
 WHERE model_name IN ('users', 'user_companies',
                      'company_members', 'access_add_user', 'access_update_member', 'access_set_active');

-- 1) Audit log (append-only; n8n_user is a superuser, so the trigger documents intent, it is not a
--    privilege boundary)
CREATE TABLE IF NOT EXISTS public.access_audit_log (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_company        integer      NOT NULL,
    actor_email       varchar(255) NOT NULL,
    is_platform_admin boolean      NOT NULL DEFAULT false,
    target_email      varchar(255) NOT NULL,
    action            varchar(30)  NOT NULL,
    old_value         jsonb,
    new_value         jsonb,
    created_at        timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT access_audit_log_action_check CHECK (action IN (
        'USER_ADDED', 'ROLE_CHANGED', 'PROFILE_UPDATED', 'USER_DEACTIVATED', 'USER_REACTIVATED',
        'SCOPE_GRANTED', 'SCOPE_REVOKED'))
);

COMMENT ON TABLE public.access_audit_log IS
  'Append-only log of membership/role/scope changes. Emails are plain text without FKs so the log survives any account change. Password values or hashes are never stored (only password_changed). is_platform_admin is always false until migration 074.';

CREATE INDEX IF NOT EXISTS idx_access_audit_log_company_created ON public.access_audit_log (id_company, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_audit_log_target ON public.access_audit_log (lower(target_email));

CREATE OR REPLACE FUNCTION public.fn_access_audit_log_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'access_audit_log es de solo inserción (% no permitido)', TG_OP USING ERRCODE = 'P0120';
END;
$function$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_access_audit_log_no_update_delete'
                     AND tgrelid = 'public.access_audit_log'::regclass) THEN
        CREATE TRIGGER trg_access_audit_log_no_update_delete
            BEFORE UPDATE OR DELETE ON public.access_audit_log
            FOR EACH ROW EXECUTE FUNCTION public.fn_access_audit_log_immutable();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_access_audit_log_no_truncate'
                     AND tgrelid = 'public.access_audit_log'::regclass) THEN
        CREATE TRIGGER trg_access_audit_log_no_truncate
            BEFORE TRUNCATE ON public.access_audit_log
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_access_audit_log_immutable();
    END IF;
END $$;

-- 2) Email helpers (fn_is_valid_email expects an already normalized value)
CREATE OR REPLACE FUNCTION public.fn_normalize_email(p_email text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT NULLIF(lower(btrim(p_email, E' \t\r\n')), '');
$$;

CREATE OR REPLACE FUNCTION public.fn_is_valid_email(p_email text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT p_email IS NOT NULL
     AND length(p_email) <= 255
     AND p_email ~ '^[a-z0-9._%+-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$';
$$;

-- 3) Shared guards for the access procedures
CREATE OR REPLACE FUNCTION public.fn_access_assert_company_admin(p_id_company integer, p_actor_email text)
RETURNS void
LANGUAGE plpgsql STABLE
AS $function$
BEGIN
    IF p_id_company IS NULL THEN
        RAISE EXCEPTION 'Se requiere la empresa activa' USING ERRCODE = 'P0101';
    END IF;
    -- 074 extends this with platform admins; every access procedure goes through here.
    IF NOT public.fn_is_active_company_admin(p_actor_email, p_id_company) THEN
        RAISE EXCEPTION 'Solo un ADMIN activo de esta empresa puede administrar su personal' USING ERRCODE = 'P0102';
    END IF;
END;
$function$;

-- Locks and returns the single membership of p_email in p_id_company (case-insensitive match).
CREATE OR REPLACE FUNCTION public.fn_access_lock_member(p_id_company integer, p_email text)
RETURNS public.user_companies
LANGUAGE plpgsql
AS $function$
DECLARE
    v_matches integer;
    v_member  public.user_companies%ROWTYPE;
BEGIN
    SELECT count(*) INTO v_matches
      FROM public.user_companies
     WHERE id_company = p_id_company AND public.fn_normalize_email(email) = p_email;

    IF v_matches = 0 THEN
        RAISE EXCEPTION 'El usuario no pertenece a esta empresa' USING ERRCODE = 'P0108';
    ELSIF v_matches > 1 THEN
        RAISE EXCEPTION 'Hay más de una membresía con ese correo (mayúsculas/espacios); requiere limpieza manual' USING ERRCODE = 'P0111';
    END IF;

    SELECT * INTO v_member
      FROM public.user_companies
     WHERE id_company = p_id_company AND public.fn_normalize_email(email) = p_email
       FOR UPDATE;
    RETURN v_member;
END;
$function$;

-- Serializes concurrent role/active changes of the same company (last-ADMIN rule).
CREATE OR REPLACE FUNCTION public.fn_access_lock_company_admins(p_id_company integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    -- PERFORM runs the query to completion, so every active ADMIN row of the company is locked.
    PERFORM 1 FROM public.user_companies
      WHERE id_company = p_id_company AND upper(role) = 'ADMIN' AND is_active IS TRUE
        FOR UPDATE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_access_other_active_admins(p_id_company integer, p_email varchar)
RETURNS integer
LANGUAGE sql STABLE
AS $$
  SELECT count(*)::integer FROM public.user_companies
   WHERE id_company = p_id_company AND upper(role) = 'ADMIN' AND is_active IS TRUE AND email <> p_email;
$$;

-- 4) Membership list of one company (gateway injects id_company = x-tenant-id)
CREATE OR REPLACE VIEW public.vw_company_members AS
SELECT uc.id_company,
       uc.email,
       u.names,
       u.lastname,
       u.phone,
       upper(uc.role)::varchar(20) AS role,
       (uc.is_active IS TRUE)      AS is_active,          -- NULL membership = no access (fail-closed)
       (u.is_active IS TRUE)       AS account_is_active,  -- global account flag (WhatsApp / Web Chat)
       NOT EXISTS (SELECT 1 FROM public.user_companies o
                    WHERE o.email = uc.email AND o.id_company <> uc.id_company) AS profile_managed_here,
       uc.created_at
  FROM public.user_companies uc
  JOIN public.users u ON u.email = uc.email;

COMMENT ON VIEW public.vw_company_members IS
  'Members of a company for the Personal UPP / Users & Access screens. Never exposes users.password. profile_managed_here = false means the person also belongs to another company (which one is not revealed): their names/phone/password are then read-only for this company.';

-- 5) Write procedures (called through the gateway: tenant from x-tenant-id at position 0, actor
--    email from the verified JWT)
CREATE OR REPLACE FUNCTION public.sp_access_add_user(
    p_id_company  integer,
    p_email       character varying,
    p_names       character varying,
    p_lastname    character varying,
    p_phone       character varying,
    p_role        character varying,
    p_password    text,
    p_actor_email character varying)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_email      text := public.fn_normalize_email(p_email);
    v_actor      text := public.fn_normalize_email(p_actor_email);
    v_role       text := upper(btrim(coalesce(p_role, '')));
    v_matches    integer;
    v_user_email varchar;
    v_created    boolean := false;
BEGIN
    PERFORM public.fn_access_assert_company_admin(p_id_company, v_actor);

    IF NOT public.fn_is_valid_email(v_email) THEN
        RAISE EXCEPTION 'Correo electrónico inválido' USING ERRCODE = 'P0103';
    END IF;
    IF v_role NOT IN ('ADMIN', 'EDITOR', 'CUSTOMER') THEN
        RAISE EXCEPTION 'Rol inválido: debe ser ADMIN, EDITOR o CUSTOMER' USING ERRCODE = 'P0104';
    END IF;

    IF EXISTS (SELECT 1 FROM user_companies
                WHERE id_company = p_id_company AND fn_normalize_email(email) = v_email) THEN
        RAISE EXCEPTION 'Esta persona ya pertenece a la empresa; edítala o reactívala desde la lista' USING ERRCODE = 'P0107';
    END IF;

    SELECT count(*) INTO v_matches FROM users WHERE fn_normalize_email(email) = v_email;
    IF v_matches > 1 THEN
        RAISE EXCEPTION 'Hay más de una cuenta con ese correo (mayúsculas/espacios); requiere limpieza manual' USING ERRCODE = 'P0111';
    END IF;
    SELECT email INTO v_user_email FROM users WHERE fn_normalize_email(email) = v_email;

    IF v_user_email IS NULL THEN
        IF btrim(coalesce(p_names, '')) = '' THEN
            RAISE EXCEPTION 'El nombre es obligatorio' USING ERRCODE = 'P0105';
        END IF;
        IF length(coalesce(p_password, '')) < 8 THEN
            RAISE EXCEPTION 'La contraseña inicial debe tener al menos 8 caracteres' USING ERRCODE = 'P0106';
        END IF;

        -- Same unsalted SHA-256 hex the gateway and jwt-service use today (bcrypt migration pending).
        INSERT INTO users (email, tenant_id, names, lastname, phone, password, role, is_active)
        VALUES (v_email, p_id_company, btrim(p_names), NULLIF(btrim(coalesce(p_lastname, '')), ''),
                NULLIF(btrim(coalesce(p_phone, '')), ''),
                encode(sha256(convert_to(p_password, 'UTF8')), 'hex'), v_role, true);
        v_user_email := v_email;
        v_created := true;
    END IF;
    -- F1: an existing account is never modified here (no profile, role or password change).

    INSERT INTO user_companies (email, id_company, role, is_active)
    VALUES (v_user_email, p_id_company, v_role, true);

    INSERT INTO access_audit_log (id_company, actor_email, target_email, action, new_value)
    VALUES (p_id_company, v_actor, v_user_email, 'USER_ADDED',
            jsonb_build_object('role', v_role, 'is_active', true, 'created_account', v_created));

    RETURN jsonb_build_object('success', true, 'email', v_user_email, 'role', v_role,
                              'created_account', v_created, 'password_applied', v_created);
END;
$function$;

-- NULL in p_names/p_lastname/p_phone = keep current value; '' in lastname/phone clears it.
-- Empty or NULL p_password = keep current password.
CREATE OR REPLACE FUNCTION public.sp_access_update_member(
    p_id_company  integer,
    p_email       character varying,
    p_names       character varying,
    p_lastname    character varying,
    p_phone       character varying,
    p_role        character varying,
    p_password    text,
    p_actor_email character varying)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_email           text := public.fn_normalize_email(p_email);
    v_actor           text := public.fn_normalize_email(p_actor_email);
    v_role            text := upper(btrim(coalesce(p_role, '')));
    v_change_password boolean := coalesce(p_password, '') <> '';
    v_member          user_companies%ROWTYPE;
    v_user            record;
    v_is_self         boolean;
    v_new_names       text;
    v_new_lastname    text;
    v_new_phone       text;
    v_profile_changed boolean;
    v_role_changed    boolean := false;
BEGIN
    PERFORM public.fn_access_assert_company_admin(p_id_company, v_actor);

    IF v_role NOT IN ('ADMIN', 'EDITOR', 'CUSTOMER') THEN
        RAISE EXCEPTION 'Rol inválido: debe ser ADMIN, EDITOR o CUSTOMER' USING ERRCODE = 'P0104';
    END IF;

    PERFORM public.fn_access_lock_company_admins(p_id_company);
    v_member  := public.fn_access_lock_member(p_id_company, v_email);
    v_is_self := lower(v_member.email) = v_actor;

    SELECT names, lastname, phone INTO v_user FROM users WHERE email = v_member.email FOR UPDATE;

    v_new_names    := CASE WHEN p_names    IS NULL THEN btrim(v_user.names) ELSE btrim(p_names) END;
    v_new_lastname := CASE WHEN p_lastname IS NULL THEN NULLIF(btrim(coalesce(v_user.lastname, '')), '')
                           ELSE NULLIF(btrim(p_lastname), '') END;
    v_new_phone    := CASE WHEN p_phone    IS NULL THEN NULLIF(btrim(coalesce(v_user.phone, '')), '')
                           ELSE NULLIF(btrim(p_phone), '') END;

    IF coalesce(v_new_names, '') = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio' USING ERRCODE = 'P0105';
    END IF;

    v_profile_changed := v_new_names    IS DISTINCT FROM btrim(v_user.names)
                      OR v_new_lastname IS DISTINCT FROM NULLIF(btrim(coalesce(v_user.lastname, '')), '')
                      OR v_new_phone    IS DISTINCT FROM NULLIF(btrim(coalesce(v_user.phone, '')), '');

    -- Role (company-level)
    IF upper(v_member.role) <> v_role THEN
        IF v_is_self THEN
            RAISE EXCEPTION 'Un ADMIN no puede cambiar su propio rol' USING ERRCODE = 'P0109';
        END IF;
        -- Unreachable while the actor must be an active ADMIN of the company (the actor counts as
        -- another admin); kept as the invariant for platform-admin actions (074).
        IF upper(v_member.role) = 'ADMIN' AND v_member.is_active IS TRUE
           AND public.fn_access_other_active_admins(p_id_company, v_member.email) = 0 THEN
            RAISE EXCEPTION 'No se puede quitar el rol al último ADMIN activo de la empresa' USING ERRCODE = 'P0110';
        END IF;

        UPDATE user_companies SET role = v_role
         WHERE email = v_member.email AND id_company = p_id_company;

        INSERT INTO access_audit_log (id_company, actor_email, target_email, action, old_value, new_value)
        VALUES (p_id_company, v_actor, v_member.email, 'ROLE_CHANGED',
                jsonb_build_object('role', upper(v_member.role)), jsonb_build_object('role', v_role));
        v_role_changed := true;
    END IF;

    -- Global profile (users row): only when the person belongs to this company alone, or is the caller.
    IF v_profile_changed OR v_change_password THEN
        IF NOT v_is_self AND EXISTS (SELECT 1 FROM user_companies
                                      WHERE email = v_member.email AND id_company <> p_id_company) THEN
            RAISE EXCEPTION 'Esta persona también pertenece a otra empresa: solo ella puede cambiar su nombre, teléfono o contraseña. Aquí puedes cambiar su rol y su acceso.'
                USING ERRCODE = 'P0112';
        END IF;
        IF v_change_password AND length(p_password) < 8 THEN
            RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres' USING ERRCODE = 'P0106';
        END IF;

        UPDATE users
           SET names    = v_new_names,
               lastname = v_new_lastname,
               phone    = v_new_phone,
               password = CASE WHEN v_change_password
                               THEN encode(sha256(convert_to(p_password, 'UTF8')), 'hex')
                               ELSE password END
         WHERE email = v_member.email;

        INSERT INTO access_audit_log (id_company, actor_email, target_email, action, old_value, new_value)
        VALUES (p_id_company, v_actor, v_member.email, 'PROFILE_UPDATED',
                jsonb_build_object('names', v_user.names, 'lastname', v_user.lastname, 'phone', v_user.phone),
                jsonb_build_object('names', v_new_names, 'lastname', v_new_lastname, 'phone', v_new_phone,
                                   'password_changed', v_change_password));
    END IF;

    -- Legacy users.role is still read by the WhatsApp agent (Phase 3 moves it to user_companies.role):
    -- keep it in sync only for people who belong to this company alone.
    IF v_role_changed AND NOT EXISTS (SELECT 1 FROM user_companies
                                       WHERE email = v_member.email AND id_company <> p_id_company) THEN
        UPDATE users SET role = v_role WHERE email = v_member.email;
    END IF;

    RETURN jsonb_build_object('success', true, 'email', v_member.email, 'role', v_role,
                              'role_changed', v_role_changed,
                              'profile_updated', v_profile_changed OR v_change_password);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_access_set_active(
    p_id_company  integer,
    p_email       character varying,
    p_is_active   boolean,
    p_actor_email character varying)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_email          text := public.fn_normalize_email(p_email);
    v_actor          text := public.fn_normalize_email(p_actor_email);
    v_member         user_companies%ROWTYPE;
    v_account_active boolean;
BEGIN
    PERFORM public.fn_access_assert_company_admin(p_id_company, v_actor);

    IF p_is_active IS NULL THEN
        RAISE EXCEPTION 'Se requiere indicar si se activa o desactiva' USING ERRCODE = 'P0113';
    END IF;

    PERFORM public.fn_access_lock_company_admins(p_id_company);
    v_member := public.fn_access_lock_member(p_id_company, v_email);
    SELECT is_active IS TRUE INTO v_account_active FROM users WHERE email = v_member.email;

    IF v_member.is_active IS NOT DISTINCT FROM p_is_active THEN
        RETURN jsonb_build_object('success', true, 'email', v_member.email, 'is_active', p_is_active,
                                  'changed', false, 'account_is_active', v_account_active);
    END IF;

    IF NOT p_is_active THEN
        IF lower(v_member.email) = v_actor THEN
            RAISE EXCEPTION 'Un ADMIN no puede desactivarse a sí mismo' USING ERRCODE = 'P0109';
        END IF;
        IF upper(v_member.role) = 'ADMIN' AND v_member.is_active IS TRUE
           AND public.fn_access_other_active_admins(p_id_company, v_member.email) = 0 THEN
            RAISE EXCEPTION 'No se puede desactivar al último ADMIN activo de la empresa' USING ERRCODE = 'P0110';
        END IF;
    END IF;

    -- Only this company's membership; users.is_active is global and never touched here.
    UPDATE user_companies SET is_active = p_is_active
     WHERE email = v_member.email AND id_company = p_id_company;

    INSERT INTO access_audit_log (id_company, actor_email, target_email, action, old_value, new_value)
    VALUES (p_id_company, v_actor, v_member.email,
            CASE WHEN p_is_active THEN 'USER_REACTIVATED' ELSE 'USER_DEACTIVATED' END,
            jsonb_build_object('is_active', v_member.is_active), jsonb_build_object('is_active', p_is_active));

    RETURN jsonb_build_object('success', true, 'email', v_member.email, 'is_active', p_is_active,
                              'changed', true, 'account_is_active', v_account_active);
END;
$function$;

-- 6) Gateway models. Upsert: a re-apply (e.g. after the rollback disabled them) always restores the
--    intended config. Never overwrites a same-named model that points at a different object.
DO $$
DECLARE
    v_conflict text;
BEGIN
    SELECT string_agg(c.model_name || ' -> ' || c.table_name, ', ') INTO v_conflict
      FROM crud_models c
      JOIN (VALUES ('company_members', 'vw_company_members'), ('access_add_user', 'sp_access_add_user'),
                   ('access_update_member', 'sp_access_update_member'), ('access_set_active', 'sp_access_set_active'))
           AS t(model_name, table_name) ON t.model_name = c.model_name
     WHERE c.table_name <> t.table_name;
    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models already has model(s) with these names for other objects: %. Review before applying.', v_conflict;
    END IF;
END $$;

INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json, allowed_ops,
                         hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
                         joins, is_global, sp_requires_tenant)
VALUES
    ('company_members', 'vw_company_members', 'email, id_company',
     '["id_company","email","names","lastname","phone","role","is_active","account_is_active","profile_managed_here","created_at"]',
     NULL, '{}', '{SELECT}', '{"pre": [], "post": []}',
     'ADMIN', 'NONE', 'NONE', 'NONE', '[]', false, false),
    ('access_add_user', 'sp_access_add_user', 'email',
     '["email","names","lastname","phone","role","password","actor_email"]',
     NULL, '{"email": {"type": "text", "required": true}, "role": {"type": "text", "required": true}}',
     '{INSERT}', '{"pre": [], "post": []}',
     'NONE', 'ADMIN', 'NONE', 'NONE', '[]', false, true),
    ('access_update_member', 'sp_access_update_member', 'email',
     '["email","names","lastname","phone","role","password","actor_email"]',
     NULL, '{"email": {"type": "text", "required": true}, "role": {"type": "text", "required": true}}',
     '{INSERT}', '{"pre": [], "post": []}',
     'NONE', 'ADMIN', 'NONE', 'NONE', '[]', false, true),
    ('access_set_active', 'sp_access_set_active', 'email',
     '["email","is_active","actor_email"]',
     NULL, '{"email": {"type": "text", "required": true}, "is_active": {"type": "boolean", "required": true}}',
     '{INSERT}', '{"pre": [], "post": []}',
     'NONE', 'ADMIN', 'NONE', 'NONE', '[]', false, true)
ON CONFLICT (model_name) DO UPDATE SET
    table_name           = EXCLUDED.table_name,
    primary_key          = EXCLUDED.primary_key,
    allowed_fields       = EXCLUDED.allowed_fields,
    default_filter       = EXCLUDED.default_filter,
    schema_json          = EXCLUDED.schema_json,
    allowed_ops          = EXCLUDED.allowed_ops,
    hooks                = EXCLUDED.hooks,
    allowed_roles_select = EXCLUDED.allowed_roles_select,
    allowed_roles_insert = EXCLUDED.allowed_roles_insert,
    allowed_roles_update = EXCLUDED.allowed_roles_update,
    allowed_roles_delete = EXCLUDED.allowed_roles_delete,
    joins                = EXCLUDED.joins,
    is_global            = EXCLUDED.is_global,
    sp_requires_tenant   = EXCLUDED.sp_requires_tenant;

-- 7) Lock down the raw models
DO $$
DECLARE
    v_current text;
BEGIN
    SELECT allowed_roles_select INTO v_current FROM crud_models WHERE model_name = 'users';
    IF v_current = 'ADMIN' THEN
        RAISE NOTICE 'users.allowed_roles_select already ADMIN - skipping (idempotent no-op).';
    ELSIF v_current = 'ADMIN,EDITOR,CUSTOMER' THEN
        UPDATE crud_models SET allowed_roles_select = 'ADMIN' WHERE model_name = 'users';
        RAISE NOTICE 'users.allowed_roles_select: ADMIN,EDITOR,CUSTOMER -> ADMIN.';
    ELSE
        RAISE EXCEPTION 'ABORT: users.allowed_roles_select is "%" - neither the expected old value (ADMIN,EDITOR,CUSTOMER) nor the target (ADMIN). Review before applying.', v_current;
    END IF;
END $$;

-- users DELETE was a global soft-delete (F2). INSERT/UPDATE stay for the hotel dashboard and are
-- guarded in Build Query (no overwrite on insert; update only for exclusive members).
UPDATE crud_models SET allowed_ops = array_remove(allowed_ops, 'DELETE')
 WHERE model_name = 'users' AND 'DELETE' = ANY (allowed_ops);

-- Membership writes go only through sp_access_* (rules above); reads stay as they are.
UPDATE crud_models
   SET allowed_ops = ARRAY(SELECT op FROM unnest(allowed_ops) AS op WHERE op NOT IN ('INSERT', 'UPDATE', 'DELETE'))
 WHERE model_name = 'user_companies' AND allowed_ops && ARRAY['INSERT', 'UPDATE', 'DELETE'];

-- 8) Verification
SELECT b.model_name,
       b.allowed_ops AS ops_before, c.allowed_ops AS ops_after,
       b.allowed_roles_select AS select_before, c.allowed_roles_select AS select_after
  FROM crud_models_backup_20261012_073 b
  JOIN crud_models c ON c.model_name = b.model_name
 WHERE b.model_name IN ('users', 'user_companies')
 ORDER BY 1;
-- Expected: users select ADMIN, no DELETE; user_companies without INSERT/UPDATE/DELETE.

SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, sp_requires_tenant
  FROM crud_models
 WHERE model_name IN ('company_members', 'access_add_user', 'access_update_member', 'access_set_active')
 ORDER BY 1;

SELECT count(*) AS password_columns_in_view
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'vw_company_members' AND column_name = 'password';
-- Expected: 0

-- Cleanup candidates (read-only report, nothing is changed): malformed or non-normalized emails.
-- Known case: '12095038@gmail.com|' (company 6), already is_active = false; never delete.
SELECT uc.id_company, uc.email, uc.role, uc.is_active
  FROM user_companies uc
 WHERE NOT public.fn_is_valid_email(uc.email) OR uc.email <> public.fn_normalize_email(uc.email)
 ORDER BY 1, 2;

COMMIT;
