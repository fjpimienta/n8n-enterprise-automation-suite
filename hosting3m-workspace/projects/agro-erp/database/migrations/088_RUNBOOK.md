# Runbook — Reproduction tracking, phase 4b: services linked to births, hardened service / void procedures, dam history (migration 088)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**Requires migrations 084, 085, 086 and 087.** 088 aborts at its first block if their helpers are missing, **and aborts if the live `sp_log_breeding_event`
(md5 `2c1ff0adf25284e069ebf46ddc3108f8`) or `sp_void_event` (md5 `c81f6faec5e61a28eca5d24b0f62a61c`) is not the production body verified on 2026-10-28.**
If it aborts with that message: **STOP** and compare the live body before doing anything else. Production order:
**084 → 085 → 086 → 087 → 088 → n8n tools → 089**.

**What changes**
- **Database (088):** `cattle_breeding_events.birth_event_id` (nullable FK to `birth_events`, additive, no backfill) with a **guard trigger**: from now on the only UPDATE the
  table accepts is setting that column from NULL to a birth of the **same company and same dam**, **once** (`P0097` for anything else, `P0096` for another company; an
  INSERT cannot carry a link; a voided service cannot be linked). 3 new functions (`fn_repro_gestation_bounds`, `fn_repro_link_birth_service`, the trigger function) and the
  read tool `sp_repro_get_dam_history`. It writes **no rows**.
- **Two existing procedures are replaced in place** (same signatures, `CREATE OR REPLACE`, not overloads):
  - `sp_log_breeding_event` (8 parameters): the reporter must be an **active member** (a NULL / blank / non-member e-mail raises `P0001`; every known caller — the MCP tool —
    always sends one, and there is no gateway model for it); the sire is resolved **inside the company only** (several matches → `{success:false, status:'ambiguous', candidates}`;
    resolves but not a `TORO` / `BECERRO_TORETE`, or the female herself → `{success:false, status:'rejected'}`; does not resolve → kept as free text + warning
    `sire_not_resolved`; a bull of **another** company cannot be told apart from an unknown name without a cross-company lookup, so it is the same warning, never a leak);
    artificial insemination without semen batch → warning `semen_batch_missing`; exact retry (same female, date, method, sire within 5 minutes, not voided) →
    `{success:true, duplicate_skipped:true}`. The existing errors (method, unknown / ambiguous / sold female) are unchanged.
  - `sp_void_event` (5 parameters): the voider must be an **active member** (NULL / blank / non-member raises `P0001`; its only caller, the MCP tool `void_event`, already
    checks membership); a service **linked to a birth** answers `{success:false, status:'rejected', code:'LINKED_TO_BIRTH', birth_event_id}`; the whitelist, one-void-per-event
    (`P0017`) and "side effects are not reversed" are unchanged.
- **Service ↔ birth link:** `sp_register_birth_event` (087) calls `fn_repro_link_birth_service` after a birth. It links **only when exactly one** non-voided, not-yet-linked service of the dam falls inside
  the plausible window; otherwise it leaves the service unlinked and the answer says why (`no_candidate` / `ambiguous`). Windows (days between service and birth; both name sets mapped,
  EQUINO = EQUIDO and OVINO = BORREGO): BOVINO 283 (238–328) · OVINO / BORREGO 152 (132–172) · EQUINO / EQUIDO 340 (295–385) · BUFALO 310 (280–340). **No old service is linked retroactively.**
- **n8n:** the tool `get_dam_reproductive_history` (in `repro_phase4_tools.json`, see `087_RUNBOOK.md`, Part 2). The existing `log_breeding_event` and `void_event` tools are **not edited**, but
  they now return the `success:false` answers above (not SQL errors) — Phase 5 must teach the prompt to relay `message` / `candidates` and show `warnings`.
- **Frontend:** nothing.

⚠️ **Behaviour you will notice:** after 088, `void_event` refuses a service that ended in a birth; to correct it, the birth has to be handled first (births cannot be voided today: backlog).

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
if their `T088` fixtures already exist **or if the two companies already have palpations** (the import-date flag counts them): use the schema-only copy.

> The commands below are the same **reconstructed** ones as in `085_RUNBOOK.md` / `086_RUNBOOK.md` (schema-only dump into a new database,
> copy `companys` and two users); replace them with the exact commands you use if they differ.

1. **Create the throwaway database with the schema only** (from the LOCAL `hosting3m_db`, the daily copy of production):

   ```bash
   docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test088
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test088 -q'
   ```

2. **Copy `companys` and two users:**

   ```bash
   docker exec n8n-enterprise-db sh -c \
     'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test088 -q -v ON_ERROR_STOP=1'
   docker exec n8n-enterprise-db sh -c \
     "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
      | psql -U n8n_user -d hosting3m_test088 -c \"COPY public.users FROM STDIN\""
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test088 -c \
     "SELECT (SELECT count(*) FROM companys WHERE is_active) AS companies, (SELECT count(*) FROM users) AS users;"
   ```

   At least 2 active companies that are **not** palm (`industry` other than `agricultura`) and 2 users.

3. **Copy the test files INTO the container and run them from that directory.** The test file includes the earlier migrations with `\ir`
   (a path relative to the test file), so the whole `migrations` folder must be inside the container and the run must start from it.

   ```bash
   docker exec n8n-enterprise-db rm -rf /tmp/m088
   docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m088
   docker exec -w /tmp/m088 -i n8n-enterprise-db \
     psql -U n8n_user -d hosting3m_test088 -v ON_ERROR_STOP=1 -f /tmp/m088/088_tests.sql 2>&1 | tee 088_tests_output.txt
   ```

   Expected: one `OK` line per test and a final `passed | failed | total` with **`failed = 0`**, ending in `*** 088 tests: everything rolled back ***`.
   (`088_tests_output.txt` is a local file: do not commit it.) Any `FAIL` line stops the rollout.

   **The run keeps going after a failed assertion**: after the fixtures are built, every assertion runs inside `pg_temp.t()`, which records an error (with its SQLSTATE) as a `FAIL`
   line instead of aborting, a tool call that raises is stored as `{"__error", "__sqlstate"}`, and psql rolls back only the failing statement (`ON_ERROR_ROLLBACK`). An `ERROR:` line
   printed *outside* the results table is an unexpected error in a fixture or helper statement - report it. The script still exits non-zero at the end when any assertion failed.
   (Why this was needed: `WHEN OTHERS` in PL/pgSQL does not catch `assert_failure`, SQLSTATE `P0004`, which the legacy procedures use for "ambiguous identifier".)

   **About a `WARNING: there is no transaction in progress` near the start of the output.** psql prints it when a `COMMIT` / `ROLLBACK` runs with no open transaction. Reading the
   included files, every one honours `embedded` and issues no `COMMIT` / `ROLLBACK` inside the tests' transaction, so I could not locate its source by reading alone; it is harmless
   **only if nothing was committed**, and the run proves it twice: the last test (`ran inside ONE transaction`) fails if the transaction id changed, and after the run this query must return 0:

   ```bash
   docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_test088 -tA -c "SELECT count(*) FROM cattle_livestock WHERE rfid_siniiga LIKE 'T0%'"
   ```

   If either check fails, stop and send the first 20 lines of the output.

4. **Clean up** when done: `docker exec n8n-enterprise-db dropdb -U n8n_user hosting3m_test088`.

**What the run proves.** Part A: the link (exactly one candidate, ambiguous = never guessed, voided and already-linked services excluded, window edges 238 / 328 days in and 237 / 329 out,
twins, the legacy NULL-e-mail path, BORREGO names, isolation of the linker). Part B: the guard trigger (the only accepted update, `P0097` / `P0096`). Part C: `sp_log_breeding_event`
(membership, sire ambiguous / not a bull / the female herself / unresolved / of another company, IA warnings, duplicate skip, unchanged errors, isolation). Part D: `sp_void_event` (membership, linked
service refused with the birth, one void per event, whitelist, no side effects). Part E: the dam history (all sections, ambiguity, expected calving, quality flags, isolation). Parts C – F contain
`ISOLATION` / fail-closed checks.

---

## Part 0. Baseline and files — **run on the VPS** (it writes to `/root`)

1. Verify the files (md5 in the table at the end): `mkdir -p /root/m088 && cd /root/m088` (copy `088_*` here) and `md5sum 088_*`.
2. Check the two production bodies, copy into the container and take the **baseline** (read-only):

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -c \
     "SELECT p.oid::regprocedure, md5(pg_get_functiondef(p.oid)) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('sp_log_breeding_event','sp_void_event');"
   #   expect sp_log_breeding_event 2c1ff0adf25284e069ebf46ddc3108f8 and sp_void_event c81f6faec5e61a28eca5d24b0f62a61c. Anything else: STOP.
   docker exec n8n-enterprise-db rm -rf /tmp/m088 && docker cp /root/m088 n8n-enterprise-db:/tmp/m088
   P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
   $P -v expect=before -f /tmp/m088/088_state_check.sql > /root/088_state_before.txt 2>&1
   tail -3 /root/088_state_before.txt        # expect: 088 state check (before): OK
   ```

## Part 1. Database

1. **Backup first** (size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db > /root/backups/hosting3m_schema_pre088_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc -t public.cattle_breeding_events -t public.event_voids -t public.birth_events \
     hosting3m_db > /root/backups/hosting3m_services_tables_pre088_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre088*
   ```

2. **State before** was taken in Part 0. Keep its `FINGERPRINT`, `LEGACY_BREEDING` / `LEGACY_VOID` lines.
3. **Dry run:** `$P -f /tmp/m088/088_repro_services.sql > /root/088_dryrun.txt 2>&1` → `088: OK` and `DRY RUN`.
4. **Tests ran on the throwaway database**, never here.
5. **Apply:** `$P -v apply=true -f /tmp/m088/088_repro_services.sql > /root/088_apply.txt 2>&1`; `tail -5` must show `088: OK` and `*** 088 COMMITTED ***`.
6. **State after:** `$P -v expect=applied -f /tmp/m088/088_state_check.sql > /root/088_state_after.txt 2>&1` → `088 state check (applied): OK`; `diff` of before / after must differ
   **only** in NOTICE / OK / `LEGACY_*` / `PHASE4B_ROWS` lines, **never in a `FINGERPRINT` line**.
7. **Read-only smoke test:** `SELECT sp_repro_get_dam_history('5','<owner email>','<a real arete SINIIGA of company 5>')->'quality_flags';` (read-only). From a user who is **not** a member of company 5 it must
   **raise** `P0001`. The state check also proves, inside a read-only transaction, that `sp_log_breeding_event` and `sp_void_event` refuse a non-member / NULL e-mail before doing anything.
   **Do not call a write tool in production** except with the owner's test company 3 and its `9999…` animals.
8. **Check what the link did** (read-only, after the first real births): `SELECT count(*) FILTER (WHERE birth_event_id IS NOT NULL) AS linked, count(*) AS services FROM cattle_breeding_events;`

**Rollback:** `$P -v apply=true -f /tmp/m088/088_rollback.sql > /root/088_rollback.txt 2>&1`, then `-v expect=rolled_back`. It drops nothing: the **original bodies**
of both procedures are restored (the state check verifies their md5), the history tool answers `disabled`, and the column, the guard trigger, the helpers and **every link already made stay**
(a link is a fact about a birth; after the rollback `sp_void_event` no longer knows the "linked" rule, but the guard trigger still blocks any other change of a service row). Re-apply keeps the links.

## Part 1b. LOCAL rehearsal on a copy with data

Same shape as `087_RUNBOOK.md` Part 1b with `/tmp/m088`: 084 – 087 first (skip each one already applied), then `088_state_check.sql -v expect=before`, the dry run, the apply, `expect=applied`, the
`diff`, the rollback, `expect=rolled_back`, the re-apply and `expect=applied`. Compare the `PHASE4B_ROWS` line: it must be identical after rollback + re-apply.

### Smoke script on the LOCAL copy (tenant 5) — `087_088_smoke_local.sql`

> ⚠️ **LOCAL ONLY. Never run it against production.** Part B writes (births, calves, a service, a historical birth) inside one transaction that ends in `ROLLBACK`; even so, a
> rolled-back write still takes locks and fires triggers, and SQL cannot tell the local copy from production - the script prints a "WHERE AM I" block first: read it.

After 087 and 088 are applied and verified on the local `hosting3m_db`, run the real tools once against tenant 5's data (no e-mail is hardcoded: it picks a real ADMIN member of tenant 5 itself and
**never prints an e-mail**; every answer goes through a scrubber that hides any `*email*` key and any text containing `@`):

```bash
docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -v ON_ERROR_STOP=1   < hosting3m-workspace/projects/agro-erp/database/migrations/087_088_smoke_local.sql > /tmp/smoke_087_088.txt 2>&1
```

(no `--single-transaction`; the output is plain text). It does **not** need 089.
- **Part A (`BEGIN READ ONLY` ... `ROLLBACK`):** births config defaults; the dam history of a PREÑADA dam with a stale imported palpation, of a VACÍA dam, and of a **duplicated fire number** (must answer
  `ambiguous` with candidates and no history); `births_batch_preview` with a valid, an ambiguous, a not_found and (if one exists) a possible_duplicate line; the historical list.
- **Part B (one transaction, `ROLLBACK` at the end):** a single birth, its exact retry (`duplicate_skipped`), the same dam again (`possible_duplicate`, then with `force`), the service of that dam linking to the birth
  (built inside the transaction with `sp_log_breeding_event`), the 50-line cap with 51 lines, a two-line batch (and its retry, and a batch with an ambiguous line that writes nothing), a historical birth and its void,
  and a non-member user / a wrong tenant / a non-numeric tenant / the legacy procedure with a non-member e-mail all raising.
- **The proof:** it prints the counts (births, calves, linked services, historical births and voids, weights, voids, a checksum of tenant 5's statuses) **before** and **after** the `ROLLBACK`, and **raises an error (psql exits non-zero) if they differ**.
  If the script stops earlier with an error, the connection closes and PostgreSQL rolls the open transaction back; run the counts check by hand to be sure.
- Whatever it cannot find in the local data it prints as `skipped: <what is missing>` (no PREÑADA dam on the stale date, no duplicated fire number, no registered birth for the possible_duplicate line, fewer than five "fresh" dams, ...);
  nothing is invented except one deliberately non-existent identifier for the not_found line, which it first checks matches nothing. `EXPECT OK` / `EXPECT MISMATCH` lines are information, not failures.
- If a statement fails, PostgreSQL's error context may print the statement text, e-mail included: read it before pasting it anywhere.

## Part 2. n8n

Import `get_dam_reproductive_history` as described in `087_RUNBOOK.md`, Part 2 (the whole file is one import; the 7 tools of 087 need 087, this one needs 088). **Do not edit** `log_breeding_event` / `void_event`.

## Part 3. Frontend

Nothing.

---

## Files and md5

| File | md5 |
|---|---|
| `088_repro_services.sql` | `575e793936da9b46be3beee3651b795a` |
| `088_tests.sql` | `dbc1935d7b7c830be47ca80b64f4d8d7` |
| `088_rollback.sql` | `6cf3fedc9da852523e5ced1ff789dcdc` |
| `088_state_check.sql` | `beae0c4e4574e7895b5109f81b307e08` |
| `087_088_smoke_local.sql` | `5f883c38aa4566e1eff8f5401edd9354` |

(Recompute with `md5sum` if any file is edited after this runbook was written.)
