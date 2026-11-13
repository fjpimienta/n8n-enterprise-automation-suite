> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database (PostgreSQL 15.4) and with an offline gateway test. NOT applied to production, NOT imported into n8n.**
> Parts 1 and 2 are required. Part 3 (frontend) is **not** part of this pull request (the "Ventas" screen is a later one): until it exists nothing in the application calls the new models.

# Runbook 107 — void and balance of the palm sales through the gateway (ADMIN only)

## Scope

| Object | Kind | Notes |
|---|---|---|
| `agri_sale_void` | `crud_models` row (new) | procedure `sp_agri_void_sale`; operations `{INSERT}` (the gateway validates `call_sp` as an insert); write role `ADMIN`; select / update / delete `NONE`; `sp_requires_tenant = true` |
| `agri_sale_balance` | `crud_models` row (new) | procedure `sp_agri_sales_balance`; same operations and roles |
| `Build Query` node of `v6/CRUD` | workflow node (changed) | two new `spConfigByModel` entries; no other node and no connection changes |

Every column of the two rows is copied from the existing rows `agri_void_expense` and `agri_expense_balance` (migration 081, checked against the local clone), except the names, the primary key, `allowed_fields` and the write role (`ADMIN` only).
The company is always the verified `x-tenant-id` header (after the membership check) and the actor e-mail is always the one of the verified token; the procedures check the `ADMIN` role again. Nothing else is touched: no table, view,
function, trigger or data, and no other `crud_models` row.

| File | Purpose |
|---|---|
| `107_agri_sale_gateway_sp.sql` | the change (dry run by default; backup `crud_models_backup_20261112_107`; preconditions on `pg_proc`; post-check) |
| `107_rollback.sql` | disables the two rows (no operation, no role); deletes nothing |
| `107_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints |
| `107_tests.sql` | one rolled-back transaction (throwaway database only) |
| `107_static_check.sh` | no line starting with DROP, TRUNCATE or DELETE in the migration, the rollback and the state check |
| `workflows/06-dynamic-crud-engine/v6/tests/test_agri_sale_sp.mjs` | offline test of the real `Build Query` code (runs in the *Agent workflow consistency* CI job) |

## Gateway change (Part 2) — expected fingerprints

`python3 -I node_fingerprints.py workflows/06-dynamic-crud-engine/v6/v6-crud.json` (workflow `ZhHDs5XoopmqgZvF`, `v6/CRUD`):

| Node | Before (`main`) | After (this branch) |
|---|---|---|
| `Build Query` | `12326918f2ff2e2639a802785e02e591` | `e270195a5f8f2643e1f050d3c8055c78` |
| `Execute a SQL query` | `3769295a…` | unchanged |
| `Get Model Config` | `fd354ca7…` | unchanged |
| `Get Model Name` | `084730d6…` | unchanged |
| `Normalize Data` | `b7741e5e…` | unchanged |

What changes in `Build Query`: inside `spConfigByModel`, two entries are added right before the entry `sp_register_livestock_panel`'s comment, in the same style as the neighbours:
`sp_agri_void_sale` (`paramOrder ['actor_email', 'sale_id', 'reason']`, `tenantPosition 0`, `actorEmailField 'actor_email'`) and
`sp_agri_sales_balance` (`paramOrder ['date_from', 'date_to', 'grain', 'plantation_id', 'lot_id', 'actor_email']`, `tenantPosition 0`, `actorEmailField 'actor_email'`).
The call order of each is `(tenant, then paramOrder)`, which is the signature of the procedure in migration 104. The export diff is one line of `v6-crud.json` (the node code is one JSON string).

## Part 1 — Database (owner only; safe to apply first: the gateway has no entry yet, so nothing can call the new models)

Conventions
```bash
P='docker exec -w /root/repro/vps107 -i n8n-enterprise-db psql -X -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Apply and roll back **without** `--single-transaction`. Without `-v apply=true` every file is a dry run (it ends in `ROLLBACK`).

0. **Files.** Copy the `107_*` files to the host and compare `md5sum` with the repo. `bash 107_static_check.sh` must print three `OK` lines.
1. **Backup and size check.** `docker exec n8n-enterprise-db pg_dump -U n8n_user -d hosting3m_db -Fc > backup_pre107_$(date +%Y%m%d_%H%M%S).dump`; confirm the file is larger than 100 KB.
2. **Read-only pre-check.** Migrations 104 and 105 must be applied, and nothing may already serve these objects:
   `SELECT model_name, table_name, allowed_ops FROM crud_models WHERE model_name IN ('agri_sale_void','agri_sale_balance') OR table_name IN ('sp_agri_void_sale','sp_agri_sales_balance');` → **0 rows**.
   `SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname IN ('sp_agri_void_sale','sp_agri_sales_balance') ORDER BY 1;` → exactly **two rows**, with the signatures of migration 104.
3. **State before.** `$P -v expect=before -f 107_state_check.sql` must print `STATE OK: before`. Save the FINGERPRINT block.
4. **Dry run.** `$P -f 107_agri_sale_gateway_sp.sql` must end with `107: OK` and `DRY RUN: 107 rolled back`.
5. **Apply — only with the owner's explicit go-ahead.** `$P -v apply=true -f 107_agri_sale_gateway_sp.sql` → `107 COMMITTED`.
6. **State after.** `$P -v expect=applied -f 107_state_check.sql` → `STATE OK: applied`. The FINGERPRINT block must be **identical** to step 3 (every other `crud_models` row, the migration 104 tables, functions, views and guard triggers,
   and the migration 105 view and model rows).
7. **Verification queries (read-only).** `SELECT model_name, table_name, primary_key, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, allowed_fields FROM crud_models WHERE model_name IN ('agri_sale_void','agri_sale_balance') ORDER BY 1;`
   → two rows, `{INSERT}`, insert role `ADMIN`, the others `NONE`.
   Tenant-column listing for all models (names only): `SELECT DISTINCT m.model_name FROM crud_models m JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name=m.table_name AND c.column_name IN ('id_company','tenant_id') WHERE NOT (m.allowed_fields ? c.column_name) ORDER BY 1;`
   → **no rows** (the two new models name a procedure, not a table, so the rule does not apply to them).

## Part 2 — n8n (owner only, by the editor UI; never `n8n import:workflow`)

Precondition: Part 1 is applied and verified, the pull request is merged to `develop` and CI is green. Nothing is published to `main` before this part is verified.

1. **Backup.** Open `v6/CRUD` in production, **⋯ → Download**, save the file outside the repo and run `chmod 600` on it (below: `prod_v6_crud.json`).
2. **Compare production with `main`.**
   `python3 -I workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py prod_v6_crud.json <main copy of workflows/06-dynamic-crud-engine/v6/v6-crud.json>`
   → must print `RESULT: IDENTICAL (nodes, connections, settings)` (an information line about node ids is fine). **If it prints anything else, STOP**: first incorporate the production differences into the repository (a separate pull request), then start again.
   Also `python3 -I node_fingerprints.py prod_v6_crud.json` → `Build Query` must be `12326918f2ff2e2639a802785e02e591`.
3. **Compare production with this branch.** The same command against the file of this branch must list **only** `Build Query` (`parameters: ['jsCode']`) under *NODES WITH DIFFERENT CONTENT* and no connection difference.
4. **Import.** In the n8n editor: **⋯ → Import from file…**, choose `workflows/06-dynamic-crud-engine/v6/v6-crud.json` of this branch, **Save**, then **Publish**. Confirm that the workflow name and its published state did not change.
5. **Export again and compare.** Download the workflow again and compare it with the file of this branch: `RESULT: IDENTICAL (nodes, connections, settings)`, and `Build Query` fingerprint `e270195a5f8f2643e1f050d3c8055c78`. Do not call it deployed until both match
   (the editor can leave a saved version unpublished).
6. **Regression (production, normal accounts).**
   * Livestock chat: one routine registration or query through the real channel, then check the latest execution of `v6/CRUD` ends in `Respond` without error.
   * Palm chat: one expense query through the real channel (palm test company).
   * Palm dashboard: expenses list and the expense balance load; no error.
   * Hotel dashboard: sign in and open reservations (the hotel uses `v5/CRUD`; this import must not change it).
   * An unauthenticated request to the gateway is denied with HTTP 403 and a clean JSON body.
7. **Verification on the palm TEST company (company 10), through the gateway** (use a synthetic sale of that company; if none exists, register one with a synthetic voucher in the test company first). Read the token without echo and never paste it or write it to a file:
   ```bash
   read -rs TOKEN        # paste the token of an ADMIN of the test company, press Enter; nothing is shown
   BASE='https://<n8n-host>/webhook/crud/v6'      # placeholder: use the real gateway base URL
   call() { curl -sS -X POST "$BASE/$1" -H "Authorization: Bearer $TOKEN" -H "x-tenant-id: 10" -H 'Content-Type: application/json' -d "$2"; echo; }
   ```
   | Call | Expected |
   |---|---|
   | `call agri_sale_void '{"operation":"call_sp","fields":{"sale_id":"<synthetic sale id>","reason":"Runbook 107 verification"}}'` | `data.status = "OK"` |
   | the same call again | `data.status = "ALREADY_VOID"` |
   | `call agri_sale_void '{"operation":"call_sp","fields":{"sale_id":"00000000-0000-4000-8000-000000000000","reason":"Runbook 107 verification"}}'` | `data.status = "NOT_FOUND"` |
   | a non-ADMIN token of the same company (EDITOR): `call agri_sale_void ...` | refused by the gateway role check (`error: true`); if it is ever reached, `data.status = "FORBIDDEN"` |
   | `call agri_sale_balance '{"operation":"call_sp","fields":{"date_from":null,"date_to":null,"grain":"MONTH","plantation_id":null,"lot_id":null}}'` | `data.success = true`; the voided sale is not counted |
   Then reload the sales list of the test company (read model `agri_sales` of migration 105) and confirm the sale shows `status = VOID` with its reason. `unset TOKEN` when done. In n8n *Executions*, open the last execution of each call and confirm the path
   (`Build Query` → `Execute a SQL query` → `Normalize Data`) and that the statement is `SELECT sp_agri_void_sale($1, $2, $3, $4)` / `SELECT sp_agri_sales_balance($1, $2, $3, $4, $5, $6, $7)`.

## Part 3 — Frontend

Not part of this pull request. The dashboard "Ventas" section and the void dialog come later; the response of the void is `{status, ...}` without a `success` key, so that screen needs its own reading of the answer
(`OK` and `ALREADY_VOID` are both final states) and must reload the list after the call.

## Rollback

1. n8n: re-import the backup saved in Part 2 step 1 (**⋯ → Import from file…**, **Save**, **Publish**) and compare it with the backup (`IDENTICAL`; `Build Query` back to `12326918f2ff2e2639a802785e02e591`).
2. Database: `$P -v apply=true -f 107_rollback.sql`, then `$P -v expect=rolled_back -f 107_state_check.sql` → `STATE OK: rolled_back` with the same fingerprints. The two rows are disabled (no operation, no role) and stay registered; nothing is deleted.
   The rollback contains no `DROP`, `DELETE` or `TRUNCATE` (`bash 107_static_check.sh` asserts it). A sale already voided stays voided (the void is an audited business event, not undone by a rollback).

## Results of the local run (throwaway database, PostgreSQL 15.4, schema + the gateway model definitions copied from a local clone, migrations 104, 105 and 106 applied, synthetic data)

* Cycle: `state before` → dry run (nothing written) → apply → `state applied` → `107_tests.sql` → rollback (dry run, apply) → `state rolled_back` → re-apply → `state applied` → `107_tests.sql`.
  The FINGERPRINT block (8 fingerprints: every other `crud_models` row and its count, the 104 columns, functions, views and guard triggers, the 105 view and its model rows) was identical in every state.
* `107_tests.sql` (one transaction, always `ROLLBACK`): `ALL 107 TESTS OK`. It checks: both rows with their exact values, every other column equal to the 081 expense models; the role matrix ADMIN / OWNER / EDITOR / CUSTOMER / GUEST against
  every operation with the same operation / role rule as the gateway (only `ADMIN`, only `insert` / `call_sp`); nothing else changed (every other `crud_models` row and the 104 procedures equal to a snapshot taken before); one procedure per name with
  the expected signature and `allowed_fields` equal to its arguments; the procedures as the gateway calls them (void: `OK`, `ALREADY_VOID`, `NOT_FOUND` identical for an unknown and a foreign id, `INVALID_REASON`, `FORBIDDEN` for OWNER / EDITOR / CUSTOMER / non-member;
  balance: ADMIN only, the voided sale excluded, the other company never counted); the generic rule "every model whose table has a tenant column lists it" passes for all models, and it **does not apply** to the two new models because a `call_sp` model names a procedure
  in `table_name`, so there is no table or column to list (the tenant comes from `sp_requires_tenant` plus the verified header); a second apply changes nothing; the rollback disables exactly the two rows and a re-apply restores them.
* Preconditions: a model with one of the names pointing elsewhere, another model serving one of the procedures, and an extra overload of either procedure each make the migration abort.
* Mutations of the file set (each made the tests fail or the static check fail): `OWNER` in the write role; an extra `SELECT` operation; `allowed_fields` without `lot_id`; a migration that also changes another row; `sp_requires_tenant = false`;
  a rollback that leaves the models enabled; a rollback that disables only one; a rollback that also changes another row; a rollback that removes a row; a rollback with a `DROP` line (static check).
* `test_agri_sale_sp.mjs` (offline, the real `Build Query` code of the export): 61 checks — the parameter order of both entries equals the signatures parsed from migration 104; the tenant is only the header (body tenant keys ignored, missing or empty header fails);
  the actor e-mail is only the verified token (body e-mail ignored, missing or empty fails); extra keys never reach the statement; a hostile sale id stays a bound parameter; a model without an entry fails as before; existing entries keep their behavior;
  migration 107 `allowed_fields` agree with the entries; against `origin/develop` only `Build Query` differs and only by the two entries. Six mutations (wrong order, tenant from the body, actor from the body, missing entry, entry for another procedure,
  an extra node changed) each make it fail, and so does the unpatched gateway.
