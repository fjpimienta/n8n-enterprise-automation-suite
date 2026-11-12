> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only (PostgreSQL 15.4). NOT applied to production.** Database only: no workflow, gateway code or
> frontend change (Part 2, n8n, does not apply). No visible behavior change is expected for the hotel; the runtime check below confirms it.

# Runbook 106 — align `allowed_fields` with the tenant column for two hotel models

## Scope

`crud_models` rows `hotel_rooms` and `hotel_maintenance_tickets`: `"id_company"` is added to `allowed_fields` (both tables have an `id_company` column; tenant-scoped models list it).
Nothing else in the two rows changes (operations, roles, primary key, default filter, joins, hooks and every other allowed field stay byte-identical). No other `crud_models` row, table, view,
procedure or workflow is touched. The change is idempotent and the rollback restores `allowed_fields` from a backup of exactly those two rows.

| File | Purpose |
|---|---|
| `106_align_hotel_models_tenant_field.sql` | the change (dry run by default; backup `crud_models_backup_20261112_106`; preconditions; post-check) |
| `106_rollback.sql` | restores `allowed_fields` of the two rows from the backup; no DROP, DELETE or TRUNCATE |
| `106_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints |
| `106_tests.sql` | one rolled-back transaction (throwaway database only) |
| `106_static_check.sh` | no line starting with DROP, TRUNCATE or DELETE in the migration, the rollback and the state check |
| `workflows/06-dynamic-crud-engine/v5/tests/test_hotel_models_fields.mjs` | permanent offline test (in the *v5 CRUD tests* CI job): the SQL built by the v5 workflow for the two models, for every operation, is identical with and without `id_company` in `allowed_fields` |

## Part 1 — Database (owner only)

Conventions
```bash
P='docker exec -w /root/repro/vps106 -i n8n-enterprise-db psql -X -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Apply and roll back **without** `--single-transaction`. Without `-v apply=true` every file is a dry run (it ends in `ROLLBACK`).

0. **Files.** Copy the `106_*` files to the host and compare `md5sum` with the repo. `bash 106_static_check.sh` must print three `OK` lines.
1. **Backup and size check.** `docker exec n8n-enterprise-db pg_dump -U n8n_user -d hosting3m_db -Fc > backup_pre106_$(date +%Y%m%d_%H%M%S).dump`; confirm the file is larger than 100 KB.
2. **Read-only pre-check.** Expect **exactly the two rows, neither listing `id_company`**:
   `SELECT model_name, table_name, allowed_fields ? 'id_company' AS lists_id_company FROM crud_models WHERE model_name IN ('hotel_rooms','hotel_maintenance_tickets') ORDER BY 1;`
   Also take the reference numbers for the runtime check (step 8): `SELECT (SELECT count(*) FROM hotel_rooms WHERE id_company = 1) AS rooms, (SELECT count(*) FROM hotel_maintenance_tickets WHERE id_company = 1 AND status <> 'DELETED') AS tickets;`
   Tenant column listing for all models (names only; expected before 106: exactly these two):
   `SELECT DISTINCT m.model_name FROM crud_models m JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name=m.table_name AND c.column_name IN ('id_company','tenant_id') WHERE NOT (m.allowed_fields ? c.column_name) ORDER BY 1;`
3. **State before.** `$P -v expect=before -f 106_state_check.sql` must print `STATE OK: before`. Save the FINGERPRINT block.
4. **Dry run.** `$P -f 106_align_hotel_models_tenant_field.sql` must end with `106: OK` and `DRY RUN: 106 rolled back`.
5. **Apply — only with the owner's explicit go-ahead.** `$P -v apply=true -f 106_align_hotel_models_tenant_field.sql` → `106 COMMITTED`.
6. **State after.** `$P -v expect=applied -f 106_state_check.sql` → `STATE OK: applied`. The FINGERPRINT block must be **identical** to step 3 (every other row, and every column of the two rows other than `allowed_fields`).
7. **Verification queries (read-only).**
   * `SELECT model_name, allowed_fields ? 'id_company' FROM crud_models WHERE model_name IN ('hotel_rooms','hotel_maintenance_tickets') ORDER BY 1;` → both `true`.
   * The tenant column listing query of step 2 → **no rows**.
   * `SELECT model_name, md5(allowed_fields::text) FROM crud_models_backup_20261112_106 ORDER BY 1;` → two rows (the original lists).
8. **Runtime check on the hotel dashboard (hotel ADMIN account).** The rooms page and the maintenance page load without errors and list the same rooms and tickets as before the change (compare the counts of step 2);
   open a room and a ticket; a room status change and a ticket update still work (revert any test change). Check that n8n *Executions* of the v5 workflow show no new errors for the two models.

## Part 2 — n8n

Not part of this pull request (no workflow or gateway change).

## Part 3 — Frontend

Not part of this pull request.

## Rollback (deletes nothing)

`$P -v apply=true -f 106_rollback.sql`, then `$P -v expect=rolled_back -f 106_state_check.sql` → `STATE OK: rolled_back` with the same fingerprints. `allowed_fields` of the two rows is restored from
`crud_models_backup_20261112_106`; the backup table stays, so a later re-apply keeps the original copy.

## Results of the local run (throwaway database, PostgreSQL 15.4, schema + the model definitions copied from a local clone, synthetic fixtures)

* Cycle: `state before` → dry run (nothing written, no backup table) → apply → `state applied` → `106_tests.sql` → rollback (dry run, apply) → `state rolled_back` → re-apply → `state applied` → second apply (no change) → `106_tests.sql`.
  The FINGERPRINT block was identical in every state.
* `106_tests.sql`: `ALL 106 TESTS OK`: both rows list `id_company`; operations, roles, joins, hooks, primary key and the other allowed fields unchanged; no other row changed (probe row included); the backup holds the two original
  rows; a second run changes nothing; the rollback restores the exact previous rows; every model over a table with `id_company` or `tenant_id` lists that column (the assertion fails and prints the names otherwise).
* `test_hotel_models_fields.mjs`: 81 checks, identical SQL and values with and without the field for both models, every operation, two token companies; it fails if the output starts to depend on the field.
* Mutations, each making a check fail: the migration changes another field; touches a third row; updates only one row; is a no-op; renames an allowed field; the rollback leaves the field; the rollback deletes a row;
  a missing row (state check fails in all three states); a migration applied to one row only (state check fails); a v5 build whose output depends on the field (the new test fails).
* `bash 106_static_check.sh`: three `OK` lines.
