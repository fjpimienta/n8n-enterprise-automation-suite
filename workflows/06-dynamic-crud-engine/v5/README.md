# Dynamic CRUD Engine v5

## Hotel company scoping

The `Extract Auth Context` and `Build Query` nodes scope every hotel operation
(`getall`, `getone`, `insert`, `update`, and `delete`) to the company ID in the verified
token. A token without a valid company is rejected with HTTP 403 and code `NO_TENANT`.
Tables without a tenant mapping are denied. Hotel data belongs to company 1.

The migration runbook for the hotel maintenance ticket company column is
[`094_095_RUNBOOK.md`](../../../hosting3m-workspace/projects/agro-erp/database/migrations/094_095_RUNBOOK.md).

## Local tests

The tests cover the workflow nodes and migrations, using PostgreSQL in WebAssembly through
`@electric-sql/pglite`. From this directory, run:

```bash
cd tests
npm install
npm test
```

## Workflow overview

`v5/CRUD` ([`v5-crud.json`](./v5-crud.json)) is the Meta-CRUD gateway workflow behind the hotel apps. Its webhook is
`POST crud/v5/:model`. It turns a JSON request into a parameterized SQL statement for the model named in the URL,
using the model definition stored in `crud_models`. This section describes the export only, not what is deployed.

The export has a model allowlist (`Model Allowlist` node) that serves only nine models: `hotel_guests`,
`hotel_bookings`, `hotel_reviews`, `hotel_expenses`, `hotel_rooms`, `hotel_room_inspections`,
`hotel_maintenance_tickets`, `hotel_assets` and `hotel_capital`. Any other model name is answered with `404` and
code `MODEL_NOT_ALLOWED`.

### Request flow by node

1. `WebhookCRUD` receives the request; `Get Model Name` takes the model from the URL and carries body and headers.
2. `Model Allowlist` and `Is Allowed Model`: a model outside the allowlist goes straight to `Respond to Webhook`.
3. `If` routes `companys` + `getall` to `Get Model Config` without a token; everything else goes to
   `Verify Token` (the `v3/SW ValidaToken` sub-workflow). Because `companys` is not in the allowlist, that public
   branch cannot be reached through this export.
4. `IsValid`: anything but `status = success` is answered by `Respond Denegate` with `401`.
5. `Get Model Config` reads the `crud_models` row; `ModelExist` false goes to `Model Not Registered` (`404`,
   code `MODEL_NOT_FOUND`). The AI auto-registration chain (`Get`, `Aggregate`, `Message a model`, `Parse IA`,
   `Execute a SQL query`) stays in the export but is disconnected.
6. `Schema Validate` copies the config forward; `Extract Auth Context` takes the role and `id_company` from the
   verified token and rejects a token without a positive integer company with `403` and code `NO_TENANT`.
7. `Security Validation` checks the operation against `allowed_ops` and the role against `allowed_roles_<op>`;
   `Security Validation Gate` sends a rejection to `Respond Security Denial` (clean `{message, code}` JSON) and a
   success to `Build Query`.
8. `Build Query` builds the statement; `Execute SQL` runs it (`onError: continueRegularOutput`);
   `Normalize Data` shapes the response; `Check Post-Hooks` optionally goes through `Insert Logs`; then
   `Respond to Webhook` answers.

### Supported operations

`getall` (aliases `list`, `select`), `getone`, `insert` (upsert on the primary key), `update`, `delete` (soft
delete through `is_active = false`) and `call_sp`. `call_sp` accepts a single hard-coded function,
`sp_procesar_salida_ganado`, called with one argument (`electronic_rfid`). Every table must appear in the
`TENANT_COLUMN` map of `Build Query` (or be `hotel_reviews`, the only unscoped table); otherwise the node throws.
Other behavior shared with v6 (pagination capped at 2000 rows, filter operators `_gte/_lte/_gt/_lt`, SHA-256 on
`password`) is described in [`../v6/README.md`](../v6/README.md). Unlike v6, the v5 `Normalize Data` node does not strip `password` from responses.

### Differences from v6

| Aspect | v5 | v6 |
| :--- | :--- | :--- |
| Route | `crud/v5/:model` | `crud/v6/:model` |
| Models | nine hotel models (allowlist node) | any model in `crud_models` |
| Tenant | `id_company` from the verified token | `x-tenant-id` header checked against `user_companies` |
| Role | role in the token | membership role in the requested company |
| `call_sp` | one whitelisted function | per-procedure `spConfigByModel` map with tenant and actor handling |
| Unknown model | `404`; auto-registration disconnected | `ADMIN` membership can trigger auto-registration |
| Rejections | `Security Validation Gate` + `Respond Security Denial` | `If Error` returns the error JSON |
