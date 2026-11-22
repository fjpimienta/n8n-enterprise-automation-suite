> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested offline only (prompt text pinned by `tests/test_palm_expense_xml.mjs`). NOT imported anywhere.** n8n itself and the model behaviour were not run.
> Part 1 (database) needs nothing: no SQL changes. **Part 2 (n8n) is this pull request:** one workflow file, `v6_ai_chat_cattle.json`, imported by the owner only through the n8n UI. No frontend.

# Runbook — palm invoice prompt: one question at a time

## What changes

Only the `AI Agent Palma` system prompt (paragraph "FACTURA XML"; 10,669 → 11,241 characters). No other node, no SQL, no tool description.

Problem: after the voucher preview the agent asked the scope question and "¿Confirmas?" in the same message; a bare "Sí" was taken as "assign that plantation", `register_palm_expense_invoice` was called with arguments the last preview did not have, the database correctly answered `preview_required`, and the agent looped. The database behaviour is correct and unchanged.

New rules: (1) with `scope_question`, ask only that and wait; (2) the answer triggers a new preview, then "¿Confirmas? Sí / No"; (3) a bare "Sí" confirms only after a "¿Confirmas?" of a current preview; (4) register receives exactly the arguments of the last preview; (5) on `preview_required` call preview again with what the user chose and ask once.

## Procedure (owner only, n8n UI; never `n8n import:workflow`)

1. **Backup:** open the live workflow, ⋯ → Download, store outside the repo, `chmod 600`.
2. **Fingerprint production vs `develop` BEFORE importing:** run the comparison snippet of the root `CLAUDE.md` (production backup vs `origin/develop` JSON) and `python3 -I ~/node_fingerprints.py`. Production may carry manual changes: if it differs from `develop`, stop and fold them into `develop` first.
3. **Diff vs this branch:** must list exactly one node, `AI Agent Palma` (parameters), and no connection change. Credentials, `webhookId`, `typeVersion` and `settings` equal.
4. **Import:** ⋯ → Import from file… → the JSON of this branch. Re-select the sub-workflow in `Venta Palma XML` and re-check the credentials of the nodes. **Save**, then **Publish**.
5. **Re-download and compare** with the JSON of this branch: `No differences.` (an editor save without Publish is detected only here).
6. **Rollback:** re-import the backup of step 1, Save, Publish.

## Production tests (TEST company 10 only, real web chat; never companies 5, 6, 7, 8)

Use a synthetic voucher whose receiver is the company's configured RFC (never a real one, never in the repo).

| # | Do | Expected |
|---|---|---|
| a | Attach the voucher. | Summary and ONLY the scope question; no "¿Confirmas?". Answer "general": new summary and "¿Confirmas? Sí / No"; "Sí" → "Gasto registrado". |
| b | New voucher; right after the scope question answer a bare "Sí". | Nothing registered; the agent asks which plantation or lot (or offers "general"). |
| c | New voucher; answer with a plantation. | A new preview with that plantation, "¿Confirmas?"; "Sí" → recorded with that plantation. |
| d | Send the same voucher again. | `duplicate`; nothing new registered. |
| e | A palm sale XML, a PDF and a plain message. | Unchanged behaviour. |

The registered test expenses are **voided from the Gastos screen, never deleted.**

## Limits

Prompt wording only: the model may still deviate; the database refuses any call whose arguments differ from the last preview.
