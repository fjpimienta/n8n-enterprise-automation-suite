> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tests pass on a throwaway LOCAL database. NOT applied to production.**
> Part 1 (database) is the only part of this change. Part 2 (n8n): **none** — no workflow changes in this step. Frontend: **none** — nothing in the
> frontend depends on this step (no component reads or writes `cattle_identifier_history`). Step 2 (tag-change authorization) is a separate change and
> is not required for, nor included in, this one.

# Runbook — identifier history: company column, append-only, real actor and reason (step 1)

Migration number: 114 (113 is reserved for the audit work).

## What it does

| Object | Kind | Notes |
|---|---|---|
| `cattle_identifier_history.id_company` | column (new) | backfilled from `cattle_livestock.tenant_id`, then `NOT NULL`; two indexes by company |
| `trg_identifier_history_set_company()` + trigger | new, BEFORE INSERT | `id_company` always comes from the animal; a different value or an unknown animal is refused (`P0130`) |
| `trg_identifier_history_immutable()` + 2 triggers | new | UPDATE, DELETE and TRUNCATE are refused (`P0131`) |
| `trg_log_identifier_changes()` | replaced in place | real actor (`app.identifier_change_user`, `UNKNOWN` if unset), reason (`app.identifier_change_reason`, `CAPTURE_CORRECTION` if unset/empty, unknown value refused with `P0132`), free text (`app.identifier_change_notes`); NULL <-> `''` and edge spaces are not changes |
| `cattle_identifier_history_reason_check` | CHECK replaced | superset: adds `INITIAL_ASSIGNMENT`, `AUTHORIZED_CHANGE` |
| `crud_models` row `cattle_identifier_history` | data (1 row) | `INSERT` removed, `allowed_roles_insert = 'NONE'`, `id_company` added to `allowed_fields` and `schema_json`; read stays `ADMIN,EDITOR,CUSTOMER`, now filtered by company by the gateway |

Untouched: `cattle_livestock` (no column, trigger or privilege change), the authorization flow, `sp_update_livestock_tag`, every workflow, the frontend.
The history rows already there are only completed with `id_company` (their values are not modified).

Effect to expect after applying: a gateway client that used to INSERT history rows gets a refusal (the trigger on `cattle_livestock` is the only writer).
Nothing in the repository does that today.

## Part 1 — database

Environment rule: apply first in LOCAL on a **fresh database restored from a dump** (not the daily-restored one, which can keep objects the dump lacks),
verify, and only then on production in the same working session. Production is applied by the owner, one command at a time.

### 1. Preconditions (read-only; stop at the first one that fails)

1. **Backup.** Before touching anything that matters:
   ```sh
   pg_dump -Fc -t public.cattle_identifier_history -t public.crud_models -f history_guards_before_<date>.dump hosting3m_db
   chmod 600 history_guards_before_<date>.dump
   ```
   Keep the file outside the repository. Also save the current logger text: `\sf public.trg_log_identifier_changes()` into a private file.
2. **Fingerprint of the logger.** The migration only replaces the 047 text (or its own / the hardened rollback text). Check:
   ```sql
   SELECT md5(pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure));
   ```
   Expected: `7068e9a8e4af7364d16c41c2b77c7570` (LOCAL, measured 2026-11-26). **Production must be measured, not assumed**: run the query there and compare.
   A different value means the production text differs from the repository: **stop**, read the live text, and bring the difference to the owner. The
   migration aborts by itself on drift, but the check comes first.
3. **Read-only orphan / null check** (nothing is written; the output is counts only):
   ```sql
   BEGIN READ ONLY;
   SELECT count(*) AS history_rows,
          count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.cattle_livestock c WHERE c.id = h.cattle_livestock_id)) AS orphan_rows,
          count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.cattle_livestock c WHERE c.id = h.cattle_livestock_id AND c.tenant_id IS NULL)) AS animals_without_company
     FROM public.cattle_identifier_history h;
   SELECT count(*) AS gateway_rows FROM public.crud_models WHERE model_name = 'cattle_identifier_history';
   SELECT to_regclass('public.cattle_identifier_history') IS NOT NULL AS table_exists,
          to_regprocedure('public.trg_log_identifier_changes()') IS NOT NULL AS logger_exists,
          EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cattle_identifier_history' AND column_name = 'id_company') AS already_applied;
   ROLLBACK;
   ```
   Expected: `orphan_rows = 0`, `animals_without_company = 0`, `gateway_rows = 1`, both `exists` true. `already_applied = true` is fine (the migration is idempotent).
   `orphan_rows > 0` or `gateway_rows <> 1`: **stop** (the migration aborts on both).
4. Nobody else is running a bulk update of identifiers at that moment (the migration takes a short lock on the history table).

### 2. Dry run

```sh
psql -X -v ON_ERROR_STOP=1 -f 114_identifier_history_tenant_guards.sql
```
Expected: a notice `114_identifier_history_tenant_guards: OK (history rows now carrying id_company: N)` and `DRY RUN, rolled back`. `N` equals `history_rows` from step 1.3.
Nothing is committed.

### 3. Apply

```sh
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 114_identifier_history_tenant_guards.sql
```
Expected: the same notice and `COMMITTED`. Running it again changes nothing (idempotent).

### 4. Verification

```sql
-- a) column and triggers
SELECT is_nullable FROM information_schema.columns
 WHERE table_name = 'cattle_identifier_history' AND column_name = 'id_company';                  -- NO
SELECT tgname, tgenabled FROM pg_trigger
 WHERE tgrelid = 'public.cattle_identifier_history'::regclass AND NOT tgisinternal ORDER BY 1;   -- 3 rows: no_truncate, no_update_delete, set_company, all 'O'
-- b) every row carries the company of its animal (expected 0)
SELECT count(*) FROM public.cattle_identifier_history h
  JOIN public.cattle_livestock c ON c.id = h.cattle_livestock_id WHERE h.id_company IS DISTINCT FROM c.tenant_id;
-- c) logger fingerprint changed and has the new text
SELECT pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) LIKE '%identifier_change_notes%' AS new_logger;   -- t
-- d) gateway model
SELECT allowed_ops, allowed_roles_insert, allowed_roles_select, allowed_fields::jsonb ? 'id_company' AS has_company
  FROM public.crud_models WHERE model_name = 'cattle_identifier_history';   -- no INSERT, NONE, ADMIN,EDITOR,CUSTOMER, t
-- e) append-only (inside a transaction that is rolled back)
BEGIN; UPDATE public.cattle_identifier_history SET notes = notes WHERE false; DELETE FROM public.cattle_identifier_history WHERE false; ROLLBACK;
-- statements that touch zero rows do not fire row triggers; to see the refusal use the throwaway database and the tests file, never real rows.
```
Behaviour checks on **production** use the test company only (`id_company = 3`) and wait for step 2's tools; this step adds no tool, so no live
n8n test applies. The tests file (`114_tests.sql`) is the evidence and is run only on a throwaway database.

Gateway check (optional, after applying): a `getall` on `cattle_identifier_history` with the test company's token returns only rows whose `id_company` is that
company; the same call with another company's header returns none of them. Use placeholders for URL and token in any record of the test.

### 5. Rollback

**Order: step 2 (tag-change authorization) first, then step 1. Never roll step 1 back while step 2 is applied** (step 2 sets the actor and reason settings
and relies on the validation and the notes column).

```sh
psql -X -v ON_ERROR_STOP=1 -f 114_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 114_rollback.sql   # commit
```
What it leaves: a **hardened 047 logger** (marker `hardened-047-logger`: `NULLIF(current_setting(...), '')`, same defaults, no validation, no company, no
notes) — **not** the exact 047 text, so the md5 will not be `7068e9a8…` again; the append-only triggers switched **off** (not dropped); the gateway
`INSERT` restored. It keeps, because they are harmless supersets: the `id_company` column and indexes, the BEFORE INSERT company trigger, the wider reason
CHECK, `id_company` in `allowed_fields`, and every history row written meanwhile.
Re-applying the migration after a rollback restores the new rules (tested). To go back to the exact 047 text, use the logger text saved in precondition 1.
Full data restore (last resort, only with the owner): `pg_restore` of the dump from precondition 1 into a scratch database and compare before touching production.

## Changed files

See the PR description. The tests (`114_tests.sql`) and the LOCAL fixtures run **only** on a database whose name contains `test`
or `rehearsal`.
