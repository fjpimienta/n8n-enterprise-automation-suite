> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested offline only (structure, real expressions and code with stubs, wiring of every failure edge). NOT imported anywhere.**
> Part 1 (database) is already in production: migrations 109 (`sp_cfdi_classify`) and 111 (`sp_agri_expense_invoice_*`). **Part 2 (n8n) is this pull request:** one workflow file, `v6_ai_chat_cattle.json`, imported by the owner only through the n8n UI. No SQL, no frontend and no cfdi-service change. The frontend does not depend on it (nothing to deploy in Part 3).
> **Production already contains the XML router (#1151).** The comparison against `develop` below must show only this PR's changes.

# Runbook — palm expense from an XML in the web chat

## What changes

Until now `EXPENSE` + palm answered a fixed text ("not available yet"). Now the router sends it to a chain of nine new nodes and the palm agent finishes the job with two new tools.

```
Ruta del comprobante (new 4th output: EXPENSE_PALM)
  → Preparar Archivo Factura Palma → Archivo Factura Palma OK → CFDI Parse Palma (profile "sale") → Parse Palma OK
  → CFDI SAT Status Palma → CFDI Store Palma → Store Palma OK → Crear Borrador Factura Palma (sp_agri_expense_invoice_draft_create, CHAT_WEB)
  → Armar Aviso Factura Palma → Catálogo Palma (existing) → AI Agent Palma (existing)
every "not OK" branch  ─────────────────────────────→ Armar Aviso Factura Palma ([FACTURA_ERROR: ...])
```

| Piece | Change |
|---|---|
| New nodes (11) | the 9 chain nodes above plus the tools `preview_palm_expense_invoice` (`sp_agri_expense_invoice_preview`) and `register_palm_expense_invoice` (`sp_agri_expense_invoice_confirm`), connected to `AI Agent Palma` as `ai_tool`. |
| `Ruta del comprobante` | a fourth rule `EXPENSE_PALM` (role `EXPENSE` and domain `PALM`) is **appended**; the three existing rules keep their output numbers and the fallback moves from output 3 to output 4. |
| `Texto fijo del comprobante` | the palm-expense text and its branch were removed (dead code: that answer no longer reaches the node; if it ever did, it would say "could not classify"). |
| `AI Agent Palma` | the `text` input now appends the `[FACTURA ...]` notice when the chain ran (same mechanism as the livestock `AI Agent`; with no XML it is exactly the chat input as before); the prompt gets the two tools in S2 and one `FACTURA XML` paragraph before `ESTILO`. Nothing else in the node changed. |
| Everything else | the other 44 existing nodes are byte-identical (the livestock chain and agent, the palm sale route, the palm tools, the classifier). WhatsApp has no router and is not touched. |

**Where the data comes from.** Tenant: `Resolver Empresa Chat` (verified membership). E-mail: `Validar Token`. Both in the draft node **and** in the two tools, by expression; the model only supplies `draft_id`, `category`, `description`, `expense_date`, `plantation` and `lot`. The chain never reads `chatInput`, the headers or the body for tenant, e-mail or role (the prepare node reads only the attached file). Roles are decided by the database: `sp_agri_expense_invoice_*` accept only ADMIN/OWNER and the 109 classifier gate refuses sales, ambiguous and unknown vouchers.

**Why the chain ends in `Catálogo Palma`.** The palm prompt reads `$('Catálogo Palma')`; going straight to `AI Agent Palma` would break its expressions. `Catálogo Palma` is only a read-only catalogue query.

**Parse profile.** `sale` was verified in `microservices/cfdi-service`: it only *adds* `tipoComprobante`, `formaPago`, `metodoPago` and, per concept, `claveUnidad`, `cantidad`, `valorUnitario`. It applies no sale rule and does not restrict units (no `KGM` check). One extra requirement: `Cantidad` and `ValorUnitario` must be valid decimals (≤ 6 decimals), which CFDI 4.0 already demands. With the default profile the payment-form warning and the quantity/unit would be lost.

**Accepted limits.** The parse runs twice (router and chain). The execution data (14 days) holds the parsed voucher, like the livestock chain already does. The `[FACTURA ...]` notice carries supplier name, RFCs, folio, total and the first concepts; it reaches the model only for ADMIN/OWNER (the draft procedure refuses other roles, so an EDITOR gets a refusal notice without amounts). The notice strips control characters, `<`, `>`, backticks, quotes and brackets from every voucher text so a supplier name cannot forge a second notice.

## Before the import (owner, production)

1. **Backup:** n8n → `v6/ai/chat cattle` → ⋯ → Download. Save it outside the repo, `chmod 600`. Note its `versionId`.
2. **Fingerprint production vs `main`:** `git show origin/main:workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json > /tmp/main_chat.json`, then
   `python3 workflows/09-MCP-Agent-Cattle/v6/repro-phase5/compare_workflow_export.py <downloaded.json> /tmp/main_chat.json`. Production already has the router, so if `main` does not have it yet (#1151 reaches `main` with its own release) the router nodes will show up as a difference: that is expected **only** if the list is exactly the 9 router nodes + the `Empresa Valida` connection. Any other difference (e.g. a manual prompt edit): **stop** and incorporate it into the repo first. The only accepted difference of a node is the `workflowId` of `Venta Palma XML`.
3. **Fingerprint production vs `develop`:** `node workflows/09-MCP-Agent-Cattle/v6/tests/diff_workflow_exports.mjs <downloaded.json> <(git show origin/develop:workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json)` must print **nodes added 0, removed 0, changed 0** (modulo the `workflowId` of `Venta Palma XML`). If not, stop.
4. **Compare with this branch:** the same tool, `<downloaded.json>` against this branch's file, must list exactly:
   * 11 nodes added: `Preparar Archivo Factura Palma`, `Archivo Factura Palma OK`, `CFDI Parse Palma`, `Parse Palma OK`, `CFDI SAT Status Palma`, `CFDI Store Palma`, `Store Palma OK`, `Crear Borrador Factura Palma`, `Armar Aviso Factura Palma`, `preview_palm_expense_invoice`, `register_palm_expense_invoice`;
   * 0 removed; 3 changed (`parameters` only): `AI Agent Palma`, `Ruta del comprobante`, `Texto fijo del comprobante`; 44 byte-identical;
   * connections changed: `Ruta del comprobante` plus the 11 new sources. Anything else: stop.
5. Confirm migrations 109 and 111 are applied: `psql -X -v ON_ERROR_STOP=1 -v expect=applied -f hosting3m-workspace/projects/agro-erp/database/migrations/109_state_check.sql` and `111_state_check.sql`.
6. **Read-only database baseline (before any test):** counts and latest ids of `agri_expense_invoices`, `expense_invoice_drafts` and `agri_expenses` for company 10 (`SELECT count(*), max(created_at) ... WHERE id_company = 10`). Keep them to compare after.

## Import (UI only; never `n8n import:workflow`; never test from the editor panels)

1. Open `v6/ai/chat cattle`, empty the canvas, ⋯ → **Import from file** → `v6_ai_chat_cattle.json`.
2. **Re-select** what the editor does not carry over: in `Venta Palma XML` pick the workflow **`v6/palm sale from xml`** and check the seven inputs; in `CFDI Parse Palma`, `CFDI SAT Status Palma` and `CFDI Store Palma` the credential **CFDI Service Token**; in `Crear Borrador Factura Palma`, `preview_palm_expense_invoice` and `register_palm_expense_invoice` the credential **Postgres account**; also re-check `Clasificar comprobante` and `CFDI Parse del router`. Never type or paste a secret.
3. **Save**, then **Publish**. Confirm the name and published state did not change.
4. **Download the workflow again** and compare it with the repo file: `compare_workflow_export.py <new export> <repo file>` may differ only in the `workflowId` of `Venta Palma XML`; `diff_workflow_exports.mjs <new export> <repo file>` must show no differences. If the editor left a saved-but-unpublished version, only this comparison reveals it.

## Verification (production, TEST company 10 only)

Company **10** only (palm, test plantation). **Never 7, 5, 6 or 8.** Use the real web chat of the dashboard, **never the editor panels**. After each test open **Executions** (production list) and check the path.

**Synthetic XML without real data.** Build the vouchers outside the repo in a `chmod 700` temporary directory and delete them afterwards. Start from a fixture of `microservices/cfdi-service/test/fixtures/` (public SAT test values) or from the generator in `microservices/cfdi-service/test/palm-sale.test.js`; swap `Rfc` of `cfdi:Emisor` / `cfdi:Receptor` and keep the totals consistent (the parser does not verify the seal). The RFC of company 10 is read with a read-only query into a shell variable and substituted with `sed`; it is never typed in a document or commit. Each fresh test needs a **new UUID** (change the `UUID` of the stamp; a reused one answers `duplicate`). SAT will answer "not found" for a synthetic UUID, so the flow stops with `sat_not_valid`: **tests 1–3 (a full registration) need a voucher SAT reports as VIGENTE, which a synthetic file never is.** Options, in order of preference: (a) the owner sends one of their own test vouchers issued to the test company's RFC through a test PAC; (b) a voucher swapped to the company's RFC from a real stamped test voucher of the owner (the SAT check uses issuer, receiver, total and UUID, so swapping an RFC breaks it again); (c) accept that only the routing, the draft, the preview and the refusal paths can be proven in production and prove registration in LOCAL with a stubbed SAT status. **Decide (a)/(c) before starting.**
For the fuel category the concept's `ClaveProdServ` must start with `1510` (`fn_agri_cfdi_category`; the SAT key family is still a `TODO(verify)` in migration 111), and for quantity and unit `ClaveUnidad` `LTR` with a decimal `Cantidad`.

| # | User / voucher | Expected |
|---|---|---|
| 1 | ADMIN of 10; company RFC as **receiver**, fuel concept (`1510…`, `LTR`), SAT VIGENTE | the agent shows the preview: supplier, folio, date, category **COMBUSTIBLE**, quantity and unit, scope question (plantation/lot, default "general de la empresa"), "¿Confirmas?" |
| 2 | same chat, answer with a plantation/lot of company 10, then **Sí** | the agent calls preview again with the scope, then register with the same arguments → "Gasto registrado" with date and scope; one new row in `agri_expenses` and `agri_expense_invoices` |
| 3 | the same XML again | `duplicate` explained ("ya estaba registrada"); no new row |
| 4 | void the test expense from the app (Gastos), then send the same XML again | the flow works again and registers (the voided link frees the UUID) |
| 5 | an EDITOR of company 10, if one exists (`qa-editor-palma@example.test`, test data) with a purchase XML | the agent says the role does not allow it, **no amounts**, no draft row |
| 6 | ADMIN of 10; a palm **sale** XML (company RFC as issuer) | the existing sale flow (`✅ Venta registrada.` or its own message) |
| 7 | ADMIN of 10; neither RFC is the company's | fixed text "Los RFC de la factura no coinciden…"; no draft |
| 8 | ADMIN of 10; company RFC on both sides | fixed text "No puedo decidir…"; no draft |
| 9 | ADMIN of 10; purchase XML **not** VIGENTE (a synthetic one) | the agent explains `sat_not_valid` (no vigente / no verificable); no expense row (a draft row is expected: the draft stores the SAT status) |
| 10 | ADMIN of 10; purchase XML, answer **No** to the summary | nothing is registered; the draft stays unconsumed |
| 11 | a message with a **PDF** or an image; a plain message without file; an `.xml` that is not a CFDI | exactly as before (palm agent / "no es un CFDI" message); none of the new nodes ran |
| 12 | livestock company 3: an invoice XML (expense), a sale XML, a plain message | exactly as before (the livestock chain; fixed text for the sale) |

Check in **Executions**: refused paths (tests 7, 8 and the EDITOR) never ran `Preview`/`register` tools; tests 7, 8, 11 and 12 never reached `Crear Borrador Factura Palma`; in test 2 the agent called `preview_palm_expense_invoice` before `register_palm_expense_invoice` and the arguments are identical; the tool calls show the tenant and e-mail of the session, not model values.
**Read-only database checks** after the tests: compare with the baseline of step 6: new rows only in the tests that were meant to write (`expense_invoice_drafts` per accepted voucher; `agri_expenses` / `agri_expense_invoices` only for tests 2 and 4); no row for any other company id; the consumed draft has `consumed_at` set. Never run a destructive statement; voids go through the app.

## Rollback

Re-import the backup of step 1 (empty the canvas, Import from file, re-select `Venta Palma XML` and the credentials, Save, Publish) and re-run tests 6, 11 and 12. Nothing in the database depends on the workflow: drafts expire by themselves and expenses are voided from the app, never deleted.

## Tests and what could not be run

* `node workflows/09-MCP-Agent-Cattle/v6/tests/test_palm_expense_xml.mjs` (new; CI job *Agent workflow consistency*): wiring and every failure edge, the real expressions and code with stubs (session first, the model supplies only six values, notice forging, agent input with and without the notice), no RFC/UUID/amount literal, credentials as references, the diff against the baseline (11 added, 3 changed in `parameters` only, 44 byte-identical).
* `tests/test_xml_router.mjs` (route table now sends EXPENSE + PALM to the chain, 4 fixed texts) and `repro-phase5/check_repro_consistency.js --baseline-ref origin/develop` (expectations updated deliberately: the palm prompt changes in exactly the S2 list and one paragraph; three existing nodes may differ; the route has five outputs). `tests/test_palm_sale_route.mjs` unchanged.
* **Not run:** n8n itself (no import, no webhook, no editor panel, by rule), the SQL inside n8n (`sp_agri_expense_invoice_*` are covered by `111_tests.sql`, not by this PR), the real Switch evaluation of the fourth rule, the model's behaviour with the new prompt paragraph (the paragraph is verified only by the production tests above), the editor's acceptance of the exported nodes, the credential selection and the `onError` behaviour of the HTTP and Postgres nodes.
