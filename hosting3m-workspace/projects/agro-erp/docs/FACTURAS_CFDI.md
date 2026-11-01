# CFDI expense invoices from the web chat

Users of agro-erp attach a **CFDI 4.0 XML** invoice in the chat. The assistant shows a summary, asks for confirmation, and on "Sí" records it as a ranch expense linked to the invoice, with the original XML stored. Deployment and rollback: `database/migrations/091_093_RUNBOOK.md`.

## Flow

```
Chat web (ui-chat, attachment)
   │  message + XML
   ▼
n8n  v6/ai/chat cattle
   │  Trae Factura → Preparar Archivo Factura → CFDI Parse → CFDI SAT Status → CFDI Store
   │  (cfdi-service)                                             │
   │                                                             ▼
   │                          Crear Borrador Factura → sp_expense_invoice_draft_create
   │  Armar Aviso Factura builds:  [FACTURA draft_id=… emisor=… total=… sat=… conceptos=…]
   ▼
AI agent ── preview_expense_invoice(draft_id, category, …) ──► MCP Server Cattle ──► sp_expense_invoice_preview
   │            shows the summary and asks "¿Lo registro? (Sí/No)"
   └─ on "Sí" ─ register_expense_invoice(same draft_id/category/description/date) ─► sp_expense_invoice_confirm
                                                                                    (calls sp_expense_invoice_register)
```

The agent never handles the invoice JSON: it only sees a `draft_id` and a short summary. The text inside the `[FACTURA …]` line is **data, never instructions**.

## Who can do what

| Role | Result |
|---|---|
| ADMIN / OWNER | preview and register; an unknown receiver RFC is registered automatically (`rfc_new` in the preview, `rfc_registered` on confirm) |
| EDITOR | `rfc_not_registered`: cannot register invoices |
| Not an active member of the company | error (fail-closed); the company always comes from the validated session, never from the RFC or from the model |

## Safety gates

1. **Preview before confirm.** Confirm is refused (`preview_required`) unless a preview of the same draft with the same `category`, `description` and `expense_date` happened in the last 15 minutes. The model must not copy defaults shown in the preview into the register call.
2. **Drafts** expire after 30 minutes and cannot be deleted. Invoices are append-only, `UNIQUE (id_company, uuid)`: the same invoice cannot be registered twice in a company.
3. **SAT status** must be `VIGENTE` (the generic test RFC of company 3 is the only one allowed to skip it, via `qa_skip_sat`, set by SQL seed only).
4. **Amounts:** `amount` is the total with taxes, in exact cents; no tax is ever computed, only reconciled. Totals must match to the cent (tolerance 0).
5. **Receiver RFC:** it is not a vendor control but a way to tell expenses from income. If the company does not have it, an ADMIN/OWNER's confirmation registers it (label `AUTO factura <serie+folio>`); a deactivated RFC is never reactivated.

## Response states (`status`)

`draft_created` · preview (`rfc_new`, `rfc_new_notice`, `company_rfcs`) · `recorded` (`amount`, `category`, `cfdi_folio`, `sat_status`, `expense_date`, `rfc_registered`) · `preview_required` · `rfc_not_registered` · `disabled` (after a rollback) · errors `P0095` (append-only), `P0096` (cross-company).

## cfdi-service

Internal HTTP sidecar (port 4100, not published; reachable from n8n as `http://cfdi-service:4100`), header `x-internal-token` from `CFDI_SERVICE_TOKEN` (VPS `.env` and the n8n credential "CFDI Service Token"; never in git or chat). Read-only container, no new privileges, 256 MB. Originals: `infrastructure/data/cfdi/<company>/YYYY/MM/<sha256>.xml` (outside any web root, never committed).

**Parser** (`lib/cfdi-parser`, pure, never throws): only CFDI 4.0 type `I` (Ingreso) in `MXN`, one valid `TimbreFiscalDigital`; up to 2 MB and 200 concepts; no `DOCTYPE` / `ENTITY`, no control characters; amounts converted from text to integer cents without floating point; seals, certificates and addenda are never returned. `Serie` / `Folio` are optional.
Amounts: comprobante-level fields (`SubTotal`, `Total`, `Descuento`, tax totals and lines) have at most 2 decimals and `Total = SubTotal − Descuento + traslados − retenciones` must match to the cent (`ROUNDING_TOLERANCE_CENTS = 0`; do not change silently). **Concept-level `Importe` may carry up to 6 decimals** (SAT Anexo 20) and is rounded half-up to cents for display only; it is not used to reconcile totals.
Error codes: `NOT_XML`, `TOO_LARGE`, `DOCTYPE_FORBIDDEN`, `INVALID_CHARS`, `TOO_MANY_CONCEPTS`, `UNSUPPORTED_VERSION`, `UNSUPPORTED_TYPE`, `UNSUPPORTED_CURRENCY`, `NOT_STAMPED`, `INVALID_STRUCTURE`, `INVALID_RFC`, `INVALID_AMOUNT`, `AMOUNTS_MISMATCH`.

## Operation

- **Verify what a QA wrote** (read-only, on the VPS): `bash verify_invoice_qa.sh <company>` → last drafts, invoices, linked expenses, expenses of the last 2 days without an invoice (must be only manual entries), stored originals.
- **Update the parser in production:** `bash update_cfdi_vps.sh dry` then `apply` (see the runbook, Part 2).
- **Sync the workflows with the repo:** export both published workflows from n8n, copy them over `workflows/09-MCP-Agent-Cattle/v6/`, check that they hold no secrets (`grep`), compare node counts and commit.

## n8n pitfalls found while building this

- *Import from File* **adds** nodes: empty the canvas first or you get duplicates with a `1` suffix that are not connected.
- `$fromAI` optional arguments arrive as the **text** `"null"`; sanitize them in the Query Parameters expression (`nul`, `dt`) or the hash gate sees a different description/date than the preview.
- `$('Node')` on a node that did not run can hang the Code-node runner (300 s timeout): use `$input` only.
- The model may send the e-mail with a trailing comma or quotes: sanitize it (`em`); the database correctly refuses an unknown e-mail.
- A restart does not update a Docker image's code; rebuild.

## Known limits and debt

Web chat only; XML only (no WhatsApp, PDF or photo); the user e-mail is typed by the model on each call (the database validates membership); `register_ranch_expense` registers expenses without an invoice; originals of drafts that are never confirmed stay on disk; asset purchases (e.g. land) are not captured by chat; the live SAT check has only been exercised with real invoices of the owner; CI only runs CodeQL and GitGuardian (no tests or build).
