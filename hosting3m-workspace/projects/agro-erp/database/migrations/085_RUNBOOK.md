# Runbook — Reproduction tracking, phase 2: empadre (migration 085 + n8n tools)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**Requires migration 084.** 085 aborts at its first block if `fn_repro_ctx` / `vw_animal_effective_birth` are missing. 084 is **not**
applied in production yet, so the production order is: **084 (its runbook) → 085 → n8n phase 1 tools → n8n phase 2 tools**.

**What changes**
- **Database (085):** 3 new tables (`repro_empadre_config`, `repro_empadre_entries`, `repro_empadre_voids`; every row has `id_company`;
  entries and voids are append-only), 6 triggers on them, 7 internal helper functions and 8 `sp_*` functions. It writes **no rows**
  (a company without a config row uses the defaults 15 months / 300 kg). Nothing existing is altered, replaced or dropped:
  `sp_void_event`, `sp_register_birth_event`, `sp_log_breeding_event`, `sp_log_palpation_event`, the 084 objects, `crud_models` and
  the gateway are untouched (the state check fingerprints all of them).
- **n8n:** 7 `postgresTool` nodes added to `v6/MCP Server Cattle` (`workflows/09-MCP-Agent-Cattle/v6/repro-phase2/`). They stay
  invisible to the agent until the two system prompts list them (phase 5), so this phase changes no chat behaviour.
  `sp_repro_empadre_set_config` (ADMIN only) has **no** tool on purpose.
- **Frontend:** nothing.

⚠️ **Strict order: database → n8n.** If the tools reach n8n first they fail with `function sp_repro_… does not exist` (harmless today:
the agent does not know them). The database rollback drops nothing: the tools answer `{"status":"disabled"}`, so the reverse order is safe too.

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
memberships inside the transaction). They refuse to run if `T085` fixtures already exist.

> The commands below were **reconstructed from the description of the 084 run** (schema-only dump into a new database, copy
> `companys` and two users). Adjust the container / database names if yours differ.

1. **Create the throwaway database with the schema only** (from the LOCAL `hosting3m_db`, which is the daily copy of production):

   ```bash
   docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test085
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test085 -q'
   ```

2. **Copy `companys` and two users** (companies first; the tests pick the first two active non-palm companies and the first two users):

   ```bash
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test085 -q -v ON_ERROR_STOP=1'
   docker exec n8n-enterprise-db sh -c \
     "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
      | psql -U n8n_user -d hosting3m_test085 -c \"COPY public.users FROM STDIN\""
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test085 -c \
     "SELECT (SELECT count(*) FROM companys WHERE is_active) AS companies, (SELECT count(*) FROM users) AS users;"
   ```

   Check that the result shows at least 2 active companies **that are not palm** (`industry` other than `agricultura`) and 2 users. If
   `users` has foreign keys that the copy rejects, copy the rows it points to first. The users are real rows: keep this database
   local and drop it afterwards (step 5).

3. **Copy the test files INTO the container and run them from that directory.** `085_tests.sql` includes `084_repro_births_age.sql` and
   `085_repro_empadre.sql` with `\ir` (a path relative to the test file), so the whole `migrations` folder must be inside the container
   and the run must start from it. `-f` always reads a path **inside** the container; the host files are not visible to `psql`.

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m085
   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m085
   docker exec -w /tmp/m085 -i n8n-enterprise-db \
     psql -U n8n_user -d hosting3m_test085 -v ON_ERROR_STOP=1 -f /tmp/m085/085_tests.sql 2>&1 | tee 085_tests_output.txt
   ```

   Expected: one `OK` line per test and a final `passed | failed | total` with **`failed = 0`**, ending in
   `*** 085 tests: everything rolled back ***`. The tests load 084 and 085 inside their own transaction, so they work whether or not
   those migrations are already applied in the throwaway database. (`085_tests_output.txt` is a local file: do not commit it.)

4. **Isolation tests are the point of this run.** Parts A–H each contain `ISOLATION` / `raises P0001` checks: a member of company A gets
   an **error** (never rows) for company B on every tool, a stranger / blank e-mail / bad tenant is refused, a palm company raises
   `P0094` (skipped with a note if the database has no palm company), and the append-only and company-guard triggers refuse direct
   writes. Any `FAIL` line stops the rollout.

5. **Clean up** when done: `docker exec n8n-enterprise-db dropdb -U n8n_user hosting3m_test085`.

---

## Part 0. Baseline and files — **run on the VPS** (it writes to `/root`)

Everything in this part runs **on the VPS, in production**, as read-only checks; the files it writes go to `/root`. Do **not** run it
on your local machine (there `/root` does not exist or is not yours, and a LOCAL baseline says nothing about production).

1. Verify the files before copying them (md5 in the table at the end of this file):

   ```bash
   mkdir -p /root/m085 && cd /root/m085          # copy 085_* AND 084_repro_births_age.sql here (scp from your machine)
   md5sum 085_* 084_repro_births_age.sql
   ```

2. Copy into the container and take the **baseline** (read-only; saved to compare at the end):

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m085 && docker cp /root/m085 n8n-enterprise-db:/tmp/m085
   P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
   $P -v expect=before -f /tmp/m085/085_state_check.sql > /root/085_state_before.txt 2>&1
   tail -3 /root/085_state_before.txt        # expect: 085 state check (before): OK
   ```

   If it says *"migration 084 is not applied here"*, stop: apply 084 first with `084_RUNBOOK.md`.

3. Fingerprint script for the n8n part: `python3 -I ~/node_fingerprints.py <export.json>`.

## Part 1. Database (VPS, container `n8n-enterprise-db`, database `hosting3m_db`)

1. **Backup first** (085 only creates new objects, but take it anyway; size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db \
     > /root/backups/hosting3m_schema_pre085_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc \
     -t public.cattle_livestock -t public.cattle_breeding_events -t public.cattle_health_logs \
     -t public.cattle_weight_logs -t public.event_voids -t public.user_companies \
     hosting3m_db > /root/backups/hosting3m_repro_tables_pre085_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre085*
   ```

2. **State before** was taken in Part 0 (`/root/085_state_before.txt`, must end with `085 state check (before): OK`). Keep the `FINGERPRINT` lines.
3. **Dry run** (rolls back): `$P -f /tmp/m085/085_repro_empadre.sql > /root/085_dryrun.txt 2>&1` → `085: OK` and `DRY RUN`.
4. **Tests ran on the throwaway database** (section above), never here.
5. **Apply** (single transaction, `ON_ERROR_STOP`; the file also opens / commits its own transaction, so psql may print a harmless
   *"there is already a transaction in progress"* warning):

   ```bash
   $P --single-transaction -v apply=true -f /tmp/m085/085_repro_empadre.sql > /root/085_apply.txt 2>&1
   tail -5 /root/085_apply.txt     # expect: 085: OK  and  *** 085 COMMITTED ***
   ```

6. **State after:** `$P -v expect=applied -f /tmp/m085/085_state_check.sql > /root/085_state_after.txt 2>&1` → `085 state check (applied): OK`;
   `diff /root/085_state_before.txt /root/085_state_after.txt` must differ **only** in the NOTICE / OK / `EMPADRE_ROWS` lines, **never in a
   `FINGERPRINT` line** (in particular `sp_void_event_only`, `preexisting_repro_procedures` and `phase1_parser_helpers_view`).
7. **Read-only smoke test** (production, tenant 5, the owner's own account; counts only):

   ```sql
   SELECT (sp_repro_empadre_get_config('5','<owner email>')->>'min_age_months') AS min_age,
          (sp_repro_list_heifers_eligible_for_empadre('5','<owner email>','1')->>'eligible_total') AS eligible,
          (sp_repro_list_open_cows('5','<owner email>','90','1')->>'total') AS open_cows;
   ```

   and, from a user who is **not** a member of company 5, `SELECT sp_repro_list_open_cows('5','<other company user>')` must **raise** `P0001`.
   **Do not call a write tool in production** except with a test company and animals (the owner's test tenant 3 "Rancho El Palomar",
   `rfid_siniiga` `9999…`), and void the test entry afterwards.

**Rollback:** `$P --single-transaction -v apply=true -f /tmp/m085/085_rollback.sql > /root/085_rollback.txt 2>&1`, then
`-v expect=rolled_back` state check. It drops nothing: the 8 tools answer `disabled`; the tables **and any entries already recorded stay**
(they are the only copy of what staff reported). Re-apply is the same command as step 5 (`CREATE OR REPLACE` / `IF NOT EXISTS`) and keeps the rows.
Removing the tables would be a separate, explicit decision of the owner (with a backup first); this runbook never does it.

## Part 1b. LOCAL rehearsal on a copy with data (before production)

On the LOCAL `hosting3m_db` (daily restored from production, so it has real data). 085 needs 084 there too:

```bash
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
docker exec n8n-enterprise-db rm -rf /tmp/m085 && docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m085
# 084 first (skip if already applied: its state check says so)
$P -v expect=before  -f /tmp/m085/084_state_check.sql
$P --single-transaction -v apply=true -f /tmp/m085/084_repro_births_age.sql
$P -v expect=applied -f /tmp/m085/084_state_check.sql
# then 085
$P -v expect=before  -f /tmp/m085/085_state_check.sql > 085_local_before.txt 2>&1
$P -f /tmp/m085/085_repro_empadre.sql                                   # dry run
$P --single-transaction -v apply=true -f /tmp/m085/085_repro_empadre.sql
$P -v expect=applied -f /tmp/m085/085_state_check.sql > 085_local_after.txt 2>&1
diff 085_local_before.txt 085_local_after.txt                           # only NOTICE / OK / EMPADRE_ROWS lines
# rollback rehearsal, then re-apply (rows must survive: compare the EMPADRE_ROWS line)
$P --single-transaction -v apply=true -f /tmp/m085/085_rollback.sql
$P -v expect=rolled_back -f /tmp/m085/085_state_check.sql
$P --single-transaction -v apply=true -f /tmp/m085/085_repro_empadre.sql
$P -v expect=applied -f /tmp/m085/085_state_check.sql
```

The daily LOCAL restore (07:00) wipes what you applied there; that is expected.

## Part 2. n8n (`v6/MCP Server Cattle`) — only if Part 1 state check is `applied`

1. Download the production export of `v6/MCP Server Cattle` and take its fingerprint (`python3 -I ~/node_fingerprints.py`); stop if it does
   not match the expected *before* fingerprint (the phase 1 tools are a separate import, see `084_RUNBOOK.md`). Compare production against `main` first:
   production can carry manual changes.
2. In the editor: paste `repro_phase2_tools.json`, check the 7 nodes are connected to `MCP Server Cattle`, **save and Publish**.
   On LOCAL first, and **check the URL of the "MCP Cattle Management" node** of the chat / WhatsApp flows before testing (Rule 16 of the agro-erp
   `CLAUDE.md`): a LOCAL test must not reach production.
3. **Download again and verify with the *after* fingerprint** (the editor can leave a saved but unpublished version).
4. Rollback: re-import the export of step 1 and publish.

## Part 3. Frontend

Nothing. (The "only if 1 and 2 are OK" rule applies to later phases.)

---

## Files and md5

| File | md5 |
|---|---|
| `085_repro_empadre.sql` | `373c4fed4fcf04118cf6bfbd809150b3` |
| `085_tests.sql` | `2314c45f91dc9a877ad56cd6502a2b77` |
| `085_rollback.sql` | `22de2551e59db0f988207352a4682a31` |
| `085_state_check.sql` | `351ebc0efb03c65ea7c4456c018543ca` |
| `repro_phase2_tools.json` | `33b28f840fe0aed9098762794d9a7532` |

(Recompute with `md5sum` if any file is edited after this runbook was written. `084_repro_births_age.sql` has its own table in `084_RUNBOOK.md`.)
