# Runbook — Reproduction tracking, phase 3: palpation condition, palpations due, upcoming calvings (migration 086 + n8n tools + tenant-5 seed)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**Requires migrations 084 and 085.** 086 aborts at its first block if either is missing. Neither is applied in production yet, so the
production order is: **084 (its runbook) → 085 (its runbook) → 086 → n8n phase 1 tools → n8n phase 2 tools → n8n phase 3 tools → tenant-5 seed**.
The seed is a **separate file that only the owner applies**, after 086 is applied and verified.

**What changes**
- **Database (086):** 2 new tables (`repro_condition_codes`, `palpation_repro_details`; every row has `id_company`; the details are
  append-only and a condition is only allowed on a VACÍA result), 3 triggers on the details, 5 internal helper functions and 5 `sp_*`
  functions. It writes **no rows**. Nothing existing is altered, replaced or dropped: `sp_log_palpation_event` (which the new wrapper
  *calls*), `sp_void_event`, `sp_register_birth_event`, `sp_log_breeding_event`, the 084 and 085 objects, `vw_cattle_kpi`,
  `crud_models` and the gateway are untouched (the state check fingerprints all of them).
- **n8n:** 4 `postgresTool` nodes added to `v6/MCP Server Cattle` (`workflows/09-MCP-Agent-Cattle/v6/repro-phase3/`). They stay
  invisible to the agent until the two system prompts list them (phase 5). The existing `log_palpation_event` and
  `log_palpation_event_batch` tools are **not modified**. `sp_repro_condition_code_set` (ADMIN only) has **no** tool on purpose.
- **Seed (separate, owner only):** `086_seed_tenant5_uterine_codes.sql` inserts 4 rows for company 5: UNE → ESTATICA; UTCL1, UTCL2,
  UTCL3 → CICLANDO. `RP`, `UTC2`, `NR`, `No apto` and `Matriz ocupada` stay UNMAPPED.
- **Frontend:** nothing.

⚠️ **Strict order: database → n8n.** If the tools reach n8n first they fail with `function sp_repro_… does not exist` (harmless today:
the agent does not know them). The database rollback drops nothing: the tools answer `{"status":"disabled"}`, so the reverse order is safe too.

⚠️ **A palpation logged through the new tool keeps the condition it had when it was logged** (`palpation_repro_details` is a snapshot,
append-only). Confirming or changing a code later does **not** rewrite old rows; there is no backfill of the 214 bulk-loaded
palpations of company 5 in this phase (they keep their raw `condicion_utero` in the health log; `list_unmapped_uterine_codes` reads it).

Nothing in this runbook is run by the assistant. Production is touched only by the owner, with the steps below.

Conventions used below
```bash
# On the VPS (production)                                  # On your machine (LOCAL)
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```

---

## Test database (LOCAL only — never production)

The tests insert fixtures and roll everything back, but they still must never run against production. They need a database with the
**real schema** and, at minimum, **two ACTIVE non-palm companies and two users** (they pick the first two of each, and arrange
memberships inside the transaction). They refuse to run if `T086` fixtures already exist **or if the two companies already have
palpations** (the import-date test counts them): use a schema-only copy, as below, not a copy with data.

> The commands below were **reconstructed from the description of the 084 run** (schema-only dump into a new database, copy
> `companys` and two users), the same as in `085_RUNBOOK.md`. Adjust the container / database names if yours differ.

1. **Create the throwaway database with the schema only** (from the LOCAL `hosting3m_db`, which is the daily copy of production):

   ```bash
   docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test086
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test086 -q'
   ```

2. **Copy `companys` and two users:**

   ```bash
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test086 -q -v ON_ERROR_STOP=1'
   docker exec n8n-enterprise-db sh -c \
     "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
      | psql -U n8n_user -d hosting3m_test086 -c \"COPY public.users FROM STDIN\""
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test086 -c \
     "SELECT (SELECT count(*) FROM companys WHERE is_active) AS companies, (SELECT count(*) FROM users) AS users;"
   ```

   At least 2 active companies that are **not** palm (`industry` other than `agricultura`) and 2 users. If `users` has foreign keys that the
   copy rejects, copy the rows it points to first. Keep this database local and drop it afterwards (step 5).

3. **Copy the test files INTO the container and run them from that directory.** `086_tests.sql` includes `084_repro_births_age.sql`,
   `085_repro_empadre.sql` and `086_repro_palpation.sql` with `\ir` (a path relative to the test file), so the whole `migrations` folder
   must be inside the container and the run must start from it. `-f` always reads a path **inside** the container.

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m086
   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m086
   docker exec -w /tmp/m086 -i n8n-enterprise-db \
     psql -U n8n_user -d hosting3m_test086 -v ON_ERROR_STOP=1 -f /tmp/m086/086_tests.sql 2>&1 | tee 086_tests_output.txt
   ```

   Expected: one `OK` line per test and a final `passed | failed | total` with **`failed = 0`**, ending in
   `*** 086 tests: everything rolled back ***`. The tests load 084, 085 and 086 inside their own transaction, so they work whether or not
   those migrations are already applied in the throwaway database. (`086_tests_output.txt` is a local file: do not commit it.)

4. **What the run proves.** Part A: the parser (UNE, UNE/NR, UTCL2/OI, `VACIA UNE`, `No apto`, N/A, empty, explicit words, never raises).
   Part C: the wrapper, including the all-or-nothing rejection, the idempotent retry and the cross-company attempt. Parts B, C, E, F, G, H
   each contain `ISOLATION` / `raises P0001` checks: a member of company A gets an **error** (never rows) for company B on every tool,
   company B never sees A's mapping, a stranger / blank e-mail / bad tenant is refused, a palm company raises `P0094` (skipped with a note
   if the database has no palm company), and the append-only and company-guard triggers refuse direct writes. Any `FAIL` line stops the rollout.

5. **Clean up** when done: `docker exec n8n-enterprise-db dropdb -U n8n_user hosting3m_test086`.

---

## Part 0. Baseline and files — **run on the VPS** (it writes to `/root`)

Everything in this part runs **on the VPS, in production**, as read-only checks; the files it writes go to `/root`. Do **not** run it
on your local machine (there `/root` does not exist or is not yours, and a LOCAL baseline says nothing about production).

1. Verify the files before copying them (md5 in the table at the end of this file):

   ```bash
   mkdir -p /root/m086 && cd /root/m086          # copy 086_* (and, if still pending, 084_* and 085_*) here (scp from your machine)
   md5sum 086_*
   ```

2. Copy into the container and take the **baseline** (read-only; saved to compare at the end):

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m086 && docker cp /root/m086 n8n-enterprise-db:/tmp/m086
   P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
   $P -v expect=before -f /tmp/m086/086_state_check.sql > /root/086_state_before.txt 2>&1
   tail -3 /root/086_state_before.txt        # expect: 086 state check (before): OK
   ```

   If it says *"migration 084 / 085 is not applied here"*, stop: apply them first with `084_RUNBOOK.md` and `085_RUNBOOK.md`.

3. Fingerprint script for the n8n part: `python3 -I ~/node_fingerprints.py <export.json>`.

## Part 1. Database (VPS, container `n8n-enterprise-db`, database `hosting3m_db`)

1. **Backup first** (086 only creates new objects, but take it anyway; size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db \
     > /root/backups/hosting3m_schema_pre086_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc \
     -t public.cattle_livestock -t public.cattle_health_logs -t public.cattle_breeding_events \
     -t public.event_voids -t public.user_companies -t public.companys \
     hosting3m_db > /root/backups/hosting3m_palpation_tables_pre086_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre086*
   ```

2. **State before** was taken in Part 0 (`/root/086_state_before.txt`, must end with `086 state check (before): OK`). Keep the `FINGERPRINT` lines.
3. **Dry run** (rolls back): `$P -f /tmp/m086/086_repro_palpation.sql > /root/086_dryrun.txt 2>&1` → `086: OK` and `DRY RUN`.
4. **Tests ran on the throwaway database** (section above), never here.
5. **Apply** (single transaction, `ON_ERROR_STOP`; the file also opens / commits its own transaction, so psql may print a harmless
   *"there is already a transaction in progress"* warning):

   ```bash
   $P --single-transaction -v apply=true -f /tmp/m086/086_repro_palpation.sql > /root/086_apply.txt 2>&1
   tail -5 /root/086_apply.txt     # expect: 086: OK  and  *** 086 COMMITTED ***
   ```

6. **State after:** `$P -v expect=applied -f /tmp/m086/086_state_check.sql > /root/086_state_after.txt 2>&1` → `086 state check (applied): OK`;
   `diff /root/086_state_before.txt /root/086_state_after.txt` must differ **only** in the NOTICE / OK / `PHASE3_ROWS` lines, **never in a
   `FINGERPRINT` line** (in particular `sp_log_palpation_event_only`, `preexisting_repro_procedures`, `phase1_parser_helpers_view`,
   `phase2_empadre_functions` and `phase2_empadre_rows`).
7. **Read-only smoke test** (production, tenant 5, the owner's own account; counts and flags only — no write tool):

   ```sql
   SELECT (sp_repro_list_palpation_due('5','<owner email>','90','1')->>'total')                    AS due_total,
          (sp_repro_list_palpation_due('5','<owner email>','90','1')->'stale_import_date')         AS stale_import,
          (sp_repro_list_upcoming_calvings('5','<owner email>','60','1')->>'stale_data_total')     AS calvings_stale,
          (sp_repro_list_upcoming_calvings('5','<owner email>','60','1')->>'upcoming_total')       AS calvings_upcoming,
          (sp_repro_list_unmapped_uterine_codes('5','<owner email>')->>'unmapped_total')           AS unmapped_codes;
   ```

   Expected from the measurements of 2026-10-27 (tenant 5): the 214 bulk-loaded palpations share **2023-07-20**, so `stale_import.flag`
   is `true` with that date; `calvings_stale` is high (most of the 82 PREÑADA cows) and `calvings_upcoming` is low; before the seed
   `unmapped_codes` counts every code, after the seed it no longer lists `UNE`, `UTCL1`, `UTCL2`, `UTCL3`. From a user who is **not** a
   member of company 5, `SELECT sp_repro_list_palpation_due('5','<other company user>')` must **raise** `P0001`.
   **Do not call `sp_repro_log_palpation_batch` in production** except with a test company and animals (the owner's test tenant 3
   "Rancho El Palomar", `rfid_siniiga` `9999…`): it changes `current_status` through the existing procedure and the details are
   append-only (a test palpation cannot be deleted, only left as test data).

**Rollback:** `$P --single-transaction -v apply=true -f /tmp/m086/086_rollback.sql > /root/086_rollback.txt 2>&1`, then
`-v expect=rolled_back` state check. It drops nothing: the 5 procedures answer `disabled`; the tables **and any rows already recorded stay**
(the details are the only copy of what staff reported). The existing palpation tools keep working throughout. Re-apply is the same
command as step 5 (`CREATE OR REPLACE` / `IF NOT EXISTS`) and keeps the rows. Removing the tables would be a separate, explicit decision of
the owner (with a backup first); this runbook never does it.

## Part 1b. LOCAL rehearsal on a copy with data (before production)

On the LOCAL `hosting3m_db` (daily restored from production, so it has real data). 086 needs 084 and 085 there too:

```bash
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
docker exec n8n-enterprise-db rm -rf /tmp/m086 && docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m086
# 084 and 085 first (skip each one that is already applied: its state check says so)
$P -v expect=before  -f /tmp/m086/084_state_check.sql
$P --single-transaction -v apply=true -f /tmp/m086/084_repro_births_age.sql
$P -v expect=before  -f /tmp/m086/085_state_check.sql
$P --single-transaction -v apply=true -f /tmp/m086/085_repro_empadre.sql
# then 086
$P -v expect=before  -f /tmp/m086/086_state_check.sql > 086_local_before.txt 2>&1
$P -f /tmp/m086/086_repro_palpation.sql                                   # dry run
$P --single-transaction -v apply=true -f /tmp/m086/086_repro_palpation.sql
$P -v expect=applied -f /tmp/m086/086_state_check.sql > 086_local_after.txt 2>&1
diff 086_local_before.txt 086_local_after.txt                           # only NOTICE / OK / PHASE3_ROWS lines
# rollback rehearsal, then re-apply (rows must survive: compare the PHASE3_ROWS line)
$P --single-transaction -v apply=true -f /tmp/m086/086_rollback.sql
$P -v expect=rolled_back -f /tmp/m086/086_state_check.sql
$P --single-transaction -v apply=true -f /tmp/m086/086_repro_palpation.sql
$P -v expect=applied -f /tmp/m086/086_state_check.sql
```

Then rehearse the **seed** on the same copy (see Part 4) and run the read-only smoke test of Part 1 step 7 against real data
(tenant 5 exists in the LOCAL copy). The daily LOCAL restore (07:00) wipes what you applied there; that is expected.

## Part 2. n8n (`v6/MCP Server Cattle`) — only if Part 1 state check is `applied`

1. Download the production export of `v6/MCP Server Cattle` and take its fingerprint (`python3 -I ~/node_fingerprints.py`); stop if it does
   not match the expected *before* fingerprint (the phase 1 and 2 tools are separate imports, see `084_RUNBOOK.md` / `085_RUNBOOK.md`).
   Compare production against `main` first: production can carry manual changes.
2. In the editor: paste `repro_phase3_tools.json`, check the 4 nodes are connected to `MCP Server Cattle`, **save and Publish**.
   On LOCAL first, and **check the URL of the "MCP Cattle Management" node** of the chat / WhatsApp flows before testing (Rule 16 of the agro-erp
   `CLAUDE.md`): a LOCAL test must not reach production.
3. **Download again and verify with the *after* fingerprint** (the editor can leave a saved but unpublished version).
4. Rollback: re-import the export of step 1 and publish.
5. Per the project rule for tool nodes in n8n 2.x, test any new parameterised query by **executing the node with real values** (numeric,
   empty, null and comma-containing text), not only with prepared SQL: every parameter here is `$n::text` and `String(...)` in both layers.

## Part 3. Frontend

Nothing. (The "only if 1 and 2 are OK" rule applies to later phases.)

## Part 4. Tenant-5 uterine-code seed (owner only, after Part 1 is `applied`)

`086_seed_tenant5_uterine_codes.sql` is data, not schema, and is applied separately. It only inserts 4 rows for company 5
(`ON CONFLICT DO NOTHING`: an existing row is never overwritten), aborts if 086 is not applied or company 5 is missing / not a livestock company, and is a dry
run unless `-v apply=true`. `confirmed_by` records who confirmed the mapping with the veterinarians.

```bash
# in the container, from the folder that holds the files
$P -v confirmed_by='<owner email>' -f /tmp/m086/086_seed_tenant5_uterine_codes.sql                   # dry run: shows BEFORE / AFTER
$P --single-transaction -v confirmed_by='<owner email>' -v apply=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql
$P -c "SELECT code, repro_condition, source, confirmed_by FROM repro_condition_codes WHERE id_company = 5 ORDER BY code;"   # 4 rows
```

Check: the `rows of OTHER companies` section is empty (or unchanged), and `sp_repro_list_unmapped_uterine_codes('5','<owner email>')` no longer
lists UNE / UTCL1..3 but still lists `NR`, `RP`, `UTC2`, `NO APTO`, `MATRIZ OCUPADA` (the vets' ambiguous answers).

**Undo (only the 4 seed rows, by exact key and source; take a backup of `repro_condition_codes` first):**
`$P -v confirmed_by='<owner email>' -v undo=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql` (dry run), then add `-v apply=true`.
Palpations already logged keep the condition they were given.

---

## Files and md5

| File | md5 |
|---|---|
| `086_repro_palpation.sql` | `3f3acd079cffefb6393d27f3221ba546` |
| `086_tests.sql` | `7da15337f709221ee04f58047a5d77b0` |
| `086_rollback.sql` | `1875de6dfd2c1bda4f7ee3045f7ce516` |
| `086_state_check.sql` | `0d31f3376a8a8286256d705d1e2d9e05` |
| `086_seed_tenant5_uterine_codes.sql` | `4cb75d7bb9dd56746d3a66966cce89d2` |
| `repro_phase3_tools.json` | `41b09665d423afb6851f2032de5bc24a` |

(Recompute with `md5sum` if any file is edited after this runbook was written. `084_*` and `085_*` have their own tables in `084_RUNBOOK.md` / `085_RUNBOOK.md`.)
