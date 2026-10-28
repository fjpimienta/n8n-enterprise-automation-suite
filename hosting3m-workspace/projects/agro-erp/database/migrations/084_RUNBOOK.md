# Runbook — Reproduction tracking, phase 1 (migration 084 + n8n query tools)

> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` despliega el frontend solo (Plesk): si se mergea antes, la pantalla nueva falla en producción.
> *This phase does not touch the frontend; the merge still goes last, per the rule.*

**What changes**
- **Database (084, functions + 1 type + 1 view only):** the `numero_fuego` age parser, `vw_animal_effective_birth`, and 5 read-only
  tools `sp_repro_*`. No table, column, trigger or `crud_models` row; `sp_register_birth_event`, `sp_log_breeding_event`,
  `sp_log_palpation_event` and `sp_void_event` are **not touched** (the state check fingerprints their bodies).
- **n8n:** 5 `postgresTool` nodes added to `v6/MCP Server Cattle` (`workflows/09-MCP-Agent-Cattle/v6/repro-phase1/`).
  They stay invisible to the agent until the two system prompts list them (phase 5), so this phase changes no chat behaviour.
- **Frontend:** nothing.

⚠️ **Strict order: database → n8n.** If the tools reach n8n first they fail with `function sp_repro_… does not exist`
(harmless today because the agent does not know them). The database rollback does not drop anything: the tools answer
`{"status":"disabled"}`, so the reverse order is safe too.

Nothing in this runbook is run by the assistant. Production is touched only by the owner, with the steps below.

## Part 0. Preparation (local)

- Verify the files (md5 in the table at the end of this file) before copying them to the VPS.
- Fingerprint script: `python3 -I ~/node_fingerprints.py <export.json>` (repo copy: `node_fingerprints.py`).
- Baseline (read-only), saved to a file and compared at the end:

  ```bash
  P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
  $P -v expect=before -f /tmp/m084/084_state_check.sql > /root/084_state_before.txt 2>&1
  ```

## Part 1. Database (VPS, container `n8n-enterprise-db`, database `hosting3m_db`)

1. **Backup first** (affected tables + the whole schema, in `/root`, size must be > 0):

   ```bash
   mkdir -p /root/backups
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc \
     -t public.birth_events -t public.cattle_breeding_events -t public.cattle_livestock \
     -t public.cattle_weight_logs -t public.cattle_health_logs -t public.event_voids \
     hosting3m_db > /root/backups/hosting3m_repro_tables_pre084_$(date +%F_%H%M).dump
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc --schema-only hosting3m_db \
     > /root/backups/hosting3m_schema_pre084_$(date +%F_%H%M).dump
   ls -l /root/backups/*pre084*
   ```

2. **Copy and verify:** copy `084_*` to `/root/m084/`, run `md5sum /root/m084/084_*` and compare with the table below, then
   `docker cp /root/m084 n8n-enterprise-db:/tmp/m084`.
3. **State before:** `$P -v expect=before -f /tmp/m084/084_state_check.sql > /root/084_state_before.txt 2>&1` → must end with
   `084 state check (before): OK`. Keep the FINGERPRINT lines.
4. **Dry run** (rolls back): `$P -f /tmp/m084/084_repro_births_age.sql > /root/084_dryrun.txt 2>&1` → `084: OK` and `DRY RUN`.
5. **Tests — LOCAL or a throwaway copy only, never production** (they insert fixtures and roll back; they refuse to run if
   `T084` fixtures or an `electronic_rfid = ''` already exist): `…/084_tests.sql` → `passed | failed | total` with `failed = 0`.
6. **Apply** (the repo convention: `-v apply=true -f FILE`, **no `--single-transaction`**; each file owns its `BEGIN` ... `COMMIT` and `ON_ERROR_STOP` stops it at the first error before the `COMMIT`, so nothing is left half-applied; the flag would only add the warnings *"there is already a transaction in progress"* / *"there is no transaction in progress"*):

   ```bash
   $P -v apply=true -f /tmp/m084/084_repro_births_age.sql > /root/084_apply.txt 2>&1
   tail -5 /root/084_apply.txt     # expect: 084: OK  and  *** 084 COMMITTED ***
   ```

7. **State after:** `$P -v expect=applied -f /tmp/m084/084_state_check.sql > /root/084_state_after.txt 2>&1` → `084 state check (applied): OK`;
   `diff /root/084_state_before.txt /root/084_state_after.txt` must differ **only** in the NOTICE/OK lines, never in the FINGERPRINT lines.
8. **Read-only smoke test** in production (tenant 5, the owner's own account; prints counts, no names):

   ```sql
   SELECT (sp_repro_list_births('5','<owner email>', '2020-01-01', current_date::text, '1')->>'total') AS births,
          (sp_repro_identifier_quality_report('5','<owner email>')->>'animals_in_scope') AS animals;
   ```

   and, from a user of another company, `SELECT sp_repro_list_births('5','<other company user>')` must **raise** `P0001`.

**Rollback:** `$P -v apply=true -f /tmp/m084/084_rollback.sql > /root/084_rollback.txt 2>&1`, then
`-v expect=rolled_back` state check. Re-apply is the same command as step 6 (idempotent, `CREATE OR REPLACE`).

## Part 2. n8n (`v6/MCP Server Cattle`) — only if Part 1 state check is `applied`

1. Download the production export and take its fingerprint (`python3 -I ~/node_fingerprints.py`); stop if it does not match the
   expected *before* fingerprint recorded for the previous deployment.
2. In the editor: paste `repro_phase1_tools.json`, check the 5 nodes are connected to `MCP Server Cattle`, **save and Publish**.
3. **Download again and verify with the *after* fingerprint** (the editor can leave a saved but unpublished version).
4. Rollback: re-import the export of step 1 and publish.

## Part 3. Frontend

Nothing. (Only "if 1 and 2 are OK" applies to later phases.)

## Files and md5

| File | md5 |
|---|---|
| `084_repro_births_age.sql` | `b3008ac99618ab8d9fabd81daeff45ec` |
| `084_tests.sql` | `56cea57c52b9efaf206e83582c944dde` |
| `084_rollback.sql` | `aa9aa76bca26f6366b7f2362957234ff` |
| `084_state_check.sql` | `44e8b1d3071d878ee74f39c14912b8a4` |
| `repro_phase1_tools.json` | `96c7317f6dd330a2bc3afa1dd7bf4ada` |

(Recompute with `md5sum` if any file is edited after this runbook was written.)

