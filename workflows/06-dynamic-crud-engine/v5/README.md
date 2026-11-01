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
