# Runbook H001: hotel test tenant

> ⛔ **PROPOSAL, NOT APPLIED. DO NOT APPLY TO ANY SHARED DATABASE UNTIL THE OWNER APPROVES EACH STEP.**
> This change touches the **database only** (data, no schema change). The frontend, n8n workflows and gateways do not depend on it and are not changed, so there is no deploy order between layers. `main` deploys the frontend automatically from the hosting panel, but this folder is not part of any build.
> Order: (1) tests in a throwaway database, (2) backup and dry-run in DEV, (3) apply in DEV, (4) verify, (5) a separate owner decision on whether production also gets a test tenant (**not part of this runbook**).

## 1. Purpose and scope
Creates a synthetic hotel test tenant so the hotel can be tried without touching real data: company `[TEST] Hotel Demo` (industry "Hotelera", flagged `metadata.qa_tenant = true`), three memberships, 12 rooms, 6 guests, 8 bookings, 4 maintenance tickets and 3 room inspections. Every row sets the company explicitly (never the column default). Everything is invented: rooms `T-101..T-112`, guests `test.guestN@example.invalid` with doc ids `TEST-000N`, bookings external ids `TEST-B01..B08`, tickets and inspections prefixed `[TEST]`. Booking dates are relative to the run date; arrival 15:00 and departure 12:00, America/Mexico_City.

Members: the company id comes from the table sequence (not chosen by the script). The owner account (existing; passed as `owner_email`) gets a direct ADMIN membership with an audit row, because `sp_access_add_user` requires an active ADMIN of the target company as actor and a new company has none (same bootstrap as the QA palm tenant seed). The synthetic ADMIN and EDITOR are created **only** through `sp_access_add_user`.

## 2. Prerequisites
- A database with the hotel structure, the `sp_access_*` functions and `access_audit_log`. For the tests, a **throwaway** copy with synthetic data only.
- An existing owner account and a password of at least 8 characters for the two synthetic accounts, passed on the command line (never stored in a file). Use a throwaway value in non-shared environments.
- `psql` run from this folder (the tests use `\i`).

## 3. Pre-checks
1. `psql -X -v ON_ERROR_STOP=1 -v expect=before -f H001_state_check.sql` must print `STATE OK: before`. **Write down the fingerprint** (it covers every row that is not the test tenant's).
2. The next company id is the one you expect (read the sequence in a read-only session). A dry run does not consume a sequence value; a real apply does.

## 4. Backup (mandatory)
Take a database dump before applying (for example `pg_dump -Fc` of the DEV database to a file outside the repository) and check that it is not empty.

## 5. Tests (throwaway database only)
`psql -X -v ON_ERROR_STOP=1 -v owner_email=<account in the throwaway database> -f H001_tests.sql`. Expected: `PASS` lines T0 to T11 and `H001 tests finished; everything rolled back`. The expected ERROR lines (six "ABORT" messages and one "current transaction is aborted" group) come from the abort-case tests. Note: tests consume sequence values (sequences are not rolled back), so the next company id in the throwaway database moves on.

## 6. Dry run (DEV)
`psql -X -v ON_ERROR_STOP=1 -v owner_email=<OWNER> -v test_password=<PASSWORD> -f H001_hotel_test_tenant.sql`. It must end with `H001 DRY RUN: rolled back, nothing changed` and write nothing. Any line starting with `ABORT:` means a guard failed: stop and investigate.

## 7. Procedure (DEV)
1. **MUTATES (database).** Same command with `-v apply=true`. The last line must say `H001 COMMITTED`.
2. `psql ... -v expect=applied -f H001_state_check.sql` must print `STATE OK: applied`, and the fingerprint must equal the one written down in section 3.
3. Sign in to the DEV application as the synthetic ADMIN, choose the test company, and check that only `T-` rooms and `[TEST]` data appear and that the real company's data does not.

## 8. Verification
- Fingerprint unchanged (section 7, step 2).
- A user with memberships in both companies sees each company's data only after choosing it at login (the gateway scopes by the company of the login).

## 9. Rollback (soft deactivation only)
1. Dry run: `psql -X -v ON_ERROR_STOP=1 -v owner_email=<OWNER> -f H001_rollback.sql`.
2. **MUTATES (database).** Same command with `-v apply=true`. Nothing is deleted: the company, memberships, synthetic accounts, rooms, guests and bookings become inactive and tickets get status `DELETED`.
3. `psql ... -v expect=rolled_back -f H001_state_check.sql`: `STATE OK: rolled_back`, same fingerprint.
A deactivated tenant is never re-seeded (the seed aborts); to start over, restore the dump. A company is never deleted (its memberships cascade on delete).

## 10. Not covered
Production use of a test tenant, the hardening changes (defaults, NOT NULL, foreign keys, per-company UNIQUE) and the roles beyond ADMIN and EDITOR are separate decisions and are not part of this runbook.
