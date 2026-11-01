# Runbook — CFDI expense invoices from the web chat (migrations 091, 092, 093)

> ⛔ **ORDEN DE DESPLIEGUE: base de datos → cfdi-service → n8n → frontend (`main`) AL FINAL.**
> `main` despliega el frontend solo (Plesk) y el frontend activa el botón de adjuntar (`attachments.enabled`): si se mergea antes de tener las partes 1 a 3, el chat acepta archivos que el backend no sabe procesar.
> *Production status: parts 1-4 are live since 2026-10-31 (see "Status in production"). This runbook is for audit, LOCAL rehearsals and any new environment.*

**Requires migration 084** (`fn_repro_ctx`). Order: **091 → 092 → 093**. Each file aborts at its first block if its predecessor is missing, and 092 / 093 abort if 091 was rolled back (the register function answers `disabled`).
Nothing existing is altered, replaced or dropped, except that **093 replaces the body of `sp_expense_invoice_register`** (same signature; 091's text is restored by `093_rollback.sql`).

## Status in production

| Item | Status |
|---|---|
| 091 | applied on 2026-10-30 |
| 092 | applied on 2026-10-30 |
| 093 | applied 2026-10-31 10:02 (America/Mexico_City), backup + state check OK |
| cfdi-service | container `n8n-cfdi-service` running; parser updated 2026-10-31 14:15 (concept amounts up to 6 decimals, PR #894 / #895) |
| n8n | `v6/ai/chat cattle` (33 nodes) and `v6/MCP Server Cattle` (56 nodes, 2 invoice tools) published |
| Frontend | `attachments.enabled = true` in agro-erp `app.config.ts`, deployed from `main` |
| QA | company 3: 2 invoices recorded; company 5: invoice recorded and receiver RFC auto-registered |

## What changes

- **Database.**
  - **091:** `company_tax_ids` (PK `id_company, rfc`; the same RFC may belong to several companies), `expense_invoices` (append-only, `UNIQUE (id_company, uuid)`, linked to its `cattle_expenses` row), `sp_company_tax_id_set` (ADMIN/OWNER only, never sets `qa_skip_sat`) and `sp_expense_invoice_register`. Errors: `P0095` append-only / not deletable, `P0096` cross-company reference.
  - **092:** `expense_invoice_drafts` (immutable except `previewed_*` / `consumed_at`; never deletable), `sp_expense_invoice_draft_create` (workflow only, **not** an agent tool), `sp_expense_invoice_preview` and `sp_expense_invoice_confirm`. Confirm is refused with `preview_required` unless a preview of the **same draft with the same category / description / date** happened in the last 15 minutes (params hash). A draft expires after 30 minutes.
  - **093:** if the receiver RFC is not registered for the company and the user is **ADMIN or OWNER**, the preview reports `rfc_new` / `rfc_new_notice` / `company_rfcs` (writes nothing) and the confirm inserts the RFC (label `AUTO factura <serie+folio>`, `is_active = true`, `qa_skip_sat = false`) in the same sub-transaction as the expense and the invoice. An EDITOR still gets `rfc_not_registered`. A deactivated RFC is **never** reactivated automatically. The SAT must answer `VIGENTE`.
- **cfdi-service** (`microservices/cfdi-service`): internal HTTP sidecar (port 4100, header `x-internal-token`) that parses the XML, checks the SAT status and stores the original (`infrastructure/data/cfdi/<company>/YYYY/MM/<sha256>.xml`).
- **n8n:** invoice branch in the chat workflow, two MCP tools, one paragraph in the chat system prompt (`🧾 FACTURAS (CFDI)`). **WhatsApp is not covered.**
- **Frontend:** optional attachment in `ui-chat`, enabled in agro-erp.

Nothing in this runbook is run by the assistant. Production is touched only by the owner, with the steps below.

Conventions
```bash
# On the VPS (production)
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Every apply and rollback: `$P -v apply=true -f <file>` **without** `--single-transaction`. Without `-v apply=true` the file is a dry run (it ends in `ROLLBACK`). The `*_state_check.sql` files are read-only: `$P -v expect=before|applied|rolled_back -f <file>`.

---

## Test database (LOCAL only — never production)

Create a throwaway database (name must contain `test` or `rehearsal`), load the schema, then run per migration, from the migrations folder copied into the container:

```bash
P='docker exec -w /tmp/m09x -i n8n-enterprise-db psql -U n8n_user -d hosting3m_rehearsal -v ON_ERROR_STOP=1'
$P -v expect=before -f 093_state_check.sql                 # STATE OK: before
$P -f 093_auto_receptor_rfc.sql                            # dry run: "*** DRY RUN: 093 rolled back"
$P -v apply=true -f 093_auto_receptor_rfc.sql              # "093 COMMITTED"
$P -v expect=applied -f 093_state_check.sql                # STATE OK: applied
$P -v tenant=3 -v admin=<ACTIVE_ADMIN_EMAIL> -f 093_tests.sql
```

`091_tests.sql`, `092_tests.sql` and `093_tests.sql` take `-v tenant=<non-palm company> -v admin=<active ADMIN/OWNER email of it>` and **roll everything back**. 093's tests switch the role to EDITOR inside the transaction. Expected for 093: `ALL 093 TESTS OK` (16 `OK T` lines per run). A full cycle (state → dry run → apply → state → tests → rollback → state → re-apply → state → tests) must show: the 11 fingerprint lines identical at every step, and only two distinct `register_def` md5 values (091 text and 093 text).

---

## Part 0. Baseline — on the VPS

1. `mkdir -p /root/repro/vps60`, copy the files of the migration there, `md5sum` them against the repo.
2. Full backup and size check (> 100 KB): `docker exec n8n-enterprise-db pg_dump -U n8n_user -d hosting3m_db -Fc > backup_preNNN_$(date +%Y%m%d_%H%M%S).dump`.
3. `$P -v expect=before -f NNN_state_check.sql` must print `STATE OK: before`. If it does not, **STOP**: do not apply on top of an unknown state.

## Part 1. Database (repeat for 091, then 092, then 093)

1. Dry run, review: `$P -f NNN_*.sql`. It must end with the "DRY RUN … rolled back" marker and no `COMMITTED`.
2. Apply: `$P -v apply=true -f NNN_*.sql` (prints `NNN COMMITTED`).
3. `$P -v expect=applied -f NNN_state_check.sql` → `STATE OK: applied`, and the fingerprint lines equal those of the dry run (the migration touched nothing it should not).
4. 091 only, **QA company 3**: `091_seed_qa_company3.sql` registers the generic RFC `XAXX010101000` with `qa_skip_sat = true` so test invoices (modified, without a valid stamp) can be registered there. It is QA only; deactivate that RFC with `sp_company_tax_id_set` when QA ends.

## Part 2. cfdi-service (VPS)

- **First install:** `bash deploy_cfdi_vps.sh prepare` then `start`. It adds the `cfdi-service` block to the VPS compose (with a backup), creates `infrastructure/data/cfdi` (uid 1000) and appends `CFDI_SERVICE_TOKEN` to `.env`. **Never paste the token in chat or in git**; copy it from the VPS `.env` straight into the n8n credential **"CFDI Service Token"** (Header Auth, header `x-internal-token`).
- **Update the code:** `bash update_cfdi_vps.sh dry`, review (only the expected files may differ), then `apply`. It refreshes **only** `microservices/cfdi-service` from `origin/main` (`git archive`, never a pull: the VPS repo has local changes), rebuilds and recreates **only** that container, and prints the rollback command. A restart alone does not update the parser: the code is baked into the image.
- Checks printed at the end: `health {"ok":true}`, `401` without token, reachable from n8n at `http://cfdi-service:4100`, the new code inside the image, the other containers still up.

## Part 3. n8n

1. **Empty the canvas first** (Import from File *adds* nodes), then import `workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json` (33 nodes) and `v6_MCP_Server_Cattle.json` (56 nodes).
2. Credentials: `CFDI Parse`, `CFDI SAT Status` and `CFDI Store` use **CFDI Service Token**; `Crear Borrador Factura` uses the Postgres account. No node may keep the `Header Auth Replicate` credential.
3. The two invoice tools (`preview_expense_invoice`, `register_expense_invoice`) must carry the same Query Parameters expression (sanitizers `em` / `nul` / `dt`): the model sends optional arguments as the text `"null"`, and an e-mail may arrive with a trailing comma.
4. Chat system prompt: the `🧾 FACTURAS (CFDI)` paragraph. Register must use **exactly** the category / description / date used in the preview.
5. Publish both workflows. Verify against the repo: `jq '.nodes|length'` → 33 and 56; both tools contain `const em =`.

## Part 4. Frontend

`attachments: { enabled: true }` in `projects/agro-erp/src/app/app.config.ts`. **The merge to `main` deploys it (Plesk).** Roll back by setting it to `false` and redeploying.

## Part 5. Verification

Real chat, ADMIN/OWNER user, XML of the company: preview shows issuer, total and SAT status → answer "Sí" → `recorded`. Then on the VPS: `bash verify_invoice_qa.sh <company>` → N invoices, N linked expenses, originals stored, no expenses without invoice from this flow.

| Case | Expected |
|---|---|
| Valid XML, ADMIN/OWNER | preview, then `recorded`; unknown receiver RFC is registered (`rfc_registered`) |
| Same invoice twice | refused as duplicate |
| PDF / photo | rejected (XML only) |
| Preview without "Sí" | nothing written; the draft expires |
| EDITOR | `rfc_not_registered` / refused by the database |
| Message without a file | the chat behaves as before |
| Amounts: concepts with 6 decimals, totals exact to the cent | accepted; a total off by one cent → `AMOUNTS_MISMATCH` |

As of 2026-10-31 the happy path and the 6-decimals case are verified live; the no-file, PDF, duplicate, EDITOR and abandoned-preview cases were verified live on 2026-11-01.

## Rollback (nothing here deletes data)

| Layer | How |
|---|---|
| Database | `$P -v apply=true -f 093_rollback.sql`, then 092, then 091 (this order), each followed by its `*_state_check.sql -v expect=rolled_back`. The functions answer `disabled` / 093 restores 091's text; tables and rows stay (append-only). RFC rows created by 093 stay; an ADMIN can deactivate them. |
| cfdi-service | the printed command: `tar xzf backup_cfdi_service_src_<stamp>.tgz -C <compose root>` then `docker compose build cfdi-service && docker compose up -d --no-deps cfdi-service` |
| n8n | re-import the previous export of each workflow (empty the canvas first) |
| Frontend | `attachments.enabled = false` and redeploy |

## Known limits

Web chat only, XML only (no WhatsApp, PDF or photo); the user e-mail is typed by the model in each tool call (the database validates membership, which is the only guard); `register_ranch_expense` can still register an expense without an invoice; originals of drafts that are never confirmed stay on disk; asset purchases (land) are not captured by chat; CI only runs CodeQL and GitGuardian.
