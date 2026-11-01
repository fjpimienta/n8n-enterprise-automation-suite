# Runbook 094 / 095 — company scoping for the hotel CRUD workflow (v5)

**Scope:** `hotel_maintenance_tickets` gets a tenant column (094, then 095 removes its default), and the `v5/CRUD` workflow takes the company only from the verified token.

## What changes
- **094:** `hotel_maintenance_tickets.id_company integer NOT NULL DEFAULT 1` + FK to `companys` + index. No data is rewritten; the previous workflow keeps working. Company 1 owns all existing hotel data.
- **v5/CRUD (nodes `Extract Auth Context`, `Build Query`):** the company comes from the verified token (missing/invalid -> 403 `NO_TENANT`); it is enforced on getall/getone/insert/update/delete; any client-supplied tenant value is ignored; tables without a mapped tenant column are denied unless listed explicitly.
- **095:** removes the default so a ticket can never be created without an explicit company. Run it only after the new workflow has been stable for a day.

## Procedure (VPS, `root@hosting3m`)
1. Backup: `pg_dump -Fc` of `hosting3m_db` into the backups folder, and download the current `v5/CRUD` JSON from n8n (it is the workflow rollback).
2. State and dry run: `check before`, then `dry 094` (everything is rolled back).
3. Apply: `apply 094`, then `check applied_094`. Fingerprints (ticket count and md5s) must not change.
4. Deploy the two nodes in n8n (replace the code, Save) and verify the hotel dashboard: list and write on bookings, guests, inventory, expenses and maintenance; Executions must show no `NO_TENANT` or "Tabla sin aislamiento" errors.
5. After a stable day: `dry 095`, `apply 095`, `check applied_095`.

Local tests: `cd workflows/06-dynamic-crud-engine/v5/tests && npm install && npm test` (PostgreSQL in WASM; reads the node code from `v5-crud.json`).

## Rollback
- Workflow: restore the previous node code (or import the JSON saved in step 1).
- Database: `094_rollback.sql` restores `DEFAULT 1` (the column stays; it is inert for the previous workflow). Removing the column is a separate, manually approved step.

## Notes
- Users who belong to several companies get the company they select at login; hotel screens show data for company 1 only.
- Every script has a dry run (default) and needs `-v apply=true` to commit. No script uses DROP COLUMN, DELETE or TRUNCATE.
