> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: written and tested LOCAL only (throwaway database + the LOCAL n8n gateway). NOT applied to production. No frontend in this change.**
> Part 2 (n8n) changes **no node**: it is a verification of the production `v6/CRUD` workflow, and it is a precondition (see below).
> TODO(verify): everything marked "expected" below comes from LOCAL; confirm each value against production before relying on it.

# Runbook 108 — read-only palpation report data (two views, two gateway models)

## Scope

| Object | Kind | Notes |
|---|---|---|
| `vw_palpation_events` | view (new) | one row per `PALPACION` event; tenant column `id_company` (from `cattle_livestock.tenant_id`) |
| `vw_palpation_herd` | view (new) | one row per animal of the company (including never palpated); last counted palpation, palpation count; `brand_code` only |
| `vw_palpation_events`, `vw_palpation_herd` | `crud_models` rows (new) | `allowed_ops {SELECT}`, `allowed_roles_select ADMIN,EDITOR`, insert / update / delete `NONE`, `joins []`, `is_global false`, `sp_requires_tenant true`; `allowed_fields` = the view columns, **with `id_company` and `created_at`** |

Nothing else changes: no table, function, trigger, data, workflow node or other `crud_models` row. The views never select `description`, notes, `metadata`, `medicines_json` or any `owner_*` column.

| File | Purpose |
|---|---|
| `108_palpation_views.sql` | the change. Dry run by default (rolled back); `-v apply=true` commits. **Aborts** if a table or column is missing, if `repro_condition_codes` has no `PRIMARY KEY (id_company, code)`, if either view or either model already exists, or if `id_company` / `created_at` is missing from a model, a forbidden field is present, or `allowed_fields` differ from the view columns |
| `108_rollback.sql` | no DROP, no DELETE: both models get `allowed_ops '{}'` and every role `NONE` (073 pattern); views stay, inert |
| `108_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints and assertions |
| `108_tests.sql` | 62 assertions, one rolled-back transaction, throwaway database only (name must contain `test` or `rehearsal`), 100% synthetic data |
| `108_abort_check.sh` | proves the abort guards and that the tests catch regressions (11 mutation / abort checks) |
| `108_static_check.sh` | no DROP / TRUNCATE / DELETE statement in the migration, rollback and state check; no forbidden column in the views |
| `108_gateway_setup.sql`, `108_gateway_tests.py`, `108_gateway_cleanup.sql` | negative and isolation tests against the **real LOCAL gateway** (28 checks). LOCAL only |

## Why the models MUST carry `id_company` (read this before touching them)

`v6/CRUD` (`Build Query`, lines 17-24) injects the verified `x-tenant-id` as a filter **only when `id_company` or `tenant_id` is in `allowed_fields`**. Without it the query has **no company filter at all**.
Proved in LOCAL (negative control, 2026-11-18): with `id_company` removed from `vw_palpation_events.allowed_fields`, `getall` for a company-A user returned 1500 rows of both companies and 9 of the 28 gateway checks failed.
`cattle_health_logs` has no tenant column, so the company comes from the join to `cattle_livestock` inside the view. The same hole exists today in other cattle models (`cattle_health_logs`, `cattle_weight_logs`, `cattle_task_evidence`, `cattle_identifier_history`, `cattle_movement_event_animals`, `cattle_movement_event_health_certs`, `cattle_tenants`): it is **out of scope of 108** and tracked separately (branch `security/gateway-v6-tenant-less-models`).
Also: `getall` and `getone` are both authorised as `select`, so `allowed_ops {SELECT}` cannot hide `getone`; it is filtered by company the same way. Default sort is `<table>.created_at`: both views expose `created_at`.

## Order (database → n8n verification → production tests → frontend, last)

### Part 0 — Preconditions (read-only, on the VPS)

1. Production already has 084-090 and 028 (the views read `palpation_repro_details`, `repro_condition_codes.meaning`, `brand_registrations`). `108_palpation_views.sql` aborts if not; the dry run below tells.
2. The production `repro_condition_codes` primary key is `(id_company, code)` (the migration aborts otherwise). Confirmed LOCAL; production **not verified**.
3. **Part 2 fingerprint (n8n) must be done BEFORE Part 1 is applied** (see Part 2).

### Part 1 — Database

1. **Backup** (before anything else; same procedure as `REPRO_PRODUCTION_RUNBOOK.md`, Step 1): `pg_dump -Fc` of `hosting3m_db`, `pg_restore --list` of the dump, `md5sum`, copy off the VPS. Record the file names. Do not continue without a verified dump.
2. **Copy the files** to a scratch directory on the VPS and `md5sum` them against the values recorded in the pull request (do not run a blanket `git pull`).
3. **State before** (read-only): `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 108_state_check.sql`. Save the output. Expected: both views `absent`, no model row, `other_crud_models` fingerprint = the one you will compare at the end. **STOP if it does not say OK.**
4. **Dry run** (default, rolled back): `psql -X -v ON_ERROR_STOP=1 -f 108_palpation_views.sql`. Expected last lines: `108: OK`, four fingerprints, `*** DRY RUN: 108 rolled back ***`. **STOP on any `ABORT`.**
5. **Fingerprints (expected from LOCAL, PostgreSQL 15.4):**

   | Fingerprint | md5 (LOCAL) |
   |---|---|
   | view `vw_palpation_events` | `410e9c6e2c228e1f3e318730e2fc167d` |
   | view `vw_palpation_herd` | `7dd565ac42cd8bdd46b21c233494d2d7` |
   | model `vw_palpation_events` | `51b93c8cc669c0cb8bb722d874790438` |
   | model `vw_palpation_herd` | `1549e96fabc11e138d8a5b9d114de788` |

   The model hashes must match exactly. The view hashes depend on the PostgreSQL version's `pg_get_viewdef` formatting: if the production version differs from 15.4 and only the view hashes differ, compare the definitions by eye and record it; if a model hash differs, stop.
6. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_palpation_views.sql` → `*** 108 COMMITTED ***`.
7. **State after:** `-v expect=applied`. The `other_crud_models`, `other_crud_models_count` and `source_table_columns` fingerprints must be **identical** to step 3.

### Part 2 — n8n (no change; verification only)

108 needs no workflow change. It does depend on the production `v6/CRUD` `Build Query` node behaving as the repo's export does for `getall` / `getone` (company filter from `allowed_fields`, default sort by `created_at`, limit 1500).
Production can carry manual changes (CLAUDE.md root, "compara producción contra `main` por huella"):

1. Download `v6/CRUD` from the production editor (⋯ → Download), `chmod 600` the file, outside the repo.
2. Compare with `origin/main` using the snippet of the root `CLAUDE.md` (runbook step 3). Expected `No differences.`; if it differs, **STOP** and resolve before continuing (an old `Build Query` without the `id_company` injection would make Part 3 fail the isolation checks).
3. Reference (LOCAL, 2026-11-18): the repo `Build Query` code md5 is `e270195a5f8f2643e1f050d3c8055c78`; the LOCAL n8n runs `12326918f2ff2e2639a802785e02e591`, which differs **only** by the two `call_sp` entries of migration 107 (`sp_agri_void_sale`, `sp_agri_sales_balance`): the `getall` / `getone` paths tested are identical.

### Part 3 — Production tests (company 10 "Plantación de Pruebas" and a user without membership in 5)

Use placeholders only in notes; never paste a token. **No data of company 5 is used or read.** Company 10 is a palm company (no cattle), so a correct filter returns **no rows**, and any row returned would be a leak.

| # | Request (real webhook) | Expected |
|---|---|---|
| 1 | no `Authorization` | `401` |
| 2 | QA user (member of 10), **no** `x-tenant-id` | `403`, `code: TENANT_FORBIDDEN`, no rows |
| 3 | QA user **without membership in 5**, `x-tenant-id: 5` (`vw_palpation_events` and `vw_palpation_herd`) | `403`, `code: TENANT_FORBIDDEN`, **no rows** |
| 4 | QA ADMIN of 10, `x-tenant-id: 10`, `getall` on both models | `200`, `error:false`, **0 rows** (`data:[{}]`); in particular none of company 5's animals |
| 5 | same, with `filter: {id_company: 5}` and `fields: {id_company: 5}` in the body | still `200` and 0 rows (the verified header wins) |
| 6 | QA ADMIN of 10, `insert` / `update` / `delete` on either model | `403` (operation not allowed) |
| 7 | a `CUSTOMER` of 10 (if one exists), `getall` | `403` (`SECURITY_VALIDATION`) |
| 8 | open the latest execution of #3 and #4 in n8n | #3 stops at `Respond Tenant Forbidden`; #4 reaches `Execute SQL` with `id_company = $…` bound to `10` |

If #3 returns anything other than `403` with no rows, or #4 returns any row, **roll back immediately** (below) and report it.
Limitation: company 10 has no cattle, so these checks prove authorization and filtering but not the content of the views. The content was tested LOCAL with synthetic data (62 + 28 checks). Seeding synthetic cattle in company 10 would be a production write: **decision of the owner**, not part of this runbook.

### Part 4 — Frontend

**Only if Parts 1, 2 and 3 are OK.** This pull request contains no frontend. The report screen is a later pull request (branch `feat/agro-erp-palpation-report`) that must not reach `main` before this runbook is completed and recorded.

## Gateway behaviour the frontend must handle (observed LOCAL, 2026-11-18)

- No `x-tenant-id` or a company the user does not belong to: `403` + `{error:true, code:"TENANT_FORBIDDEN"}`. Role not allowed: `403` + `code:"SECURITY_VALIDATION"`.
- An empty collection is `data:[{}]`, not `[]`: filter by identifier before counting.
- A `sort_by` that is not a plain identifier, and other errors thrown by `Build Query`, answer **HTTP 200 with an EMPTY body** (the execution fails; it is not `error:true`). An unknown column answers `error:true`. The client must treat an empty body as an error, never as "0 rows".
- The default limit is **1500**; `limit` up to 2000. Exactly 1500 rows (or `rows == limit`) means **truncated**: show an error / paging state, never a complete list.

## Rollback

`psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_rollback.sql`, then `-v expect=rolled_back` on `108_state_check.sql`. Both models then deny every role (reproduced in `108_tests.sql`; **not exercised against the gateway**: check it in production with one request, expected `403`); the views remain (nothing reads them). Nothing is dropped or deleted. If the data (not the gateway) is the problem, the backup of Part 1, step 1 is the recovery point. Re-enabling is a separate reviewed change (the migration aborts when the objects exist).

## LOCAL evidence (2026-11-18, PostgreSQL 15.4, local `n8n-enterprise-core`)

- `108_tests.sql` on a throwaway database restored from the LOCAL schema: **62 assertions passed**, rolled back. Covers: the 2023 historical load (key `resultado` without `result`) and the mixed-format event; new events with and without details row; `UNMAPPED` (`code_meaning` forced to NULL even when the code has a meaning); NR (not counted as palpated), RP, NO APTO, MATRIZ OCUPADA (ranch terms, outside the clinical results); pregnant without usable gestation; never-palpated animals; sold animals; a non-object `medicines_json`; the accented event type; the same code `NR` in company B with another meaning; isolation between companies A and B; the gateway gate (ADMIN / EDITOR read, CUSTOMER and writes denied) and the company filter as `Build Query` builds it; rollback leaves the views and every other `crud_models` row untouched.
- `108_abort_check.sh`: **11 / 11** (second run aborts; existing model row aborts; removing `id_company` or `created_at`, adding a forbidden field, or widening the roles aborts; mutated views make the tests fail; the static check rejects a view that selects `description`).
- `108_gateway_tests.py` against the real LOCAL gateway: **28 / 28** (list in the pull request). Negative control without `id_company`: 19 / 28, with the leak visible (1500 mixed rows).
- State fingerprints `other_crud_models` (`27178bfa1f57bf93182b401a788d9897`, 87 rows) and `source_table_columns` identical before, after applying and after rolling back.
- LOCAL `hosting3m_db` was restored to its previous state after the gateway tests (models and views removed, fixtures deleted).
