> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status (reported by the owner, 2026-11-18, CDMX):** migration 108 is **applied and enabled in production**. It was applied at 13:07, rolled back at 13:23, and re-enabled with `108_reenable.sql` at 13:52; the production checks of Part 3 passed **7/7** at 13:54. The full record, with times, is in "Production execution record" below. Two decisions are still open (see "Open items"). This runbook was otherwise tested on LOCAL only. No frontend in this change.
> Part 2 (n8n) changes **no node**: it is a verification of the production `v6/CRUD` workflow and a **PRECONDITION OF THE APPLY of Part 1**: it must be recorded as `RESULT: ACCEPTED` and five `PRESENT` lines **before** step 7 of Part 1. If the production `Build Query` does not inject `x-tenant-id`, the two new models would be readable across companies from the apply until the rollback.
> The Part 0 facts were verified in production by read-only queries on 2026-11-18 (reported by Francisco). They must be re-run before Part 1.

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

## Production execution record (2026-11-18, America/Mexico_City)

Reported by the owner. All times are CDMX. Only counts and fingerprints are recorded: no row, token, user name or host.

| Time | Step | Result |
|---|---|---|
| before 13:07 | Part 1 step 1, backup | verified; md5 `a40ddb802de73820dbc25b664ce94048`; a copy kept **outside the VPS** |
| before 13:07 | Part 2, n8n verification (precondition) | `RESULT: ACCEPTED`, **5/5 `PRESENT`**, and the three membership nodes present |
| before 13:07 | Part 1 steps 3-5 | state `before`; the dry run printed the four fingerprints of step 5 |
| **13:07** | Part 1 step 7, **apply** | committed |
| 13:22 | first run of `108_prod_checks.py` | **void.** Six `HTTP 403` with `Content-Type: text/plain` from the User-Agent filter of the default Python client; **no execution in n8n**. It proves nothing (see Part 3) |
| **13:23** | `108_rollback.sql` | both models disabled (`allowed_ops '{}'`, every role `NONE`); the views stay |
| 13:38 | `108_prod_checks.py --after-rollback` (own User-Agent) | **2/2**: the transport reaches the gateway and the disabled models answer `403` with no rows |
| 13:50 | Part 1b, dry run of `108_reenable.sql` | rolled back, nothing changed; fingerprints `51b93c8c…` (model `vw_palpation_events`) and `7d020967…` (model `vw_palpation_herd`) |
| **13:52** | Part 1b, `108_reenable.sql` apply | committed |
| 13:52 | `108_state_check.sql -v expect=applied` | state `applied`; `model_rows` `888bab62…` |
| **13:54** | Part 3, `108_prod_checks.py --expect-herd-rows` | **7/7**: `vw_palpation_herd` returned **138** rows and `vw_palpation_events` **20** rows for company 3, and **0** rows of any other company; the two denial checks (no tenant header, a company the user does not belong to) answered the gateway's own `403` |
| about 15:10 | `108_contract_probe.py` against production (read-only) | `event_date` arrives as a timestamp that is **always `T06:00:00.000Z`** (a calendar date serialized at local midnight, UTC-6) |

Notes on this record:

- **Part 3 ran with an ADMIN of company 3, not with the EDITOR** the Part 3 procedure recommends. The `EDITOR` role is covered by the LOCAL gateway tests (28/28, ADMIN and EDITOR) and by the model fingerprint: `allowed_roles_select` is part of the hashed row of both models, and it matched the expected value at 13:50 and 13:52.
- Writes and the `CUSTOMER` role were not tested in production, as planned: the models carry `allowed_ops {SELECT}` and `NONE` for insert, update and delete (part of the same fingerprint).
- Between 13:07 and 13:23 the models were readable by ADMIN and EDITOR, filtered by company: the Part 2 precondition (the production `Build Query` injects the verified tenant) was recorded as ACCEPTED before the apply.
- The 13:22 run is kept in the record on purpose: a PASS that did not come from the gateway must not be mistaken for a result.

### Open items

1. **Should the `OWNER` role see the report?** Today only `ADMIN` and `EDITOR` can read both models, and the screen shows "sin permiso" to an `OWNER`. Allowing `OWNER` changes the two production models (`allowed_roles_select`), so it needs a new reviewed change with new fingerprints, and the screen constant `PALPATION_ALLOWED_ROLES` must change together with it. Undecided.
2. **Models without a tenant column.** The gateway only filters by company when `id_company` or `tenant_id` is in `allowed_fields` (see "Why the models MUST carry `id_company`"). Several existing cattle models have no such column and are readable across companies by any authorised role. It is **out of scope of 108** and is tracked separately (branch `security/gateway-v6-tenant-less-models`). TODO(verify): the issue number, to be added by the owner.

## Order of execution

Part 0 → **Part 2 (n8n verification, precondition)** → Part 1 steps 1-6 (backup, checksums, state before, dry run, fingerprints, authorization) → Part 1 step 7 (**apply, blocked until Part 2 is recorded**) → Part 1 step 8 → Part 3 (production tests) → Part 4 (frontend, last).
The parts keep their numbers (Part 1 = database, Part 2 = n8n) because the ⛔ box refers to them.

### Part 0 — Preconditions

Verified in production by read-only queries (2026-11-18, reported by Francisco). **Re-run them before Part 1 and record the output:**

| Fact | Verified value |
|---|---|
| PostgreSQL | `PostgreSQL 15.4 (Debian 15.4-2.pgdg120+1)` = the same as LOCAL |
| primary key of `repro_condition_codes` | `PRIMARY KEY (id_company, code)` |
| objects of migrations 084-090 | the tables exist |
| `vw_palpation_events`, `vw_palpation_herd` and their two `crud_models` rows | **do not exist** |
| columns of `crud_models` | 17: `id`, `model_name`, `table_name`, `primary_key`, `allowed_fields`, `default_filter`, `created_at`, `schema_json`, `allowed_ops`, `hooks`, `allowed_roles_select`, `allowed_roles_insert`, `allowed_roles_update`, `allowed_roles_delete`, `joins`, `is_global`, `sp_requires_tenant` (the migration inserts 15 of them; `id` and `created_at` take their defaults) |
| indexes the views rely on | `idx_health_livestock`, `idx_livestock_tenant`, `idx_livestock_brand`, and the `UNIQUE` constraint on `palpation_repro_details.health_log_id` |
| rows of `crud_models` | **95** before; **97** after applying. `other_crud_models_count` = **95** in production (87 in LOCAL) |
| company 3 ("Rancho El Palomar") | 2 active ADMIN and 1 active EDITOR, **none with membership in company 5**; 138 animals |

The `other_crud_models` md5 `27178bfa1f57bf93182b401a788d9897` quoted in the LOCAL evidence is the hash of LOCAL's 87 rows: **do not compare it with production**. Record the production value at step 3 and compare it with step 8 (same environment).
The migration itself aborts if any of these facts is false, and the dry run tells before anything is written.

### Part 1 — Database

Nothing is copied to the VPS: every command runs on your machine and streams the file over standard input (`ssh` → `docker exec -i … psql`). Apart from the backup of step 1, nothing is left on the server. `vps` is the SSH alias of the production server.

1. **Backup** (before anything else). Only operations that neither delete nor overwrite: new file names carrying a timestamp, `noclobber`, `mkdir` without `-p` for the local directory, `scp` into that new directory. The dump contains **real data**: it never goes into the repo; record the file names and the md5 in the runbook record.

   Timestamp (on your machine, used in every name below):

   ```sh
   export STAMP=$(date -u +%Y%m%dT%H%M%SZ); echo "$STAMP"
   ```

   1a. **Space** (read-only). **STOP if free space is below about 3 times the database size:**

```sh
ssh vps bash -s <<'EOF'
df -h /root /var/lib/docker
docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_db -Atc "SELECT pg_size_pretty(pg_database_size('hosting3m_db'))"
EOF
```

   1b. **Dump inside the container, list it, md5** (the dump goes to `/root/backups` on the VPS under a name that must not exist yet):

```sh
ssh vps "STAMP=$STAMP bash -s" <<'EOF'
set -euo pipefail
set -o noclobber                      # a '>' can never overwrite an existing file
umask 077
BK=/root/backups
DUMP="$BK/hosting3m_pre108_${STAMP}.dump"
test -d "$BK" && test ! -e "$DUMP"
docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > "$DUMP"
test -s "$DUMP"
docker exec -i n8n-enterprise-db pg_restore --list < "$DUMP" > "$BK/list_pre108_${STAMP}.txt"
test -s "$BK/list_pre108_${STAMP}.txt"
( cd "$BK" && md5sum "hosting3m_pre108_${STAMP}.dump" > "pre108_${STAMP}.md5" )
ls -l "$DUMP" "$BK/list_pre108_${STAMP}.txt" "$BK/pre108_${STAMP}.md5"
cat "$BK/pre108_${STAMP}.md5"
EOF
```

   1c. **Copy OFF the VPS** (from your machine, into a NEW directory outside the repo) and verify:

   ```sh
   LOCAL_BK="$HOME/backups-hosting3m-pre108"
   mkdir -m 700 "$LOCAL_BK"             # fails if it already exists: nothing is overwritten
   scp -p "vps:/root/backups/hosting3m_pre108_${STAMP}.dump" "vps:/root/backups/pre108_${STAMP}.md5" "vps:/root/backups/list_pre108_${STAMP}.txt" "$LOCAL_BK/"
   ( cd "$LOCAL_BK" && md5sum -c "pre108_${STAMP}.md5" )
   ```

   **STOP if** a file is missing, the dump or its list is empty, or `md5sum -c` does not print `OK`. Do not continue without a verified dump. (Same commands as step 1 of `REPRO_PRODUCTION_RUNBOOK.md`, whose `pg_dump` / `pg_restore --list` part was executed in production on 2026-10-28, with the additions above.)
2. **Local checksums** of the three files (from the repo checkout, in `hosting3m-workspace/projects/agro-erp/database/migrations/`); compare them with the reviewed values. Never stream the test, fixture or abort-check scripts.

   ```sh
   md5sum 108_palpation_views.sql 108_rollback.sql 108_state_check.sql
   # at the time of writing (verify against `git show <commit>:<file> | md5sum`):
   # ecc83a6c7865a17a770dccbf029aa620  108_palpation_views.sql
   # d3a8548a88e489c704338e3ce422db2c  108_rollback.sql
   # 08a3448fcde81818cfa4ba13a1b04911  108_state_check.sql
   ```
3. **State before** (read-only: the session itself is forced read-only):

   ```sh
   ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v expect=before -U n8n_user -d hosting3m_db' < 108_state_check.sql
   ```

   Save the output (it holds `other_crud_models` and `other_crud_models_count`). Expected: both views `absent`, no model row, `other_crud_models_count` = 95. **STOP if it does not say OK.**
4. **Dry run** (default, rolled back; no `PGOPTIONS`, because it writes inside a transaction that is rolled back):

   ```sh
   ssh vps 'docker exec -i n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -U n8n_user -d hosting3m_db' < 108_palpation_views.sql
   ```

   Expected last lines: `108: OK`, four fingerprints, `*** DRY RUN: 108 rolled back ***`. **STOP on any `ABORT`.**
5. **Fingerprints.** The production PostgreSQL version is the same as LOCAL's (15.4, Debian 15.4-2.pgdg120+1), so **all four hashes MUST match**:

   | Fingerprint | md5 (LOCAL = expected in production) |
   |---|---|
   | model `vw_palpation_events` | `51b93c8cc669c0cb8bb722d874790438` |
   | model `vw_palpation_herd` | `7d0209677c2bd1189fbdc35792bf4599` |
   | view `vw_palpation_events` | `410e9c6e2c228e1f3e318730e2fc167d` |
   | view `vw_palpation_herd` | `fe8d10d7179d9e97d990731de5799431` |

   **If any hash differs: STOP.** Do not apply. (The view hashes are only comparable because `version()` is identical: if the production version changes before the deployment, a different view hash is no longer conclusive on its own: compare the definitions with `pg_get_viewdef` against the file and decide with the owner. The model hashes are independent of the version.)
6. **Authorization.** Do not continue without it:

   `Written authorization of Francisco: ______________________  (date: ____________)`
7. **Apply** (no `PGOPTIONS`). **BLOCKED until Part 2 is recorded** (the n8n `Build Query` of production must inject `x-tenant-id`; otherwise the models would be readable across companies until the rollback):

   `Part 2 recorded: RESULT ______________  PRESENT lines ____/5  (date: ____________  by: ____________)`


   ```sh
   ssh vps 'docker exec -i n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v apply=true -U n8n_user -d hosting3m_db' < 108_palpation_views.sql
   ```

   → `*** 108 COMMITTED ***`.
8. **State after:**

   ```sh
   ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v expect=applied -U n8n_user -d hosting3m_db' < 108_state_check.sql
   ```

   The `other_crud_models`, `other_crud_models_count` (95) and `source_table_columns` fingerprints must be **identical** to step 3; `crud_models` now has 97 rows.

### Part 1b — Re-enable the two models (after a rollback)

Use only when both models are disabled (the state of 13:23 on 2026-11-18). **Executed on 2026-11-18 between 13:50 and 13:54 (see the execution record).** `108_palpation_views.sql` aborts on existing objects, so it cannot re-enable: this is `108_reenable.sql`, the exact inverse of `108_rollback.sql`. It is **generated** by `108_make_reenable.py` from the migration's `INSERT` (values copied, not retyped; `python3 -I 108_make_reenable.py --check` must print `OK`). It touches **two `crud_models` rows and nothing else**: no INSERT, DELETE, DROP or view change. A backup is not required for this change, because the only state it writes is the one `108_rollback.sql` wrote; the guards below stop it on any other state. Every command is labelled with the place where it runs.

Guards (all inside the script): both views exist; exactly two model rows; both rows reverted (`allowed_ops '{}'`, every role `NONE`) or it aborts without changing anything; after the restore the two row fingerprints must equal the ones printed by the apply, or the transaction is aborted before the commit.

1. **[LAPTOP] Checksums and generator consistency.** From the repo checkout, in `hosting3m-workspace/projects/agro-erp/database/migrations/`:

   ```sh
   python3 -I 108_make_reenable.py --check   # expected: OK    108_reenable.sql matches the generator and the migration
   md5sum 108_reenable.sql 108_make_reenable.py 108_palpation_views.sql
   ```

   Record the three md5 values in the runbook record. **STOP** if the check does not print `OK`.

2. **[VPS, read-only] State before.** It must be `rolled_back`; anything else is a **STOP**:

   ```sh
   ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -U n8n_user -d hosting3m_db' < 108_state_check.sql
   ```

3. **[VPS, dry run, rolled back; no `PGOPTIONS`, because the script writes inside its own transaction and rolls it back.]** Expected: the two `NOTICE` lines with the fingerprints of step 4, then `*** 108 RE-ENABLE DRY RUN: rolled back, nothing changed ***`:

   ```sh
   ssh vps 'docker exec -i n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -U n8n_user -d hosting3m_db' < 108_reenable.sql
   ```

4. **Fingerprints** printed by the dry run (LOCAL, the same values the apply of 108 printed; production must print the same). If any differs, **STOP**:

   | Fingerprint | Expected |
   |---|---|
   | model `vw_palpation_events` | `51b93c8cc669c0cb8bb722d874790438` |
   | model `vw_palpation_herd` | `7d0209677c2bd1189fbdc35792bf4599` |

5. **Authorization.** Do not continue without it:

   `Written authorization of Francisco: ______________________  (date: ____________)`

6. **[VPS, apply] Re-enable.** Only after step 5 is filled in:

   ```sh
   ssh vps 'docker exec -i n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v apply=true -U n8n_user -d hosting3m_db' < 108_reenable.sql
   ```

   Expected: the two `NOTICE` lines of step 4 and `*** 108 RE-ENABLED (committed) ***`.

7. **[VPS, read-only] State after.** `model_rows` must be **`888bab6298cecf8df9899212cd713f05`** (the value of the apply of 108), and the `other_crud_models` fingerprint must be the one recorded in Part 1 step 3:

   ```sh
   ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v expect=applied -U n8n_user -d hosting3m_db' < 108_state_check.sql
   ```

   If `model_rows` differs, do **not** force anything: the fingerprint printed by the apply is the reference; compare the two rows with `row_to_json` against `108_palpation_views.sql` and stop.

8. **[LAPTOP] Repeat Part 3** (new run, new token, counts only). A run with no new executions in n8n proves nothing (see Part 3).

### Part 2 — n8n (no change; verification only)

108 needs no workflow change. It does depend on the production `v6/CRUD` `Build Query` node behaving as the repo's export does for `getall` / `getone`, and **that is why this part is a precondition of the apply (Part 1, step 7)**: if the node does not inject the verified `x-tenant-id` for models that list `id_company`, the two new models would be readable across companies from the apply until the rollback. **Compare only the node's `jsCode`, not the whole workflow** (the whole-workflow snippet of the root `CLAUDE.md` is a separate release step and compares `parameters` of every node):

1. Download `v6/CRUD` from the production editor (⋯ → Download), `chmod 600` the file, outside the repo. `git fetch origin main` first.
2. **Accepted difference:** none, **or** only the two `call_sp` entries of migration 107 (`sp_agri_void_sale`, `sp_agri_sales_balance` in `spConfigByModel`, 12 lines) present in `origin/main` and absent in production (their gateway publication is Part 2 of runbook 107, which may not be done yet). **Any other difference, in either direction, is a STOP.** The snippet below does the comparison and the evidence checks of step 3 (run it from the repo root; it reads the export and `git show`, it connects to nothing):

```sh
python3 -I - /path/to/production-export.json <<'PY'
import difflib, json, re, subprocess, sys

def build_query_code(doc):
    return next(n for n in doc["nodes"] if n["name"] == "Build Query")["parameters"]["jsCode"]

prod = build_query_code(json.load(open(sys.argv[1])))
repo = build_query_code(json.loads(subprocess.check_output(
    ["git", "show", "origin/main:workflows/06-dynamic-crud-engine/v6/v6-crud.json"])))
prod_l, repo_l = [l.rstrip() for l in prod.split("\n")], [l.rstrip() for l in repo.split("\n")]

# The only difference accepted: the migration 107 block of spConfigByModel (sp_agri_void_sale, sp_agri_sales_balance).
start = next(i for i, l in enumerate(repo_l) if "Palm sales (migration 107)" in l)
bal = next(i for i, l in enumerate(repo_l) if "'sp_agri_sales_balance'" in l)
end = next(i for i in range(bal, len(repo_l)) if repo_l[i].strip().startswith("}"))
block = {l.strip() for l in repo_l[start:end + 1]}
size = end - start + 1

raw = list(difflib.unified_diff(prod_l, repo_l, "production", "origin/main", lineterm="", n=0))
diff = [l for l in raw[2:] if not l.startswith("@@")]   # drop ONLY the two header lines and the @@ hunk lines
only_prod = [l for l in diff if l.startswith("-")]
only_repo = [l for l in diff if l.startswith("+")]
ok_diff = not only_prod and (not only_repo or (len(only_repo) == size and all(l[1:].strip() in block for l in only_repo)))
print("jsCode lines: production", len(prod_l), "| origin/main", len(repo_l))
print("DIFFERENCES:", "none" if not diff else f"{len(only_repo)} line(s) only in main, {len(only_prod)} only in production")
print("RESULT:", "ACCEPTED" if ok_diff else "STOP: differences other than the migration 107 call_sp entries")

# Evidence that the behaviour 108 depends on is in the PRODUCTION code (patterns searched in the production jsCode).
checks = {
  "x-tenant-id injected only when the model has tenant_id / id_company (lines 17-24)":
     r"if \(tenantIdHeader && modelHasTenantId\)\s*\{\s*fields\['tenant_id'\] = tenantIdHeader;\s*\}\s*else if \(tenantIdHeader && modelHasIdCompany\)\s*\{\s*fields\['id_company'\] = tenantIdHeader;",
  "model flags read from allowed_fields":
     r"modelHasTenantId = \(config\.allowed_fields \|\| \[\]\)\.includes\('tenant_id'\);\s*const modelHasIdCompany = \(config\.allowed_fields \|\| \[\]\)\.includes\('id_company'\)",
  "default sort column is created_at":
     r"let sortCol = body\.sort_by \? body\.sort_by : \(fields\.published_at \? 'published_at' : 'created_at'\)",
  "ORDER BY <table>.<sortCol> DESC":
     r"finalSortCol = .*`\$\{table\}\.\$\{sortCol\}`",
  "default limit 1500, maximum 2000":
     r"let limit = 1500;[\s\S]*?Math\.min\(parsedLimit, 2000\)",
}
bad = 0
for name, rx in checks.items():
    hit = re.search(rx, prod) is not None
    bad += not hit
    print(("PRESENT  " if hit else "MISSING  ") + name)
# The hole: getall has no company condition besides that injection.
print("INFO     company filter of getall = the injection above only: a model whose allowed_fields lack tenant_id and id_company has NO company filter")
sys.exit(0 if ok_diff and not bad else 1)
PY
```

   Expected: `RESULT: ACCEPTED` and five `PRESENT` lines; **record them in Part 1, step 7**. (Tested only on files, never on a production export: the repo export, the same export without the 107 block, a copy without the injection, a copy with an extra line, and copies with a line that starts with `--` or `++`. An earlier version dropped every line starting with `---` / `+++` and accepted the copy with a `-- ...` line; this one skips only the two header lines and the `@@` lines.)
3. **Evidence in the export** (what the snippet checks in the production `jsCode`): the `x-tenant-id` injection condition (`if (tenantIdHeader && modelHasTenantId) … else if (tenantIdHeader && modelHasIdCompany)`, lines 17-24 of the node code), the `modelHasTenantId` / `modelHasIdCompany` flags read from `allowed_fields`, the default sort `created_at` and `ORDER BY <table>.<sortCol>`, and the default limit 1500 (maximum 2000). An old `Build Query` without the `id_company` injection must stop the deployment here, before the apply.
4. **The same export answers whether the hole of company-less models exists in production** (step 0 of the security issue `security/gateway-v6-tenant-less-models`): when the injection of step 3 is present and `getall` has no other company condition (the snippet prints it as `INFO`), every model whose `allowed_fields` lack both `tenant_id` and `id_company` is readable across companies. Which models are in that situation is configuration, readable without touching data (read-only session, aggregated names only):

```sh
ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -U n8n_user -d hosting3m_db' <<'SQL'
SELECT model_name, table_name FROM crud_models
 WHERE NOT (allowed_fields ? 'id_company') AND NOT (allowed_fields ? 'tenant_id')
   AND 'SELECT' = ANY (allowed_ops) AND table_name !~ '^sp_' ORDER BY 1;
SQL
```

   The two 108 models must **not** appear in that list after Part 1. Record the list for the security issue.
5. Reference (LOCAL): the repo `Build Query` code md5 is `e270195a5f8f2643e1f050d3c8055c78`; the LOCAL n8n runs `12326918f2ff2e2639a802785e02e591`, which differs **only** by the two `call_sp` entries of migration 107: the `getall` / `getone` paths tested are identical.

### Part 3 — Production tests (company 3 "Rancho El Palomar", test company)

Rules: a user **with membership in company 3 and without membership in company 5** (verified: company 3 has 2 ADMIN and 1 EDITOR, none in 5; use the EDITOR, the least privilege that can read); **no writes, no seeded data**; only **counts** are printed, never a row body; company 5 data is never read. If a row of another company ever appears: **stop, do not show it, tell the owner**.

**What the first production run showed (2026-11-18) and the rules now.** The first run of `108_prod_checks.py` against production received six `HTTP 403` answers with `Content-Type: text/plain` and a 17-byte body, and the script's default `Python-urllib` User-Agent. None of the six produced an execution in n8n, so **those 403s and the PASS results did not come from the gateway, and that run proves nothing.** The source of the block is **not verified**: the root `CLAUDE.md` states that the production n8n host sits behind Cloudflare, so a CDN or WAF rule on the default client User-Agent is plausible; the owner must confirm it in the Cloudflare security events for those requests. The script now applies these rules:

- It identifies itself with `User-Agent: hosting3m-108-prod-check/1.0`. It does not imitate a browser or another client.
- **A 403 counts as a PASS only when it is the gateway's own denial:** `Content-Type: application/json` and a body with `error: true` and `status: 403`. The gateway's codes are `TENANT_FORBIDDEN` (`Respond Tenant Forbidden`, no tenant header or no membership), `SECURITY_VALIDATION` (`Security Validation`, role not allowed) and no code at all (operation disabled, which is what the models answer after the rollback). A missing token is answered **401** by the gateway (`Respond Denegate`), never 403.
- **Any other 403** (text, HTML, a CDN page, a JSON without the gateway shape) prints `FAIL ... blocked before the gateway` and the script **stops with exit 3**. The script prints the code and the classification, never the body.
- **A run with no new executions in n8n proves nothing.** After every run the owner counts the new executions of `v6/CRUD` in the n8n editor. Each request that reached the webhook creates one, including the ones that end in `Respond Tenant Forbidden`; a request blocked before n8n creates none. A run whose PASS lines have no matching new executions is void.
- Path: the webhook is `POST crud/v6/:model` (`v6-crud.json`, node `WebhookCRUD`, `path` and `httpMethod`). A POST to the base **without a model** does not match that route: on LOCAL it returns `404`, `application/json`, 388 bytes, the same size reported from production. The script sends `{base}/{model}`, which is the right form.

The production run above is **not** a valid Part 3 result. Part 3 is repeated with the corrected script; `--after-rollback` follows the same rules.

**Getting the token with ONE login** (by the code of `jwt-service` the login is rate-limited to 20 per 15 minutes per address; not measured in production; if the login fails, wait 15 minutes, do not retry in a loop; never `curl` a password or a token on the command line):

1. In a private browser window, open the production agro-erp, log in **once** as that user and pick company 3.
2. In the DevTools console of that page: `copy(localStorage.getItem('authToken'))`. The token goes to the clipboard without being printed. (`authToken` is the key `TOKEN_KEY` of `hosting3m-workspace/projects/core-auth/src/lib/services/auth.service.ts:11`, written at login at line 217; `hosting3m-workspace/projects/agro-erp/src/app/features/admin/services/admin.service.ts:53` reads the same key.)
3. In the terminal, type the token hidden (nothing is echoed, nothing reaches the shell history): `read -rs PALP_TOKEN; export PALP_TOKEN`, paste, Enter.
4. Clear the clipboard (`copy('')` in the console) and close the private window. Logging out does not revoke a JWT: it stays valid until its `exp`, so treat it as a secret until then and never paste it in a chat.

Recount the herd of company 3 just before (read-only; expected 138 at the time of the Part 0 verification) and pass it as `N`:

```sh
ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -A -t -v ON_ERROR_STOP=1 -U n8n_user -d hosting3m_db -c "SELECT count(*) FROM cattle_livestock WHERE tenant_id = 3"'
```

```sh
read -rs PALP_TOKEN; export PALP_TOKEN
python3 -I 108_prod_checks.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6 --expect-herd-rows N
unset PALP_TOKEN
```

(`108_prod_checks.py` only sends `getall`, takes the token from the environment and prints counts only; `--company` only accepts `3`. `--expect-herd-rows N` adds a 7th check: `vw_palpation_herd` must return exactly `N` rows for company 3, fewer than the 1500 limit; expected 138 unless the recount says otherwise. A mismatch is not a leak but must be explained before going on.)

| # | Request (both models) | Expected | The script prints |
|---|---|---|---|
| 1 | no `x-tenant-id` | `403`, no rows | status and row count |
| 2 | `x-tenant-id: 5` with that user | `403`, no rows. A `200` means the user belongs to 5 or the gateway does not enforce membership: **the script does not inspect the answer, stops (exit 3)** | status and row count |
| 3 | `x-tenant-id: 3` | `200`; **rows with `id_company` ≠ 3 must be 0**. If not 0: stop (exit 3), content not shown | status, total rows, rows of other companies, truncated yes/no |

Then, by hand in n8n: open the latest executions of #1 and #2 (they must stop at `Respond Tenant Forbidden`) and #3 (it must go through `Execute SQL` and finish successfully). **Look only at the route and the status of each execution; do not open the input or output of any node** (they hold rows).
Writes and the `CUSTOMER` role are **not** tested in production: they are covered by the model fingerprint of Part 1, step 5 (`allowed_ops {SELECT}` and every role are part of the hashed row) and by the LOCAL gateway tests (28 / 28).
If #2 or #3 fail: **roll back immediately** (below) and report.
`108_prod_checks.py` was validated against the LOCAL gateway with synthetic companies, including `--expect-herd-rows` and `--after-rollback` (see the LOCAL evidence below), and it stops with exit 3 when the company filter is removed from a model.

### Part 4 — Frontend

**Only if Parts 1, 2 and 3 are OK.** This pull request contains no frontend. The report screen is a later pull request (branch `feat/agro-erp-palpation-report`) that must not reach `main` before this runbook is completed and recorded. Parts 1, 2 and 3 were completed and recorded on 2026-11-18 (see the execution record): the models are active in production, so the frontend can follow.

## Gateway behaviour the frontend must handle (observed LOCAL)

- No `x-tenant-id` or a company the user does not belong to: `403` + `{error:true, code:"TENANT_FORBIDDEN"}`. Role not allowed: `403` + `code:"SECURITY_VALIDATION"`. A model with no operations (after the rollback): `403`.
- An empty collection is `data:[{}]`, not `[]`: filter by identifier before counting.
- A `sort_by` that is not a plain identifier, and other errors thrown by `Build Query`, answer **HTTP 200 with an EMPTY body** (the execution fails; it is not `error:true`). An unknown column answers `error:true`. The client must treat an empty body as an error, never as "0 rows".
- The default limit is **1500**; `limit` up to 2000. Exactly 1500 rows (or `rows == limit`) means **truncated**: show an error / paging state, never a complete list.
- `jwt-service` limits logins to 20 per 15 minutes per address. When repeating the LOCAL gateway tests, `docker restart n8n-jwt-service` clears the in-memory counter: **LOCAL ONLY; never in production; in production wait 15 minutes.**

## Rollback

Both models then deny every role. **Verified against the LOCAL gateway:** apply, 28 / 28 checks, rollback, then `getall` and `getone` of both models for ADMIN and EDITOR answer `403` with no rows (8 / 8; the same users got `200` before the rollback). The views remain (nothing reads them). Nothing is dropped or deleted. If the data (not the gateway) is the problem, the backup of Part 1, step 1 is the recovery point. Re-enabling is a separate reviewed change (the migration aborts when the objects exist).

```sh
ssh vps 'docker exec -i n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v apply=true -U n8n_user -d hosting3m_db' < 108_rollback.sql
ssh vps 'docker exec -i -e PGOPTIONS="-c default_transaction_read_only=on" n8n-enterprise-db psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -U n8n_user -d hosting3m_db' < 108_state_check.sql
```

**Check in production after the rollback:** with the same user as Part 3 (the token of Part 3 if it has not expired; otherwise ONE new login by the same procedure), run `python3 -I 108_prod_checks.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6 --after-rollback`. Expected `2/2`: `getall` with the header of company 3 answers `403` with no rows on both models.

## LOCAL evidence (PostgreSQL 15.4, local `n8n-enterprise-core`)

- `108_tests.sql` on a throwaway database restored from the LOCAL schema: **67 assertions passed**, rolled back. Covers: the 2023 historical load (key `resultado` without `result`) and the mixed-format event; new events with and without details row; `UNMAPPED` (`code_meaning` forced to NULL even when the code has a meaning); NR (not counted as palpated), RP, NO APTO, MATRIZ OCUPADA (ranch terms, outside the clinical results); pregnant without usable gestation; never-palpated animals; sold animals; **a synthetic bull (`TORO`) and calf (`BECERRO`) that appear with their category and species**; a non-object `medicines_json`; the accented event type; the same code `NR` in company B with another meaning; isolation between companies A and B; the gateway gate and the company filter as `Build Query` builds it; the rollback leaves the views and every other `crud_models` row untouched.
- `108_abort_check.sh`: **13 / 13**.
- `108_prod_checks.py` against the LOCAL gateway (synthetic companies; test copy with `https` relaxed and the company choice removed, because LOCAL has no company 3): normal mode **6 / 6**; with `--expect-herd-rows 3` **7 / 7**; with `--expect-herd-rows 99` it fails as it must (**6 / 7**, exit 1); after `108_rollback.sql` and `108_state_check.sql -v expect=rolled_back`, `--after-rollback` **2 / 2** (`403`, no rows); the real script rejects `--company 9101` (argparse choices) and refuses `--expect-herd-rows` together with `--after-rollback`. LOCAL was returned to `before` afterwards.
- `108_gateway_tests.py` against the real LOCAL gateway: **28 / 28**; after `108_rollback.sql` (`--after-rollback`): **8 / 8** (`403`). Negative control without `id_company`: 19 / 28, leak visible (1500 mixed rows).
- State fingerprints `other_crud_models` (`27178bfa1f57bf93182b401a788d9897`, 87 rows) and `source_table_columns` identical before, after applying and after rolling back.
- `108_prod_checks.py` after the User-Agent and gateway-403 change, against the LOCAL gateway (test copy with `https` relaxed, as above): normal mode with `--expect-herd-rows 3` **7 / 7**, all 403 classified `gateway` (`TENANT_FORBIDDEN`); after `108_rollback.sql` and `expect=rolled_back`, `--after-rollback` **2 / 2** (403 `gateway`, no code: operation disabled); against a local test double that answers 403 `text/plain` of 17 bytes, and against one answering 403 JSON without the gateway shape, the script prints `FAIL ... blocked before the gateway` and exits **3** (the double received only `User-Agent: hosting3m-108-prod-check/1.0`); a POST to the base without a model returns `404` `application/json` of 388 bytes.
- Re-enable (`108_reenable.sql`), LOCAL: apply of 108, then the re-enable on the applied state **aborts** (`only 0 of 2 models are in the reverted state`); rollback; with the models absent (one row renamed inside a rolled-back transaction) **aborts** (`expected exactly the two palpation model rows`); with the views absent (renamed inside a rolled-back transaction) **aborts** (`the two palpation views do not exist`); with `default_filter` changed in a rolled-back transaction **aborts** on the fingerprint (nothing committed); dry run prints `51b93c8c…` and `7d020967…` and changes nothing; apply: `state_check applied` with `model_rows` `888bab6298cecf8df9899212cd713f05` and `other_crud_models` `27178bfa…` unchanged.
- After the re-enable, `108_gateway_tests.py` **28 / 28**; `108_prod_checks.py` normal mode with `--expect-herd-rows 3` **7 / 7**. Negative cases of the normal mode: a CUSTOMER of company 3's test copy gets `FAIL … code=SECURITY_VALIDATION` on the own-company check (exit 1); a gateway-shaped 403 with `SECURITY_VALIDATION` on the local double makes checks #1 and #2 FAIL with the code printed (`0/6`, exit 1); a gateway-shaped 403 with no code likewise (`0/6`, exit 1); after the rollback, the normal mode shows `code=-` on the own-company check (exit 1), and `--after-rollback` is **2 / 2**.
- LOCAL `hosting3m_db` was returned to its previous state after the gateway tests (models and views removed, fixtures deleted). `rehearsal_108` is kept as a throwaway database.
