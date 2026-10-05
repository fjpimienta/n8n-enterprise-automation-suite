-- Migration 065 (DRAFT — tested on LOCAL only, not yet reviewed/applied to PRODUCTION):
-- Restrict INSERT/UPDATE on companys and user_companies to ADMIN only.
--
-- Prompted by a read-only audit of users / employee_credentials / user_companies / companys /
-- vw_cattle_kpi, requested separately from this migration. Full audit findings below; this
-- migration only acts on the two rows that audit flagged as writable by EDITOR with no
-- confirmed legitimate EDITOR-reachable flow.
--
-- AUDIT FINDINGS (all read from LOCAL — n8n-enterprise-db — not production; verify there
-- before trusting these values as current prod state, per Rule 7):
--
-- 1) allowed_ops / allowed_fields (crud_models, LOCAL):
--      companys              SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL
--      employee_credentials  SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL  (table_name: view_employee_credentials)
--      user_companies        SELECT,INSERT,UPDATE,DELETE,GETALL,GETONE
--      users                 SELECT,INSERT,UPDATE,DELETE,GETALL,GETONE
--      vw_cattle_kpi         SELECT,GETALL
--
-- 2) 🔴 users.allowed_fields INCLUDES "password". allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER'.
--    Confirmed against the live v6/CRUD Build Query code (both the 'getall' and 'getone' cases):
--    buildSelectFields() always returns `${table}.*` — `allowed_fields` is a whitelist for what
--    can be WRITTEN/FILTERED on (SET/WHERE), it does NOT restrict which columns a SELECT/GETALL/
--    GETONE returns. This means EVERY column of `users`, including the password hash, is
--    returned to ANY role in allowed_roles_select today — EDITOR and CUSTOMER included.
--    THIS IS NOT FIXED BY THIS MIGRATION. It requires either a column-projection change in
--    Build Query (SELECT explicit columns, not `table.*`, for at least the `users` model) or a
--    tenant-scoped view that excludes `password`, registered as the model instead of the raw
--    table. Flagged here as the single highest-severity finding of this audit — out of scope
--    for a crud_models-only migration, needs a gateway code change. Not touched by this file.
--    employee_credentials' table_name is already a VIEW (`view_employee_credentials`) and its
--    allowed_fields list (id, id_company, nombre, curp, nss, email, active, last_emission,
--    success, process, created_at, is_ready) does NOT include a password/hash column — no
--    equivalent exposure there, though `curp`/`nss` are PII and worth a separate look someday
--    (out of scope here).
--
-- 3) 🔴 vw_cattle_kpi DOES expose financial data to EDITOR — not through a dedicated column
--    (current_weight_kg is not financial by itself; capitalización is a hardcoded frontend
--    constant, confirmed in an earlier session), but through `metadata` (jsonb, in
--    allowed_fields, returned via `vw_cattle_kpi.*` same as any other SELECT). Sampled actual
--    key names present in cattle_livestock.metadata on LOCAL: purchase_price, seller_name,
--    purchase_date, nota_venta — written by the register_livestock_purchase MCP tool. EDITOR
--    (allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER' on vw_cattle_kpi) can already see this
--    today via the unguarded "Ver detalle" / metadata modal in both main-dashboard's Inventario
--    tab and cattle-list.component — neither gates `openMetadata()`/the info-circle button
--    behind isAdminForActiveTenant(). THIS IS NOT FIXED BY THIS MIGRATION — it's a frontend gap
--    in an already-committed component, parallel to but distinct from the cattle_expenses fix
--    in migration 064. Flagged for a separate follow-up.
--
-- 4) Grep across agro-erp, dashboard, hotel-website and pista-hielo frontends: no flow in any
--    of the four apps performs an INSERT/UPDATE against user_companies or companys while
--    authenticated as EDITOR.
--      - agro-erp is the ONLY app with write flows to either model (admin.service.ts, called
--        from tenant-list.component.ts for companys and user-list.component.ts for
--        user_companies via saveUserCompany). Both routes ('/admin/tenants', '/admin/personal')
--        carry `canActivate: [roleGuard(['ADMIN'])]` in admin.routes.ts.
--      - dashboard and pista-hielo each call POST .../companys, but only with
--        `operation: 'getall'` (a read, for a login-time company picker) — no write call site
--        found in either app. Neither app writes to user_companies at all.
--      - hotel-website has no hits for either model (expected — public marketing SPA).
--    Caveat inherited from the earlier JWT-role-staleness finding (agro-erp/CLAUDE.md): if a
--    user is ADMIN at login in one company and switches to a company where they're actually
--    EDITOR, `roleGuard` still passes them through on the frozen JWT role — not a gap specific
--    to this migration, the same pre-existing architectural issue as everywhere else in the app.
--    No account with mixed roles across companies exists today, so this isn't a live exploit,
--    only a standing design gap.
--    Net: no legitimate EDITOR-authenticated flow exercises either write today. The only thing
--    stopping a deliberately-crafted direct API call (bypassing the Angular route guard
--    entirely) from writing to companys/user_companies as EDITOR is the fact that nobody has
--    tried it — the gateway itself would accept it. That's the justification for this migration.
--
-- 5) No MCP tool returns gastos or valuación to a non-ADMIN conversational user. Read the actual
--    SQL of every postgresTool node in the live v6/MCP Server Cattle workflow (25 tools):
--    `get_livestock_info` and `find_livestock_by_criteria` (the two "look up an animal" tools)
--    both use explicit column lists, neither selects `metadata` or touches cattle_expenses.
--    `register_ranch_expense`/`register_livestock_purchase` are INSERT-only — the only
--    "financial" data a user sees via the AI Agent is the natural echo of a purchase/expense
--    they themselves just reported, not a leak of other data. (Aside, not in scope:
--    `get_table_metadata` SELECTs crud_models.schema_json/joins/allowed_ops for any table name
--    the LLM passes it — an internal-architecture disclosure surface, unrelated to money, not
--    acted on here.)
--
-- SCOPE OF THIS MIGRATION — two guarded changes:
--   1) companys.allowed_roles_insert        : 'ADMIN,EDITOR' -> 'ADMIN'
--   2) companys.allowed_roles_update        : 'ADMIN,EDITOR' -> 'ADMIN'
--   3) user_companies.allowed_roles_insert  : 'ADMIN,EDITOR' -> 'ADMIN'
--   4) user_companies.allowed_roles_update  : 'ADMIN,EDITOR' -> 'ADMIN'
--
-- NOT touched, and why: allowed_roles_select on both (EDITOR/CUSTOMER read access to companys/
-- user_companies is a separate question, not asked here, and tightening SELECT on
-- `user_companies` specifically could break the Context Switcher's own company list if any
-- client-side code reads it directly rather than via the JWT/login response — not audited in
-- this pass, deliberately left alone); `users`/`employee_credentials`/`vw_cattle_kpi` (both
-- real findings above need a gateway code change or a frontend fix, not a crud_models role
-- edit — a role-only migration can't close either).
--
-- Same guard/idempotency/backup/rollback pattern as migration 064 — see that file for the full
-- rationale of the pattern itself.

BEGIN;

CREATE TABLE IF NOT EXISTS crud_models_backup_20261005_065 AS
SELECT * FROM crud_models WHERE model_name IN ('companys', 'user_companies');

DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_insert INTO v_current FROM crud_models WHERE model_name = 'companys';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'companys.allowed_roles_insert already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_insert = 'ADMIN' WHERE model_name = 'companys';
    RAISE NOTICE 'companys.allowed_roles_insert: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: companys.allowed_roles_insert is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_update INTO v_current FROM crud_models WHERE model_name = 'companys';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'companys.allowed_roles_update already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_update = 'ADMIN' WHERE model_name = 'companys';
    RAISE NOTICE 'companys.allowed_roles_update: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: companys.allowed_roles_update is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_insert INTO v_current FROM crud_models WHERE model_name = 'user_companies';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'user_companies.allowed_roles_insert already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_insert = 'ADMIN' WHERE model_name = 'user_companies';
    RAISE NOTICE 'user_companies.allowed_roles_insert: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: user_companies.allowed_roles_insert is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_update INTO v_current FROM crud_models WHERE model_name = 'user_companies';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'user_companies.allowed_roles_update already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_update = 'ADMIN' WHERE model_name = 'user_companies';
    RAISE NOTICE 'user_companies.allowed_roles_update: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: user_companies.allowed_roles_update is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

SELECT
  b.model_name,
  b.allowed_roles_insert AS insert_before, c.allowed_roles_insert AS insert_after,
  b.allowed_roles_update AS update_before, c.allowed_roles_update AS update_after,
  b.allowed_roles_select AS select_unchanged_before, c.allowed_roles_select AS select_unchanged_after
FROM crud_models_backup_20261005_065 b
JOIN crud_models c ON c.model_name = b.model_name
ORDER BY b.model_name;
-- Expected final state: both rows insert=ADMIN, update=ADMIN, select unchanged (ADMIN,EDITOR,CUSTOMER).

COMMIT;

-- ---------------------------------------------------------------------------------------------
-- Rollback (manual — NOT part of the forward migration, run only if needed):
--
-- BEGIN;
-- UPDATE crud_models c
--    SET allowed_roles_insert = b.allowed_roles_insert,
--        allowed_roles_update = b.allowed_roles_update
--   FROM crud_models_backup_20261005_065 b
--  WHERE c.model_name = b.model_name
--    AND c.model_name IN ('companys', 'user_companies');
-- SELECT model_name, allowed_roles_insert, allowed_roles_update FROM crud_models WHERE model_name IN ('companys', 'user_companies');
-- COMMIT;
