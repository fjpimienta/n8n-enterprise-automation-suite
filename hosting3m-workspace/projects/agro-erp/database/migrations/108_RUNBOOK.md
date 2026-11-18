> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: written and tested LOCAL only (throwaway database + the LOCAL n8n gateway). NOT applied to production. No frontend in this change.**
> Part 2 (n8n) changes **no node**: it is a verification of the production `v6/CRUD` workflow, and it is a precondition (see below).
> Values marked "confirmed by the owner" were reported by Francisco from read-only checks in production; they were **not** re-verified by the author of this runbook.

# Runbook 108 — read-only palpation report data (two views, two gateway models)

## Scope

| Object | Kind | Notes |
|---|---|---|
| `vw_palpation_events` | view (new) | one row per `PALPACION` event; tenant column `id_company` (from `cattle_livestock.tenant_id`) |
| `vw_palpation_herd` | view (new) | one row per animal of the company (including never palpated); `category`, `species`, last counted palpation, palpation count; `brand_code` only |
| `vw_palpation_events`, `vw_palpation_herd` | `crud_models` rows (new) | `allowed_ops {SELECT}`, `allowed_roles_select ADMIN,EDITOR`, insert / update / delete `NONE`, `joins []`, `is_global false`, `sp_requires_tenant true`; `allowed_fields` = the view columns, **with `id_company` and `created_at`** |

Nothing else changes: no table, function, trigger, data, workflow node or other `crud_models` row. The views never select `description`, notes, `metadata`, `medicines_json` or any `owner_*` column.

**`ranch_term` is a fixed list** (`NR`, `RP`, `NO APTO`, `MATRIZ OCUPADA`, taken from `upper(btrim(raw_code))`). Adding a ranch term is **not** a data change: it needs a new version of the view (a new migration). Anything else stays a clinical result or an unconfirmed code (`UNMAPPED` → `code_meaning` NULL, never interpreted).

| File | Purpose |
|---|---|
| `108_palpation_views.sql` | the change. Dry run by default (rolled back); `-v apply=true` commits. **Aborts** if a table or column is missing, if `repro_condition_codes` has no `PRIMARY KEY (id_company, code)`, if either view or either model already exists, or if `id_company` / `created_at` is missing from a model, `category` / `species` are missing from the herd model, a forbidden field is present, or `allowed_fields` differ from the view columns |
| `108_rollback.sql` | no DROP, no DELETE: both models get `allowed_ops '{}'` and every role `NONE` (073 pattern); views stay, inert |
| `108_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints and assertions |
| `108_tests.sql` | 67 assertions, one rolled-back transaction, throwaway database only, 100% synthetic data |
| `108_abort_check.sh` | 13 abort / mutation checks |
| `108_static_check.sh` | no DROP / TRUNCATE / DELETE statement in the migration, rollback and state check; no forbidden column in the views; herd view and model carry `category` / `species` |
| `108_gateway_setup.sql`, `108_gateway_tests.py`, `108_gateway_cleanup.sql` | negative and isolation tests against the **real LOCAL gateway** (28 checks, plus 8 after the rollback). LOCAL only |
| `108_prod_checks.py` | the **production** checks of Part 3: only `getall` reads, prints counts only |

**Environment guard.** Every script that inserts or deletes (`108_tests.sql`, `108_abort_check.sh`, `108_gateway_setup.sql`, `108_gateway_cleanup.sql`, `108_gateway_tests.py`) aborts with `looks like production` if company 5 exists in `companys` or any animal has `tenant_id = 5`. LOCAL has neither; production has both. The synthetic companies use explicit ids (9001, 9002, 9101, 9102), never 5. The migration itself and the rollback have no such guard (they are meant for production).

## Why the models MUST carry `id_company` (read this before touching them)

`v6/CRUD` (`Build Query`, lines 17-24) injects the verified `x-tenant-id` as a filter **only when `id_company` or `tenant_id` is in `allowed_fields`**. Without it the query has **no company filter at all**.
Proved in LOCAL (negative control): with `id_company` removed from `vw_palpation_events.allowed_fields`, `getall` for a company-A user returned 1500 rows of both companies and 9 of the 28 gateway checks failed; `108_prod_checks.py` stops with exit code 3 in that situation.
`cattle_health_logs` has no tenant column, so the company comes from the join to `cattle_livestock` inside the view. The same hole exists today in other cattle models (`cattle_health_logs`, `cattle_weight_logs`, `cattle_task_evidence`, `cattle_identifier_history`, `cattle_movement_event_animals`, `cattle_movement_event_health_certs`, `cattle_tenants`): it is **out of scope of 108** and tracked separately (branch `security/gateway-v6-tenant-less-models`).
Also: `getall` and `getone` are both authorised as `select`, so `allowed_ops {SELECT}` cannot hide `getone`; it is filtered by company the same way. Default sort is `<table>.created_at`: both views expose `created_at`.

## Order (database → n8n verification → production tests → frontend, last)

### Part 0 — Preconditions

Confirmed by the owner in production (read-only checks, reported 2026-11-18; **re-run them yourself before Part 1** and record the output):

| Fact | Confirmed value |
|---|---|
| primary key of `repro_condition_codes` | `PRIMARY KEY (id_company, code)` |
| objects of migrations 084-090 | the tables exist |
| `vw_palpation_events`, `vw_palpation_herd` and their two `crud_models` rows | **do not exist** |
| columns of `crud_models` | 17: `id`, `model_name`, `table_name`, `primary_key`, `allowed_fields`, `default_filter`, `created_at`, `schema_json`, `allowed_ops`, `hooks`, `allowed_roles_select`, `allowed_roles_insert`, `allowed_roles_update`, `allowed_roles_delete`, `joins`, `is_global`, `sp_requires_tenant` (the migration inserts 15 of them; `id` and `created_at` take their defaults) |

**Record `SELECT version();` of production** in the runbook record. See the fingerprint note in Part 1, step 5.
The migration itself aborts if any of these is false, and the dry run tells before anything is written.

### Part 1 — Database

1. **Backup** (before anything else; same procedure as `REPRO_PRODUCTION_RUNBOOK.md`, Step 1): `pg_dump -Fc` of `hosting3m_db`, `pg_restore --list` of the dump, `md5sum`, copy off the VPS. Record the file names. Do not continue without a verified dump.
2. **Copy the files** to a scratch directory on the VPS and `md5sum` them against the values recorded in the pull request (do not run a blanket `git pull`). Copy **only** the migration, rollback and state check: never the test, fixture or abort-check scripts.
3. **State before** (read-only): `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 108_state_check.sql`. Save the output. Expected: both views `absent`, no model row. **STOP if it does not say OK.**
4. **Dry run** (default, rolled back): `psql -X -v ON_ERROR_STOP=1 -f 108_palpation_views.sql`. Expected last lines: `108: OK`, four fingerprints, `*** DRY RUN: 108 rolled back ***`. **STOP on any `ABORT`.**
5. **Fingerprints (expected from LOCAL, PostgreSQL 15.4):**

   | Fingerprint | md5 (LOCAL) | Comparable across servers? |
   |---|---|---|
   | model `vw_palpation_events` | `51b93c8cc669c0cb8bb722d874790438` | **yes** (a hash of configuration rows, independent of the Postgres version) |
   | model `vw_palpation_herd` | `7d0209677c2bd1189fbdc35792bf4599` | **yes** |
   | view `vw_palpation_events` | `410e9c6e2c228e1f3e318730e2fc167d` | **only with the same `version()` of PostgreSQL** (`pg_get_viewdef` formatting can differ between versions) |
   | view `vw_palpation_herd` | `fe8d10d7179d9e97d990731de5799431` | **only with the same `version()`** |

   The two model hashes must match exactly; if one differs, stop. If the production `version()` is not the LOCAL one (15.4), a different view hash is **not** a failure by itself: compare the view definitions by eye (`SELECT pg_get_viewdef('vw_palpation_events'::regclass, true)` against the file) and record both. If the version is the same and a view hash differs, stop.
6. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_palpation_views.sql` → `*** 108 COMMITTED ***`.
7. **State after:** `-v expect=applied`. The `other_crud_models`, `other_crud_models_count` and `source_table_columns` fingerprints must be **identical** to step 3.

### Part 2 — n8n (no change; verification only)

108 needs no workflow change. It does depend on the production `v6/CRUD` `Build Query` node behaving as the repo's export does for `getall` / `getone` (company filter from `allowed_fields`, default sort by `created_at`, limit 1500).
Production can carry manual changes (root `CLAUDE.md`, "compara producción contra `main` por huella"):

1. Download `v6/CRUD` from the production editor (⋯ → Download), `chmod 600` the file, outside the repo.
2. Compare with `origin/main` using the snippet of the root `CLAUDE.md` (runbook step 3). Expected `No differences.`; if it differs, **STOP** and resolve before continuing (an old `Build Query` without the `id_company` injection would make Part 3 fail the isolation checks).
3. Reference (LOCAL): the repo `Build Query` code md5 is `e270195a5f8f2643e1f050d3c8055c78`; the LOCAL n8n runs `12326918f2ff2e2639a802785e02e591`, which differs **only** by the two `call_sp` entries of migration 107: the `getall` / `getone` paths tested are identical.

### Part 3 — Production tests (company 3 "Rancho El Palomar", test company)

Rules: a user **with membership in company 3 and without membership in company 5**; **no writes, no seeded data**; only **counts** are printed, never a row body; company 5 data is never read. If a row of another company ever appears: **stop, do not show it, tell the owner**.

Use `108_prod_checks.py` (only `getall`; the token goes in the environment, never in an argument or a chat):

```sh
export PALP_TOKEN='<token of the user; never paste it anywhere>'
python3 -I 108_prod_checks.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6
unset PALP_TOKEN
```

| # | Request (both models) | Expected | The script prints |
|---|---|---|---|
| 1 | no `x-tenant-id` | `403`, no rows | status and row count |
| 2 | `x-tenant-id: 5` with that user | `403`, no rows. A `200` means the user belongs to 5 or the gateway does not enforce membership: **the script does not inspect the answer, stops (exit 3)** | status and row count |
| 3 | `x-tenant-id: 3` | `200`; **rows with `id_company` ≠ 3 must be 0**. If not 0: stop (exit 3), content not shown | status, total rows, rows of other companies, truncated yes/no |

Then, by hand in n8n (no data shown): open the latest executions of #1 and #2 (they stop at `Respond Tenant Forbidden`) and #3 (reaches `Execute SQL` bound to `3`).
Also try `insert` / `update` / `delete` with an ADMIN token: expected `403`; and, if a `CUSTOMER` of company 3 exists, `getall`: expected `403`. These two are not in the script (writes are never sent from it); send them with an **empty `fields` object and no key** (`{"operation":"insert","fields":{}}`), so that even if a model were misconfigured nothing could be written; the gateway rejects the operation before touching a table.
If #2 or #3 fail: **roll back immediately** (below) and report.
`108_prod_checks.py` was validated against the LOCAL gateway with synthetic companies (6 / 6; and it stops with exit 3 when the company filter is removed from a model).

### Part 4 — Frontend

**Only if Parts 1, 2 and 3 are OK.** This pull request contains no frontend. The report screen is a later pull request (branch `feat/agro-erp-palpation-report`) that must not reach `main` before this runbook is completed and recorded.

## Gateway behaviour the frontend must handle (observed LOCAL)

- No `x-tenant-id` or a company the user does not belong to: `403` + `{error:true, code:"TENANT_FORBIDDEN"}`. Role not allowed: `403` + `code:"SECURITY_VALIDATION"`. A model with no operations (after the rollback): `403`.
- An empty collection is `data:[{}]`, not `[]`: filter by identifier before counting.
- A `sort_by` that is not a plain identifier, and other errors thrown by `Build Query`, answer **HTTP 200 with an EMPTY body** (the execution fails; it is not `error:true`). An unknown column answers `error:true`. The client must treat an empty body as an error, never as "0 rows".
- The default limit is **1500**; `limit` up to 2000. Exactly 1500 rows (or `rows == limit`) means **truncated**: show an error / paging state, never a complete list.
- `jwt-service` limits logins to 20 per 15 minutes per address (relevant when repeating the LOCAL gateway tests: `docker restart n8n-jwt-service` clears the in-memory counter in LOCAL).

## Rollback

`psql -X -v ON_ERROR_STOP=1 -v apply=true -f 108_rollback.sql`, then `-v expect=rolled_back` on `108_state_check.sql`. Both models then deny every role: **verified against the LOCAL gateway** (apply, 28 / 28 checks, rollback, then `getall` and `getone` of both models for ADMIN and EDITOR answer `403` with no rows, 8 / 8; the same users got `200` before the rollback). In production repeat one request (a `getall` with the user of Part 3, expected `403`). The views remain (nothing reads them). Nothing is dropped or deleted. If the data (not the gateway) is the problem, the backup of Part 1, step 1 is the recovery point. Re-enabling is a separate reviewed change (the migration aborts when the objects exist).

## LOCAL evidence (PostgreSQL 15.4, local `n8n-enterprise-core`)

- `108_tests.sql` on a throwaway database restored from the LOCAL schema: **67 assertions passed**, rolled back. Covers: the 2023 historical load (key `resultado` without `result`) and the mixed-format event; new events with and without details row; `UNMAPPED` (`code_meaning` forced to NULL even when the code has a meaning); NR (not counted as palpated), RP, NO APTO, MATRIZ OCUPADA (ranch terms, outside the clinical results); pregnant without usable gestation; never-palpated animals; sold animals; **a synthetic bull (`TORO`) and calf (`BECERRO`) that appear with their category and species**; a non-object `medicines_json`; the accented event type; the same code `NR` in company B with another meaning; isolation between companies A and B; the gateway gate and the company filter as `Build Query` builds it; the rollback leaves the views and every other `crud_models` row untouched.
- `108_abort_check.sh`: **13 / 13**.
- `108_gateway_tests.py` against the real LOCAL gateway: **28 / 28**; after `108_rollback.sql` (`--after-rollback`): **8 / 8** (`403`). Negative control without `id_company`: 19 / 28, leak visible (1500 mixed rows).
- State fingerprints `other_crud_models` (`27178bfa1f57bf93182b401a788d9897`, 87 rows) and `source_table_columns` identical before, after applying and after rolling back.
- LOCAL `hosting3m_db` was returned to its previous state after the gateway tests (models and views removed, fixtures deleted). `rehearsal_108` is kept as a throwaway database.
