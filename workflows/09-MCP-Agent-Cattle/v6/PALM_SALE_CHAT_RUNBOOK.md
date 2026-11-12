> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested offline and with a local end-to-end run that does NOT use n8n. NOT imported anywhere.** Part 1 (database: migration 104) and the
> cfdi-service `sale` profile are already in production. **Part 2 (n8n) is this pull request:** two workflow files, imported by the owner only through the n8n
> UI (Import from file, Save, Publish). No frontend change: the chat widget already sends the attached file.

# Runbook — palm sale from an XML attached in the dashboard web chat

## What changes

| Piece | Change |
|---|---|
| **New** `v6_palm_sale_from_xml.json` (workflow `v6/palm sale from xml`) | Sub-workflow: validate input -> `POST /parse` (`profile: "sale"`) -> SAT status -> `/store` -> `sp_agri_register_sale` -> one fixed Spanish reply. No LLM, agent, `$fromAI` or MCP. **Saves no execution data on success or error.** |
| `v6_ai_chat_cattle.json` (workflow `v6/ai/chat cattle`) | Three nodes added and one connection changed: `Dominio[PALM] -> Palma: XML adjunto` (IF). XML attached -> `Venta Palma XML` (Execute Workflow, continues on error) -> `Palma: respuesta de venta` (fixed fallback text) -> existing `Respond to Webhook`. Not an XML -> `Catálogo Palma` exactly as today. The `OTHER` (livestock) output and the other 35 nodes are byte-identical. |

Rules of the route: palm domain only; an attached file whose name ends in `.xml` and whose type is `text/xml`, `application/xml` or `application/octet-stream`;
only the ADMIN of the company registers (the procedure re-checks); tenant, role and actor e-mail come from the verified session
(`Resolver Empresa Chat`, `Validar Token`), never from the message text or a model; direct load (no preview); void and balance are **not** part of this change.
Any other file, or no file, keeps today's behavior.

**Retention note (accepted):** the attachment arrives as base64 inside the webhook JSON, so the parent execution keeps that copy for 14 days
(`EXECUTIONS_DATA_MAX_AGE=336`), exactly as it already does for livestock invoices. The new sub-workflow keeps nothing, and the Execute Workflow node returns only
the reply text.

## Before the import (owner, production)

1. **Backup:** in n8n open `v6/ai/chat cattle` -> menu -> Download. Save it outside the repo and `chmod 600`. Note its `versionId`.
2. **Fingerprint against `main`:** `python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py <downloaded.json> <repo file at main>` must print
   `RESULT: IDENTICAL`. If production carries a manual change, stop: incorporate it into the repo first (lesson of 2026-10-24).
3. **Compare with this branch:** `node workflows/09-MCP-Agent-Cattle/v6/tests/diff_workflow_exports.mjs <downloaded.json> workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json`
   must list exactly: 3 nodes added (`Palma: XML adjunto`, `Venta Palma XML`, `Palma: respuesta de venta`), 0 removed, 0 changed, 35 byte-identical, connections changed:
   `Dominio` plus the three new sources. Anything else: stop.

## Import (UI only; never `n8n import:workflow`; never test from the editor panels)

Order matters: **sub-workflow first, then the chat workflow.**

1. Empty a new canvas and **Import from file** `v6_palm_sale_from_xml.json`. Check that the nodes show the credentials **"CFDI Service Token"** (three HTTP nodes) and
   **"Postgres account"** (`Registrar Venta`); pick them if the editor asks. Open **Settings** and confirm *Save failed/successful production executions* = **Do not save**.
   **Save**, then **Publish**. Note the workflow id from the URL.
2. Open `v6/ai/chat cattle`, empty the canvas, **Import from file** `v6_ai_chat_cattle.json`. In the node **`Venta Palma XML`** select the workflow
   **`v6/palm sale from xml`** from the list (the id of the repo file is a placeholder; the instance assigns its own) and check that the seven inputs are mapped
   (`id_company`, `actor_email`, `role`, `file_name`, `file_type`, `file_size`, `xml_base64`; if the editor shows them empty, map them again with the expressions of the repo file).
   **Save**, then **Publish**.
3. Export both again. `compare_workflow_export.py <new export> <repo file>` must differ only in the `workflowId` parameter of `Venta Palma XML` (instance id), nothing else.
   `diff_workflow_exports.mjs <backup> <new export>` must show the same list as step 3 above. (Optional follow-up PR: commit the instance ids.)

## Verification (production, palm TEST company, synthetic voucher only)

| # | Action | Expected |
|---|---|---|
| 1 | As ADMIN of the palm test company attach a synthetic XML (valid, with `(ticket N)`) and type any text | `✅ Venta registrada.` with folio, date, buyer, kg, price, total and ticket; the model is not involved |
| 2 | Same file again | `ℹ️ Esta factura ya estaba registrada; no se hizo ningún cambio.` |
| 3 | Valid XML without a ticket | registered + `Avisos:` with the ticket warning |
| 4 | As EDITOR of the same company, attach an XML | fixed administrator-only text (cfdi-service is not called) |
| 5 | Attach a PDF or an image in the palm chat | today's behavior (the agent answers; no sale) |
| 6 | Type a normal palm message without a file | the palm agent as before |
| 7 | Sub-workflow `v6/palm sale from xml` -> Executions | **empty** (nothing saved) |
| 8 | In the database (read-only) | one `REGISTER` audit row per accepted sale; no row for rejected ones except `REJECT` codes |

**Regression of the livestock chat (company 3, the test livestock company; never a client company):** (a) a normal message; (b) an invoice XML attachment: preview
and confirm as before; (c) a sale-order request; (d) a message with a PDF. All must behave exactly as before the import.

## Rollback

Re-import the backup of `v6/ai/chat cattle` from step 1 (empty the canvas, Import from file, Save, Publish) and re-run the livestock regression. The sub-workflow can stay
published and unused (nothing calls it) or be unpublished. Nothing in the database depends on the route: sales already registered stay (append-only); a wrong sale is voided
with `sp_agri_void_sale` (never deleted).

## Tests and what could not be run

* `node workflows/09-MCP-Agent-Cattle/v6/tests/test_palm_sale_route.mjs` (CI job *Agent workflow consistency*): structure of both workflows, the one changed connection,
  the real code and expressions with stubs, reply text for every procedure status and reason (taken from the SQL, so a new status forces a decision), parser errors, role and
  input checks, credentials as references only, settings `none`/`none`, no `$fromAI` or LLM node in the sub-workflow. The diff against the baseline runs when `origin/develop`
  does not yet contain the route.
* `E2E_DB=<throwaway database> node workflows/09-MCP-Agent-Cattle/v6/tests/e2e_palm_sale_local.mjs` (manual, needs docker): a small interpreter runs the exported nodes as written
  against a cfdi-service started in-process and a throwaway database with migration 104, a fake palm test company and a fake issuer RFC. It is **not n8n**.
* **Not run:** n8n itself (no import, no webhook call, no editor panel, by rule). Therefore not verified: that the editor accepts the hand-written Execute Workflow input mapping and
  trigger declaration exactly as exported (hence the explicit mapping check in Import step 2), the real behavior of Execute Workflow `onError`, the credential selection in the editor,
  how the widget renders the line breaks of the reply (plain text with `\n`; if they collapse, add `white-space: pre-line` to the message bubble in a later UI change).
* Known limits: originals of rejected vouchers stay on disk (content-addressed, private) because the file is stored before the procedure runs; the worst-case duration of the three cfdi-service
  calls plus the SAT retry is below Cloudflare's 100 s.
