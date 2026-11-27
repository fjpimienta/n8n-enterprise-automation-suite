> ✅ **DESPLEGADO EN PRODUCCIÓN (2026-11-27; reportado por el dueño, no verificable en el repo).** Las partes 1 (base de datos) y 2 (n8n) están completas, así que el aviso de orden de merge que abría este archivo ya no aplica.
> `main` se despliega desde el panel de hosting en modo **automático** para los sitios de la suite (no manual). Este cambio no trae código de aplicación de agro-erp, por lo que las reconstrucciones automáticas no cambian esas apps.

> **Status (2026-11-27): deployed.** Migrations 114, 115 and 116 are applied in production (reported by owner, not verifiable in repo). Verified read-only on a restored copy of production taken the same day (2026-11-27, reported by owner): all objects present, and a dry run of each migration ends OK and rolls back (idempotent). Local tests: the files in this folder, on a throwaway database.
> This runbook covers **PR 2a (database only)**. Part 2 (n8n: the new tools, the notification label, the `Resolver Tenant` fix) is PR 2b; the frontend is PR 2c;
> the guard on the identifier columns is PR 2d; bulk assignment is PR 2f. **Nothing in 2a creates a request by itself**: no workflow calls the new functions
> until 2b is imported, so applying 2a first is safe and invisible to users, with one exception (see "Visible effects").
> Requires step 1 (`114_identifier_history_tenant_guards`) applied first.

# Runbook — tag-change authorization, database part (PR 2a)

Migration number: 115 (113 is reserved for the audit work).

## What it does

| Object | Kind | Notes |
|---|---|---|
| `sp_assign_livestock_identifier(tenant, email, identifier, tag_type, value, preview_token)` | new | chip or fire number, only when empty; ADMIN/EDITOR; preview then execute |
| `sp_request_tag_change(tenant, email, identifier, tag_type, new_value, reason, preview_token)` | new | ear tag (empty or not), chip replacement, fire-number change: always a pending request |
| `sp_cancel_tag_change(tenant, email, request_id)` | new | requester or active ADMIN, same local day |
| `sp_apply_tag_change(request_id, approver)` | new, internal | runs only from the dispatcher (`app.tag_dispatch`) |
| `fn_resolve_identifier`, `fn_tag_*`, `fn_normalize_identifier` | new, read-only helpers | alias lookup (current wins, retired values found as `PREVIOUS`) |
| `tag_change_previews` + trigger `trg_tag_change_previews_company` | new table | single-use 10-minute tokens, CHECKs on e-mail case, hash shape, dates; the animal must belong to the company |
| `pending_authorizations_tipo_check` | CHECK replaced | adds `CAMBIO_ARETE` |
| `sp_resolver_autorizacion(uuid,varchar,varchar,text,jsonb)` | patched in place | one new dispatcher branch; refuses any text but md5 `84913beb0d1f4d0b4168c4789fa6c4b5` |
| `fn_pending_auth_one_pending_guard()` | patched in place | message names the type; refuses any text but md5 `aec290a3825f398bbfb7389923377abe` |
| `vw_cattle_event_log` | patched in place | `SOLICITUD_CAMBIO_ARETE` instead of a NULL event type; refuses unless the CASE appears exactly once |

Untouched: `cattle_livestock` (no column, trigger or privilege change), `trg_log_identifier_changes` (step 1), `fn_is_active_company_admin`, `sp_solicitar_autorizacion`,
every workflow, the frontend. Self-approval behaves exactly as for bajas (no check was added).

### Visible effects
- The event log (Bitácora) can show the new type as the raw code `SOLICITUD_CAMBIO_ARETE` until PR 2c adds its label. Only relevant once requests exist (after 2b).
- A pending tag change blocks a baja or a sale of that animal until midnight or until it is cancelled (`sp_solicitar_venta_orden` then answers "Ya tiene una solicitud pendiente" for that animal and refuses the whole order).

### Session flags (for whoever reads the code)
`app.tag_dispatch`: set by the dispatcher, read by `sp_apply_tag_change`. `app.identifier_gate`: set by `sp_assign_livestock_identifier` and `sp_apply_tag_change` right before
their UPDATE, read by the guard of PR 2d. `app.identifier_change_user/_reason/_notes`: set by the same two functions, read by the step 1 logger. All are cleared right after use, and
`''` means unset. They are an application-level guard (gateway, panel, fixed workflow queries); direct database sessions are out of their scope.

## Part 1 — database

Apply first in LOCAL on a **fresh database restored from a dump**, verify, then production in the same session, applied by the owner one command at a time.

### 1. Preconditions (read-only; stop at the first that fails)
1. **Step 1 applied:** `SELECT count(*) FROM information_schema.columns WHERE table_name='cattle_identifier_history' AND column_name='id_company';` → 1, and
   `SELECT pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) LIKE '%identifier_change_notes%';` → t.
2. **Fingerprints of the three objects that are patched in place** (LOCAL values measured 2026-11-26; **measure production, do not assume**):
   ```sql
   SELECT md5(pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure));  -- 84913beb0d1f4d0b4168c4789fa6c4b5
   SELECT md5(pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure));                                              -- aec290a3825f398bbfb7389923377abe
   SELECT regexp_count(pg_get_viewdef('public.vw_cattle_event_log'::regclass, true), 'THEN ''SOLICITUD_VENTA''::text\s+ELSE NULL::text');   -- 1
   ```
   A different value means production differs from the repository: **stop**, read the live text and bring the difference to the owner (the migration also aborts by itself).
3. **No leftovers:** `SELECT count(*) FROM public.pending_authorizations WHERE tipo_evento NOT IN ('BAJA_MORTANDAD','VENTA');` → 0.
4. **Backup** (outside the repository, permissions 600):
   ```sh
   pg_dump -Fc -t public.pending_authorizations -t public.crud_models -f tag_change_before_<date>.dump hosting3m_db
   ```
   Also save the text of `sp_resolver_autorizacion`, `fn_pending_auth_one_pending_guard` and `pg_get_viewdef('vw_cattle_event_log', true)` to private files.
5. **Evidence in a throwaway database first:** `115_tests.sql` ("ALL TESTS PASSED") and `115_concurrency_check.sh` ("ALL CONCURRENCY CHECKS PASSED").

### 2. Dry run
```sh
psql -X -v ON_ERROR_STOP=1 -f 115_tag_change_authorization.sql
```
Expected: `115_tag_change_authorization: OK` and `DRY RUN, rolled back`.

### 3. Apply
```sh
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 115_tag_change_authorization.sql
```
Expected: the same notice and `COMMITTED`. Running it again changes nothing.

### 4. Verification (read-only)
```sql
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='pending_authorizations_tipo_check';          -- lists CAMBIO_ARETE
SELECT pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure) LIKE '%sp_apply_tag_change%';  -- t
SELECT pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure) LIKE '%cambio de arete%';  -- t
SELECT pg_get_viewdef('public.vw_cattle_event_log'::regclass, true) LIKE '%SOLICITUD_CAMBIO_ARETE%';             -- t
SELECT to_regprocedure('public.sp_assign_livestock_identifier(text,text,text,text,text,text)') IS NOT NULL,
       to_regprocedure('public.sp_request_tag_change(text,text,text,text,text,text,text)') IS NOT NULL,
       to_regprocedure('public.sp_cancel_tag_change(text,text,text)') IS NOT NULL,
       to_regprocedure('public.sp_apply_tag_change(uuid,text)') IS NOT NULL;                                      -- t, t, t, t
SELECT count(*) FROM public.pending_authorizations WHERE tipo_evento = 'CAMBIO_ARETE';                            -- 0
```
Behaviour on production is verified in PR 2b with the real n8n nodes and the test company (`id_company = 3`); 2a adds no tool, so there is no live behaviour test here.

### 5. Rollback
**Order when several parts are applied: 2d (guard) → 2b (re-import the original workflows) → 2a (this script) → step 1. Never roll a lower part back while a higher one is applied.**
```sh
psql -X -v ON_ERROR_STOP=1 -f 115_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 115_rollback.sql   # commit
```
What it does: restores the dispatcher, the guard message and the event log to their original text (the tests compare the md5 round trip), puts the CHECK back to two values,
and turns the four public functions into stubs that answer `disabled`. It keeps the read-only helpers and the `tag_change_previews` table.

**It refuses (and changes nothing) when any `CAMBIO_ARETE` row exists in `pending_authorizations`, in any state** — the CHECK cannot go back while such rows exist, and deleting rows from
an approvals table is not something a rollback does. Once real requests exist, the supported way to "turn it off" is therefore not this script:
1. Re-import the original workflows (PR 2b rollback): nobody can create requests any more.
2. Let the pending ones be resolved or cancelled (they expire at midnight).
3. Leave the schema as it is. If the owner still wants the schema rolled back, that is a decision with the rows in front of them (export, then decide); do not improvise a `DELETE`.

## Files of this PR
`115_tag_change_authorization.sql`, `115_rollback.sql`, `115_tests.sql`, `115_concurrency_check.sh`, this runbook.
The tests and the concurrency script run **only** on a database whose name contains `test` or `rehearsal`.

## What follows
| PR | Content |
|---|---|
| 2b | n8n -DEV workflows: tools `assign_livestock_identifier`, `request_tag_change`, `cancel_tag_change`; prompt dictionaries; retire `update_livestock_tag`; `get_livestock_info` through `fn_resolve_identifier`; notification label; `Resolver Tenant` rejects a phone that matches more than one user |
| 2c | frontend: labels for the new type, identifier fields read-only in the edit modal |
| 2d | guard on the three identifier columns (own migration, applied last) |
| 2f | bulk assignment (pasted list or CSV, dry-run summary, one confirmation) on top of `sp_assign_livestock_identifier` |
