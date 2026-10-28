# Runbook — Reproduction tracking, phase 4a: births (migration 087 + n8n tools)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**Requires migrations 084 and 085** (086 is not a dependency of 087 - 088 needs it - but production applies them in order). 087 aborts at its first block if their helpers are missing, **and aborts if the live
`sp_register_birth_event` (13 parameters) is not the production body verified on 2026-10-28 (md5 `8eaf6f52716165a6bc59f8f4a6a7ce4a`)** —
production procedures have been edited by hand before. If it aborts with that message: **STOP** and compare the live body before doing anything else.
None of 084 / 085 / 086 is applied in production yet, so the production order is:
**084 → 085 → 086 → 087 → 088 → n8n tools of phases 1 to 4 → 089 (optional, after its pre-checks)**. The seed of 086 is separate (`086_RUNBOOK.md`).

**What changes**
- **Database (087):** `birth_events.reported_by_email` (nullable, no default, no backfill); 3 new tables (`repro_births_config`,
  `repro_historical_births`, `repro_historical_birth_voids`; every row has `id_company`; the two historical tables are append-only, 6 triggers);
  9 internal helper functions and 8 `sp_*` functions; and **one existing procedure is replaced in place**: `sp_register_birth_event`
  (same 13-parameter signature, `CREATE OR REPLACE`, not an overload). It writes **no rows**.
- **The replaced procedure** (`sp_register_birth_event`) now:
  1. when `p_reported_by_email` is given, requires an **active membership** in `p_id_company` (`P0001`, fail closed);
  2. answers `{success:true, duplicate_skipped:true, birth_event_id, calf_id, ...}` for an **exact retry** (same company, dam, date, calf sex and
     birth weight — `IS NOT DISTINCT FROM`, so twins with different weights are not a retry — created within the last 5 minutes);
  3. stores the reporter in `birth_events.reported_by_email`;
  4. after the birth, links the dam's single plausible service **if migration 088 is applied** (skipped otherwise);
  5. is otherwise **unchanged**: a NULL e-mail keeps the legacy path, and a dam that is not found or is ambiguous still registers an orphan calf with a warning.
- **Legacy NULL e-mail path (documented, kept on purpose):** the Meta-CRUD gateway model `nacimiento` (crud_models id 70) calls the procedure
  *without* an e-mail, so no membership check runs there. Migration **089** disables that model. The procedure itself keeps accepting a
  NULL e-mail in this phase; **backlog:** make it fail closed on a NULL e-mail once 089 is applied and a review period shows no NULL callers
  (see the monitoring query in Part 1, step 8).
- **n8n:** 8 `postgresTool` nodes (`workflows/09-MCP-Agent-Cattle/v6/repro-phase4/`; one of them needs 088). They stay invisible to the agent until the
  two system prompts list them (phase 5). The existing `register_birth_event` tool is **not edited**, but it now gets the behaviour above.
- **Frontend:** nothing.

⚠️ **Strict order: database → n8n.** If the tools reach n8n first they fail with `function sp_repro_… does not exist` (harmless today: the agent does not
know them). The database rollback drops nothing: it restores the original body of `sp_register_birth_event` and the new tools answer
`{"status":"disabled"}`, so the reverse order is safe too.

⚠️ **There is only ONE overload of `sp_register_birth_event` in production (13 parameters)**, verified on the server on 2026-10-28; the 12-parameter
overload that earlier notes mentioned does not exist there. The gateway's 12-argument call resolves to the 13-parameter function through the
default of its last parameter. The state check works for either shape: it fingerprints any other overload separately (`other_birth_overloads`).

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
if their `T087` fixtures already exist (the tests also create a production unit, lot and paddock fixture per company to prove that ids of another company are refused).

> The commands below are the same **reconstructed** ones as in `085_RUNBOOK.md` / `086_RUNBOOK.md` (schema-only dump into a new database,
> copy `companys` and two users); replace them with the exact commands you use if they differ.

1. **Create the throwaway database with the schema only** (from the LOCAL `hosting3m_db`, the daily copy of production):

   ```bash
   docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test087
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test087 -q'
   ```

2. **Copy `companys` and two users:**

   ```bash
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test087 -q -v ON_ERROR_STOP=1'
   docker exec n8n-enterprise-db sh -c \
     "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
      | psql -U n8n_user -d hosting3m_test087 -c \"COPY public.users FROM STDIN\""
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test087 -c \
     "SELECT (SELECT count(*) FROM companys WHERE is_active) AS companies, (SELECT count(*) FROM users) AS users;"
   ```

   At least 2 active companies that are **not** palm (`industry` other than `agricultura`) and 2 users.

3. **Copy the test files INTO the container and run them from that directory.** The test file includes the earlier migrations with `\ir`
   (a path relative to the test file), so the whole `migrations` folder must be inside the container and the run must start from it.

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m087
   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m087
   docker exec -w /tmp/m087 -i n8n-enterprise-db \
     psql -U n8n_user -d hosting3m_test087 -v ON_ERROR_STOP=1 -f /tmp/m087/087_tests.sql 2>&1 | tee 087_tests_output.txt
   ```

   Expected: one `OK` line per test and a final `passed | failed | total` with **`failed = 0`**, ending in `*** 087 tests: everything rolled back ***`.
   (`087_tests_output.txt` is a local file: do not commit it.) Any `FAIL` line stops the rollout.

   **The run keeps going after a failed assertion**: after the fixtures are built, every assertion runs inside `pg_temp.t()`, which records an error (with its SQLSTATE) as a `FAIL`
   line instead of aborting, a tool call that raises is stored as `{"__error", "__sqlstate"}`, and psql rolls back only the failing statement (`ON_ERROR_ROLLBACK`). An `ERROR:` line
   printed *outside* the results table is an unexpected error in a fixture or helper statement - report it. The script still exits non-zero at the end when any assertion failed.
   (Why this was needed: `WHEN OTHERS` in PL/pgSQL does not catch `assert_failure`, SQLSTATE `P0004`, which the legacy procedures use for "ambiguous identifier".)

   **About a `WARNING: there is no transaction in progress` near the start of the output.** psql prints it when a `COMMIT` / `ROLLBACK` runs with no open transaction. Reading the
   included files, every one honours `embedded` and issues no `COMMIT` / `ROLLBACK` inside the tests' transaction, so I could not locate its source by reading alone; it is harmless
   **only if nothing was committed**, and the run proves it twice: the last test (`ran inside ONE transaction`) fails if the transaction id changed, and after the run this query must return 0:

   ```bash
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test087 -tA -c "SELECT count(*) FROM cattle_livestock WHERE rfid_siniiga LIKE 'T0%'"
   ```

   If either check fails, stop and send the first 20 lines of the output.

4. **Clean up** when done: `docker exec n8n-enterprise-db dropdb -U n8n_user hosting3m_test087`.

**What the run proves.** Part A: a birth line is validated (dam by id / RFID / fire number, ambiguity with candidates, sex, date, weight, dam sold or not female,
lot / UPP / paddock of another company). Part B: the new single tool (calf, status change, reporter, `possible_duplicate`, `force`, identical twins, exact retry, the
per-company window, roles, isolation). Part C: the **legacy** procedure (non-member refused before any write, NULL path still works, exact retry, twins with a
different weight, orphan-calf behaviour untouched). Part D: blocks (preview is a pure read, register is all-or-nothing and re-validates, cap of 50, no trust in a
previous preview). Part E: historical births (no calf, no status change, idempotent, voidable, precision rules, window interplay, append-only, isolation).
Parts B, C, D, E, F contain `ISOLATION` checks: company A gets an **error** (never rows) for company B on every tool, a stranger / blank e-mail / bad tenant is
refused, a palm company raises `P0094` (skipped with a note if the database has none).

---

## Part 0. Baseline and files — **run on the VPS** (it writes to `/root`)

Everything in this part runs **on the VPS, in production**, as read-only checks; the files it writes go to `/root`. Do **not** run it on your local machine.

1. Verify the files before copying them (md5 in the table at the end of this file):

   ```bash
   mkdir -p /root/m087 && cd /root/m087          # copy 087_* (and, if still pending, 084_* 085_* 086_*) here (scp from your machine)
   md5sum 087_*
   ```

2. Check that the production body is the verified one, copy into the container and take the **baseline** (read-only):

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -c \
     "SELECT p.oid::regprocedure, md5(pg_get_functiondef(p.oid)) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname='sp_register_birth_event';"
   #   expect ONE row, md5 8eaf6f52716165a6bc59f8f4a6a7ce4a. Anything else: STOP and tell the maintainer before applying.
   docker exec n8n-enterprise-db rm -rf /tmp/m087 && docker cp /root/m087 n8n-enterprise-db:/tmp/m087
   P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
   $P -v expect=before -f /tmp/m087/087_state_check.sql > /root/087_state_before.txt 2>&1
   tail -3 /root/087_state_before.txt        # expect: 087 state check (before): OK
   ```

   If it says *"migration 084 / 085 is not applied here"*, stop: apply them first with their runbooks.

## Part 1. Database (VPS, container `n8n-enterprise-db`, database `hosting3m_db`)

1. **Backup first** (size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db > /root/backups/hosting3m_schema_pre087_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc -t public.birth_events -t public.cattle_livestock -t public.cattle_weight_logs \
     hosting3m_db > /root/backups/hosting3m_births_tables_pre087_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre087*
   ```

2. **State before** was taken in Part 0 (`/root/087_state_before.txt`). Keep its `FINGERPRINT` and `LEGACY_BIRTH` lines.
3. **Dry run** (rolls back): `$P -f /tmp/m087/087_repro_births.sql > /root/087_dryrun.txt 2>&1` → `087: OK` and `DRY RUN`.
4. **Tests ran on the throwaway database** (section above), never here.
5. **Apply** (the file commits its own transaction; no `--single-transaction`, see the conventions above):

   ```bash
   $P -v apply=true -f /tmp/m087/087_repro_births.sql > /root/087_apply.txt 2>&1
   tail -5 /root/087_apply.txt     # expect: 087: OK  and  *** 087 COMMITTED ***
   ```

6. **State after:** `$P -v expect=applied -f /tmp/m087/087_state_check.sql > /root/087_state_after.txt 2>&1` → `087 state check (applied): OK`;
   `diff /root/087_state_before.txt /root/087_state_after.txt` must differ **only** in the NOTICE / OK / `LEGACY_BIRTH` / `PHASE4A_ROWS` lines,
   **never in a `FINGERPRINT` line** (in particular `sp_log_breeding_event_only`, `sp_void_event_only`, `sp_log_palpation_event_only`,
   `other_birth_overloads`, `birth_events_original_columns`).
7. **Read-only smoke test** (production, the owner's own account; counts only):

   ```sql
   SELECT sp_repro_births_get_config('5','<owner email>')->>'possible_duplicate_days' AS window_days,
          (SELECT count(*) FROM birth_events WHERE id_company = 5) AS births_company_5,
          (SELECT count(*) FROM repro_historical_births) AS historical_births;
   ```

   From a user who is **not** a member of company 5, `SELECT sp_repro_list_historical_births('5','<other company user>')` must **raise** `P0001`; and
   `SELECT sp_register_birth_event(5,'MACHO','BOVINO',NULL,NULL,NULL,CURRENT_DATE,NULL,NULL,NULL,NULL,NULL,'nobody@example.test')` must raise `P0001`
   **before writing anything** (the state check does this probe inside a read-only transaction). **Do not call a write tool in production** except with the
   owner's test company 3 "Rancho El Palomar" and its `9999…` animals; a registered birth creates a calf and cannot be deleted by a tool.
8. **Monitoring query for the review period** (read-only; run it weekly after 089): births with no reporter are the legacy NULL path.

   ```sql
   SELECT date_trunc('week', created_at) AS week, count(*) AS births, count(*) FILTER (WHERE reported_by_email IS NULL) AS without_reporter
     FROM birth_events WHERE created_at >= now() - interval '90 days' GROUP BY 1 ORDER BY 1;
   ```

   When `without_reporter` stays 0 after 089, the NULL e-mail path of `sp_register_birth_event` can be closed (backlog item; separate decision and PR).

**Rollback:** `$P -v apply=true -f /tmp/m087/087_rollback.sql > /root/087_rollback.txt 2>&1`, then the `-v expect=rolled_back` state check.
It drops nothing: the original body of `sp_register_birth_event` (md5 `8eaf6f52…`) is restored — the state check verifies the md5 — the 8 tools answer `disabled`,
and `birth_events.reported_by_email`, the tables and every row stay. Re-apply is the same command as step 5 and keeps the rows.

## Part 1b. LOCAL rehearsal on a copy with data (before production)

On the LOCAL `hosting3m_db` (daily restored from production, so it has the verified body). 087 needs 084 and 085 there too:

```bash
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
docker exec n8n-enterprise-db rm -rf /tmp/m087 && docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m087
# 084 and 085 first (skip each one already applied: its state check says so)
$P -v expect=before  -f /tmp/m087/087_state_check.sql > 087_local_before.txt 2>&1
$P -f /tmp/m087/087_repro_births.sql                                   # dry run
$P -v apply=true -f /tmp/m087/087_repro_births.sql
$P -v expect=applied -f /tmp/m087/087_state_check.sql > 087_local_after.txt 2>&1
diff 087_local_before.txt 087_local_after.txt                           # only NOTICE / OK / LEGACY_BIRTH / PHASE4A_ROWS lines
# rollback rehearsal, then re-apply (rows must survive: compare the PHASE4A_ROWS line)
$P -v apply=true -f /tmp/m087/087_rollback.sql
$P -v expect=rolled_back -f /tmp/m087/087_state_check.sql
$P -v apply=true -f /tmp/m087/087_repro_births.sql
$P -v expect=applied -f /tmp/m087/087_state_check.sql
```

The daily LOCAL restore (07:00) wipes what you applied there; that is expected.

## Part 2. n8n (`v6/MCP Server Cattle`) — only if Part 1 state check is `applied`

1. Download the production export of `v6/MCP Server Cattle`, take its fingerprint (`python3 -I ~/node_fingerprints.py`) and compare production against `main`
   (production can carry manual changes); stop if it does not match the expected *before* fingerprint.
2. In the editor: paste `repro_phase4_tools.json`, check the nodes are connected to `MCP Server Cattle`, **save and Publish**. `get_dam_reproductive_history` answers
   `function … does not exist` until 088 is applied: import it after 088. On LOCAL first, and **check the URL of the "MCP Cattle Management" node** of the chat / WhatsApp
   flows before testing (Rule 16 of the agro-erp `CLAUDE.md`): a LOCAL test must not reach production.
3. **Download again and verify with the *after* fingerprint** (the editor can leave a saved but unpublished version).
4. Test any parameterised query by **executing the node with real values** (numeric, empty, null and comma-containing text); every parameter is `$n::text` and `String(...)` in both layers.
5. Rollback: re-import the export of step 1 and publish.

## Part 3. Frontend

Nothing.

---

## Files and md5

| File | md5 |
|---|---|
| `087_repro_births.sql` | `9b6a37ff583cd1c05c619bd87f2d9bdc` |
| `087_tests.sql` | `dd64a49d3b6aa8547d890191e286892d` |
| `087_rollback.sql` | `23e723a27e02e38db3bf6ba183933a62` |
| `087_state_check.sql` | `d54a87ec1c444f474283bcf8aaaa6db8` |
| `repro_phase4_tools.json` | `177d47123840fbdad81d7fe11daae378` |

(Recompute with `md5sum` if any file is edited after this runbook was written. `084_*`, `085_*` and `086_*` have their own tables in their runbooks.)
