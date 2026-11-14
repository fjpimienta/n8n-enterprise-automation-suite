# Dynamic CRUD Engine v6

`v6/CRUD` is the Meta-CRUD gateway workflow used by `agro-erp` (per the root `CLAUDE.md`; TODO(verify): not provable from this export). It exposes one webhook, `POST crud/v6/:model`,
and turns a JSON request into a parameterized SQL statement (or a stored procedure call) for the model named in
the URL. The model definition (table, allowed fields, allowed operations, allowed roles, joins, default filter)
lives in the `crud_models` table, not in the workflow.

The workflow is exported in [`v6-crud.json`](./v6-crud.json). This document describes only what that export and
its tests contain. It says nothing about what is deployed; check the live workflow before relying on it.

## Request contract

* **Route:** `POST crud/v6/:model` (response mode: respond-to-webhook node, `allowedOrigins` `*`).
* **Model name:** the URL segment. `Get Model Name` rejects anything that is not `^[A-Za-z][A-Za-z0-9_]{0,62}$`
  and writes `model_name` after spreading the body, so the body cannot override it.
* **Operation:** `action` or `operation` in the body (lower-cased). A missing value answers `400` with code
  `MISSING_OPERATION`. `Security Validation` maps `list`/`select` to `getall`; `getall`, `getone`, `insert`,
  `update`, `delete` and `call_sp` map to themselves; an unknown value falls back to `getall`.
* **Payload:** `body.filter`, `body.filters` or `body.fields`, in that order; if none is present, the whole body.
* **Headers:** `Authorization` (verified by the token sub-workflow) and `x-tenant-id` (the company the request
  acts on).

## Request flow by node

Main path for an authenticated request:

1. **`WebhookCRUD`** receives the request.
2. **`Get Model Name`** validates the model name and carries the body and headers forward.
3. **`If`** sends `companys` + `getall` (read from `$json.operation`) to `Get Model Config` without a token (the
   public company list, a documented exception, #1064; see the rules below). Every other request goes to `Verify Token`.
4. **`Verify Token`** runs the `v3/SW ValidaToken` sub-workflow. **`IsValid`** requires `status = success`;
   otherwise **`Respond Denegate`** answers `401` `{"mensaje": "Acceso denegado"}`.
5. **`Get Membresia`** looks up the active `user_companies` row for the token's user and the `x-tenant-id` header
   and returns its role (upper-cased). **`Existe Membresia`** requires a non-empty role; otherwise
   **`Respond Tenant Forbidden`** answers `403` with code `TENANT_FORBIDDEN`.
6. **`Get Model Config`** reads the `crud_models` row for the model. **`ModelExist`** checks that a row (`id`)
   exists.
7. **`Schema Validate`** copies the model config forward (`{ ...modelConfig, validated: true }`). For `insert`/`update`
   it loops over `schema_json` with `Object.keys(schema).forEach(...)` and checks `required === true` fields against
   `WebhookCRUD.body.fields`. **This check has no effect (known deviation, #1054):** the `return { json: { error: true,
   status: 400, code: "SCHEMA_VALIDATION" } }` sits inside the `forEach` callback, so it only ends that callback and
   is discarded. The node never emits an error, and the required fields are not enforced. Even if the object were
   returned, nothing would deliver it: `Extract Auth Context` replaces the item with `{ user, id_company/email }`, and
   `Security Validation` reads `$('Schema Validate').first().json` directly, then returns `error: false`, so no `400`
   reaches `If Error`. A `throw` would not help either: a failed execution does not return the gateway's
   `{ error: true }` format. Fixing it would take two changes: validate required fields only on `insert` (partial
   `update` calls such as `updateProductionUnit` in agro-erp send a subset of fields) and route the error to `If Error`
   from `Security Validation`. Both change behavior for existing callers, so they are deferred until the impact is
   measured; see #1054. The v5 gateway has the same code and the same behavior.
   TODO(verify): how many models in live `crud_models.schema_json` have `required: true`, and which callers send partial
   `update` payloads. The migrations (12 files, 73 `"required": true` occurrences) do not give the live state.
8. **`Extract Auth Context`** builds the actor: role from the membership row, email from the token's `user`
   claim (never from the body). The public `companys` path gets role `CUSTOMER`. No role: `401` `NO_ROLE`.
9. **`Security Validation`** checks the operation against the model's `allowed_ops`, then the role against
   `allowed_roles_<op>` (comma-separated list in `crud_models`). It returns the model config plus `user_role`,
   `user_email` and the normalized `operation`. A failure carries `error: true` and a `status`.
10. **`If Error`**: on error, **`Respond to Webhook`** answers with the error JSON and the status it carries;
    otherwise **`Build Query`** continues.
11. **`Build Query`** builds `{ query, values, operation, require_row, is_transactional }`.
12. **`Execute SQL`** runs it with `queryReplacement` = `values` (`onError: continueRegularOutput`).
13. **`Normalize Data`** converts the rows into the response (see "Response shape").
14. **`Check Post-Hooks`**: if the model config has `hooks.post` and the call succeeded, **`Insert Logs`** writes a
    `crud_logs` row; then **`Respond to Webhook`** answers.

Side branches:

* **Unknown model:** `ModelExist` false goes to **`Can Register Model`**, which continues only if the caller's
  membership role is `ADMIN`; otherwise **`Respond Model Not Found`** answers `404`. For an `ADMIN`, the
  auto-registration chain runs: `Get` (reads `information_schema` columns) -> `Aggregate` -> `Message a model`
  (OpenAI chat model) -> `Parse IA` -> `Execute a SQL query` (inserts the `crud_models` row) -> back to
  `Extract Auth Context`. `Parse IA` refuses tables without a `tenant_id`/`id_company` column and reserved names
  (`crud_*`, `pg_*`, `n8n*`, `*_backup_*`), and takes columns from the real catalog, not from the model output.
  The chain re-enters `Extract Auth Context` and then `Security Validation`, which reads `Schema Validate`
  (`v6-crud.json`: `Execute a SQL query` and `Schema Validate` both connect to `Extract Auth Context`, which
  connects to `Security Validation`). TODO(verify): a live execution that completes this path for a new model
  has not been run.
* `If1` (`error` true) is connected to `Respond to Webhook`; nothing in the export connects into `If1`.

## Operations

All SQL values are bound parameters. Table, column, join and sort names are interpolated, so they come from
`crud_models` or pass an identifier regex (`sort_by` and the `getone` search field).

| Operation | Behavior in `Build Query` |
| :--- | :--- |
| `getall` (`list`, `select`) | `SELECT` with optional joins (`LEFT JOIN`, plus `row_to_json` of the joined table), filters on `allowed_fields` only, `_gte/_lte/_gt/_lt` operators, date-like values cast to `date`, `default_filter` from the model, `ORDER BY <sort_by> DESC NULLS LAST` (default `published_at` if sent as a filter, else `created_at`; `companys` sorts by `company_name`), `LIMIT` default 1500 and capped at 2000, `OFFSET`. |
| `getone` | One row by the primary key, or by `email`, or by the first field sent. |
| `insert` | Upsert: `INSERT ... ON CONFLICT (<primary_key>) DO UPDATE` (except `users` and `companys`, see below) over the allowed fields; `DO NOTHING` when nothing is updatable. Tenant columns and `url`/`created_at` are not updated by the conflict branch. |
| `update` | `UPDATE ... WHERE <primary_key> = ...` over the allowed fields; tenant columns and primary-key columns are never in the `SET`. A `password` that arrives empty is skipped. |
| `delete` | Soft delete: `UPDATE <table> SET is_active = false WHERE <primary_key> = ...`. |
| `call_sp` | `SELECT <procedure>(...) AS resultado`; see "Stored procedure models". |

Other rules in the same node:

* `password` values are hashed with SHA-256 (no salt) before they are bound; `Normalize Data` removes any
  `password` key recursively from every response.
* `users`: explicit safe column list (never `password`), `insert` is `DO NOTHING`, `update` only touches members
  of the requesting company and of no other company, `delete` throws, `getall`/`getone` require `x-tenant-id`;
  `getall` joins `user_companies` and `getone` filters with an `EXISTS` on it.
* `companys`: `insert` never takes `id_company` and never upserts.
* **Documented exception (#1064): public `companys` `getall`.** This is a deliberate decision by the owner, not an
  oversight. `companys` + `getall` skips `Verify Token`, membership (`Get Membresia`) and `X-Tenant-ID`; it is the
  only branch of `If` that does so. `Build Query` forces the columns to `id_company` and `company_name` only (no
  `metadata`, notes or revenue). Current callers do not rely on it without a token: `loadCompanies` in `agro-erp`
  is cancelled when there is no token, and `dashboard` has no callers. TODO(verify): no external client or workflow
  calls this route without a token.

## Tenant, actor and roles

* **Tenant:** the `x-tenant-id` header. It is checked against `user_companies` (active membership for the token's
  user) before the model is loaded, so a non-member gets `403` `TENANT_FORBIDDEN`. `Build Query` then writes it
  into the payload as `tenant_id` or `id_company`, only if that column is in the model's `allowed_fields`
  (overriding any client value), and uses it in the `WHERE` of `getone`, `update` and `delete`, and in the
  upsert conflict guard. For `getall`, the injected value becomes an equality filter.
* **Fail-closed spots in the code:** a tenant-scoped upsert (`insert` with updatable fields), an `update` of a model with a tenant column, and a `call_sp` that requires the tenant throw without the header.
  `getone`, `delete` and `getall` on a model with a tenant column add the tenant filter only when the header is
  present, but the membership step earlier already denies a request without a valid header.
* **Actor:** `user_email` comes from the verified token (`user` claim, falling back to `email`). For `call_sp`,
  the procedure's actor field is overwritten with it; if it is missing, the node throws.
* **Roles:** the role is the membership role for the requested company, not a role frozen in the token. It must be
  in `allowed_roles_select|insert|update|delete` of the model. `call_sp` is validated as an `insert`, so a stored
  procedure is granted through `allowed_roles_insert` and `allowed_ops` must contain `INSERT`.
* **Auto-registration:** only an `ADMIN` membership role gets past `Can Register Model`.

## Stored procedure models (`call_sp`)

`Build Query` calls only procedures that have an entry in the in-node `spConfigByModel` map; the lookup key is the
model's `table_name`. An unknown name throws `No hay configuración de parámetros para el procedimiento <name>`.
Business arguments are read from the payload in `paramOrder` (missing ones travel as `null`; objects are sent as
JSON text). The tenant is inserted at `tenantPosition` when `sp_requires_tenant` is not `false`, as an integer
from `x-tenant-id`. The statement is `SELECT <procedure>($1, ..., $n) AS resultado;`. `allowed_fields` does not
filter `call_sp` arguments.

| Procedure (`spConfigByModel` key) | `paramOrder` (business arguments only; the tenant is inserted at `tenantPosition`) | `tenantPosition` | Actor field |
| :--- | :--- | :--- | :--- |
| `sp_procesar_salida_ganado` | `electronic_rfid`, `rfid_siniiga`, `numero_fuego`, `livestock_id` | 1 | none |
| `sp_register_birth_event` | `calf_sex`, `species`, `dam_id`, `dam_ear_tag`, `dam_fire_number`, `birth_date`, `lot_id`, `production_unit_id`, `paddock_id`, `birth_weight_kg`, `notes` | 0 | none |
| `sp_procesar_baja_mortandad` | `electronic_rfid`, `rfid_siniiga`, `numero_fuego`, `causa_mortandad`, `fecha_evento`, `descripcion`, `reportado_por_email`, `autorizado_por_email` | 3 | none |
| `sp_solicitar_autorizacion` | `electronic_rfid`, `rfid_siniiga`, `numero_fuego`, `livestock_id`, `tipo_evento`, `payload`, `solicitado_por_email` | 4 | `solicitado_por_email` |
| `sp_resolver_autorizacion` | `request_id`, `decision`, `resuelto_por_email`, `notas`, `datos_venta` | `null` | `resuelto_por_email` |
| `sp_cancelar_autorizacion` | `request_id`, `cancelado_por_email`, `motivo` | 1 | `cancelado_por_email` |
| `sp_access_add_user` | `email`, `names`, `lastname`, `phone`, `role`, `password`, `actor_email` | 0 | `actor_email` |
| `sp_access_update_member` | `email`, `names`, `lastname`, `phone`, `role`, `password`, `actor_email` | 0 | `actor_email` |
| `sp_access_set_active` | `email`, `is_active`, `actor_email` | 0 | `actor_email` |
| `sp_agri_set_default_plantation` | `plantation_id`, `actor_email` | 0 | `actor_email` |
| `sp_agri_bulk_create_rows` | `lot_id`, `from_row`, `to_row`, `positions_per_row`, `actor_email` | 0 | `actor_email` |
| `sp_agri_record_row_census` | `row_id`, `alive_plants`, `reason`, `census_date`, `notes`, `actor_email`, `planting_positions` | 0 | `actor_email` |
| `sp_agri_record_expense` | `plantation_id`, `lot_id`, `category_id`, `expense_date`, `amount`, `quantity`, `unit_code`, `supplier_name`, `description`, `is_invoiced`, `invoice_folio`, `actor_email` | 0 | `actor_email` |
| `sp_agri_void_expense` | `expense_id`, `reason`, `actor_email` | 0 | `actor_email` |
| `sp_agri_expense_balance` | `date_from`, `date_to`, `grain`, `plantation_id`, `lot_id`, `category_id`, `actor_email` | 0 | `actor_email` |
| `sp_agri_void_sale` | `actor_email`, `sale_id`, `reason` | 0 | `actor_email` |
| `sp_agri_sales_balance` | `date_from`, `date_to`, `grain`, `plantation_id`, `lot_id`, `actor_email` | 0 | `actor_email` |
| `sp_register_livestock_panel` | `upp`, `lot`, `species`, `category`, `business_model`, `ear_tag`, `fire_number`, `electronic_rfid`, `weight_kg`, `birth_date`, `origin_upp`, `tb_test_date`, `br_test_date`, `notes`, `confirmed`, `preview_hash`, `force_duplicate`, `actor_email` | 0 | `actor_email` |

Notes:

* The in-code comments say that tenant/role (`sp_resolver_autorizacion`), role/company/last-ADMIN rules
  (`sp_access_*`), role, company and parent rules (palm procedures) and preview/commit rules
  (`sp_register_livestock_panel`) are enforced inside the procedures.
* `sp_resolver_autorizacion` has `tenantPosition: null`; the comment in the code says the procedure validates
  tenant and role itself. TODO(verify): this relies on `sp_requires_tenant = false` in its `crud_models` row; with
  `true`, `splice(null, 0, tenant)` would insert the tenant at position 0. The row is not in this repository
  export.
* The `crud_models` rows (operations, roles, `sp_requires_tenant`) are database state and are not described by
  the workflow export. For the palm sales models see the runbook below.

## Response shape

`Normalize Data` returns `{ error, operation, message, data, execution_info }`; `Respond to Webhook` uses
`$json.status` as the HTTP code, defaulting to `200`.

* A database error from `Execute SQL` (it continues on error) becomes `error: true` with the database message
  and **HTTP 200**: always inspect `error` in the payload.
* `getone` without a row, `update` or `delete` matching no row, and a tenant-scoped upsert returning no row set
  `error: true` (HTTP 200) with a message.
* `call_sp` returns the `resultado` column of the first row as `data`.
* Rejections from `Extract Auth Context`, `Security Validation` and the membership gate carry `error: true` and
  an HTTP status (`400`, `401`, `403`, `500` for missing role configuration). A `throw` inside `Build Query`
  ends the execution with an error instead (no `Respond to Webhook`); TODO(verify): the HTTP response a caller
  sees in that case (v5 documents an empty `200`).

## Differences from v5 (visible in the exports)

| Aspect | v5 (`crud/v5/:model`) | v6 (`crud/v6/:model`) |
| :--- | :--- | :--- |
| Models served | `Model Allowlist` node limits it to nine hotel models | any model in `crud_models` |
| Tenant source | `id_company` claim of the verified token; `403` `NO_TENANT` without it | `x-tenant-id` header checked against `user_companies` |
| Role source | role in the token | membership role in the requested company |
| Unknown model | `Model Not Registered` answers `404`; the auto-registration chain is left disconnected | `ADMIN` membership can trigger auto-registration; others get `404` |
| `call_sp` | a single whitelisted function (`sp_procesar_salida_ganado`) | the `spConfigByModel` map above, tenant and actor handling |
| Security rejections | `Security Validation Gate` and `Respond Security Denial` (clean `{message, code}`) | `If Error` returns the error JSON as is |
| `users` / `companys` rules | not served | handled in `Build Query` as described above |

See [`../v5/README.md`](../v5/README.md) for the v5 description.

## Tests

Offline tests run the real `Build Query` code from `v6-crud.json` with the upstream nodes stubbed. They need only
Node.js; there is no `package.json` in this folder. From the repository root:

```bash
node workflows/06-dynamic-crud-engine/v6/tests/test_v6_panel_sp.mjs
node workflows/06-dynamic-crud-engine/v6/tests/test_agri_sale_sp.mjs
```

| Test | Covers |
| :--- | :--- |
| [`test_v6_panel_sp.mjs`](./tests/test_v6_panel_sp.mjs) | `sp_register_livestock_panel` (migration 102): 19 values, tenant first as a number, token actor overwrites a client value, missing header or email throws, an older entry still builds. |
| [`test_agri_sale_sp.mjs`](./tests/test_agri_sale_sp.mjs) | `sp_agri_void_sale` and `sp_agri_sales_balance` (migration 107): argument order against the signatures parsed from migration 104, tenant and actor handling, hostile values stay bound parameters, unknown models throw, the two model rows of migration 107 match, and the export is compared with a base git ref. |

`test_agri_sale_sp.mjs` reads migrations 104 and 107 and calls `git` for its comparison; optional environment
overrides are `V6_CRUD_JSON`, `SQL_104` and `SQL_107`. The v5 tests are described in [`../v5/README.md`](../v5/README.md).

## Related runbooks

* [`107_RUNBOOK.md`](../../../hosting3m-workspace/projects/agro-erp/database/migrations/107_RUNBOOK.md): palm sales
  void and balance through the gateway (two `crud_models` rows and two `spConfigByModel` entries).
* [`102_RUNBOOK.md`](../../../hosting3m-workspace/projects/agro-erp/database/migrations/102_RUNBOOK.md): panel
  livestock intake procedure.
* [`081_RUNBOOK.md`](../../../hosting3m-workspace/projects/agro-erp/database/migrations/081_RUNBOOK.md): palm
  expenses procedures.
* Workflow deployment steps for n8n 2.x are in the root `CLAUDE.md` and `CONTRIBUTING.md`; follow them before
  importing this export anywhere.
