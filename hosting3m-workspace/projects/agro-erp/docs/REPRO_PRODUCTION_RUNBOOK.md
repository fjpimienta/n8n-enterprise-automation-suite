# Production runbook — reproduction tracking (migrations 084-090) and the two livestock agents (phase 5)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LOS PASOS 1 A 7** (respaldo, base de datos, semillas, n8n, prompts, QA, el paso 6b si se hace y — si aplica — 089, todo verificado con sus huellas).
> `main` despliega el frontend solo (Plesk) y este rollout depende de base de datos y de n8n: si se mergea antes, lo que dependa de ellos falla en producción.
> **Nada de este documento se ha ejecutado en producción.** Lo ejecuta el dueño, paso a paso, y se detiene en cada condición de parada.

**Who runs it:** the owner. **When:** a low-usage window; nobody edits workflows in the n8n editor during the rollout. **Order is strict:** `1 → 2 → 3 → 4 → 5 → 6 → 6b → 7 → 8`. Each step has a **STOP condition** and a **ROLLBACK**.
A step is never started until the previous one passed its verification. **Steps 4 and 5 run back to back in the same window** (see "Why 4 and 5 are one unit" below).

## How to read the status of a command
- ✅ **EXECUTED** — the owner ran exactly this command (or its LOCAL / throwaway equivalent with another database name or folder) and it worked; the phase where that happened is named.
- ⚠️ **UNTESTED** — nobody has run it. This includes **everything on production**, the n8n import, the QA, the real gateway check, 089 on production and the new step scripts below.
  Several files of earlier phases failed on their first real run (a `CASE` inside an `IF` condition, a stale snapshot in a test): treat every UNTESTED block as a draft and read it before running it.
  If an UNTESTED command fails, **STOP**, keep the output, and do not improvise a workaround.

## Variables — declare them ONCE, no placeholder is ever typed inside a command
Save this block as `repro_vars.sh` (outside git: it is not committed) next to the step scripts, **fill the values**, and copy it to every machine where a step runs. Every step block below is saved as its own script (`step1.sh`, `step2.sh` ...)
and run with `bash stepN.sh` — **never pasted line by line**, so a failed check stops it (`set -euo pipefail`). Each script starts with `. ./repro_vars.sh` and a `need` line that **fails when a variable is empty, unset, or still holds a placeholder** (`<` or `FILL`).
⚠️ UNTESTED as a whole; the `need` function itself was run by the author on a laptop shell with six cases (set, empty, unset, `<FILL: x>`, `FILL later`, two variables with one empty): it passed the good one and stopped on every bad one.
```bash
# repro_vars.sh
OWNER_EMAIL=''              # e-mail of a member of company 5 AND of company 3 (read-only smoke checks)
CONFIRMED_BY_086=''         # the confirmed_by value of the 086 seed — the owner states it before step 3
COMPANY5_ARETE=''           # one real arete SINIIGA of company 5 (read-only smoke check)
QA_MEMBER_EMAIL=''          # an active member of company 3 (list_lots diff, QA)
STAMP=''                    # one timestamp for the whole rollout, e.g. 2026-10-28_1500 (backup file names)
VPS_SSH=''                  # user@host of the VPS, used from your machine to copy the dumps off
LOCAL_BACKUP_DIR=''         # folder on your machine that receives the dumps
COMMIT_BEFORE_PHASE5=14dd60c   # the develop commit just before the phase 5 merge (#879)
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
# TOKEN is NEVER written to a file: step 7 reads it with `read -rs TOKEN` (Rule 4).

need() {   # stops a `set -e` script when a variable is empty, unset or still a placeholder
  local v
  for v in "$@"; do
    : "${!v:?$v is empty or unset}"
    case "${!v}" in *'<'*|*FILL*) echo "STOP: $v still holds a placeholder: ${!v}" >&2; return 1;; esac
  done
}
```
The same `P` shape was executed on LOCAL (another database name). Every apply / rollback uses `$P -v apply=true -f FILE` **without `--single-transaction`** (each file owns its `BEGIN` ... `COMMIT`); without `-v apply=true` the file is a dry run. ✅ EXECUTED on LOCAL / throwaway in phases 1-3b.

## What is deployed
- **Database:** 084 (births and age tools) → 085 (empadre) → 086 (palpation condition) → 087 (checked births, historical births) → 088 (service ↔ birth link, hardened `sp_log_breeding_event` / `sp_void_event`, dam history) → 090 (foreman-confirmed code meanings). **089** (disables the legacy gateway model `nacimiento`) is deliberately **last and optional** (step 7).
  Two seeds (data, dry run by default): `086_seed_tenant5_uterine_codes.sql` and `090_seed_tenant5_vet_code_meanings.sql`.
- **n8n:** the MCP server `v6/MCP Server Cattle` gains **24 tool nodes** (53 tools in total; `list_lots` gains two NEW keys, `lot_id` and `production_unit_id`); both livestock agents (`v6/ai/chat cattle` and `v6/WhatsApp Agent Catlte`, node `AI Agent`) get a new prompt (sections A5, B1, B5, C, E and a new G). `AI Agent Palma` is not touched.
- **Frontend:** nothing.
- **Confirmation levels (owner's decisions):** reads = NIVEL 1; routine writes (single birth, palpation batch, empadre single / batch, services) = NIVEL 2, no confirmation; births by block, historical births and every void = NIVEL 3, a summary and an explicit "Sí". Every role may capture; death and sale still need an ADMIN.
- **Not exposed to the agents:** `sp_repro_condition_code_set`, `sp_repro_empadre_set_config`, `sp_repro_births_set_config`.
- **The old tools** `register_birth_event` and `log_palpation_event_batch` leave the agents' dictionary but their **nodes stay in this PR's MCP export** (rollback path of 087) until **step 6b**, which deletes them after the QA passes. Their `toolDescription` (only that) now starts with `OBSOLETA: no la uses. Usa register_birth_checked.` / `... Usa log_palpation_with_condition.`; `log_palpation_event` (single) stays and gets one sentence: with a vet code use the wrapper with ONE element.
  - Why they are obsolete: `register_birth_event` calls the 13-parameter `sp_register_birth_event` and resolves lot / UPP names with a partial `ILIKE ... LIMIT 1` (no ambiguity check); `log_palpation_event_batch` calls `sp_log_palpation_event` once per animal and turns ANY text without a PRE…ADA word into VACÍA — **it can overwrite a PREÑADA animal with VACÍA, without the 090 `NEEDS_EXPLICIT_RESULT` guard** (that guard lives only in `sp_repro_log_palpation_batch`).

### Why 4 and 5 are one unit
After step 4 the MCP server says `OBSOLETA` on the two legacy tools **while the previous prompts still tell the agents to use them**. So the MCP import (4) and the prompt imports (5) are done in the same window, one right after the other, and **rolling back step 5 also rolls back step 4**.

## Files and md5 (verify with `md5sum` before copying anything to the VPS)
| File | md5 |
|---|---|
| `084_repro_births_age.sql` | `b3008ac99618ab8d9fabd81daeff45ec` |
| `084_rollback.sql` | `aa9aa76bca26f6366b7f2362957234ff` |
| `084_state_check.sql` | `44e8b1d3071d878ee74f39c14912b8a4` |
| `085_repro_empadre.sql` | `373c4fed4fcf04118cf6bfbd809150b3` |
| `085_rollback.sql` | `22de2551e59db0f988207352a4682a31` |
| `085_state_check.sql` | `351ebc0efb03c65ea7c4456c018543ca` |
| `086_repro_palpation.sql` | `3f8c236bc0432d5f0d0bad9699b7d6d1` |
| `086_rollback.sql` | `ef48d0ceb28d652e22d39eadec7b298a` |
| `086_state_check.sql` | `52d5bd629942829dac222f60aad416b3` |
| `086_seed_tenant5_uterine_codes.sql` | `c9654b54a959e5b4bb0b3738ff50af88` |
| `087_repro_births.sql` | `9b6a37ff583cd1c05c619bd87f2d9bdc` |
| `087_rollback.sql` | `23e723a27e02e38db3bf6ba183933a62` |
| `087_state_check.sql` | `d54a87ec1c444f474283bcf8aaaa6db8` |
| `088_repro_services.sql` | `575e793936da9b46be3beee3651b795a` |
| `088_rollback.sql` | `6cf3fedc9da852523e5ced1ff789dcdc` |
| `088_state_check.sql` | `beae0c4e4574e7895b5109f81b307e08` |
| `089_disable_nacimiento_gateway.sql` | `4f52348630b514c4de86b8da030db556` |
| `089_rollback.sql` | `04315d056abfbc9b8b4043f535477a7f` |
| `089_state_check.sql` | `12e7ede521226451319c08e9b0cc8aa6` |
| `090_repro_vet_code_semantics.sql` | `1297f97ca2d9945d546197547d02f014` |
| `090_rollback.sql` | `6298fabaffa857917c7052f00809e572` |
| `090_state_check.sql` | `7ef4d3de8ede12c994bb2e9c36eed691` |
| `090_seed_tenant5_vet_code_meanings.sql` | `23d8cfa6f3cf10e77afcadb6b1f40a64` |

| Workflow export | md5 |
|---|---|
| `v6_MCP_Server_Cattle.json` | `348d17217e7878bcd729f09d07f2df0d` |
| `v6_ai_chat_cattle.json` | `40beb5273eea7262d73e060972e7a5ff` |
| `v6_WhatsApp_Agent_Cattle.json` | `dfedcae289bfa2c3e4fb1a120c9f2769` |

| Phase 5 tools and QA | md5 |
|---|---|
| `repro-phase5/add_repro_tools.py` | `69a2bc534bdf8c501130874e4ea14f5e` |
| `repro-phase5/update_tool_descriptions.py` | `1cd01a0d2a7934484a1d5463167b9f7b` |
| `repro-phase5/update_prompts.py` | `704271602e6cfc0c43242f3049114c16` |
| `repro-phase5/compare_workflow_export.py` | `7071aa8d17c0e6ef1cde545ab16e37ed` |
| `repro-phase5/check_repro_consistency.js` | `78b66693cf462cefd51d5e87b7def16c` |
| `repro-phase5/list_lots_diff.py` | `fcf70c0c7fd6d911c347727370327683` |
| `repro-phase5/qa_fixtures.sql` | `45422c6d2ccaa0540b145a231075a64e` |
| `repro-phase5/REPRO_QA_SCRIPT.md` | `6a75f8c794b60ee4fcd3cc7762156364` |

(Recompute with `md5sum` if a file is edited after this runbook was written. The per-migration runbooks `0NN_RUNBOOK.md` hold the detail of each migration and their own md5 tables.)

---

## Step 1 — Full backup, and a copy OFF the VPS
**STOP if** disk space is short, a dump is empty or cannot be listed, the copy is missing, or its md5 differs. **ROLLBACK:** nothing was changed yet.

**1a. On the VPS** — ⚠️ UNTESTED on production (the `pg_dump` shape was executed on LOCAL in the per-migration rehearsals; the n8n database name `n8n_db` was verified with `pg_database` on the server, the dump command for it is UNTESTED). `df -h` runs first; the dump file names are variables (no glob in any redirect):
```bash
set -euo pipefail
. ./repro_vars.sh
need STAMP
BK=/root/backups
DUMP_APP="$BK/hosting3m_full_prerepro_${STAMP}.dump"
DUMP_N8N="$BK/n8n_db_prerepro_${STAMP}.dump"
df -h /root /var/lib/docker
docker exec n8n-enterprise-db psql -U n8n_user -d hosting3m_db -Atc "SELECT pg_size_pretty(pg_database_size('hosting3m_db')) || ' / ' || pg_size_pretty(pg_database_size('n8n_db'))"
read -rp 'Is there free space for both dumps (about 3x the sizes above)? Type YES to continue: ' ok; [ "$ok" = YES ]
mkdir -p "$BK"
docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > "$DUMP_APP"
docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc n8n_db > "$DUMP_N8N"
test -s "$DUMP_APP" && test -s "$DUMP_N8N"
docker exec -i n8n-enterprise-db pg_restore --list < "$DUMP_APP" > "$BK/list_app_${STAMP}.txt"
docker exec -i n8n-enterprise-db pg_restore --list < "$DUMP_N8N" > "$BK/list_n8n_${STAMP}.txt"
test -s "$BK/list_app_${STAMP}.txt" && test -s "$BK/list_n8n_${STAMP}.txt"
( cd "$BK" && md5sum "hosting3m_full_prerepro_${STAMP}.dump" "n8n_db_prerepro_${STAMP}.dump" > "prerepro_${STAMP}.md5" )
ls -l "$DUMP_APP" "$DUMP_N8N" "$BK/prerepro_${STAMP}.md5"
```
**1b. Copy the dumps OFF the VPS, from YOUR machine** — ⚠️ UNTESTED. **STOP if** a file is missing or `md5sum -c` does not print `OK` for both dumps:
```bash
set -euo pipefail
. ./repro_vars.sh
need STAMP VPS_SSH LOCAL_BACKUP_DIR
mkdir -p "$LOCAL_BACKUP_DIR"
scp "$VPS_SSH:/root/backups/hosting3m_full_prerepro_${STAMP}.dump" "$VPS_SSH:/root/backups/n8n_db_prerepro_${STAMP}.dump" "$VPS_SSH:/root/backups/prerepro_${STAMP}.md5" "$LOCAL_BACKUP_DIR/"
test -s "$LOCAL_BACKUP_DIR/hosting3m_full_prerepro_${STAMP}.dump" && test -s "$LOCAL_BACKUP_DIR/n8n_db_prerepro_${STAMP}.dump"
( cd "$LOCAL_BACKUP_DIR" && md5sum -c "prerepro_${STAMP}.md5" )
```
**1c. Workflow exports.** From the n8n editor, **download (Export) the three workflows as they are now** and keep them as `live_before_mcp.json`, `live_before_chat.json`, `live_before_whatsapp.json` — `v6/MCP Server Cattle`, `v6/ai/chat cattle`, `v6/WhatsApp Agent Catlte` (⚠️ UNTESTED: the names in the editor may differ slightly; use the ones you see). They are the fallback of steps 4-5.

## Step 2 — Database migrations, in repo order
Order: **084 → 085 → 086 → 087 → 088 → 090** (089 is step 7). One pass per migration; set `MIG` and `FILE` from this table for each pass:

| MIG | FILE |
|---|---|
| 084 | `084_repro_births_age.sql` |
| 085 | `085_repro_empadre.sql` |
| 086 | `086_repro_palpation.sql` |
| 087 | `087_repro_births.sql` |
| 088 | `088_repro_services.sql` |
| 090 | `090_repro_vet_code_semantics.sql` |

Before each pass (by hand): copy the `MIG_*` files to `/root/m$MIG` on the VPS and `md5sum` them against the table above. Then (✅ EXECUTED on LOCAL and on the throwaway database for every migration with these exact `psql` commands in phases 1-3b; the wrapper script and production are ⚠️ UNTESTED):
```bash
# usage:  MIG=087 FILE=087_repro_births.sql bash step2.sh
set -euo pipefail
. ./repro_vars.sh
need MIG FILE
docker exec n8n-enterprise-db rm -rf "/tmp/m$MIG"
docker cp "/root/m$MIG" "n8n-enterprise-db:/tmp/m$MIG"
$P -v expect=before -f "/tmp/m$MIG/${MIG}_state_check.sql" > "/root/${MIG}_state_before.txt" 2>&1
tail -3 "/root/${MIG}_state_before.txt"            # last line: ${MIG} state check (before): OK
$P -f "/tmp/m$MIG/$FILE" > "/root/${MIG}_dryrun.txt" 2>&1
tail -3 "/root/${MIG}_dryrun.txt"                  # ends in DRY RUN, no ERROR
read -rp "Dry run read and clean? Type APPLY to apply $FILE: " ok; [ "$ok" = APPLY ]
$P -v apply=true -f "/tmp/m$MIG/$FILE" > "/root/${MIG}_apply.txt" 2>&1
tail -5 "/root/${MIG}_apply.txt"                   # ${MIG}: OK and *** ${MIG} COMMITTED ***
$P -v expect=applied -f "/tmp/m$MIG/${MIG}_state_check.sql" > "/root/${MIG}_state_after.txt" 2>&1
tail -3 "/root/${MIG}_state_after.txt"             # ${MIG} state check (applied): OK
diff "/root/${MIG}_state_before.txt" "/root/${MIG}_state_after.txt" || true     # only NOTICE / OK / body / row-count lines may differ, NEVER a FINGERPRINT line
```
(For 090 `expect=before` is valid only before 090 exists.)

| Migration | Guard that can abort it (STOP, compare, do not force) | Notes |
|---|---|---|
| 084 | the file checks its own preconditions (see `084_RUNBOOK.md`) | see `084_RUNBOOK.md` |
| 085 | needs 084 (the file aborts otherwise) | new append-only tables |
| 086 | needs 084 and 085 (the file aborts otherwise) | new side table; **no seed rows** |
| 087 | **md5 guard of the live `sp_register_birth_event` = `8eaf6f52716165a6bc59f8f4a6a7ce4a`** | replaces the legacy births procedure with membership + exact retry |
| 088 | **md5 guards of `sp_log_breeding_event` = `2c1ff0adf25284e069ebf46ddc3108f8` and `sp_void_event` = `c81f6faec5e61a28eca5d24b0f62a61c`** | replaces those two procedures |
| 090 | **md5 guards of 7 bodies created by 086 / 088** (table in `090_RUNBOOK.md`) | adds the nullable column `repro_condition_codes.meaning` |

**STOP if** any guard aborts (the message names the live md5), any state check fails, a `FINGERPRINT` line differs, or a dry run errors. A guard abort means production differs from what was verified: compare the live body first.
**ROLLBACK (reverse order 090, 088, 087, 086, 085, 084; each drops nothing; 087 / 088 put the ORIGINAL bodies back and the state check verifies their md5)** — ⚠️ UNTESTED on production, ✅ executed on LOCAL per migration:
```bash
# usage:  MIG=090 bash rollback2.sh     (then MIG=088, 087, 086, 085, 084)
set -euo pipefail
. ./repro_vars.sh
need MIG
$P -v apply=true -f "/tmp/m$MIG/${MIG}_rollback.sql" > "/root/${MIG}_rollback.txt" 2>&1
tail -3 "/root/${MIG}_rollback.txt"
$P -v expect=rolled_back -f "/tmp/m$MIG/${MIG}_state_check.sql" > "/root/${MIG}_state_rolled_back.txt" 2>&1
tail -3 "/root/${MIG}_state_rolled_back.txt"       # ${MIG} state check (rolled_back): OK
```
**Smoke after step 2 (read-only, ⚠️ UNTESTED on production):**
```bash
set -euo pipefail
. ./repro_vars.sh
need OWNER_EMAIL COMPANY5_ARETE
$P -X -v owner="$OWNER_EMAIL" -v arete="$COMPANY5_ARETE" -f - <<'SQL'
SELECT sp_repro_get_dam_history('5', :'owner', :'arete')->>'status';       -- expect: ok
SQL
if $P -X -f - >/dev/null 2>&1 <<'SQL'
SELECT sp_repro_get_dam_history('5', 'nadie@example.test', 'x');
SQL
then echo "STOP: a stranger got an answer from the dam history"; exit 1; fi   # it must RAISE P0001
```
Do not call write tools in production except on company 3.

## Step 3 — The two seeds, back to back, BEFORE any palpation tool is connected to an agent
**Why this order:** with the 086 seed's pending rows in place and no meanings, a bare `NR` / `RP` / `NO APTO` would be accepted as an inferred VACÍA. So the 086 seed and the 090 seed run **one after the other, in this step, before step 4**. The 090 seed only touches rows the 086 seed left pending.
**STOP if** a dry run does not show company 5 as the expected company, lists a row you did not expect, the 090 seed aborts ("already has a condition or a different meaning"), or the verification below differs. **ROLLBACK:** each seed has an undo (below).

Dry run first (✅ EXECUTED on LOCAL for both seeds: the 086 seed in phase 3, the 090 seed applied and idempotent in phase 3b), then apply (⚠️ UNTESTED on production). `CONFIRMED_BY_086` is the value the owner states; the 090 seed always uses the foreman's value:
```bash
set -euo pipefail
. ./repro_vars.sh
need CONFIRMED_BY_086
# 3a  086 seed (UNE, UTCL1-3 confirmed by the veterinarians; RP, UTC2, NR, NO APTO, MATRIZ OCUPADA as known-pending)
$P -v confirmed_by="$CONFIRMED_BY_086" -f /tmp/m086/086_seed_tenant5_uterine_codes.sql > /root/086_seed_dryrun.txt 2>&1
cat /root/086_seed_dryrun.txt
read -rp 'The 086 seed dry run is as expected? Type APPLY: ' ok; [ "$ok" = APPLY ]
$P -v confirmed_by="$CONFIRMED_BY_086" -v apply=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql > /root/086_seed_apply.txt 2>&1
# 3b  090 seed (NR, RP, NO APTO get a meaning; confirmed by the ranch FOREMAN, not by a veterinarian)
$P -v confirmed_by='capataz (sin confirmacion veterinaria)' -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql > /root/090_seed_dryrun.txt 2>&1
cat /root/090_seed_dryrun.txt
read -rp 'The 090 seed dry run is as expected (differences = 0)? Type APPLY: ' ok; [ "$ok" = APPLY ]
$P -v confirmed_by='capataz (sin confirmacion veterinaria)' -v apply=true -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql > /root/090_seed_apply.txt 2>&1
```
Read each dry run before applying: company 5 is the expected company, the AFTER table shows what you expect, and for the 090 seed the "OTHER companies" difference count is **0**. The 090 seed only updates rows still pending (condition NULL and meaning NULL); it aborts instead of overwriting.
**Undo** (090 seed first; the values are literal because the undo ignores them):
```bash
$P -v confirmed_by=x -v undo=true -v apply=true -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql     # back to pending
$P -v confirmed_by=x -v undo=true -v apply=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql          # deletes only the 9 rows it inserted and nobody changed
```
**Verify — read-only, ⚠️ UNTESTED (the column names come from the 086 and 090 migrations):** the 9 rows of the 086 seed on company 5 as they must look **after 3a and 3b**:
```bash
$P -X -f - <<'SQL'
SELECT code, repro_condition, meaning, source, confirmed_by
  FROM public.repro_condition_codes
 WHERE id_company = 5
   AND code IN ('UNE', 'UTCL1', 'UTCL2', 'UTCL3', 'NR', 'RP', 'NO APTO', 'UTC2', 'MATRIZ OCUPADA')
 ORDER BY code;
SQL
```
| code | repro_condition | meaning | source | confirmed_by |
|---|---|---|---|---|
| `MATRIZ OCUPADA` | NULL | NULL | `pending veterinarian confirmation` | NULL |
| `NO APTO` | NULL | `UNFIT` | `SEED_090_FOREMAN_CONFIRMED` | `capataz (sin confirmacion veterinaria)` |
| `NR` | NULL | `NOT_EXAMINED` | `SEED_090_FOREMAN_CONFIRMED` | `capataz (sin confirmacion veterinaria)` |
| `RP` | NULL | `POSTPARTUM` | `SEED_090_FOREMAN_CONFIRMED` | `capataz (sin confirmacion veterinaria)` |
| `UNE` | `ESTATICA` | NULL | `SEED_086_VET_CONFIRMED` | the 086 value, lower-cased and trimmed |
| `UTC2` | NULL | NULL | `pending veterinarian confirmation` | NULL |
| `UTCL1`, `UTCL2`, `UTCL3` | `CICLANDO` | NULL | `SEED_086_VET_CONFIRMED` | the 086 value, lower-cased and trimmed |

**Exactly 9 rows.** After 3a alone (before 3b), `NO APTO`, `NR` and `RP` show `meaning` NULL and source `pending veterinarian confirmation`. **STOP if** there are fewer than 9 rows, any value differs, or a code already had another condition before the 086 seed (the seed never overwrites: a row from an earlier hand edit keeps its own values — review it).
Second check through the tool (read-only, ⚠️ UNTESTED):
```bash
set -euo pipefail
. ./repro_vars.sh
need OWNER_EMAIL
$P -X -v owner="$OWNER_EMAIL" -f - <<'SQL'
SELECT sp_repro_list_unmapped_uterine_codes('5', :'owner')->'meanings_configured';   -- 3 rows: NR, RP, NO APTO
SELECT sp_repro_list_unmapped_uterine_codes('5', :'owner')->'unmapped';              -- still lists UTC2 with known_pending: true
SQL
```

## Step 4 — n8n: export, diff against the repo, import the MCP server
The repo export is **assumed equal to the live workflow**. This step proves it before importing anything. **Do steps 4 and 5 in the same window** (see "Why 4 and 5 are one unit").

**4a. Diff the live workflows against the repo files as they were before this change** (⚠️ UNTESTED on the real exports; the script itself was run by the author on the repo files). `compare_workflow_export.py` exits 1 on any real difference, so the script stops:
```bash
set -euo pipefail
. ./repro_vars.sh
need COMMIT_BEFORE_PHASE5
V=workflows/09-MCP-Agent-Cattle/v6
git show "$COMMIT_BEFORE_PHASE5:$V/v6_MCP_Server_Cattle.json"      > repo_before_mcp.json
git show "$COMMIT_BEFORE_PHASE5:$V/v6_ai_chat_cattle.json"         > repo_before_chat.json
git show "$COMMIT_BEFORE_PHASE5:$V/v6_WhatsApp_Agent_Cattle.json"  > repo_before_whatsapp.json
python3 "$V/repro-phase5/compare_workflow_export.py" live_before_mcp.json repo_before_mcp.json
python3 "$V/repro-phase5/compare_workflow_export.py" live_before_chat.json repo_before_chat.json
python3 "$V/repro-phase5/compare_workflow_export.py" live_before_whatsapp.json repo_before_whatsapp.json
```
Each prints `RESULT: IDENTICAL`. **STOP if** any is `DIFFERENT`: production has manual changes (precedent: 2026-10-24, the mortality fix made by hand in the prompts). First incorporate the live change into the repo file, review it, and only then continue. Position-only differences are reported as info and are fine.

**What the live-vs-repo comparison will show after the import:** four EXISTING nodes differ in content — `list_lots` (SQL + description), and `register_birth_event`, `log_palpation_event_batch`, `log_palpation_event` (**toolDescription only**; `add_repro_tools.py` proves it) — plus the 24 new nodes and their connections. Anything else is a surprise: STOP.

**4b. The `list_lots` change is a change to an EXISTING tool's answer** (two new keys, no key removed or renamed). Prove it is additive **before** importing (⚠️ UNTESTED; read-only SQL, run it on LOCAL first). The generated SQL compares the old and the new query for company 3:
```bash
set -euo pipefail
. ./repro_vars.sh
need QA_MEMBER_EMAIL
python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/list_lots_diff.py --tenant 3 --email "$QA_MEMBER_EMAIL" --old-file live_before_mcp.json > list_lots_diff.sql
$P -X -f - < list_lots_diff.sql        # expect rows_old = rows_new; only_in_old = 0; only_in_new = 0; production_unit_id NULL = 0
```
**STOP if** `only_in_old` or `only_in_new` is not 0.

**4c. Import the MCP server.** n8n 2.x: `n8n import:workflow` DEACTIVATES what it imports and changes the `versionId`, so do it from the editor (same workflow id and webhook path), as the root `CLAUDE.md` says: open `v6/MCP Server Cattle`, replace its content with `v6_MCP_Server_Cattle.json` (paste into the canvas), check the Postgres credential on the new nodes (it is the same `Postgres account` as the existing tools), **Save and Publish**. ⚠️ UNTESTED.
The new tools are connected to the MCP trigger but **no agent mentions them yet**, so they stay inert until step 5.
**4d. Verify** (⚠️ UNTESTED): re-export the workflow as `live_after_mcp.json` (keep it: step 6b's rollback needs it) and compare with the new repo file (the script exits 1 on a difference):
```bash
python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py live_after_mcp.json workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json
```
→ `IDENTICAL` (and `Publish` really applied: the editor can leave a saved but unpublished version — the re-export shows it). In the editor the trigger must list 53 tools. The endpoint URL of the agents' `MCP Cattle Management` / `MCP Client` nodes stays `https://n8n.hosting3m.com/mcp/v6/cattle-management` (production) in the repo.
**STOP if** the import fails, the credential is missing, or the re-export differs. **ROLLBACK of step 4 alone (before step 5 starts):** import `live_before_mcp.json` (the export of step 1) the same way, Publish, re-export and compare it with `live_before_mcp.json` → `IDENTICAL`. The database changes of steps 2-3 stay (they are additive and the old tools still work with them).

## Step 5 — n8n: the two agent prompts (right after step 4, same window)
Import the two agent workflows the same way (4c) from `v6_ai_chat_cattle.json` and `v6_WhatsApp_Agent_Cattle.json`. They differ from the live ones **only** in the `systemMessage` of the node `AI Agent` (proved offline by `check_repro_consistency.js`). Do WhatsApp last. ⚠️ UNTESTED.
Verify: re-export both and compare with the repo files (`IDENTICAL`); from the repo, run the offline check (✅ executed by the author on the repo files; **75 passed, 0 failed** at the last run):
```bash
set -euo pipefail
V=workflows/09-MCP-Agent-Cattle/v6
python3 "$V/repro-phase5/compare_workflow_export.py" live_after_chat.json "$V/v6_ai_chat_cattle.json"
python3 "$V/repro-phase5/compare_workflow_export.py" live_after_whatsapp.json "$V/v6_WhatsApp_Agent_Cattle.json"
node "$V/repro-phase5/check_repro_consistency.js"        # exit 0, no FAIL (75 passed)
```
Then one read-only message per channel on company 3, **through the real channel** (never the editor's Chat / Test panel — Rules 6 and 11): "¿Cuántos partos hubo en los últimos 30 días?" → a total.
**STOP if** the import fails, a re-export differs, or the smoke message answers with a technical error.
**ROLLBACK of step 5 = rollback of steps 5 AND 4, together.** Import `live_before_chat.json`, `live_before_whatsapp.json` **and `live_before_mcp.json`**, Publish each, re-export each and compare with the saved export (`IDENTICAL`). **The MCP server must NOT stay on the new export:** its legacy tool descriptions say `OBSOLETA` while the previous prompts still tell the agents to use `register_birth_event` and `log_palpation_event_batch`. (The database stays.)

## Step 6 — QA on the owner's test company (company 3, never company 5)
Files: `REPRO_QA_SCRIPT.md` (40 dialogs, the exact messages, the expected tool and reply shape, a WhatsApp subset of 10) and `qa_fixtures.sql`. ⚠️ UNTESTED, all of it. **The kit uses run 2:** company 3 already holds 6 older test calves with tags `9999100001`..`9999100006`, so run 1 can never be applied there.
1. **Fixtures — LOCAL first**, then production. The file is applied from inside the container, so copy it first:
   ```bash
   set -euo pipefail
   . ./repro_vars.sh
   docker cp workflows/09-MCP-Agent-Cattle/v6/repro-phase5/qa_fixtures.sql n8n-enterprise-db:/tmp/qa_fixtures.sql
   $P -v run=2 -f /tmp/qa_fixtures.sql > /root/qa_fixtures_dryrun.txt 2>&1
   cat /root/qa_fixtures_dryrun.txt                  # read the identifier table it prints
   read -rp 'Fixture dry run as expected? Type APPLY: ' ok; [ "$ok" = APPLY ]
   $P -v run=2 -v apply=true -f /tmp/qa_fixtures.sql > /root/qa_fixtures_apply.txt 2>&1
   ```
   It writes only to company 3 and aborts if company 3 is not "Rancho El Palomar" (and, if a tag of the run already exists anywhere, it says how many, in which `tenant_id`, and lists up to 5).
   **There is NO cleanup script, on purpose:** company 3 is in production and the births, empadre and historical tables are append-only; the QA events remain as residue in the test company (every fixture row carries a QA marker: tags `99992#####` and fire numbers / names starting `QA5R2`). A second pass needs `-v run=3`.
2. Run the dialogs on **Chat Web (40) and WhatsApp (the subset of 10)**, writing into the tables of the QA script. WhatsApp needs the tester's phone linked to an ADMIN user of company 3 (how it is resolved, and a read-only check, are in the QA script, "Antes de empezar").
3. **Measure tool selection** (`gpt-4.1-mini`, 53 tools): at least **90 %** of the dialogs pick the right tool on the first try, **per channel** (WhatsApp: 10 dialogs, so at most 1 miss).
4. For "an animal of another company" use **only read tools** with the identifier you put in the placeholder of Q38.

**Pass criteria:** the measure ≥ 90 % on both channels, every "Criterios de aprobación adicionales" item of the QA script holds, no UUID / `lot_id` shown, no NIVEL 3 write without a "Sí", no NIVEL 2 write that asks for confirmation, **and no QA execution called either legacy tool (`register_birth_event`, `log_palpation_event_batch`)**.
**How to check that no QA execution called a legacy tool (⚠️ UNTESTED, in the n8n editor):**
1. First make sure successful executions are being saved (the `EXECUTIONS_DATA_SAVE_ON_SUCCESS` setting, the same one `089_RUNBOOK.md` Part 0 asks you to check). **If they are not saved, this check is impossible: STOP, do not do step 6b, and leave the two nodes in place.**
2. Executions → filter **Workflow = `v6/MCP Server Cattle`**, and the date range of the QA. Each tool call of an agent is one execution of that workflow.
3. Open every execution of the QA window: the canvas marks the nodes that ran. None may show data on `register_birth_event` or `log_palpation_event_batch`. (A shorter cross-check: in the agent workflows' executions, the `AI Agent` node's log lists the tool calls of each turn.)
4. Write down the number of executions reviewed and the window. The retention of executions bounds how long you can do this after the QA.
**STOP if** any criterion fails. **If the measure is below 90 %** (do exactly one, then re-run the whole QA):
- **(a) Trim the dictionary.** Remove, from section E and the NIVEL lists of **both** prompts (edit `update_prompts.py`, regenerate, and update the expected sets in `check_repro_consistency.js`), the least-used reproduction reads first: `identifier_quality_report`, `get_births_summary`, `list_unregistered_historical_births`, `get_births_config`, `get_empadre_config`. The nodes can stay in the MCP server. Re-import the two agents, re-run the consistency check and the QA.
- **(b) Move the agent to a stronger model.** Change the model of the node `OpenAI Chat Model` (Chat) and `OpenAI Chat Model1` (WhatsApp) in the editor; this changes cost and latency and is a separate decision of the owner; re-run the whole QA.
- **(c) Roll back to the previous prompts and tools** (the Step 5 rollback, which includes Step 4). The database stays.

## Step 6b — Delete the two legacy nodes from the MCP server (only after the QA passed)
This PR **keeps** `register_birth_event` and `log_palpation_event_batch` in the repo export; step 6b removes them from the LIVE server first and from the repo in a **separate follow-up commit**. Skip it if the executions check above was impossible or any criterion failed.
**6b.1 Build the export without the two nodes, with the proof** — the proof part was executed by the author on the repo export (53 → 51 tools, every remaining node and connection byte-identical); writing the file and importing it are ⚠️ UNTESTED:
```bash
set -euo pipefail
python3 - <<'PY'
import json
src = 'workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json'
dst = 'v6_MCP_Server_Cattle.6b.json'
LEGACY = ['register_birth_event', 'log_palpation_event_batch']
d = json.load(open(src, encoding='utf-8'))
names = {n['name'] for n in d['nodes']}
assert all(x in names for x in LEGACY), 'a legacy node is not in the export'
out = json.loads(json.dumps(d))
out['nodes'] = [n for n in out['nodes'] if n['name'] not in LEGACY]
for x in LEGACY:
    out['connections'].pop(x)
# --- proof: nothing else changed
by = {n['name']: n for n in d['nodes']}
keep = {n['name'] for n in out['nodes']}
assert len(out['nodes']) == len(d['nodes']) - 2 and len(out['connections']) == len(d['connections']) - 2
assert all(by[n['name']] == n for n in out['nodes']), 'a remaining node changed'
assert all(d['connections'][k] == v for k, v in out['connections'].items()), 'a remaining connection changed'
assert all(t['node'] in keep for v in out['connections'].values() for b in v.values() for l in b for t in l), 'a connection points at a removed node'
for k in ('name', 'pinData', 'active', 'settings', 'versionId', 'meta'):
    assert d[k] == out[k], k
tools = [n for n in out['nodes'] if n['type'].endswith('postgresTool')]
assert len(tools) == 51, len(tools)
with open(dst, 'w', encoding='utf-8') as fh:
    fh.write(json.dumps(out, indent=2, ensure_ascii=False))
print('OK: removed', LEGACY, '->', len(out['nodes']), 'nodes,', len(tools), 'tools; written', dst)
PY
```
**6b.2 Import** `v6_MCP_Server_Cattle.6b.json` into `v6/MCP Server Cattle` from the editor (as 4c), **Save and Publish**. ⚠️ UNTESTED.
**6b.3 Re-import check** (⚠️ UNTESTED): re-export as `live_after_6b.json` and compare; in the editor the trigger must list **51** tools; then one read-only message per channel on company 3 and a quick Q03 (a birth through the agent) to prove the agents do not need the deleted tools:
```bash
python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py live_after_6b.json v6_MCP_Server_Cattle.6b.json
```
→ `IDENTICAL`. **STOP if** it differs, the import fails or an agent message errors. **ROLLBACK of 6b:** import `live_after_mcp.json` (the export of 4d) the same way, Publish, re-export and compare → `IDENTICAL` (it brings both nodes back).
**6b.4 Follow-up commit (after 6b is verified):** replace `v6_MCP_Server_Cattle.json` in the repo with the 6b file, in a separate PR; in `check_repro_consistency.js` change the expected count from 53 to 51 and drop the two legacy exceptions; update backlog items 24-25. Never before 6b is verified live.

## Step 7 — 089 (disable the legacy `nacimiento` gateway model) — only after its pre-checks and a successful gateway check
Skip this step if any condition below fails; everything above works without 089.
1. **Pre-checks, read-only (⚠️ UNTESTED on production):** run `089_RUNBOOK.md`, Part 0: the **oldest retained n8n execution** and the EXECUTIONS_* retention settings, executions mentioning `nacimiento` for the CRUD workflow, and the **distribution of the `birth_events` source** (the agent births vs. other sources). **STOP if** any birth path other than the agent's still uses the model.
2. **State before / dry run / apply** exactly as `089_RUNBOOK.md` Part 1 (✅ EXECUTED on LOCAL in phase 4: apply, state_check, rollback, rolled_back, re-apply; throwaway tests 11/11). ⚠️ UNTESTED on production.
3. **Check through the REAL gateway** (⚠️ UNTESTED; needs an ADMIN token of company 3, obtained through the real login, never pasted into a chat — Rule 4). The token is read silently and never stored. Save this as its own script and run it:
```bash
set -euo pipefail
. ./repro_vars.sh
read -rsp 'ADMIN token of company 3 (hidden): ' TOKEN; echo
need TOKEN
curl -s -o /dev/null -w '%{http_code}\n' -X POST 'https://n8n.hosting3m.com/webhook/crud/v6/nacimiento' \
  -H "Authorization: Bearer $TOKEN" -H 'x-tenant-id: 3' -H 'Content-Type: application/json' \
  -d '{"entity":"nacimiento","table_name":"sp_register_birth_event","operation":"insert","fields":{}}'
# expect 403 ("Operacion no permitida para este modelo") and NO row created:
$P -X -f - <<'SQL'
SELECT count(*) AS births_in_the_last_5_minutes FROM birth_events WHERE created_at > now() - interval '5 minutes';
SQL
```
   If the shape of the body is wrong the gateway may answer another status: compare with a normal model to confirm the endpoint is the live one, and read the response body (Meta-CRUD errors can arrive as HTTP 200 with `error:true` — inspect the payload).
4. **Re-run Q03 and Q05 of the QA** (births through the agent) to prove the agent path does not depend on the model.
**STOP if** the gateway answers 200 with data, or a QA birth fails. **ROLLBACK:** `$P -v apply=true -f /tmp/m089/089_rollback.sql` then `$P -v expect=rolled_back -f /tmp/m089/089_state_check.sql` (restores the original row exactly).

## Step 8 — Merge `develop` into `main`, LAST
Only when steps 1-6 (6b and 7 if you did them) are verified. `main` deploys the frontends through Plesk, so first list what would be published (⚠️ UNTESTED shape):
```bash
set -euo pipefail
git diff --stat main...develop -- hosting3m-workspace/projects/agro-erp/src hosting3m-workspace/projects/
```
**STOP if** the diff contains frontend files that are not expected (this phase changes none). After the merge, record the merge commit (`MERGE_COMMIT=$(git rev-parse HEAD)`). **ROLLBACK:** `git revert -m 1 "$MERGE_COMMIT"` on `main` (no force push, no history rewrite); the database and n8n stay as they are.

---

## If the n8n import fails (steps 4-5)
1. Do not edit the workflow by hand in the editor to "make it work". Keep the error text.
2. Import the matching `live_before_*.json` of step 1, **Publish**, re-export and compare with the saved export (`IDENTICAL`). If the failure is in step 5, restore **all three** (chat, WhatsApp and MCP): see the step 5 rollback.
3. Check that the three workflows are active and the webhook / MCP endpoint answers (a read-only message on company 3).
4. The database stays as it is: 084-090 are additive and the legacy tools still work. If the failure needs the DB back too, use the reverse rollbacks of step 2.
5. Common causes to check first: the import deactivates the workflow (Publish again); the credential id of the new nodes; an unpublished saved version (only the re-export shows it); the Postgres node pointing at a different database than expected (Rule 11).

## Fallback summary
| Failure | Go back to |
|---|---|
| step 1 | nothing was changed; fix space / copy and repeat |
| step 2 / 3 | the per-migration rollback (reverse order) and the seed undos; the full backup of step 1 is the last resort |
| step 4 (MCP), before step 5 started | import `live_before_mcp.json` |
| step 5 (prompts) | import `live_before_chat.json`, `live_before_whatsapp.json` **and `live_before_mcp.json`** — rolling back step 5 also rolls back step 4 (the legacy tool descriptions say OBSOLETA while the old prompts still use those tools) |
| step 6 (QA below 90 %) | trim the dictionary, or a stronger model, or the step 5 rollback (which includes step 4) |
| step 6b | import `live_after_mcp.json` (the export of 4d) |
| step 7 (089) | `089_rollback.sql` |
| step 8 (main) | `git revert -m 1` of the merge |

## After the rollout (backlog, not part of it)
24. delete the node `register_birth_event`, 25. delete the node `log_palpation_event_batch` — **both in step 6b** once the QA passed and no QA execution called them; the repo export follows in a separate commit. 23. inject `tenant_id` and the e-mail from the trusted context for all MCP tools. 26. the QA residue in company 3. See `docs/reproduction-discovery.md`.
