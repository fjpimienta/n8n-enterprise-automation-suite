# Local rehearsal of the reproduction rollout

A dress rehearsal, in the **LOCAL** container `n8n-enterprise-db`, of `docs/REPRO_PRODUCTION_RUNBOOK.md` steps 2 and 3, plus the QA fixtures dry run and the `list_lots` diff.
It never touches the VPS, production or n8n. **The rehearsal scripts have not been run by their author** (they need your local database): the first run is yours. `test_rehearsal_helpers.sh` (offline, no database) has been run.

> ⚠️ **Do not use the local `hosting3m_db` for the rehearsal.** The local copy is **not a clean base**: objects of 084-090 (new functions and tables) survive the daily local refresh while replaced procedures and tables are restored to the production state, so the state checks find no known state and the rollback script cannot help. (This is **inferred from three observations on 2026-10-28, not a documented behaviour of the refresh tool**: see "Evidence" at the end.) The scripts **refuse** `hosting3m_db`. Use a **fresh database restored from a production dump** (next section).

## Create the rehearsal database (once; from a production dump)
You need a custom-format dump of the production `hosting3m_db`, for example the one taken in Step 1 of the runbook (taken on 2026-10-28: 1088844 bytes, 1053 TOC entries). The name `hosting3m_rehearsal` is only an example: any name matching `^hosting3m_[a-z0-9_]+$` other than `hosting3m_db` works.
```bash
# 1. create the empty database (run on the postgres database of the local container)
docker exec n8n-enterprise-db psql -U n8n_user -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE hosting3m_rehearsal OWNER n8n_user"

# 2. copy the dump into the container
: "${DUMP_FILE:?set DUMP_FILE to the path of the production dump on this machine}"
docker cp "$DUMP_FILE" n8n-enterprise-db:/tmp/hosting3m_rehearsal.dump

# 3. restore it (pg_restore exits non-zero when it hits an error: read what it prints before going on)
docker exec n8n-enterprise-db pg_restore -U n8n_user -d hosting3m_rehearsal --no-owner --no-privileges /tmp/hosting3m_rehearsal.dump

# 4. verify that it is a production base with none of 084-090
docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_rehearsal -X -v ON_ERROR_STOP=1 -f - <<'SQL'
SELECT (SELECT count(*) FROM public.cattle_livestock) AS animals,
       (SELECT count(*) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname ~ '^(sp_repro_|fn_repro_|fn_uterine_split|fn_parse_uterine_code|fn_estimate_birth_from_fire_number|fn_fire_number_shape|fn_is_placeholder_birth_date|fn_trg_empadre|fn_trg_palp|fn_trg_hist|fn_trg_breeding)') AS repro_functions;
SQL
```
**Expected for a production dump taken on 2026-10-28: `animals = 644` and `repro_functions = 0`.** If `repro_functions` is not 0 the base already holds objects of 084-090: do not use it.

## Run it
```bash
cd workflows/09-MCP-Agent-Cattle/v6/repro-phase5/rehearsal
REHEARSAL_DB=hosting3m_rehearsal bash rehearse_local.sh --i-know-this-is-local            # applies 084-090 and both seeds on the rehearsal database
REHEARSAL_DB=hosting3m_rehearsal bash rehearse_local_rollback.sh --i-know-this-is-local   # undoes it (seed undos, then the rollbacks in reverse order)
bash test_rehearsal_helpers.sh                                                              # offline tests of the helpers (no database)
```
Without `REHEARSAL_DB` the default is `hosting3m_db`, which is **refused** with a message pointing here. Dropping the rehearsal database afterwards is up to you; the scripts never delete anything.
Other environment: `CONFIRMED_BY_086` (default `veterinarios del rancho (interpretacion verbal, nombre pendiente)`), `OWNER_EMAIL` (default: a real active member of company 5, found read-only and never printed), `STAMP`, `REHEARSAL_OUT` (default `/tmp/rehearsal`).

**Starting state.** The first step of every migration is `state_check` with `expect=before`; if that fails the script tries `expect=rolled_back`, so you can run the rehearsal again right after the rollback script. If a migration is already **applied** the rehearsal stops: use a fresh database restored from a production dump (above), or run the rollback script first if only this rehearsal applied it.

## What it does (one output file per step: `/tmp/rehearsal/NN_step.txt`; the first failure stops it)
0. **Guard** (first action of both scripts): refuses unless `--i-know-this-is-local` is given, you are not root, `REHEARSAL_DB` is valid (`^hosting3m_[a-z0-9_]+$`; `postgres`, `template0`, `template1` and `hosting3m_db` are rejected) **and exists** in the container, the docker daemon is a **local socket**, the container is `n8n-enterprise-db`, and the **local-only marker database** `n8n_db_prod_clone` exists in the cluster. It prints the database host and **the database the run will write to**. *Why so many layers:* the runbook's `P` string (container and database names) is identical on the VPS and locally, so names alone cannot tell them apart.
1. Extracts the runbook's **variables block verbatim** (`# repro_vars.sh` ... ), sources it (so its `need()` is the one the runbook uses), points `P` at `REHEARSAL_DB` and exercises `need()` (rejects empty / unset / angle-bracket / `FILL` values).
2. (a) `md5sum` of the 23 files of 084-090 against the runbook table.
3. (b) For 084, 085, 086, 087, 088, 090 in order: `state_check expect=before` → dry run → apply → `expect=applied` → the **FINGERPRINTS** rows before and after must be identical.
4. (c) The 086 seed and the 090 seed **back to back**, dry run first and then apply (the 090 seed with `capataz (sin confirmacion veterinaria)`; its dry run must report 0 differences in other companies).
5. (d) The step 3 verify SELECTs: the 9-row SELECT of the runbook plus an assertion that all 9 rows have the expected values, and the `meanings_configured` / `UTC2 known_pending` check through the tool.
6. (e) `qa_fixtures.sql -v run=2` in **dry run only** (this script never applies the fixtures).
7. (f) `list_lots_diff.py` for tenant 5 (read-only): old = the MCP export of `COMMIT_BEFORE_PHASE5`, new = the repo file; it reports `rows_old`, `rows_new`, `only_in_old`, `only_in_new` and requires equal rows and zeros. (The script only generates SQL; it does not name any database.)
8. (g) A **summary table** (printed even when a step fails).

## How to read the summary
```
== SUMMARY (database hosting3m_rehearsal; output files in /tmp/rehearsal) ==
NN  STEP                                       RESULT
01  need_selftest                              OK
...
```
`OK` = the step passed. `SKIP` = the step found nothing to do (rollback script only: a migration or seed that was not applied). `FAIL` = it stopped there; the last 20 lines are printed and the full output is in the file named in the line `-> NN_step.txt`. Later steps did not run. The last line says how many steps ran and how many failed.

## What it does NOT test
- Anything that runs on the **VPS**: the `/root/...` paths, `docker cp` from `/root/mNNN`, the human `APPLY` gates (replaced here by output checks), running as root.
- The **backup** (step 1: `df`, `pg_dump`, the copy off the VPS).
- The **n8n import** (steps 4c, 4d, 5, 6b): exports, `compare_workflow_export.py` against a live export, publishing.
- The **gateway `curl`** and the 089 step (it is not applied here).
- The **QA dialogs** and the tool-selection measure, and the QA preconditions of step 6.0 (tester memberships, WhatsApp phone, selected company).
- The post-step-2 smoke check with `COMPANY5_ARETE` (not in this rehearsal).

## Things to know
- `/tmp/rehearsal/list_lots_diff.sql` contains a real member's e-mail (the diff compares per member). Delete it when you are done; the scripts never delete anything.
- The scripts copy the migrations folder into a **new** folder of the container, `/tmp/reh_STAMP`; nothing is removed (no `rm -rf` anywhere).
- The rollbacks of 084-090 keep their tables, columns and helpers **by design**: "back as it was" means the old behaviour, not an identical schema. A truly clean start is a **new database restored from a production dump**, not the rollback and not the daily local refresh.
- The restored dump holds real client data (companies 5, 6 ...). The rehearsal writes only the migration objects and the 9 seed rows of company 5 into `REHEARSAL_DB`; the fixtures are dry run only. The seed undos delete only the rows the seeds inserted.

## Evidence
"The local refresh leaves a mixed state" is **inferred from three observations made on 2026-10-28**. It is **not** a documented behaviour of the refresh tool: its script (`~/scripts/backup_postgres_vps_to_local.sh`) lives outside this repository and was not read for this rehearsal.
1. The local `hosting3m_db` held objects of 084-090 (new functions and tables) that are **absent** from the production dump, while the tables and the replaced procedures that **are** in the dump were back in the production state.
2. On that mixed base the state checks found **no known state** (`before`, `applied` or `rolled_back`), so the rehearsal could not start and the rollback script could not help.
3. A **fresh database restored from a production dump** (`hosting3m_rehearsal`) ran the whole sequence cleanly:

| Run | Script | Result |
|---|---|---|
| 1 | `rehearse_local.sh` (fresh base) | **42 of 42** steps OK |
| 2 | `rehearse_local_rollback.sh` | **10 of 10** steps OK |
| 3 | `rehearse_local.sh` again (re-apply from the `rolled_back` state) | **42 of 42** steps OK |

The dump used was taken on **production on 2026-10-28**: 1088844 bytes, 1053 TOC entries (`pg_restore --list`), 35 GB free on the VPS at the time (Step 1a of `docs/REPRO_PRODUCTION_RUNBOOK.md`). The step counts are the lines of the summary table: 4 setup steps, 5 per migration for 6 migrations, 4 seed steps, 2 verifications, the fixtures dry run and the `list_lots` diff (42); and 2 setup steps, 2 seed undos and 6 rollbacks (10).
