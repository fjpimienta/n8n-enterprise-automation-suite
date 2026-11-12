> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested locally (unit tests and an end-to-end check on a throwaway database). NOT deployed.** Part 1 (database) is migration 104,
> already merged and applied. Part 2 (n8n) does not apply to this pull request: no workflow calls the new profile yet. The only deployable
> piece here is the cfdi-service image.

# Runbook — cfdi-service `sale` parse profile

## Scope

`POST /parse` accepts an optional `"profile":"sale"`. With it the response adds `tipoComprobante`, `formaPago`, `metodoPago` and, per concept,
`claveUnidad`, `cantidad`, `valorUnitario` (exact decimal strings), which is the parsed-voucher contract of `sp_agri_register_sale` (migration 104).
**Without `profile` the response is identical to the previous one (same keys and values)**, so the livestock expense flow (`preview_expense_invoice`,
`register_expense_invoice`) is unaffected. `/sat-status` and `/store` are not changed. Nothing is logged beyond method, route, status, size and time.

## Deployment (owner only; same procedure as `091_093_RUNBOOK.md`, Part 2)

1. On the VPS, refresh only `microservices/cfdi-service` from `origin/main` (never a blanket `git pull`):
   `bash update_cfdi_vps.sh dry`, review that only the expected files differ (`lib/cfdi-parser/index.js`, `lib/cfdi-parser/index.d.ts`,
   `lib/cfdi-parser/README.md`, `src/app.js`, `README.md`, `SALE_PROFILE_RUNBOOK.md`, `test/palm-sale.test.js`), then `bash update_cfdi_vps.sh apply`
   (it keeps a source backup, rebuilds the image and recreates only the `cfdi-service` container).
   The script is not part of this repository; follow its own prompts.
2. Checks printed by the script must still pass: `health {"ok":true}`, `401` without the token, reachable from n8n at `http://cfdi-service:4100`.
3. Behavior check **with a synthetic voucher only** (never a real one). From the n8n container network, with the token taken from the environment and
   never typed or pasted:
   * `POST /parse` with `{"xmlBase64": "<synthetic voucher>"}` → the previous response (no `tipoComprobante`, concepts with three keys).
   * the same body plus `"profile":"sale"` → the response with `tipoComprobante`, `formaPago`, `metodoPago` and six-key concepts.
   * `"profile":"other"` → `422 {"status":"invalid","code":"INVALID_BODY"}`.
4. Confirm the livestock expense flow still works end to end with an existing test company (a normal invoice attachment in the chat).

## Rollback

Restore the previous source from the backup the script prints (`tar xzf backup_cfdi_service_src_<stamp>.tgz -C <compose root>`), then
`docker compose build cfdi-service && docker compose up -d --no-deps cfdi-service`. Nothing else changes: no database object, workflow or
frontend depends on the profile yet.

## Tests

`npm ci && npm test` in `microservices/cfdi-service` (CI job "CFDI service tests"). `test/palm-sale.test.js` holds a synthetic voucher generator
(fictional UUID, RFCs and names, dummy seals) and covers: contract key names and types, ticket present / missing, two concepts, USD, PPD, type E,
16% IVA, discount, concept amounts with more than two decimals (half-up rounding), missing optional attributes, hostile XML, no seal or certificate
in the output, unchanged default output on the existing fixtures, and the service route.
