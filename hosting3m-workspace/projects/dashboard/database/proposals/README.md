# Dashboard database proposals

Files in this folder are **proposals**. Nothing here is applied by any workflow, CI job or build; each file is applied by hand, after the owner approves it and a backup has been taken. There is no development database; H001 targets the production database as an isolated test company. Files use the `H###_` prefix (hotel migrations belong to this project; migrations 094, 095 and 106 stay in the agro-erp project as history).

| Proposal | What | Status |
|---|---|---|
| `H001_hotel_test_tenant.sql` | Synthetic hotel test tenant (company, members, rooms, guests, bookings, tickets, inspections) | File only, not applied. Dry run, rehearsal, apply, rollback and tests passed in a throwaway local database. |
| `H001_tests.sql` | Tests for H001 (ends in ROLLBACK) | Same |
| `H001_rollback.sql` | Soft deactivation of the test tenant (no DROP, no DELETE) | Same |
| `H001_state_check.sql` | Read-only state and fingerprint check | Same |
| `H001_RUNBOOK.md` | Procedure for the production database (isolated test company, data only) | Pending approval of each step |
