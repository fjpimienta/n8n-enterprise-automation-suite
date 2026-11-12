> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only (PostgreSQL 15.4). NOT applied to production.** This pull request changes the
> database layer only: nothing in n8n, the gateway (`crud_models`), the parser or the frontend uses these objects yet. Part 2 (n8n)
> does not apply to this pull request; it is stated explicitly so the checklist above stays honest.

# Runbook 104 — palm sales from a CFDI voucher: database layer (PR A)

## Scope

| Object | Kind | Notes |
|---|---|---|
| `company_flags` | table | platform-managed `is_test` flag per company; not in `crud_models` |
| `company_issuer_rfcs` | table | RFCs a palm company may issue sales vouchers with; platform-managed; not in `crud_models` |
| `agri_sale_invoices` | table | one row per sale voucher; append-only; the only change allowed is ACTIVE → VOID |
| `agri_sale_audit` | table | append-only trail: REGISTER / VOID / REJECT, codes only |
| `sp_agri_register_sale` | procedure | direct load of a parsed voucher; ADMIN of a palm company only; no amount parameter |
| `sp_agri_void_sale` | procedure | ADMIN only, any time, reason 5..300 characters, audited, idempotent |
| `sp_agri_sales_balance` | procedure | dashboard totals (ADMIN only); same call contract as `sp_agri_expense_balance` + previous period |
| `vw_agri_sale_list`, `vw_agri_sale_summary` | views | to be registered in `crud_models` (ADMIN only) by a later pull request |
| `104_seed_company_flags.sql`, `104_seed_issuer_rfc.sql` | seeds | NOT part of the migration; dry run by default |

Not touched: every 091/092/093 object, `fn_repro_ctx`, `fn_reject_palm_company`, `crud_models`, n8n workflows, the gateway, the
parser, the frontend. Error codes: `P0110` (sale records are append-only / not valid), `P0111` (platform-managed table); the reads
reuse `P0080`, `P0084`, `P0092`, `P0093`.

## Design in one page

* **Tenant and role.** The procedures receive the tenant that the caller already validated and read the actor's role from
  `user_companies` through `fn_agri_actor_role` inside the procedure. A role is never a parameter. Only `ADMIN` loads or voids a sale.
  Anything that is not a palm company answers `NOT_PALM`.
* **Amounts.** There is no amount parameter. Totals, subtotal, discount and taxes are stored as the voucher states them (integer
  cents). The only arithmetic is the reconciliation `subtotal − discount + transferred − withheld = total`, exact to the cent. Quantity
  and unit price keep six decimals (`numeric(18,6)`). The 16%/2% fiscal engine is not involved.
* **Accepted vouchers.** Type `I`, `MXN`, `MetodoPago = PUE`, exactly one concept, unit `KGM`, buyer different from the issuer, date not
  in the future and not older than 365 days (constant `c_max_age_days` at the top of `sp_agri_register_sale`; change it there if the
  owner decides otherwise), SAT status `VIGENTE`. A test company may proceed when the SAT has no answer (stored as `SKIPPED_TEST`);
  `CANCELADO` is never accepted.
* **Issuer RFC.** The voucher issuer must be an active RFC in `company_issuer_rfcs` for the company. That list is written only by a
  platform seed and never from a voucher. A company without entries answers `ISSUER_RFC_NOT_CONFIGURED`.
* **Ticket.** `(ticket N)` in the concept description (case-insensitive). Exactly one match → `ticket_ref`; otherwise the sale is accepted
  with `ticket_ref = NULL`, `ticket_warning = true` and the warning `ticket_missing_or_unrecognized`. The same ticket in another active
  sale of the company adds the warning `ticket_already_used` and does not block.
* **Idempotency and uniqueness.** `UNIQUE (id_company, uuid)` everywhere plus `UNIQUE (uuid) WHERE NOT is_test`. The same voucher sent
  again by the same company answers `ALREADY_REGISTERED` with the existing sale. Any other collision (another real company, or a voided
  sale) answers `DUPLICATE` with the same generic message and the audit stores only the code `DUPLICATE_UUID`, never a UUID. A test
  company and a real company may hold the same UUID.
* **`is_test`.** Derived from `company_flags` by a trigger on every insert; a value sent by the caller is replaced. `company_flags` and
  `company_issuer_rfcs` change only inside a transaction that sets the platform setting `app.platform_seed = on` (the two seed files
  do; no procedure or gateway model does). `is_test` of a company cannot change once it has issuer RFCs or sales, and rows are never deleted.
* **Void.** `sp_agri_void_sale` is the only writer of the ACTIVE → VOID transition (a transaction-local setting plus a guard trigger).
  Voided sales are excluded from the balance and the summary view, stay in the list view with their status, and keep their UUID occupied.
* **Original file.** `original_path` follows the same pattern as `expense_invoices` and must be `<tenant>/<yyyy>/<mm>/<sha256>.xml`
  (cfdi-service `/store`). Seals and certificates are never stored in the database or in the audit trail.

## Parsed voucher contract (for the parser pull request)

`sp_agri_register_sale(p_tenant_id, p_actor_email, p_parsed, p_sat_status, p_original_path, p_source_sha256)`. `p_parsed` keys:
`tipoComprobante`, `uuid`, `serie`, `folio`, `fechaEmision`, `fechaTimbrado`, `emisor{rfc,nombre}`, `receptor{rfc,nombre}`, `moneda`,
`subtotalCents`, `descuentoCents`, `totalCents`, `traslados[]`, `retenciones[]`, `formaPago`, `metodoPago`, optional `sourceSha256`
(must equal `p_source_sha256`) and `conceptos[]` with exactly one `{claveProdServ, claveUnidad, cantidad, valorUnitario, descripcion,
importeCents}`; `cantidad` and `valorUnitario` are decimal strings (or numbers) with up to six decimals. The current parser does not
return `tipoComprobante`, `formaPago`, `metodoPago`, `claveUnidad`, `cantidad` or `valorUnitario` yet: the missing keys make the
procedure answer `INVALID_VOUCHER` (fail-closed) until the parser extension exists.

Answers (`status`): `OK`, `ALREADY_REGISTERED`, `FORBIDDEN`, `NOT_PALM`, `ISSUER_RFC_NOT_CONFIGURED`, `ISSUER_RFC_MISMATCH`,
`INVALID_VOUCHER` (+ `reason`), `DUPLICATE`. Void: `OK`, `ALREADY_VOID`, `FORBIDDEN`, `NOT_PALM`, `NOT_FOUND`, `INVALID_REASON`.

## Part 1 — Database (owner only)

Conventions
```bash
P='docker exec -w /root/repro/vps104 -i n8n-enterprise-db psql -X -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Apply and rollback **without** `--single-transaction`. Without `-v apply=true` every file is a dry run (it ends in `ROLLBACK`).

0. **Baseline.** Copy the 104 files to the host, compare `md5sum` with the repo.
1. **Backup and size check.** `docker exec n8n-enterprise-db pg_dump -U n8n_user -d hosting3m_db -Fc > backup_pre104_$(date +%Y%m%d_%H%M%S).dump`
   and confirm the file is larger than 100 KB.
2. **State before.** `$P -v expect=before -f 104_state_check.sql` must print `STATE OK: before`. Otherwise **STOP**.
3. **Dry run.** `$P -f 104_agri_sale_invoices.sql`; it must end with `DRY RUN: 104 rolled back` and `104: OK`.
4. **Apply (owner only).** `$P -v apply=true -f 104_agri_sale_invoices.sql` → `104 COMMITTED`.
5. **State after.** `$P -v expect=applied -f 104_state_check.sql` → `STATE OK: applied`; the FINGERPRINT lines must equal those of
   step 2 (the migration changes no existing table, row or function; `fn_repro_ctx` and `fn_reject_palm_company` are fingerprinted).
6. **Seeds (separate, after the migration).** Test company only; both are dry runs unless `-v apply=true`.
   ```bash
   $P -f 104_seed_company_flags.sql                          # company 10 => is_test (refuses unless it exists and is a palm company)
   $P -v apply=true -f 104_seed_company_flags.sql
   $P -v issuer_rfc="$ISSUER_RFC" -f 104_seed_issuer_rfc.sql  # RFC only from the variable; output shows a fingerprint, never the RFC
   $P -v issuer_rfc="$ISSUER_RFC" -v apply=true -f 104_seed_issuer_rfc.sql
   ```
   Do not paste the RFC in chat or commit it. The issuer seed refuses a company that is not flagged `is_test` unless
   `-v allow_non_test=yes` is passed on purpose. Confirm the id of the palm test company first (read-only):
   `SELECT id_company, company_name FROM companys WHERE fn_company_business_domain(id_company) = 'PALM' ORDER BY 1;`
7. **Production checks (test company only).** Read-only: `SELECT count(*) FROM agri_sale_invoices;` (0 before any load) and
   `SELECT id_company, is_test, is_active, left(md5(rfc), 8) FROM company_issuer_rfcs;`. A real load waits for the parser, n8n and gateway
   pull requests.

## Part 2 — n8n

Not part of this pull request (no workflow or gateway change). Later pull requests add the parser extension, the WhatsApp branch and the
`crud_models` rows for the reads, each with its own runbook.

## Part 3 — Frontend

Not part of this pull request.

## Rollback (deletes nothing)

`$P -v apply=true -f 104_rollback.sql`, then `$P -v expect=rolled_back -f 104_state_check.sql`. The three procedures answer `disabled`;
tables, rows, guard triggers, audit and views stay. Re-applying `104_agri_sale_invoices.sql` restores the procedures and keeps the rows.

## Results of the local run (throwaway database, PostgreSQL 15.4, schema only, synthetic data)

* `104_state_check.sql`: `before` → `applied` → `rolled_back` → `applied`; the fingerprint block was identical in every state
  (including `fn_repro_ctx`, `fn_reject_palm_company`, `sp_expense_invoice_register`, `sp_agri_expense_balance`).
* `104_tests.sql` (one transaction, always `ROLLBACK`): `ALL 104 TESTS OK`, run against the embedded file and again against the committed
  migration, before and after a rollback/re-apply cycle. Covered: valid sale; ticket missing / changed / several / case; two concepts;
  USD; PPD; type E; total off by one cent (both directions); 16% IVA total taken from the voucher; issuer not in the list; company
  without a list; same UUID in the same company, in another real company, in a test and a real company; same ticket with another
  UUID; EDITOR, non-member and ADMIN of another company; livestock company; future and old dates and their boundaries; SAT handling;
  void (ADMIN only, reason bounds, twice, other tenant, UUID stays occupied); balance excludes voided sales and respects the tenant;
  `company_flags` / `company_issuer_rfcs` writes blocked without the platform setting and never deletable; `is_test` fixed and derived;
  no amount-like parameter and extra voucher keys ignored; UPDATE / DELETE / TRUNCATE blocked on invoices and audit; composite keys of
  plantation and lot; audit holds codes only and no seal / certificate / xml column exists.
* Mutation check: weakening the ADMIN-only rule in a copy of the migration made the suite fail (`T16a`).
* Seeds on the throwaway database: dry run writes nothing; apply writes one row; a missing variable, a non-palm company and a palm company
  not flagged `is_test` are refused; the seed files contain no RFC literal.
