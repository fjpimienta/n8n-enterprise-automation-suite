> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested offline only (structure, real expressions and code with stubs, exhaustive routing table). NOT imported anywhere.**
> Part 1 (database) is already in production: migration 109 (`sp_cfdi_classify`) and 110 (expense registration refuses sales). **Part 2 (n8n) is this pull request:** one workflow file,
> `v6_ai_chat_cattle.json`, imported by the owner only through the n8n UI (Import from file, Save, Publish). No SQL, no frontend and no cfdi-service change.
> **The classifier itself cannot be exercised in the local n8n** (the local database lacks 104–110): the routing behaviour is verified only by the production tests of this runbook.

# Runbook — XML router of the web chat (classify the voucher before choosing the flow)

## What changes

Today the chat decides what to do with an attached XML by the company domain only: palm companies send every `.xml` to the sale sub-workflow (a fuel expense then fails with a unit message) and livestock companies send every attachment to the expense chain.
The router asks the classifier first: is the voucher a **sale**, an **expense**, **ambiguous** or **unknown** for the active company?

| Piece | Change |
|---|---|
| `v6_ai_chat_cattle.json` (workflow `v6/ai/chat cattle`) | **9 nodes added and one connection rewired** (`Empresa Valida` valid-company output now goes to the new `XML adjunto?`; it used to go to `Dominio`). The other 38 nodes are byte-identical. The agent prompts are untouched. |
| `tests/test_xml_router.mjs`, `repro-phase5/check_repro_consistency.js`, `.github/workflows/ci.yml` | offline test of the router; the consistency check now expects the new nodes (deliberately); the test runs in the *Agent workflow consistency* CI job. |

New nodes, in order: `XML adjunto?` (IF; same expression as `Palma: XML adjunto`, any domain) → `Preparar XML del router` (Code; base64 only, size limit) → `XML del router OK` (IF) → `CFDI Parse del router` (HTTP; the existing parse call, default profile) →
`Parse del router OK` (IF) → `RFC del comprobante` (Code; keeps only the two RFCs) → `Clasificar comprobante` (Postgres: `sp_cfdi_classify`) → `Ruta del comprobante` (Switch) → `Texto fijo del comprobante` (Code; fixed Spanish texts, no model) → the existing `Respond to Webhook`.

The classifier receives: tenant = the `id_company` of `Resolver Empresa Chat` (verified membership), e-mail = the verified session e-mail (`Validar Token`), and the two RFCs of the parsed voucher, all as query parameters. Never the request body, the message text or the model.

| Classifier answer (+ company domain) | Route |
|---|---|
| `SALE` + palm | existing `Venta Palma XML` (ADMIN only, as today) |
| `SALE` + any other domain | fixed text: it looks like a sale, this chat does not register sales for this company type, nothing registered |
| `EXPENSE` + livestock or unknown domain | existing `Trae Factura` chain, unchanged |
| `EXPENSE` + palm | fixed text: expenses from XML are not available for palm companies yet; register it manually in Gastos as "facturado" with the folio (a later PR replaces this branch) |
| `AMBIGUOUS` | fixed text: cannot decide purchase vs sale, the company is on both sides, nothing registered |
| `UNKNOWN` / `NEITHER` + livestock or unknown domain | existing `Trae Factura` chain (the ask flow of 093 applies; the 110 gate protects it) |
| `UNKNOWN` / `NEITHER` + palm | fixed text: the RFCs of the voucher match no RFC configured for this company, nothing registered |
| anything else: error, `FORBIDDEN`, `INVALID_INPUT`, `DISABLED`, empty or unreadable answer | fixed text "could not classify", **stop** (fail closed); never reaches a registration path |
| no XML attached, a PDF or an image, an XML that cannot be read or parsed | `Dominio` exactly as today (the existing nodes produce their existing messages) |

The fixed texts never echo an RFC, a UUID, a name or an amount. The role is not decided here: `Venta Palma XML` keeps ADMIN only and the livestock chain keeps its own rules.
How the fixed text is answered: `Texto fijo del comprobante` returns `{output: <text>}` into the existing `Respond to Webhook` (the same pattern as `Palma: respuesta de venta`).

**Behaviour changes to be aware of (intended):** a palm voucher is now classified before the sale sub-workflow: a palm sale whose issuer is not one of the company's configured RFCs now gets the "RFCs do not match" text instead of the sub-workflow's own message, and a palm voucher with the company on both sides is refused as ambiguous.
The parse runs twice for the livestock expense path (once here, once in `Preparar Archivo Factura` / `CFDI Parse`); the first run is only used to read the two RFCs.
**Retention note (accepted):** the execution data of the chat workflow (14 days) now also holds the parse result of the router call, like it already holds the existing `CFDI Parse` result.

## Before the import (owner, production)

1. **Backup:** in n8n open `v6/ai/chat cattle` → ⋯ → Download. Save it outside the repo and `chmod 600`. Note its `versionId`.
2. **Fingerprint against `main`** (production may carry manual changes): `git show origin/main:workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json > /tmp/main_chat.json`, then
   `python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py <downloaded.json> /tmp/main_chat.json` must print `RESULT: IDENTICAL`, and the snippet of the root `CLAUDE.md` (step 3 of the n8n runbook) must print `No differences.`.
   The only accepted difference is the `workflowId` of `Venta Palma XML` (the instance id of the sub-workflow). If production has any other difference, **stop**: incorporate it into the repo first.
3. **Compare with this branch:** `node workflows/09-MCP-Agent-Cattle/v6/tests/diff_workflow_exports.mjs <downloaded.json> workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json` must list exactly:
   9 nodes added (the list above), 0 removed, 0 changed, 38 byte-identical, connections changed: `Empresa Valida` plus the 9 new sources. Anything else: stop.
   Also confirm that `credentials`, `webhookId`, `typeVersion` of the existing nodes and `settings` are equal (the tool above compares every node byte for byte).
4. Confirm `v6/palm sale from xml` is published and that migrations 109 and 110 are applied: `psql -X -v ON_ERROR_STOP=1 -v expect=applied -f hosting3m-workspace/projects/agro-erp/database/migrations/109_state_check.sql` (and `110_state_check.sql`).

## Import (UI only; never `n8n import:workflow`; never test from the editor panels)

1. Open `v6/ai/chat cattle`, empty the canvas, ⋯ → **Import from file** `v6_ai_chat_cattle.json`.
2. Check the credentials: `Clasificar comprobante` → **Postgres account**; `CFDI Parse del router` → **CFDI Service Token**. Select them if the editor asks. Do not type or paste any secret.
3. In `Venta Palma XML` select the workflow **`v6/palm sale from xml`** from the list (the file carries a placeholder id; the instance has its own) and check that the seven inputs are mapped (`id_company`, `actor_email`, `role`, `file_name`, `file_type`, `file_size`, `xml_base64`).
4. **Save**, then **Publish**. (In n8n 2.x production keeps the previously published version until you press Publish; the first import once stayed saved but unpublished: the re-download below catches it.)
5. Confirm the workflow name and published state did not change.
6. **Download the workflow again** and compare it with the repo file: `compare_workflow_export.py <new export> <repo file>` may differ only in the `workflowId` of `Venta Palma XML`; `diff_workflow_exports.mjs <backup> <new export>` must show the list of step 3 above. Do not consider it deployed until they match.

## Verification (production, TEST companies only)

Use only the test companies: **3** (livestock, "Rancho El Palomar") and **10** (palm, test plantation). **Never 5, 6, 7 or 8**, never a client company. Use the real web chat of the dashboard, **never the n8n editor panels** (Test / Chat) — they do not follow the real tenant flow.
Check each result in the chat and then in **Executions** (production list, not the editor panel): the path taken is the expected one and the answer text is the fixed text where one is expected.

**Synthetic XML without real data.** Build the vouchers outside the repo, in a temporary directory with `chmod 700`, and delete them afterwards:
* Start from the diesel voucher of the cfdi-service test fixtures (`microservices/cfdi-service/test/fixtures/`, issuer and receiver are public SAT test values) or from the synthetic voucher generator of `microservices/cfdi-service/test/palm-sale.test.js` (palm sale).
* Swap the `Rfc="..."` of `cfdi:Emisor` and `cfdi:Receptor` with a text editor to create each case. The parser does not verify the seal, only the amounts and the structure. Totals must stay consistent.
* The RFC owned by each test company is read from the database into a shell variable with a read-only query and substituted with `sed`; it is never typed in a document, a prompt or a commit. For company 3 the owned RFC is the QA test RFC of its seed; for company 10 it is its configured issuer RFC.
* A swapped voucher is still a stamped-looking file with a fake UUID: SAT answers "not found" and the flows that need `VIGENTE` stop with their own message. That is fine: the router tests below only need the route and the first reply.

| # | Company / role | Voucher | Expected |
|---|---|---|---|
| 1 | 3 (livestock) ADMIN | company RFC as **issuer** (a sale) | fixed text "parece una venta … este chat no registra ventas para este tipo de empresa … No registré nada"; nothing stored (no draft, no RFC) |
| 2 | 3 ADMIN | company RFC as **receiver**, another issuer (an expense) | the normal invoice flow: the agent shows the preview with the draft |
| 3 | 3 ADMIN | neither RFC is the company's | the existing 093 flow (preview that says the receiver RFC will be registered); answer **No** — do not confirm |
| 4 | 3 ADMIN | company RFC on both sides (if the QA RFC allows it) | fixed text "no puedo decidir si es una compra o una venta … No registré nada" |
| 5 | 10 (palm) ADMIN | company issuer RFC as issuer, a palm sale voucher | the existing sale flow (`✅ Venta registrada.` or its own message) |
| 6 | 10 ADMIN | company RFC as **receiver**, diesel concept (a fuel expense) | fixed text "Por ahora no puedo registrar gastos desde un XML en empresas de palma … Gastos … facturado … folio" |
| 7 | 10 ADMIN | neither RFC is the company's | fixed text "Los RFC de la factura no coinciden con ningún RFC configurado para esta empresa" |
| 8 | 10 EDITOR | a palm sale voucher | the existing administrator-only text (the route reaches `Venta Palma XML`, which checks the role) |
| 9 | 3 and 10 | a message **without** a file | the agent answers exactly as before |
| 10 | 3 and 10 | a **PDF** or an image | exactly as before (livestock: "solo puedo leer facturas en formato XML"; palm: the palm agent) |
| 11 | 3 | an `.xml` that is not a CFDI (a few bytes of text) | exactly as before (the existing message about the invoice), no classifier text |
| 12 | any | classifier failure path | **not testable in production** without breaking the database: it is covered offline (empty, malformed, `FORBIDDEN`, `INVALID_INPUT`, `DISABLED`, error and unknown answers all go to the fixed text). Do not roll back 109 to test it. |

Also check in **Executions**: for the refused cases (1, 4, 6, 7) the run ends in `Texto fijo del comprobante` → `Respond to Webhook` and **none** of `Venta Palma XML`, `Trae Factura`, `Crear Borrador Factura` ran. For case 2 the run goes through `Trae Factura`.
Check in the database (read-only) that tests 1, 4, 6 and 7 left no new row in `expense_invoice_drafts`, `expense_invoices` or `agri_sale_invoices`.
**Regression of the livestock chat (company 3):** a normal message; an invoice XML attachment (preview and confirm as before, then void/clean the test expense per the usual procedure); a sale-order request; a message with a PDF. All must behave as before the import.

## Rollback

Re-import the backup of step 1 (empty the canvas, Import from file, check `Venta Palma XML` points to the sub-workflow, Save, Publish) and re-run the regression of the livestock chat and cases 5, 9 and 10. Nothing in the database depends on the router: no row is written by it. Sales and expenses registered during the tests are append-only and are voided with their procedures, never deleted.

## Tests and what could not be run

* `node workflows/09-MCP-Agent-Cattle/v6/tests/test_xml_router.mjs` (CI job *Agent workflow consistency*): structure and wiring, the one rewired connection, the real expressions and code with stubbed inputs, an exhaustive table of role × reason × domain (315 combinations) and the fixed texts, no RFC / UUID / digit in any text, and the diff against `origin/develop` (9 nodes added, 38 byte-identical).
* `node workflows/09-MCP-Agent-Cattle/v6/repro-phase5/check_repro_consistency.js --baseline-ref origin/develop`: 206 checks, 5 of them new for the router (expectations updated deliberately).
* **Not run:** n8n itself (no import, no webhook call, no editor panel, by rule), and the classifier inside n8n (the local database lacks 104–110). Therefore **not verified until the production tests above:** that the editor accepts the new nodes as exported, the real Switch evaluation on the Postgres output shape (`result` as an object), the credential selection, the `onError` behaviour of the HTTP and Postgres nodes, and the rendering of the texts in the widget.
