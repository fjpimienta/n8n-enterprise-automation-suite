# Runbook — Reproduction tracking, phase 4c: disable the `nacimiento` Meta-CRUD gateway model (migration 089, OPTIONAL)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**Optional and independent:** 089 can be omitted without affecting 087 / 088. It only needs 085 (the append-only trigger function). Recommended order: **after 087 is verified in
production and after the pre-checks below.**

**Why.** The gateway model `nacimiento` (crud_models id 70, `table_name = sp_register_birth_event`, `allowed_roles_insert = ADMIN,EDITOR`, `allowed_ops = {INSERT}`) calls the birth procedure
**without an e-mail**, so the membership check of 087 never runs on that path. A repo-wide search (2026-10-28) found no frontend consumer (only comments); both AI agents use the MCP tool, which
always sends the verified e-mail.

**How, and why the row is not deleted.** `v6/CRUD` reads `select * from crud_models where model_name = '<model>'` (node *Get Model Config*). A **missing** row goes to the *Can Register Model* branch, where
an ADMIN of a company can **auto-register** a model — so deleting row 70 would reopen that path. With the row present, *Security Validation* answers HTTP 403 "Operación no permitida para este modelo" when the
operation is not in `allowed_ops`, before any role check or query. 089 therefore sets, on the **one** row `id = 70 AND model_name = 'nacimiento' AND table_name = 'sp_register_birth_event'`:
`allowed_ops = '{}'` and `allowed_roles_select / insert / update / delete = 'NONE'` (the 073 pattern). Anything else at id 70 aborts the migration.

**What it writes.** The new append-only table `crud_models_backup_089` receives the **whole original row** (`to_jsonb`) as a `DISABLE` entry first; then those five columns change. Nothing else.
Applying twice is idempotent by state (no second backup while the row is disabled); a row found disabled **without** a backup aborts (it was disabled by hand and the original would be lost).
`089_rollback.sql` restores exactly those five columns from the most recent `DISABLE` backup, **compares the whole row with the backup and aborts if anything differs**, and records a `RESTORE` entry. Nothing is deleted.

Nothing in this runbook is run by the assistant. Production is touched only by the owner, with the steps below.

Conventions used below
```bash
# On the VPS (production)                                  # On your machine (LOCAL)
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```

**The intended psql command, for every apply and every rollback in this runbook: `$P -v apply=true -f <file>` - WITHOUT `--single-transaction`.** Each file opens and
commits its own transaction (`BEGIN` ... `COMMIT`) and `ON_ERROR_STOP` stops it at the first error *before* the `COMMIT`, so nothing is left half-applied. Adding
`--single-transaction` opens a second one: psql prints `WARNING: there is already a transaction in progress` at the file's `BEGIN` and
`WARNING: there is no transaction in progress` at the file's own final `COMMIT` - harmless, but noisy. Without `-v apply=true` the file is a dry run (it ends in `ROLLBACK`).
The `*_state_check.sql` files open `BEGIN READ ONLY` and end in `ROLLBACK` themselves; they need no flag either.

---

## Test database (LOCAL only — never production)

The tests insert fixtures and roll everything back, but they still must never run against production. They need a database with the
**real schema** (so the production procedures have their verified bodies: the migration aborts otherwise) and, at minimum, **two ACTIVE
non-palm companies and two users** (they pick the first two of each and arrange memberships inside the transaction). They refuse to run
if their `T089` fixtures already exist (if the schema-only copy has no `crud_models` row 70 the test inserts a fixture one, plus two neighbour fixtures).

> The commands below are the same **reconstructed** ones as in `085_RUNBOOK.md` / `086_RUNBOOK.md` (schema-only dump into a new database,
> copy `companys` and two users); replace them with the exact commands you use if they differ.

1. **Create the throwaway database with the schema only** (from the LOCAL `hosting3m_db`, the daily copy of production):

   ```bash
   docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test089
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test089 -q'
   ```

2. **Copy `companys` and two users:**

   ```bash
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test089 -q -v ON_ERROR_STOP=1'
   docker exec n8n-enterprise-db sh -c \
     "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
      | psql -U n8n_user -d hosting3m_test089 -c \"COPY public.users FROM STDIN\""
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test089 -c \
     "SELECT (SELECT count(*) FROM companys WHERE is_active) AS companies, (SELECT count(*) FROM users) AS users;"
   ```

   At least 2 active companies that are **not** palm (`industry` other than `agricultura`) and 2 users.

3. **Copy the test files INTO the container and run them from that directory.** The test file includes the earlier migrations with `\ir`
   (a path relative to the test file), so the whole `migrations` folder must be inside the container and the run must start from it.

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m089
   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m089
   docker exec -w /tmp/m089 -i n8n-enterprise-db \
     psql -U n8n_user -d hosting3m_test089 -v ON_ERROR_STOP=1 -f /tmp/m089/089_tests.sql 2>&1 | tee 089_tests_output.txt
   ```

   Expected: one `OK` line per test and a final `passed | failed | total` with **`failed = 0`**, ending in `*** 089 tests: everything rolled back ***`.
   (`089_tests_output.txt` is a local file: do not commit it.) Any `FAIL` line stops the rollout.

   **The run keeps going after a failed assertion**: after the fixtures are built, every assertion runs inside `pg_temp.t()`, which records an error (with its SQLSTATE) as a `FAIL`
   line instead of aborting, a tool call that raises is stored as `{"__error", "__sqlstate"}`, and psql rolls back only the failing statement (`ON_ERROR_ROLLBACK`). An `ERROR:` line
   printed *outside* the results table is an unexpected error in a fixture or helper statement - report it. The script still exits non-zero at the end when any assertion failed.
   (Why this was needed: `WHEN OTHERS` in PL/pgSQL does not catch `assert_failure`, SQLSTATE `P0004`, which the legacy procedures use for "ambiguous identifier".)

   **About a `WARNING: there is no transaction in progress` near the start of the output.** psql prints it when a `COMMIT` / `ROLLBACK` runs with no open transaction. Reading the
   included files, every one honours `embedded` and issues no `COMMIT` / `ROLLBACK` inside the tests' transaction, so I could not locate its source by reading alone; it is harmless
   **only if nothing was committed**, and the run proves it twice: the last test (`ran inside ONE transaction`) fails if the transaction id changed, and after the run this query must return 0:

   ```bash
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test089 -tA -c "SELECT count(*) FROM cattle_livestock WHERE rfid_siniiga LIKE 'T0%'"
   ```

   If either check fails, stop and send the first 20 lines of the output.

4. **Clean up** when done: `docker exec n8n-enterprise-db dropdb -U n8n_user hosting3m_test089`.


## Part 0. Pre-checks — **run on the VPS, read-only** (decide with these whether to apply)

1. **The row is what we expect** (expect exactly one row: id 70, `nacimiento`, `sp_register_birth_event`, `ADMIN,EDITOR` for insert, `ADMIN` for the rest, `{INSERT}`):

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -c \
     "SELECT id, model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, sp_requires_tenant FROM crud_models WHERE id = 70 OR model_name = 'nacimiento';"
   ```

2. **Recent use of the model through the gateway** — (a) count n8n executions of `v6/CRUD` (workflow id `ZhHDs5XoopmqgZvF`) that mention `nacimiento` in the last 90 days, **and (b) report how far back n8n
   still keeps executions: a zero is meaningless if the execution data is pruned.** Run in the n8n database (`n8n_db`, same Postgres container), then read the retention settings of the n8n container:

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d n8n_db -X <<'SQL'
   SELECT count(*) AS executions_mentioning_nacimiento_90d, min(e."startedAt") AS oldest_of_them, max(e."startedAt") AS newest_of_them
     FROM execution_entity e JOIN execution_data d ON d."executionId" = e.id
    WHERE e."workflowId" = 'ZhHDs5XoopmqgZvF' AND e."startedAt" > now() - interval '90 days' AND d.data ILIKE '%nacimiento%';
   SELECT min("startedAt") AS oldest_execution_retained, count(*) AS executions_retained,
          count(*) FILTER (WHERE "workflowId" = 'ZhHDs5XoopmqgZvF') AS executions_retained_of_v6_crud
     FROM execution_entity;
   SQL
   docker exec n8n-enterprise-core printenv | grep -E '^EXECUTIONS_(DATA_PRUNE|DATA_MAX_AGE|DATA_PRUNE_MAX_COUNT|DATA_SAVE_ON_SUCCESS|DATA_SAVE_ON_ERROR)='
   ```

   Read it like this: **zero + the oldest retained execution is older than 90 days → good evidence of no use.** Zero but the oldest retained execution is recent (or `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none`) →
   the check says nothing; use the Cloudflare request log for the path `/crud/v6/nacimiento` instead, or accept the risk knowingly. If executions were found, **do not apply**: find the caller first.
   (If the `execution_data` table has another shape in your n8n version, adapt the join; the intent is "any execution of v6/CRUD whose data mentions the model".)

3. **Where do the births in the database come from?** (read-only). All 23 rows had `source = 'MOBILE_APP'` on 2026-10-28, which is what *both* the gateway and the MCP tool write, so this does not tell them apart by itself:

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -c "SELECT source, count(*) FROM birth_events GROUP BY 1 ORDER BY 2 DESC;"
   ```

   After 087, births from the MCP tool carry `reported_by_email`; births without it come from the gateway (or from the legacy NULL path): `SELECT count(*) FILTER (WHERE reported_by_email IS NULL) FROM birth_events WHERE created_at > <087 date>;`

## Part 1. Database

1. **Backup first:** `docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc -t public.crud_models hosting3m_db > /root/backups/hosting3m_crud_models_pre089_$(date +%F_%H%M).dump` (size > 0).
2. **State before:** `mkdir -p /root/m089` (copy `089_*` there, `md5sum 089_*`), `docker cp /root/m089 n8n-enterprise-db:/tmp/m089`, then
   `$P -v expect=before -f /tmp/m089/089_state_check.sql > /root/089_state_before.txt 2>&1` → `089 state check (before): OK`.
3. **Dry run:** `$P -f /tmp/m089/089_disable_nacimiento_gateway.sql > /root/089_dryrun.txt 2>&1` — it prints the row BEFORE / AFTER and ends in `DRY RUN`.
4. **Tests ran on the throwaway database**, never here.
5. **Apply:** `$P -v apply=true -f /tmp/m089/089_disable_nacimiento_gateway.sql > /root/089_apply.txt 2>&1` → `089: OK` and `*** 089 COMMITTED ***`.
6. **State after:** `$P -v expect=applied -f /tmp/m089/089_state_check.sql > /root/089_state_after.txt 2>&1` → `089 state check (applied): OK`; `diff` before / after: only the `ROW 70` / NOTICE / `BACKUP_ROWS` lines
   differ, **never a `FINGERPRINT` line** (`crud_models_without_row_70` proves no other model changed).
7. **Check through the real gateway** (an ADMIN token of the owner's test company 3): `POST /webhook/crud/v6/nacimiento` with any `insert` body must answer **403 "Operación no permitida para este modelo."** and create no row. Other models keep working.

**Rollback:** `$P -v apply=true -f /tmp/m089/089_rollback.sql > /root/089_rollback.txt 2>&1`, then `-v expect=rolled_back` (it checks that the row is **identical** to the backed-up original). It drops and deletes nothing; the backup table keeps its rows (`DISABLE` + `RESTORE` entries).

## Part 2. n8n

Nothing. (The gateway workflow is not edited: only the `crud_models` row changes.)

## Part 3. Frontend

Nothing. (No consumer of the model was found; if the pre-check shows one, do not apply.)

---

## Files and md5

| File | md5 |
|---|---|
| `089_disable_nacimiento_gateway.sql` | `4f52348630b514c4de86b8da030db556` |
| `089_tests.sql` | `47d2f145e4e4cfa23554b2c5235e31ce` |
| `089_rollback.sql` | `04315d056abfbc9b8b4043f535477a7f` |
| `089_state_check.sql` | `12e7ede521226451319c08e9b0cc8aa6` |

(Recompute with `md5sum` if any file is edited after this runbook was written.)
