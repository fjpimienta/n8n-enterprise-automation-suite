# Runbook — Reproduction tracking, phase 3b: what the ranch's uterine codes mean (migration 090)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend and changes no n8n node (Part 2 says so explicitly); the merge still goes last, per the rule.*

**Requires migrations 084 – 088** (it replaces 7 bodies created by 086 and 088 and calls a function of 087). 089 is independent. 090 aborts at its first block if they are missing,
**and aborts if any of the 7 live bodies is neither the one created by 086 / 088 (md5 table below) nor already carries the marker `-- 090:vet-codes-v1`.**
If it aborts with that message: **STOP** and compare the live body before doing anything else (a body edited by hand is never overwritten).

Production order: **084 → 085 → 086 → 087 → 088 → (089 any time after 085) → 090 → 090 seed**. Production has none of 084 – 089 yet, so 090 is written to go right after 086 / 088 in the same sitting.

⚠️ **The seed is part of the rollout, not an extra, and the order matters.** Without the meanings, a company whose pending codes were registered by the 086 seed (`RP`, `NR`, `NO APTO`, `MATRIZ OCUPADA`, `UTC2`) accepts a
bare `NR` / `RP` / `NO APTO` as an inferred VACÍA exactly as 086 did (the defect this phase fixes; `MATRIZ OCUPADA` is fixed by 090 itself). Decided by the owner:
- **LOCAL:** the 090 seed runs **right after 090** (the LOCAL copy already has the 086 seed; it is restored from production every day at 07:00, so re-run it after a restore).
- **Production (the phase 5 rollout runbook):** the **086 seed and the 090 seed run back to back, BEFORE the palpation tools are connected to the agents**, so no agent can ever call the tool while the codes are pending without their meaning.
- The 090 seed is always run with `-v confirmed_by='capataz (sin confirmacion veterinaria)'`: the foreman confirmed these meanings, not a veterinarian. The 086 seed (UNE, UTCL1-3) keeps its own `confirmed_by` (the veterinarians').

**What changes**
- **Database (090):** one additive column `repro_condition_codes.meaning` (nullable text, no default, no table rewrite) with two CHECKs: `meaning IN ('NOT_EXAMINED','POSTPARTUM','UNFIT')` and "a code with a meaning has a NULL
  `repro_condition`". Three new internal helpers (`fn_repro_code_meaning`, `fn_repro_palp_text`, `fn_repro_palp_code_info`) and **7 bodies replaced in place** (same names and signatures, `CREATE OR REPLACE`, not overloads):
  `fn_repro_diagnosis_kind`, `sp_repro_log_palpation_batch`, `sp_repro_list_palpation_due`, `sp_repro_list_upcoming_calvings`, `sp_repro_list_unmapped_uterine_codes`, `sp_repro_condition_code_set`, `sp_repro_get_dam_history`.
  The migration writes **no rows**. `fn_uterine_split`, `fn_parse_uterine_code`, `sp_log_palpation_event` and `palpation_repro_details` are not touched (so **N/A is still "no code"**, exactly as before).
- **Meanings (confirmed by the ranch FOREMAN, not by a veterinarian):**

  | Input | Meaning | What the wrapper does |
  |---|---|---|
  | `MATRIZ OCUPADA` | pregnant (fixed phrase, every company) | PREÑADA, no gestation days needed, wording kept in `raw_code`; with VACIA / an explicit word / RP / NO APTO → `DIAGNOSIS_CONFLICT` |
  | `NR` alone | not examined | validated, then `line_status: not_examined`; **nothing written** (no palpation, no details, no status change); other lines processed; an only-NR batch answers `recorded`, `written: 0` |
  | `UNE/NR` | unchanged | real palpation, condition NULL, UNMAPPED; reported in `composite_unconfirmed` (NR after a slash is unconfirmed) |
  | `RP` | recién parida | VACÍA, condition NULL, `NOT_APPLICABLE`, `vet_flag: POSTPARTUM`, category untouched; `rp_without_registered_birth: true` when no birth of the animal is registered within 90 days of the palpation date |
  | `NO APTO` | unfit for breeding | same as RP with `vet_flag: UNFIT` (no birth flag) |
  | **Any code-only line on a PREÑADA animal** (`RP`, `NO APTO`, `UTC2`, `UNE`, `UTCL1-3`, `UNE/NR`, any known code; no explicit result word) | | **rejected** (`NEEDS_EXPLICIT_RESULT`, and so the whole batch): the VACÍA would be inferred and could erase a real pregnancy; the user restates it with an explicit result (`VACIA RP`, `PREÑADA UNE`). `NR` alone is not rejected (it infers nothing) |
  | `RP` / `NO APTO` with a PREÑADA word | | `DIAGNOSIS_CONFLICT` |
  | `UTC2` | general uterine tone, **not** ciclando | unchanged: known-pending, condition NULL, UNMAPPED |

  **The PREÑADA guard covers every code-only line** (owner decision): a line with a code but no explicit result word (`PREÑADA`, `VACIA`, `ciclando`, `estática`, `MATRIZ OCUPADA`) is VACÍA by inference, so it is never
  accepted over an animal whose current status is PREÑADA. A line with an explicit result word, any line on a non-PREÑADA animal, `N/A` / no-code behaviour and `NR` alone are exactly as in the table.
- **Assumption — the RP birth window:** `rp_without_registered_birth` looks for a registered birth (a `birth_events` row, or a non-voided historical birth with DAY / MONTH precision) of the same animal **within 90 days of the palpation date, in
  both directions** (symmetric: `fn_repro_birth_window_matches(…, 90)`). 90 days is an assumption of this phase, not a ranch rule; change `v_birth_win` in `sp_repro_log_palpation_batch` if the ranch defines "recién parida" differently.
- **Read tools:** `list_palpation_due`, `list_upcoming_calvings` and the dam history show `last_palpation_code` / `last_palpation_vet_flag`; the dam history adds `palpation_code_contradicts_result` and `palpations_with_vet_flag`
  (**display only**: the imported `MATRIZ OCUPADA` row of tenant 5, stored as `VACIA` with the animal `VACÍA`, is shown as a contradiction and **never corrected**); `list_unmapped_uterine_codes` adds `known_meanings`,
  `composite_unconfirmed` and `meanings_configured` and no longer reports a known meaning as unknown.
- **`sp_repro_condition_code_set`:** refuses to redefine `MATRIZ OCUPADA` and refuses to give a condition to a code that has a meaning (a friendly `invalid` answer, not a database error).
- **n8n:** **no node is edited.** The answers only gain keys. Phase 5 must teach the prompts to relay `not_examined`, `needs_explicit_result`, `rp_without_registered_birth` and the `vet_flag`s
  (`workflows/09-MCP-Agent-Cattle/v6/repro-phase3/README.md`, last section).
- **Frontend:** nothing.

Nothing in this runbook is run by the assistant. Production is touched only by the owner, with the steps below.

Conventions used below
```bash
# On the VPS (production)                                  # On your machine (LOCAL)
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```

**The intended psql command, for every apply and every rollback in this runbook: `$P -v apply=true -f <file>` - WITHOUT `--single-transaction`.** Each file opens and commits its own transaction (`BEGIN` ... `COMMIT`)
and `ON_ERROR_STOP` stops it at the first error *before* the `COMMIT`. Without `-v apply=true` the file is a dry run (it ends in `ROLLBACK`). The `*_state_check.sql` files open `BEGIN READ ONLY` and end in `ROLLBACK` themselves.

---

## Test database (LOCAL only — never production)

Same as `088_RUNBOOK.md`, "Test database" (schema-only copy, `companys` and two users; **no palpations** in the two companies it picks, and no `T090` fixtures). Use a database name of your own, e.g. `hosting3m_test090`:

```bash
docker exec n8n-enterprise-db createdb -U n8n_user hosting3m_test090
docker exec n8n-enterprise-db sh -c \
  'pg_dump -U n8n_user --schema-only --no-owner hosting3m_db | psql -U n8n_user -d hosting3m_test090 -q'
docker exec n8n-enterprise-db sh -c \
  'pg_dump -U n8n_user -d hosting3m_db --data-only --column-inserts -t public.companys | psql -U n8n_user -d hosting3m_test090 -q -v ON_ERROR_STOP=1'
docker exec n8n-enterprise-db sh -c \
  "psql -U n8n_user -d hosting3m_db -c \"COPY (SELECT * FROM public.users ORDER BY email LIMIT 2) TO STDOUT\" \
   | psql -U n8n_user -d hosting3m_test090 -c \"COPY public.users FROM STDIN\""

docker exec n8n-enterprise-db rm -rf /tmp/m090
docker cp hosting3m-workspace/projects/agro-erp/database/migrations n8n-enterprise-db:/tmp/m090
docker exec -w /tmp/m090 -i n8n-enterprise-db \
  psql -U n8n_user -d hosting3m_test090 -v ON_ERROR_STOP=1 -f /tmp/m090/090_tests.sql 2>&1 | tee 090_tests_output.txt
```

Expected: one `OK` line per test, a final `passed | failed | total` with **`failed = 0`**, ending in `*** 090 tests: everything rolled back ***`. The run keeps going after a failed assertion (same mechanism as the
087 / 088 tests: `pg_temp.t()`, `__error` answers, `ON_ERROR_ROLLBACK`); **every `FAIL` line has its `detail` column filled**. An `ERROR:` line printed *outside* the results table is an unexpected error in a fixture or
helper statement - report it. After the run this must return 0: `SELECT count(*) FROM cattle_livestock WHERE rfid_siniiga LIKE 'T0%'`. Clean up: `dropdb -U n8n_user hosting3m_test090`.

**A failure always shows its whole answer:** the results table prints the `detail` column untruncated and, right after the totals, a `=== FAILURES (full detail, expanded)` block repeats every failed test with its detail one field per line.
`090_diag_t28.sql` is a LOCAL-only diagnostic (it builds one fixture inside a transaction that ends in `ROLLBACK`, prints two answers in full and leaves nothing behind); run it the same way as the tests, from the migrations folder inside the container.

**If only the tests or this runbook change later, re-run only `090_tests.sql`. If `090_repro_vet_code_semantics.sql` changes, rebuild the throwaway database first.**

**What the run proves.** Part A: the pure functions (the phrase, conflicts, NR alone / composite, RP / NO APTO kinds, the helpers, **the parser and N/A untouched**, the two CHECKs). Part B: the wrapper — every row of the table above,
including the PREÑADA guard for every code-only line (UTC2, UNE, UTCL1/OI, UNE/NR, RP, NO APTO: the whole batch rejected, nothing written; restated with an explicit word they are accepted; NR alone is not rejected), the birth flag with a birth 30 days before (no flag) and 200 days before (flag), company isolation (B has no NR / RP meaning), idempotent retry, all-or-nothing, regression
of `ciclando` / UTCL1 / `PREÑADA 4 MESES`. Part C: the four read tools, the old keys still present, nothing written by the history tool, isolation. Part D: `sp_repro_condition_code_set`. Part E: fail-closed. Part F: every function 090 must not
touch is byte-identical to its state before 090, exactly 7 bodies carry the marker, NR-only animals have no palpation, the imported MATRIZ OCUPADA animal is **not** corrected, and the run stayed in one transaction.

---

## Part 0. Baseline and files — **run on the VPS** (it writes to `/root`)

1. Verify the files (md5 in the table at the end): `mkdir -p /root/m090 && cd /root/m090` (copy `090_*` here) and `md5sum 090_*`.
2. Check the 7 live bodies (read-only). Production will have the bodies created by **our own** 086 and 088, so each md5 must equal the "before 090" column of the table below:

   ```bash
   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -c \
     "SELECT p.proname, md5(pg_get_functiondef(p.oid)) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('fn_repro_diagnosis_kind','sp_repro_log_palpation_batch','sp_repro_list_palpation_due','sp_repro_list_upcoming_calvings','sp_repro_list_unmapped_uterine_codes','sp_repro_condition_code_set','sp_repro_get_dam_history') ORDER BY 1;"
   docker exec n8n-enterprise-db rm -rf /tmp/m090 && docker cp /root/m090 n8n-enterprise-db:/tmp/m090
   P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
   $P -v expect=before -f /tmp/m090/090_state_check.sql > /root/090_state_before.txt 2>&1
   tail -3 /root/090_state_before.txt        # expect: 090 state check (before): OK
   ```

## Part 1. Database

1. **Backup first** (size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db > /root/backups/hosting3m_schema_pre090_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc -t public.repro_condition_codes -t public.palpation_repro_details \
     hosting3m_db > /root/backups/hosting3m_palpation_tables_pre090_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre090*
   ```

2. **State before** was taken in Part 0. Keep its `FINGERPRINT` and `BODY_*` lines.
3. **Dry run:** `$P -f /tmp/m090/090_repro_vet_code_semantics.sql > /root/090_dryrun.txt 2>&1` → `090: OK` and `DRY RUN`.
4. **Tests ran on the throwaway database**, never here.
5. **Apply:** `$P -v apply=true -f /tmp/m090/090_repro_vet_code_semantics.sql > /root/090_apply.txt 2>&1`; `tail -5` must show `090: OK` and `*** 090 COMMITTED ***`.
6. **State after:** `$P -v expect=applied -f /tmp/m090/090_state_check.sql > /root/090_state_after.txt 2>&1` → `090 state check (applied): OK`; `diff` of before / after must differ **only** in NOTICE / OK /
   `BODY_*` / `PHASE3B_ROWS` lines, **never in a `FINGERPRINT` line**. Compare the 7 `BODY_*` md5s with the "after 090" column below.
7. **The seed (data, separate file, dry run by default).** The meanings of NR, RP and NO APTO were confirmed by the **ranch foreman**, not by a veterinarian; the seed records that in `source = 'SEED_090_FOREMAN_CONFIRMED'` and in
   `confirmed_by`. The 086 seed (UNE, UTCL1-3) keeps its own source and `confirmed_by` (veterinarians):

   ```bash
   $P -v confirmed_by='capataz (sin confirmacion veterinaria)' -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql > /root/090_seed_dryrun.txt 2>&1
   #   read it: company 5 is the expected one; AFTER shows NR NOT_EXAMINED, RP POSTPARTUM, NO APTO UNFIT; "differences" = 0; ends in DRY RUN
   $P -v confirmed_by='capataz (sin confirmacion veterinaria)' -v apply=true -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql > /root/090_seed_apply.txt 2>&1
   ```

   It aborts if one of the three codes already has a condition or a different meaning (nothing is overwritten), touches no other company and sets no condition. `UTC2` stays pending; `MATRIZ OCUPADA` needs no row.
   Undo (back to the pending state, deletes nothing): `$P -v confirmed_by=x -v undo=true [-v apply=true] -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql`.
8. **Read-only smoke test** (company 5, a member's e-mail; from a non-member each call must **raise** `P0001`):

   ```sql
   SELECT sp_repro_list_unmapped_uterine_codes('5','<owner email>')->'known_meanings';          -- RP, NO APTO, MATRIZ OCUPADA (and NR if some row carries it alone)
   SELECT sp_repro_list_unmapped_uterine_codes('5','<owner email>')->'composite_unconfirmed';   -- NR with example UNE/NR
   SELECT sp_repro_get_dam_history('5','<owner email>','<arete of the imported MATRIZ OCUPADA animal>')->'quality_flags'->'palpation_code_contradicts_result';   -- expect 1
   ```

   **Do not call the write tool in production** except with the owner's test company 3 and its `9999…` animals.

**Rollback:** `$P -v apply=true -f /tmp/m090/090_rollback.sql > /root/090_rollback.txt 2>&1`, then `-v expect=rolled_back`. It drops nothing: the 7 **original bodies** are put back byte for byte (the rollback verifies each md5),
and the column, its CHECKs, the three helpers and every meaning set by the seed stay. Re-apply keeps them. (With the original `sp_repro_condition_code_set`, re-confirming a code that has a meaning would hit the CHECK as a raw
database error; undo the seed first if you want the meanings gone.)

## Part 1b. LOCAL rehearsal on a copy with data

Same shape as `088_RUNBOOK.md` Part 1b with `/tmp/m090`: 084 – 088 first (skip each one already applied), then `090_state_check.sql -v expect=before`, the dry run, the apply, `expect=applied`, the `diff`, the seed
(dry run, then apply), the rollback, `expect=rolled_back`, the re-apply and `expect=applied`. The `FINGERPRINT` lines must be identical at every step; the `PHASE3B_ROWS` line must be identical after rollback + re-apply.
After the seed on LOCAL, try the three imported codes of tenant 5 **through the read tools only** (the smoke test above). The LOCAL copy is restored from production every day at 07:00, so the seed has to be re-run after a restore.

⚠️ After 090 the older state checks (`086_state_check.sql`, `088_state_check.sql`) report a different `phase3_palpation_functions` fingerprint: expected, those are the 7 functions 090 replaces. Use `090_state_check.sql` from here on.

## Part 2. n8n

**Nothing to import and no node to edit.** The four phase-3 tools and `get_dam_reproductive_history` call the same functions with the same arguments. Answers only gain keys. Phase 5 (agent prompts) decides how the agent relays them.

## Part 3. Frontend

Nothing.

---

## Reference for phase 5 (agent prompts) — exact names, one example answer each

Reuse verbatim. Everything is a key of the jsonb the tool returns; the agent relays `message` / `issues[].message` and never invents a status. Examples are shortened (`…`).

**Top-level `status` of `log_palpation_with_condition`**

| `status` | Meaning | Example answer |
|---|---|---|
| `recorded` | the batch was accepted (`written` may be 0 when every line was `not_examined`) | `{"status":"recorded","written":2,"pregnant":1,"empty":1,"with_condition":0,"unmapped":0,"duplicate_skipped":0,"not_examined":1,"rp_without_registered_birth":0,"results":[…],"not_examined_lines":[…]}` |
| `rejected` | at least one line has an issue: **nothing was written** | `{"status":"rejected","written":0,"issues":[{"index":2,"identifier":"9999000001","code":"NEEDS_EXPLICIT_RESULT","line_status":"needs_explicit_result","current_status":"PREÑADA","message":"El animal 9999000001 esta PREÑADA y \"RP\" no dice VACIA ni PREÑADA…"}],"message":"No se guardo nada del lote: corrige los renglones indicados y vuelve a enviarlo completo."}` |
| `invalid` | the call itself is wrong (`code`: `BAD_DATE`, `BAD_ITEMS`, `TOO_MANY_ITEMS`) | `{"status":"invalid","code":"BAD_DATE","message":"La fecha debe tener el formato AAAA-MM-DD."}` |

**Line statuses**

| Where | `line_status` | Meaning | Example |
|---|---|---|---|
| `results[]` | `recorded` | the palpation was written | `{"index":1,"identifier":"9999000002","result_used":"VACÍA","line_status":"recorded","mapping_status":"MAPPED","repro_condition":"CICLANDO","vet_flag":null,…}` |
| `results[]` | `duplicate_skipped` | an identical palpation of the last 5 minutes already existed; nothing new was written | `{"index":1,"identifier":"9999000002","line_status":"duplicate_skipped","duplicate_skipped":true,…}` |
| `not_examined_lines[]` | `not_examined` | `NR` alone: validated, **nothing written**, the animal's status did not change; not an error | `{"index":3,"identifier":"9999000003","raw_diagnosis":"NR","line_status":"not_examined","current_status":"VACÍA","written":false}` |
| `issues[]` | `needs_explicit_result` | a code-only line on a PREÑADA animal; the user must restate it with an explicit result | see the `rejected` example above |

**Issue `code`s (`issues[]`)**: `ITEM_INCOMPLETE`, `ANIMAL_NOT_FOUND`, `ANIMAL_AMBIGUOUS` (with `candidates`), `NOT_ACTIVE`, `DUPLICATE_IN_BATCH`, `DIAGNOSIS_CONFLICT` (a PREÑADA word / `MATRIZ OCUPADA` together with VACIA, an explicit word, `RP` or `NO APTO`),
`DIAGNOSIS_UNRECOGNIZED` (never defaulted to VACÍA), `NEEDS_EXPLICIT_RESULT`. **`mapping_status`**: `MAPPED`, `EXPLICIT`, `UNMAPPED`, `NOT_APPLICABLE` (RP, NO APTO and PREÑADA lines).

**Answer keys to teach** (the agent must say each one in plain Spanish and never present a foreman's meaning as a veterinary diagnosis)

| Key | Where | Meaning | Example |
|---|---|---|---|
| `not_examined` / `not_examined_lines` | `log_palpation_with_condition` | lines with `NR` alone; nothing stored about them | `"not_examined":1` |
| `vet_flag` | `results[]`, `last_palpation_vet_flag` (due / calvings), `palpations[].vet_flag` (history) | `POSTPARTUM` (RP, recién parida) · `UNFIT` (NO APTO, no apta para reproducción) · `NOT_EXAMINED` (read side only, an imported bare NR) · `null` | `"vet_flag":"POSTPARTUM"` |
| `rp_without_registered_birth` | `results[]` (boolean or null) and top level (count) | an RP line whose animal has no registered birth within 90 days of the palpation date: the birth may not have been captured — ask whether to register it | `"rp_without_registered_birth":true` |
| `palpation_code_contradicts_result` | `get_dam_reproductive_history` → `quality_flags` (count); per palpation `code_contradicts_result` | a stored code that means PREÑADA (`MATRIZ OCUPADA`) next to a stored result VACÍA. **Display only; nothing is corrected** | `"quality_flags":{"palpation_code_contradicts_result":1,…}` |
| `known_meanings` | `list_unmapped_uterine_codes` | codes with a meaning (and the `MATRIZ OCUPADA` phrase): **no longer unknown** | `{"code":"RP","meaning":"POSTPARTUM","palpations":2,"from_bulk_load":2,"from_logged":0}` |
| `composite_unconfirmed` | `list_unmapped_uterine_codes` | `NR` next to another code (`UNE/NR`): its meaning in that position is not confirmed | `{"code":"NR","meaning":"NOT_EXAMINED","palpations":1,"example_values":["UNE/NR"],"note":"NR junto a otro codigo: su significado en esa posicion no esta confirmado."}` |
| `meanings_configured` | `list_unmapped_uterine_codes` | who confirmed each meaning (the foreman, not a veterinarian) | `{"code":"NO APTO","meaning":"UNFIT","source":"SEED_090_FOREMAN_CONFIRMED","confirmed_by":"capataz (sin confirmacion veterinaria)",…}` |
| `last_palpation_code`, `last_palpation_code_means_pregnant`, `last_palpation_code_nr_composite` | `list_palpation_due` (`last_palpation_code_nr_composite` only there) and `list_upcoming_calvings` (without it) | the last palpation's uterine code as stored | `"last_palpation_code":"RP"` |
| `uterine_code`, `code_means_pregnant`, `code_nr_composite` | `get_dam_reproductive_history` → `palpations[]` | the code of that palpation and what it means | `"uterine_code":"MATRIZ OCUPADA","code_means_pregnant":true` |

---

## Files and md5

| File | md5 |
|---|---|
| `090_repro_vet_code_semantics.sql` | `1297f97ca2d9945d546197547d02f014` |
| `090_tests.sql` | `fcab49a22876ff7f7c020d7c9b6a316c` |
| `090_diag_t28.sql` | `495abcec62c902547b37efcf70a09358` |
| `090_rollback.sql` | `6298fabaffa857917c7052f00809e572` |
| `090_state_check.sql` | `7ef4d3de8ede12c994bb2e9c36eed691` |
| `090_seed_tenant5_vet_code_meanings.sql` | `23d8cfa6f3cf10e77afcadb6b1f40a64` |

(Recompute with `md5sum` if any file is edited after this runbook was written.)

**The 7 replaced bodies (`pg_get_functiondef`).** "Before 090" = the body created by 086 / 088; the owner reproduced these 7 values on LOCAL on 2026-10-28 and they equal what the repo files produce. "After 090" values were
**computed from the file** by rebuilding `pg_get_functiondef` text (the same method reproduced the 7 LOCAL values exactly); confirm them with `090_state_check.sql -v expect=applied` — if one differs, send me the real value, it is not a failure of the migration.

| Function | Before 090 (086 / 088) | After 090 (computed) |
|---|---|---|
| `fn_repro_diagnosis_kind` | `c14027757d85c745756a704ced03ab5f` | `a4c8fd03e4bf0a7043923f7df05d9d37` |
| `sp_repro_log_palpation_batch` | `845854fd40df5406c8c4f1f90fd558c9` | `2bf0f0dd11a5a86c57e5b1907d0611a0` |
| `sp_repro_list_palpation_due` | `d04d1f85f5d3aadae7d7bf1b8df73518` | `e71276983bbfc91501b2e3b89031ffeb` |
| `sp_repro_list_upcoming_calvings` | `0fab0832c5818b6be09cd94efb826ddb` | `a611b3ed7fd6372cc1f8b54217c17c23` |
| `sp_repro_list_unmapped_uterine_codes` | `4f682a0ea099c051d5b3b95a8eb553d0` | `4afa56b964eb6fe706576d6d0b5923d5` |
| `sp_repro_condition_code_set` | `46e720910cf97de3eb3921fb83f820b3` | `6975c03d3f4bfb9f5323e067454d5cbb` |
| `sp_repro_get_dam_history` | `79927c5b2478ae8f31307b9eb89d97d7` | `4fa3d587dbb49f13a1551f8046796aa0` |
