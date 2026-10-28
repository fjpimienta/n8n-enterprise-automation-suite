# Production runbook — reproduction tracking (migrations 084-090) and the two livestock agents (phase 5)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LOS PASOS 1 A 7** (respaldo, base de datos, semillas, n8n, prompts, QA y — si aplica — 089, todo verificado con sus huellas).
> `main` despliega el frontend solo (Plesk) y este rollout depende de base de datos y de n8n: si se mergea antes, lo que dependa de ellos falla en producción.
> **Nada de este documento se ha ejecutado en producción.** Lo ejecuta el dueño, paso a paso, y se detiene en cada condición de parada.

**Who runs it:** the owner. **When:** a low-usage window; nobody edits workflows in the n8n editor during the rollout. **Order is strict:** `1 → 2 → 3 → 4 → 5 → 6 → 7 → 8`. Each step has a **STOP condition** and a **ROLLBACK**.
A step is never started until the previous one passed its verification.

## How to read the status of a command
- ✅ **EXECUTED** — the owner ran exactly this command (or its LOCAL / throwaway equivalent with another database name or folder) and it worked; the phase where that happened is named.
- ⚠️ **UNTESTED** — nobody has run it. This includes **everything on production**, the n8n import, the QA, the real gateway check and 089 on production.
  Several files of earlier phases failed on their first real run (a `CASE` inside an `IF` condition, a stale snapshot in a test): treat every UNTESTED block as a draft and read it before running it.
  If an UNTESTED command fails, **STOP**, keep the output, and do not improvise a workaround.

Conventions
```bash
# On the VPS (production). The same shape was executed on LOCAL with another database name.
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Every apply / rollback uses `$P -v apply=true -f <file>` **without `--single-transaction`** (each file owns its `BEGIN` ... `COMMIT`); without `-v apply=true` the file is a dry run. ✅ EXECUTED on LOCAL / throwaway in phases 1-3b.

## What is deployed
- **Database:** 084 (births and age tools) → 085 (empadre) → 086 (palpation condition) → 087 (checked births, historical births) → 088 (service ↔ birth link, hardened `sp_log_breeding_event` / `sp_void_event`, dam history) → 090 (foreman-confirmed code meanings). **089** (disables the legacy gateway model `nacimiento`) is deliberately **last and optional** (step 7).
  Two seeds (data, dry run by default): `086_seed_tenant5_uterine_codes.sql` and `090_seed_tenant5_vet_code_meanings.sql`.
- **n8n:** the MCP server `v6/MCP Server Cattle` gains **24 tool nodes** (and `list_lots` gains two NEW keys, `lot_id` and `production_unit_id`); both livestock agents (`v6/ai/chat cattle` and `v6/WhatsApp Agent Catlte`, node `AI Agent`) get a new prompt (sections A5, B1, B5, C, E and a new G). `AI Agent Palma` is not touched.
- **Frontend:** nothing.
- **Confirmation levels (owner's decisions):** reads = NIVEL 1; routine writes (single birth, palpation batch, empadre single / batch, services) = NIVEL 2, no confirmation; births by block, historical births and every void = NIVEL 3, a summary and an explicit "Sí". Every role may capture; death and sale still need an ADMIN.
- **Not exposed to the agents:** `sp_repro_condition_code_set`, `sp_repro_empadre_set_config`, `sp_repro_births_set_config`.
- **The old tools** `register_birth_event` and `log_palpation_event_batch` leave the agents' dictionary but their **nodes stay** in the MCP server (rollback path of 087). Their `toolDescription` (only that) now starts with `OBSOLETA: no la uses. Usa register_birth_checked.` / `... Usa log_palpation_with_condition.`; `log_palpation_event` (single) stays and gets one sentence: with a vet code use the wrapper with ONE element. Deleting the two nodes is backlog items 24-25.
  - Why they are obsolete: `register_birth_event` calls the 13-parameter `sp_register_birth_event` and resolves lot / UPP names with a partial `ILIKE ... LIMIT 1` (no ambiguity check); `log_palpation_event_batch` calls `sp_log_palpation_event` once per animal and turns ANY text without a PRE…ADA word into VACÍA — **it can overwrite a PREÑADA animal with VACÍA, without the 090 `NEEDS_EXPLICIT_RESULT` guard** (that guard lives only in `sp_repro_log_palpation_batch`).

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
| `repro-phase5/qa_fixtures.sql` | `21f3fe09d0cbaa02ae5d80fd26bf7e1b` |
| `repro-phase5/REPRO_QA_SCRIPT.md` | `906f6248480fba57dafcaf460550c42c` |

(Recompute with `md5sum` if a file is edited after this runbook was written. The per-migration runbooks `0NN_RUNBOOK.md` hold the detail of each migration and their own md5 tables.)

---

## Step 1 — Full backup
**STOP if** a dump is empty or cannot be listed. **ROLLBACK:** nothing was changed yet.

⚠️ UNTESTED on production (the same `pg_dump` shape was executed on LOCAL in the per-migration rehearsals):
```bash
mkdir -p /root/backups
docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > /root/backups/hosting3m_full_prerepro_$(date +%F_%H%M).dump
docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc n8n_db > /root/backups/n8n_db_prerepro_$(date +%F_%H%M).dump      # UNTESTED: confirm the n8n database name first (backup script / docker-compose)
ls -l /root/backups/*prerepro*                         # sizes > 0
docker exec -i n8n-enterprise-db pg_restore --list < /root/backups/hosting3m_full_prerepro_*.dump | head -5     # must list objects
```
Also, from the n8n editor, **download (Export) the three workflows as they are now** and keep them as `live_before_*.json`:
`v6/MCP Server Cattle`, `v6/ai/chat cattle`, `v6/WhatsApp Agent Catlte` (⚠️ UNTESTED: the names in the editor may differ slightly; use the ones you see). These files are the fallback of steps 4-5.

## Step 2 — Database migrations, in repo order
Order: **084 → 085 → 086 → 087 → 088 → 090** (089 is step 7). For EACH migration `NNN`, follow `NNN_RUNBOOK.md` Part 0 and Part 1 (✅ EXECUTED on LOCAL and on the throwaway database for every migration, with the results recorded in earlier phases; ⚠️ UNTESTED on production):

1. Copy the `NNN_*` files to `/root/mNNN`, `md5sum` them against the table above, `docker cp` into the container (`/tmp/mNNN`).
2. **State before:** `$P -v expect=before -f /tmp/mNNN/NNN_state_check.sql > /root/NNN_state_before.txt 2>&1` → last line `NNN state check (before): OK`. (For 090: `expect=before` is only valid before 090 exists.)
3. **Dry run** `$P -f /tmp/mNNN/<migration>.sql` → ends in `DRY RUN`, no error.
4. **Apply** `$P -v apply=true -f /tmp/mNNN/<migration>.sql` → `NNN: OK` and `*** NNN COMMITTED ***`.
5. **State after** `-v expect=applied` → `OK`; `diff` before / after differs only in NOTICE / OK / body / row-count lines, **never in a `FINGERPRINT` line**.

| Migration | Guard that can abort it (STOP, compare, do not force) | Notes |
|---|---|---|
| 084 | the file checks its own preconditions (see `084_RUNBOOK.md`) | see `084_RUNBOOK.md` |
| 085 | needs 084 (the file aborts otherwise) | new append-only tables |
| 086 | needs 084 and 085 (the file aborts otherwise) | new side table; **no seed rows** |
| 087 | **md5 guard of the live `sp_register_birth_event` = `8eaf6f52716165a6bc59f8f4a6a7ce4a`** | replaces the legacy births procedure with membership + exact retry |
| 088 | **md5 guards of `sp_log_breeding_event` = `2c1ff0adf25284e069ebf46ddc3108f8` and `sp_void_event` = `c81f6faec5e61a28eca5d24b0f62a61c`** | replaces those two procedures |
| 090 | **md5 guards of 7 bodies created by 086 / 088** (table in `090_RUNBOOK.md`) | adds the nullable column `repro_condition_codes.meaning` |

**STOP if** any guard aborts (the message names the live md5), any state check fails, a `FINGERPRINT` line differs, or a dry run errors. A guard abort means production differs from what was verified: compare the live body first.
**ROLLBACK (reverse order, each drops nothing):** `$P -v apply=true -f /tmp/mNNN/NNN_rollback.sql` then `-v expect=rolled_back -f NNN_state_check.sql`, for `090`, then `088`, `087`, `086`, `085`, `084`. The rollbacks of 087 / 088 put the ORIGINAL bodies back (the state check verifies their md5).
**Smoke after step 2 (read-only, ⚠️ UNTESTED on production):** `SELECT sp_repro_get_dam_history('5','<owner e-mail>','<an arete of company 5>')->>'status';` → `ok`; from a non-member e-mail it must raise `P0001`. Do not call write tools in production except on company 3.

## Step 3 — The two seeds, back to back, BEFORE any palpation tool is connected to an agent
**Why this order:** with the 086 seed's pending rows in place and no meanings, a bare `NR` / `RP` / `NO APTO` would be accepted as an inferred VACÍA. So the 086 seed and the 090 seed run **one after the other, in this step, before step 4**.
**STOP if** the dry run does not show company 5 as the expected company, or lists a row you did not expect, or the 090 seed aborts ("already has a condition or a different meaning"). **ROLLBACK:** each seed has an undo (below).

Dry run first (✅ EXECUTED on LOCAL for both seeds: the 086 seed in phase 3, the 090 seed applied and idempotent in phase 3b), then apply (⚠️ UNTESTED on production):
```bash
# 3a  086 seed (UNE, UTCL1-3 confirmed by the veterinarians; RP, UTC2, NR, NO APTO, MATRIZ OCUPADA as known-pending)
$P -v confirmed_by='<FILL: confirmed_by for the 086 seed — the owner will state it>' -f /tmp/m086/086_seed_tenant5_uterine_codes.sql            > /root/086_seed_dryrun.txt 2>&1
$P -v confirmed_by='<FILL: same value>' -v apply=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql                                              > /root/086_seed_apply.txt 2>&1
# 3b  090 seed (NR, RP, NO APTO get a meaning; ONLY rows the 086 seed left pending; confirmed by the ranch FOREMAN, not by a veterinarian)
$P -v confirmed_by='capataz (sin confirmacion veterinaria)' -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql                                    > /root/090_seed_dryrun.txt 2>&1
$P -v confirmed_by='capataz (sin confirmacion veterinaria)' -v apply=true -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql                      > /root/090_seed_apply.txt 2>&1
```
Read each dry run before applying: company 5 is the expected company, the AFTER table shows what you expect, and for the 090 seed the "OTHER companies" difference count is **0**. The 090 seed only updates rows still pending (condition NULL and meaning NULL); it aborts instead of overwriting.
**Undo:** `$P -v confirmed_by=x -v undo=true -v apply=true -f /tmp/m090/090_seed_tenant5_vet_code_meanings.sql` (back to pending) and `$P -v undo=true -v confirmed_by=x -v apply=true -f /tmp/m086/086_seed_tenant5_uterine_codes.sql` (deletes only the 9 rows it inserted and nobody changed). 090 seed undo first.
**Verify (read-only, ⚠️ UNTESTED on production):** `SELECT sp_repro_list_unmapped_uterine_codes('5','<owner e-mail>')->'meanings_configured';` → 3 rows (NR, RP, NO APTO) with `confirmed_by` = `capataz (sin confirmacion veterinaria)`, and `->'unmapped'` still lists `UTC2` with `known_pending: true`.

## Step 4 — n8n: export, diff against the repo, import the MCP server
The repo export is **assumed equal to the live workflow**. This step proves it before importing anything.

**4a. Diff the live workflow against the repo file as it was before this change** (⚠️ UNTESTED on the real export; the script itself was run by the author on the repo files):
```bash
git show <COMMIT_BEFORE_PHASE5>:workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json > repo_before_mcp.json     # <COMMIT_BEFORE_PHASE5> = the develop commit just before the phase 5 merge (git log --oneline -- that file)
python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py live_before_mcp.json repo_before_mcp.json
```
It prints `RESULT: IDENTICAL` and exits 0, or lists the differing nodes / connections. Repeat for the two agent workflows (`live_before_chat.json` vs the previous `v6_ai_chat_cattle.json`, `live_before_whatsapp.json` vs the previous `v6_WhatsApp_Agent_Cattle.json`).
**STOP if** any is `DIFFERENT`: production has manual changes (precedent: 2026-10-24, the mortality fix made by hand in the prompts). First incorporate the live change into the repo file, review it, and only then continue. Position-only differences are reported as info and are fine.

**What the live-vs-repo comparison will show after the import:** four EXISTING nodes differ in content — `list_lots` (SQL + description), and `register_birth_event`, `log_palpation_event_batch`, `log_palpation_event` (**toolDescription only**; `add_repro_tools.py` proves it) — plus the 24 new nodes and their connections. Anything else is a surprise: STOP.

**4b. The `list_lots` change is a change to an EXISTING tool's answer** (two new keys, no key removed or renamed). Prove it is additive **before** importing (⚠️ UNTESTED; read-only SQL, run it on LOCAL first):
```bash
python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/list_lots_diff.py --tenant 3 --email '<a member of company 3>' --old-file live_before_mcp.json > list_lots_diff.sql
$P -X -f list_lots_diff.sql        # expect rows_old = rows_new; only_in_old = 0; only_in_new = 0; production_unit_id NULL = 0
```
**STOP if** `only_in_old` or `only_in_new` is not 0.

**4c. Import the MCP server.** n8n 2.x: `n8n import:workflow` DEACTIVATES what it imports and changes the `versionId`, so do it from the editor (same workflow id and webhook path), as the root `CLAUDE.md` says: open `v6/MCP Server Cattle`, replace its content with `v6_MCP_Server_Cattle.json` (paste into the canvas), check the Postgres credential on the new nodes (it is the same `Postgres account` as the existing tools), **Save and Publish**. ⚠️ UNTESTED.
The new tools are connected to the MCP trigger but **no agent mentions them yet**, so they are inert until step 5.
**4d. Verify** (⚠️ UNTESTED): re-export the workflow and compare with the new repo file: `compare_workflow_export.py live_after_mcp.json workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json` → `IDENTICAL` (and `Publish` really applied: the editor can leave a saved but unpublished version — the re-export shows it). In the editor the trigger must list 53 tools. The endpoint URL of the agents' `MCP Cattle Management` / `MCP Client` nodes stays `https://n8n.hosting3m.com/mcp/v6/cattle-management` (production) in the repo.
**STOP if** the import fails, the credential is missing, or the re-export differs. **ROLLBACK of step 4:** import `live_before_mcp.json` (the export of step 1) the same way, Publish, re-export and compare it with `live_before_mcp.json` → `IDENTICAL`. The database changes of steps 2-3 stay (they are additive and the old tools still work with them).

## Step 5 — n8n: the two agent prompts
Import the two agent workflows the same way (4c) from `v6_ai_chat_cattle.json` and `v6_WhatsApp_Agent_Cattle.json`. They differ from the live ones **only** in the `systemMessage` of the node `AI Agent` (proved offline by `check_repro_consistency.js`). Do WhatsApp last. ⚠️ UNTESTED.
Verify: re-export both and compare with the repo files (`IDENTICAL`); from the repo, run the offline check (✅ executed by the author on the repo files; **64 passed, 0 failed** at the last run):
```bash
node workflows/09-MCP-Agent-Cattle/v6/repro-phase5/check_repro_consistency.js        # exit 0, no FAIL
```
Then one read-only message per channel on company 3, **through the real channel** (never the editor's Chat / Test panel — Rules 6 and 11): "¿Cuántos partos hubo en los últimos 30 días?" → a total.
**STOP if** the import fails, a re-export differs, or the smoke message answers with a technical error. **ROLLBACK of step 5 (back to the previous prompts):** import `live_before_chat.json` and `live_before_whatsapp.json`, Publish, re-export, compare → `IDENTICAL`. The MCP server may stay (the old prompts do not mention the new tools, and the old tools `register_birth_event` / `log_palpation_event_batch` are still there).

## Step 6 — QA on the owner's test company (company 3, never company 5)
Files: `REPRO_QA_SCRIPT.md` (40 dialogs, the exact messages, the expected tool and reply shape, a WhatsApp subset) and `qa_fixtures.sql`. ⚠️ UNTESTED, all of it.
1. **Fixtures — LOCAL first**, then production: `psql -v ON_ERROR_STOP=1 -v run=1 -f qa_fixtures.sql` (dry run: read the table it prints), then `-v apply=true`. It writes only to company 3 and aborts if company 3 is not "Rancho El Palomar".
   **There is NO cleanup script, on purpose:** company 3 is in production and the births, empadre and historical tables are append-only; the QA events remain as residue in the test company (every fixture row carries a `QA5R<run>` / `9999<run>#####` marker). A second pass needs `-v run=2`.
2. Run the dialogs on **Chat Web and WhatsApp (subset)**, writing into the tables of the QA script.
3. **Measure tool selection** (`gpt-4.1-mini`, ~51 tools): at least **90 %** of the dialogs that should call a tool pick the right tool on the first try, **per channel**.
4. For "an animal of another company" use **only read tools** with the identifier you put in the placeholder.

**Pass criteria:** the measure ≥ 90 % on both channels, every "Criterios de aprobación adicionales" item of the QA script holds, no UUID / `lot_id` shown, no NIVEL 3 write without a "Sí", no NIVEL 2 write that asks for confirmation.
**STOP if** any criterion fails. **If the measure is below 90 %** (do exactly one, then re-run the whole QA):
- **(a) Trim the dictionary.** Remove, from section E and the NIVEL lists of **both** prompts (edit `update_prompts.py`, regenerate, and update the expected sets in `check_repro_consistency.js`), the least-used reproduction reads first: `identifier_quality_report`, `get_births_summary`, `list_unregistered_historical_births`, `get_births_config`, `get_empadre_config`. The nodes can stay in the MCP server. Re-import the two agents, re-run the consistency check and the QA.
- **(b) Move the agent to a stronger model.** Change the model of the node `OpenAI Chat Model` (Chat) and `OpenAI Chat Model1` (WhatsApp) in the editor; this changes cost and latency and is a separate decision of the owner; re-run the whole QA.
- **(c) Roll back to the previous prompts and tools** (Step 5 rollback, then Step 4 rollback). The database stays.

## Step 7 — 089 (disable the legacy `nacimiento` gateway model) — only after its pre-checks and a successful gateway check
Skip this step if any condition below fails; everything above works without 089.
1. **Pre-checks, read-only (⚠️ UNTESTED on production):** run `089_RUNBOOK.md`, Part 0: the **oldest retained n8n execution** and the EXECUTIONS_* retention settings, executions mentioning `nacimiento` for the CRUD workflow, and the **distribution of the `birth_events` source** (the agent births vs. other sources). **STOP if** any birth path other than the agent's still uses the model.
2. **State before / dry run / apply** exactly as `089_RUNBOOK.md` Part 1 (✅ EXECUTED on LOCAL in phase 4: apply, state_check, rollback, rolled_back, re-apply; throwaway tests 11/11). ⚠️ UNTESTED on production.
3. **Check through the REAL gateway** (⚠️ UNTESTED; needs an ADMIN token of company 3, obtained through the real login, never pasted into a chat — Rule 4):
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST 'https://n8n.hosting3m.com/webhook/crud/v6/nacimiento' \
     -H "Authorization: Bearer $TOKEN" -H 'x-tenant-id: 3' -H 'Content-Type: application/json' \
     -d '{"entity":"nacimiento","table_name":"sp_register_birth_event","operation":"insert","fields":{}}'
   # expect 403 ("Operacion no permitida para este modelo") and NO row created; confirm with: SELECT count(*) FROM birth_events WHERE created_at > now() - interval '5 minutes';
   ```
   If the shape of the body is wrong the gateway may answer another status: compare with a normal model to confirm the endpoint is the live one, and read the response body (Meta-CRUD errors can arrive as HTTP 200 with `error:true` — inspect the payload).
4. **Re-run Q03 and Q05 of the QA** (births through the agent) to prove the agent path does not depend on the model.
**STOP if** the gateway answers 200 with data, or a QA birth fails. **ROLLBACK:** `$P -v apply=true -f /tmp/m089/089_rollback.sql` then `-v expect=rolled_back` (restores the original row exactly).

## Step 8 — Merge `develop` into `main`, LAST
Only when steps 1-6 (and 7 if you did it) are verified. `main` deploys the frontends through Plesk, so first list what would be published: `git diff --stat main...develop -- hosting3m-workspace/projects/agro-erp/src hosting3m-workspace/projects/` (⚠️ UNTESTED shape).
**STOP if** the diff contains frontend files that are not expected (this phase changes none). **ROLLBACK:** `git revert -m 1 <merge commit>` on `main` (no force push, no history rewrite); the database and n8n stay as they are.

---

## If the n8n import fails (steps 4-5)
1. Do not edit the workflow by hand in the editor to "make it work". Keep the error text.
2. Import the matching `live_before_*.json` of step 1, **Publish**, re-export and compare with the saved export (`IDENTICAL`).
3. Check that the three workflows are active and the webhook / MCP endpoint answers (a read-only message on company 3).
4. The database stays as it is: 084-090 are additive and the legacy tools still work. If the failure needs the DB back too, use the reverse rollbacks of step 2.
5. Common causes to check first: the import deactivates the workflow (Publish again); the credential id of the new nodes; an unpublished saved version (only the re-export shows it); the Postgres node pointing at a different database than expected (Rule 11).

## Fallback summary
| Failure | Go back to |
|---|---|
| step 2 / 3 | the per-migration rollback (reverse order) and the seed undos; the full backup of step 1 is the last resort |
| step 4 (MCP) | import `live_before_mcp.json` |
| step 5 (prompts) | import `live_before_chat.json` and `live_before_whatsapp.json`; the MCP server may stay |
| step 6 (QA below 90 %) | trim the dictionary, or a stronger model, or the step 5 + 4 rollbacks |
| step 7 (089) | `089_rollback.sql` |
| step 8 (main) | `git revert -m 1` of the merge |

## After the rollout (backlog, not part of it)
24. delete the node `register_birth_event`; 25. delete the node `log_palpation_event_batch` (after a verification period); 23. inject `tenant_id` and the e-mail from the trusted context for all MCP tools; 26. the QA residue in company 3. See `docs/reproduction-discovery.md`.
