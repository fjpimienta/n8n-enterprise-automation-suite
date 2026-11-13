> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente: el dueño entra a Plesk y despliega con git. Si el frontend se despliega antes, si se mergea antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only (PostgreSQL 15.4). NOT applied to production.** This pull request changes the database only.
> Part 2 (n8n) does not apply: no workflow or gateway code changes, and nothing in the frontend calls the new models yet (PR C2 adds the gateway
> entries for the balance and the void, PR E the dashboard). It is stated explicitly so the checklist above stays honest.

# Runbook 105 — gateway models for the palm sales (database only)

## Scope

| Object | Kind | Notes |
|---|---|---|
| `vw_agri_sale_ui_list` | view (new) | the browser view of the sales of a company; reduced columns; no company filter of its own (the gateway adds `id_company`) |
| `agri_sales` | `crud_models` row | read model over `vw_agri_sale_ui_list`; operations `SELECT, GETONE, GETALL`; read role `ADMIN`; no insert / update / delete role |
| `agri_sale_summary` | `crud_models` row | read model over `vw_agri_sale_summary` (active sales only, aggregates); same operations and roles |
| `agri_sale_invoices`, `agri_sale_audit`, `company_flags`, `company_issuer_rfcs` | `crud_models` rows | **restricted models**: registered with no operation and no role; the procedures and the platform seeds remain the only writers |

`vw_agri_sale_ui_list` columns, in order: `id, id_company, folio, sale_date, buyer_name, quantity, unit_code, unit_price, total_amount, payment_method, ticket_ref, ticket_warning,
plantation_id, plantation_code, plantation_name, lot_id, lot_code, lot_name, status, void_reason, voided_at, is_test, created_at`. It does not carry the voucher UUID, the buyer tax id,
the SAT state, e-mail addresses, file paths or hashes. Voided sales stay in the list with their `status`; the summary excludes them. Every model lists `id_company` in `allowed_fields`.

Not touched: every other `crud_models` row, the procedures and tables of migration 104, workflows, the gateway code and the frontend.
Pattern followed: `081_agri_expenses.sql` (upsert on `model_name`, backup first) and the ADMIN-only reads of `071` / `073`.

## Part 1 — Database (owner only)

Conventions
```bash
P='docker exec -w /root/repro/vps105 -i n8n-enterprise-db psql -X -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```
Apply and roll back **without** `--single-transaction`. Without `-v apply=true` every file is a dry run (it ends in `ROLLBACK`).

0. **Files.** Copy the `105_*` files to the host and compare `md5sum` with the repo.
1. **Backup and size check.** `docker exec n8n-enterprise-db pg_dump -U n8n_user -d hosting3m_db -Fc > backup_pre105_$(date +%Y%m%d_%H%M%S).dump`; confirm the file is larger than 100 KB.
2. **Read-only pre-check.** Nothing may already serve these objects:
   `SELECT model_name, table_name, allowed_ops FROM crud_models WHERE model_name IN ('agri_sales','agri_sale_summary','agri_sale_invoices','agri_sale_audit','company_flags','company_issuer_rfcs')
   OR table_name IN ('vw_agri_sale_ui_list','vw_agri_sale_summary','agri_sale_invoices','agri_sale_audit','company_flags','company_issuer_rfcs');`
   Expected: **0 rows**. If any row appears, stop and review it (the migration overwrites rows with these model names and aborts if the table name differs).
3. **State before.** `$P -v expect=before -f 105_state_check.sql` must print `STATE OK: before`. Save the FINGERPRINT block.
4. **Dry run.** `$P -f 105_agri_sale_gateway_models.sql` must end with `105: OK` and `DRY RUN: 105 rolled back`.
5. **Apply — only with the owner's explicit go-ahead.** `$P -v apply=true -f 105_agri_sale_gateway_models.sql` → `105 COMMITTED`.
6. **State after.** `$P -v expect=applied -f 105_state_check.sql` → `STATE OK: applied`. The FINGERPRINT block must be **identical** to step 3 (every other `crud_models` row, the migration 104 tables,
   functions, views and guard triggers are fingerprinted).
7. **Verification queries (read-only).**
   * The six rows: `SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, allowed_fields FROM crud_models WHERE model_name IN (...) ORDER BY 1;`
     → two read models (`{SELECT,GETONE,GETALL}`, `ADMIN`, other roles `NONE`) and four restricted models (empty operations, all roles `NONE`).
   * The view columns: `SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='vw_agri_sale_ui_list';`
   * Tenant column in every model whose table or view has `id_company`:
     `SELECT m.model_name FROM crud_models m JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name=m.table_name AND c.column_name='id_company' WHERE NOT (m.allowed_fields ? 'id_company') ORDER BY 1;`
     (report only: this migration does not change any row outside its six).
8. **Runtime check (after PR C2 and the dashboard exist, test company only).** An ADMIN of the palm test company reads `agri_sales` / `agri_sale_summary` through the gateway and sees only that company;
   an EDITOR gets a role refusal; a write operation on either model is refused.

## Part 2 — n8n

Not part of this pull request (no workflow or gateway change).

## Part 3 — Frontend

Not part of this pull request.

## Rollback (deletes no data)

`$P -v apply=true -f 105_rollback.sql`, then `$P -v expect=rolled_back -f 105_state_check.sql`. The two read models are disabled (no operation, no role) and `vw_agri_sale_ui_list` stays in place
(a view definition; it holds no data). The four restricted models stay registered. The rollback contains no `DROP`, `DELETE` or `TRUNCATE`
(`bash 105_static_check.sh` asserts it for every 105 file except the tests). Re-applying `105_agri_sale_gateway_models.sql` keeps using `CREATE OR REPLACE VIEW` and re-enables the read models.

## Results of the local run (throwaway database, PostgreSQL 15.4, schema + the gateway model definitions copied from a local clone, synthetic data)

* From zero: `state before` → dry run (nothing written) → apply → `state applied` → `105_tests.sql` → rollback (dry run, apply) → `state rolled_back` → re-apply → `state applied` → `105_tests.sql`.
  The FINGERPRINT block was identical in every state (all other `crud_models` rows, the migration 104 columns, functions, views and guard triggers). After the rollback the view still exists with the
  same definition (its md5 equals the one of `applied`) and the two read models are disabled.
* `105_tests.sql` (one transaction, always `ROLLBACK`): `ALL 105 TESTS OK`. It checks: `id_company` in `allowed_fields` of the six models; the four restricted models have no operation and no role (no operation
  allowed for ADMIN either); the read models allow only `SELECT/GETONE/GETALL` and only `ADMIN` (role matrix ADMIN / OWNER / EDITOR / CUSTOMER / GUEST against every operation, with the same operation / role
  rule as the gateway); the exact column list of `vw_agri_sale_ui_list` and of the summary, with `id_company` present and none of the excluded columns; the summary excludes voided sales while the list shows them;
  two fake companies never mix when filtered by `id_company` (list and summary) and a sale cannot point at a plantation of another company; the sale tables of migration 104 still reject direct changes;
  a generic report of every model whose table or view has an `id_company` column and does not list it in `allowed_fields` (report only).
* Mutation checks: each rule was broken once (twelve cases: tenant field removed, restricted model with an operation, read model with INSERT, read role widened, view with an extra SAT state column, view with an extra
  voucher UUID column, restricted model missing, restricted model with a role, wrong `id_company` in the view, summary including voided sales, 104 guard disabled, view columns reordered) and every case made
  the tests fail (the cases that change the migration also fail its own post-check); a rollback that drops the view, a rollback that deletes the restricted models and a rollback that leaves a read model enabled each made `state_check -v expect=rolled_back` fail.
* Static check: `bash 105_static_check.sh` reports no line starting with `DROP`, `TRUNCATE` or `DELETE` (comments excluded) in the migration, the rollback or the state check; a rollback with a `DROP` line makes it fail.
