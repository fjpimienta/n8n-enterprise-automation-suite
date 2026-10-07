-- Migration 064: Restrict financial/audit READ visibility to ADMIN in crud_models.
--
-- Closes the server-side half of "non-ADMIN (EDITOR, ranch foreman) must not see or fetch
-- financial data": Cattle Event Log and cattle_expenses were both left at the raw column
-- default ('ADMIN,EDITOR,CUSTOMER') when their models were registered — never hardened on
-- purpose. Replaces the earlier draft (064_restrict_cattle_expenses_select_to_admin.sql,
-- never applied anywhere) with a single file covering both models.
--
-- SCOPE — two guarded changes, nothing else touched:
--   1) cattle_event_log.allowed_roles_select : 'ADMIN,EDITOR,CUSTOMER' -> 'ADMIN'
--      (table_name is the view vw_cattle_event_log; there is no separate model for it — this
--      row IS the only gate for that view's GETALL/GETONE.)
--   2) cattle_expenses.allowed_roles_select  : 'ADMIN,EDITOR,CUSTOMER' -> 'ADMIN'
--
-- BUSINESS RULE (project owner, 2026-10-06): the foreman (EDITOR) may perform every cattle
-- event (birth, weaning, purchase intake, weight assignment, vaccines, supplements, palpation,
-- insemination, embryo transfer). Only "baja por muerte" and "baja por venta" require ADMIN
-- authorization. This migration therefore restricts READ access to financial data only. It
-- deliberately does NOT touch cattle_expenses.allowed_roles_insert / allowed_roles_update, which
-- stay 'ADMIN,EDITOR'.
--
-- NOT touched, and why: `cattle_livestock`/`vw_cattle_kpi` SELECT (EDITOR needs it for weighing,
-- health-event target lookup and inventory — not in scope); `cattle_expenses` INSERT/UPDATE
-- (business rule above) and DELETE (already 'ADMIN' only); `cattle_weight_logs`/
-- `cattle_health_logs` INSERT (EDITOR must keep write access).
--
-- GUARD / IDEMPOTENCY: each change is wrapped in a DO block that reads the column's CURRENT
-- value first:
--   * already at the TARGET value  -> RAISE NOTICE, no-op (safe to re-run after a successful
--     apply, e.g. LOCAL already has cattle_event_log at 'ADMIN' from the earlier fix — this
--     migration detects that and skips it without erroring).
--   * at the EXPECTED OLD value (confirmed against both LOCAL and the values the project owner
--     read directly from PRODUCTION on 2026-10-05 and 2026-10-06) -> applies the UPDATE.
--   * any OTHER value -> RAISE EXCEPTION and ABORT THE WHOLE TRANSACTION (ROLLBACK), so an
--     environment that has drifted from the assumed baseline is never silently overwritten.
--
-- Backup: full pre-migration snapshot of both crud_models rows, taken before any UPDATE, kept
-- in a dated table. Verification SELECT prints before/after for every role column. Rollback
-- script at the bottom (commented out — run manually, not part of the forward migration).
--
-- LOCAL NOTE: a LOCAL database that already ran the EARLIER version of this migration (which
-- also set cattle_expenses insert/update to 'ADMIN') must be realigned once, by hand:
--   UPDATE crud_models
--      SET allowed_roles_insert = 'ADMIN,EDITOR', allowed_roles_update = 'ADMIN,EDITOR'
--    WHERE model_name = 'cattle_expenses';
--
-- Protocol: apply and test on LOCAL first. Production is applied by the project owner, same
-- Rule-7 protocol as every prior migration in this file.

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

-- 3) Verification: before (from the backup snapshot) vs. after (live table), every role column.
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
--   cattle_event_log | select ADMIN | insert NONE         | update NONE         | delete NONE  (all but select untouched)
--   cattle_expenses  | select ADMIN | insert ADMIN,EDITOR | update ADMIN,EDITOR | delete ADMIN (all but select untouched)

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
