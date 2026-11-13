# Runbook 094 / 095 — company scoping for the hotel CRUD workflow (v5)

## 1. Purpose and scope

Environment: **production VPS** (`root@hosting3m`), database `hosting3m_db` in the container `n8n-enterprise-db`. The local tests (section 3) run on a developer machine.

- **094:** adds `hotel_maintenance_tickets.id_company integer NOT NULL DEFAULT 1` + FK to `companys` + index. No data is rewritten; the previous workflow keeps working. Company 1 owns all existing hotel data (assumption stated in the SQL header; see section 9).
- **v5/CRUD (nodes `Extract Auth Context`, `Build Query`):** the company comes only from the verified token (missing/invalid -> 403 `NO_TENANT`); it is enforced on getall/getone/insert/update/delete; any client-supplied tenant value is ignored; tables without a mapped tenant column are denied unless listed explicitly.
- **095:** removes the default so a ticket can never be created without an explicit company. Run it only after the new workflow has been stable for a day.

Status: 094 and 095 applied on 2026-11-01.

## 2. Prerequisites

- Shell on the VPS. `run_m094.sh` refuses to run if the hostname does not start with `hosting3m`.
- Run it from the folder that holds the 094/095 `.sql` files.
- Docker access to the container `n8n-enterprise-db`. The wrapper reads `POSTGRES_USER` from inside the container; the backup command below uses `-U n8n_user`.
- Access to the n8n editor (workflow changes are made there, never with `n8n import:workflow`).
- For the local tests: Node and npm.

## 3. Pre-checks

1. Container is up: `docker ps --filter name=n8n-enterprise-db`.
2. Disk space for the backup: `df -h /root/backups`.
3. Current state, read-only: `./run_m094.sh check before`. It must print `STATE OK: before`. **Write down the three fingerprint values** (`tickets_rows`, `tickets_data_md5`, `crud_models_md5`); they must not change across the steps.
4. Local tests of the workflow code: `cd workflows/06-dynamic-crud-engine/v5/tests && npm install && npm test` (PostgreSQL in WASM; reads the node code from `v5-crud.json`). TODO(verify): base directory of that `cd` (repository root?).

## 4. Backup (mandatory)

1. Database backup, following the convention of runbooks 081-090 (creates a file; does not change the database):
   `docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > /root/backups/hosting3m_db_pre094_$(date +%F_%H%M).dump`
2. Verify it: `ls -lh /root/backups/hosting3m_db_pre094_*.dump`. The size must be reasonable (runbook 091-093 uses "> 100 KB" as the minimum); 0 bytes means the backup failed.
3. Download the current `v5/CRUD` workflow JSON from the n8n editor and keep it. It is the workflow rollback.

## 5. Dry run

`./run_m094.sh dry 094` executes the statements inside a transaction and rolls them back. It briefly takes the same table lock as the real run (see the lock note in section 9).

Read the last line before continuing: it must say `094 DRY RUN: rolled back, nothing changed.` Any line starting with `ABORT:` means a guard failed; stop and investigate (wrong database, company 1 missing, or 094 already applied).

## 6. Procedure

1. **MUTATES (database).** `./run_m094.sh apply 094`. The last line must say `094 APPLIED (committed)`.
2. `./run_m094.sh check applied_094`. It must print `STATE OK: applied_094`, and the three fingerprints must equal the ones from step 3 of section 3.
3. **MUTATES (n8n, production workflow).** In the n8n editor, replace the code of the node `Extract Auth Context` in `v5/CRUD`.
4. **MUTATES (n8n, production workflow).** Replace the code of the node `Build Query`.
5. **MUTATES (n8n, production workflow).** Save the workflow.
6. Verify the hotel dashboard (section 7, "After the workflow").
7. Wait a stable day. Do not apply 095 before that.
8. `./run_m094.sh dry 095`. The last line must say `095 DRY RUN: nothing changed.`
9. **MUTATES (database).** `./run_m094.sh apply 095`. The last line must say `095 APPLIED (default removed)`.
10. `./run_m094.sh check applied_095`.

## 7. Verification

- **After 094:** `check applied_094` prints `STATE OK: applied_094` and the fingerprints are unchanged.
- **After the workflow:** the hotel dashboard lists and writes on bookings, guests, inventory, expenses and maintenance. In n8n Executions there must be no `NO_TENANT` and no "Tabla sin aislamiento" errors.
- **After 095:** `check applied_095` prints `STATE OK: applied_095` (`id_company` is `NOT NULL` without a default) and the fingerprints are unchanged. Repeat the maintenance write from the hotel dashboard.

## 8. Rollback

There is **no script that undoes 094**. The file `094_rollback.sql` undoes **095**: it restores `DEFAULT 1` and leaves the table in the 094 state.

- **Undo 095** (for example, the old v5 workflow has to come back): run `./run_m094.sh rollback-dry`, then **MUTATES (database):** `./run_m094.sh rollback-apply`, then `./run_m094.sh check applied_094`. Do this **before** restoring the old workflow, because after 095 the old workflow's inserts (which send no company) fail.
- **Undo the workflow change:** restore the previous node code, or import the JSON saved in section 4, step 3, from the n8n editor.
- **Undo 094:** not scripted. The column, FK and index stay; they are inert for the old workflow once `DEFAULT 1` is back. Physically removing the column is a separate decision that needs explicit owner approval and a verified backup; it is not described here.
- A restore of the full backup is the owner's decision and is not described here.

## 9. Known risks

- **Wrapper argument handling.** In `dry` and `apply`, any second argument that is not exactly `094` selects the 095 script. A typo such as `apply 94` applies **095**. Type the number exactly and read the last line of the dry run before the real run. (The `check` and `rollback-*` commands are not affected.)
- **Tenant isolation.** The 094 script assigns `id_company = 1` to every existing ticket and checks only that company 1 exists. It cannot check that all those tickets really belong to company 1; that premise comes from the SQL header and must be confirmed by the owner. After this change, hotel screens show data for company 1 only, and users who belong to several companies get the company they select at login.
- **095 and the old workflow.** After 095, any insert into `hotel_maintenance_tickets` without `id_company` fails (`NOT NULL`, no default).
- **Lock timeout.** All three scripts use `lock_timeout = 5s`: if the table is busy they abort instead of waiting. Re-run later; nothing is left half-done because each script is one transaction.
- **Destructive statements.** No script uses DROP COLUMN, DELETE or TRUNCATE. Every script defaults to a dry run and needs `-v apply=true` (done by the wrapper's `apply`) to commit.
