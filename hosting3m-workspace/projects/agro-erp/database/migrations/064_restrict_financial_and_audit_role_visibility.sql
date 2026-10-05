-- Migration 064: Restrict financial/audit visibility to ADMIN in crud_models.
--
-- Closes the server-side half of "non-ADMIN (EDITOR, ranch foreman) must not see or fetch
-- financial data": Cattle Event Log and cattle_expenses were both left at the raw column
-- default ('ADMIN,EDITOR,CUSTOMER'/'ADMIN,EDITOR') when their models were registered — never
-- hardened on purpose. Replaces the earlier draft (064_restrict_cattle_expenses_select_to_admin.sql,
-- never applied anywhere) with a single file covering both models.
--
-- SCOPE — four guarded changes, nothing else touched:
--   1) cattle_event_log.allowed_roles_select : 'ADMIN,EDITOR,CUSTOMER' -> 'ADMIN'
--      (table_name is the view vw_cattle_event_log; there is no separate model for it — this
--      row IS the only gate for that view's GETALL/GETONE.)
--   2) cattle_expenses.allowed_roles_select  : 'ADMIN,EDITOR,CUSTOMER' -> 'ADMIN'
--   3) cattle_expenses.allowed_roles_update  : 'ADMIN,EDITOR'          -> 'ADMIN'
--   4) cattle_expenses.allowed_roles_insert  : 'ADMIN,EDITOR'          -> 'ADMIN'  (RECOMMENDATION —
--      kept in its own DO block, trivially removable by deleting that block alone, see below.)
--
-- Change #4 rationale, CONFIRMED against the LIVE n8n workflow (not the repo export) on
-- 2026-10-05: the AI Agent's `register_ranch_expense` tool (`v6/MCP Server Cattle`, node
-- `register_ranch_expense`, type `postgresTool`) runs its own hardcoded
-- `INSERT INTO cattle_expenses (...) SELECT ... WHERE EXISTS (SELECT 1 FROM user_companies uc
-- JOIN users u ON u.email = uc.email WHERE u.email = $5 AND uc.id_company = $1 AND
-- uc.is_active = true) RETURNING id, amount;` directly against Postgres. It never calls the
-- `v6/CRUD` webhook and therefore never passes through `Security Validation` or reads
-- `crud_models.allowed_roles_insert` at all — tightening this column to ADMIN-only has ZERO
-- effect on the AI Agent's ability to register an expense for EDITOR. It only removes EDITOR's
-- ability to INSERT an expense through the generic Meta-CRUD gateway directly (e.g. a manual
-- "Registrar Gasto" web-panel submission bypassing the now-hidden button) — which nothing in the
-- current frontend does once the "Registrar Gasto" button is hidden for non-ADMIN (see companion
-- frontend diff). Still shipped as a separate, independently-droppable block in case the project
-- owner wants EDITOR to keep INSERT via the gateway for some other reason.
--
-- NOT touched, and why: `cattle_livestock`/`vw_cattle_kpi` SELECT (EDITOR needs it for weighing,
-- health-event target lookup and inventory — not in scope); `cattle_expenses.allowed_roles_delete`
-- (already 'ADMIN' only, nothing to change); `cattle_weight_logs`/`cattle_health_logs` INSERT
-- (EDITOR must keep write access — explicit ask of this same follow-up, see verification query).
--
-- GUARD / IDEMPOTENCY: each change is wrapped in a DO block that reads the column's CURRENT
-- value first:
--   * already at the TARGET value  -> RAISE NOTICE, no-op (safe to re-run after a successful
--     apply, e.g. LOCAL already has cattle_event_log at 'ADMIN' from the earlier fix — this
--     migration detects that and skips it without erroring).
--   * at the EXPECTED OLD value (confirmed against both LOCAL and the values the project owner
--     read directly from PRODUCTION on 2026-10-05) -> applies the UPDATE.
--   * any OTHER value -> RAISE EXCEPTION and ABORT THE WHOLE TRANSACTION (ROLLBACK), so an
--     environment that has drifted from the assumed baseline is never silently overwritten.
--
-- Backup: full pre-migration snapshot of both crud_models rows, taken before any UPDATE, kept
-- in a dated table. Verification SELECT prints before/after for every touched column. Rollback
-- script at the bottom (commented out — run manually, not part of the forward migration).
--
-- Protocol: apply and test on LOCAL only in this change. Production is applied by the project
-- owner, same Rule-7 protocol as every prior migration in this file.

BEGIN;

-- 0) Pre-change backup — one row per model, whatever its current state actually is right now.
CREATE TABLE IF NOT EXISTS crud_models_backup_20261005 AS
SELECT * FROM crud_models WHERE model_name IN ('cattle_event_log', 'cattle_expenses');

-- 1) cattle_event_log.allowed_roles_select -> 'ADMIN'
DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_select INTO v_current FROM crud_models WHERE model_name = 'cattle_event_log';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'cattle_event_log.allowed_roles_select already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR,CUSTOMER' THEN
    UPDATE crud_models SET allowed_roles_select = 'ADMIN' WHERE model_name = 'cattle_event_log';
    RAISE NOTICE 'cattle_event_log.allowed_roles_select: ADMIN,EDITOR,CUSTOMER -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: cattle_event_log.allowed_roles_select is "%" — neither the expected old value (ADMIN,EDITOR,CUSTOMER) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

-- 2) cattle_expenses.allowed_roles_select -> 'ADMIN'
DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_select INTO v_current FROM crud_models WHERE model_name = 'cattle_expenses';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'cattle_expenses.allowed_roles_select already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR,CUSTOMER' THEN
    UPDATE crud_models SET allowed_roles_select = 'ADMIN' WHERE model_name = 'cattle_expenses';
    RAISE NOTICE 'cattle_expenses.allowed_roles_select: ADMIN,EDITOR,CUSTOMER -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: cattle_expenses.allowed_roles_select is "%" — neither the expected old value (ADMIN,EDITOR,CUSTOMER) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

-- 3) cattle_expenses.allowed_roles_update -> 'ADMIN'
DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_update INTO v_current FROM crud_models WHERE model_name = 'cattle_expenses';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'cattle_expenses.allowed_roles_update already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_update = 'ADMIN' WHERE model_name = 'cattle_expenses';
    RAISE NOTICE 'cattle_expenses.allowed_roles_update: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: cattle_expenses.allowed_roles_update is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

-- 4) cattle_expenses.allowed_roles_insert -> 'ADMIN'  [RECOMMENDATION — delete this whole DO
--    block (and nothing else) to keep EDITOR's gateway INSERT access if the project owner
--    decides against it; it does not affect register_ranch_expense either way, see header].
DO $$
DECLARE
  v_current text;
BEGIN
  SELECT allowed_roles_insert INTO v_current FROM crud_models WHERE model_name = 'cattle_expenses';
  IF v_current = 'ADMIN' THEN
    RAISE NOTICE 'cattle_expenses.allowed_roles_insert already ADMIN — skipping (idempotent no-op).';
  ELSIF v_current = 'ADMIN,EDITOR' THEN
    UPDATE crud_models SET allowed_roles_insert = 'ADMIN' WHERE model_name = 'cattle_expenses';
    RAISE NOTICE 'cattle_expenses.allowed_roles_insert: ADMIN,EDITOR -> ADMIN.';
  ELSE
    RAISE EXCEPTION 'ABORT: cattle_expenses.allowed_roles_insert is "%" — neither the expected old value (ADMIN,EDITOR) nor the target (ADMIN). Review before applying.', v_current;
  END IF;
END $$;

-- 5) Verification: before (from the backup snapshot) vs. after (live table), every touched column.
SELECT
  b.model_name,
  b.allowed_roles_select AS select_before, c.allowed_roles_select AS select_after,
  b.allowed_roles_insert AS insert_before, c.allowed_roles_insert AS insert_after,
  b.allowed_roles_update AS update_before, c.allowed_roles_update AS update_after,
  b.allowed_roles_delete AS delete_before, c.allowed_roles_delete AS delete_after
FROM crud_models_backup_20261005 b
JOIN crud_models c ON c.model_name = b.model_name
ORDER BY b.model_name;
-- Expected final state:
--   cattle_event_log | select ADMIN | insert NONE  | update NONE  | delete NONE  (insert/update/delete untouched, already NONE)
--   cattle_expenses  | select ADMIN | insert ADMIN | update ADMIN | delete ADMIN (delete untouched, already ADMIN)

COMMIT;

-- ---------------------------------------------------------------------------------------------
-- Rollback (manual — NOT part of the forward migration, run only if needed):
--
-- BEGIN;
-- UPDATE crud_models c
--    SET allowed_roles_select = b.allowed_roles_select,
--        allowed_roles_insert = b.allowed_roles_insert,
--        allowed_roles_update = b.allowed_roles_update,
--        allowed_roles_delete = b.allowed_roles_delete
--   FROM crud_models_backup_20261005 b
--  WHERE c.model_name = b.model_name
--    AND c.model_name IN ('cattle_event_log', 'cattle_expenses');
-- SELECT model_name, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
--   FROM crud_models WHERE model_name IN ('cattle_event_log', 'cattle_expenses');
-- COMMIT;
