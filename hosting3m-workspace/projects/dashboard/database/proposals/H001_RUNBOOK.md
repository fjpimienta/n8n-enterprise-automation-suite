# Runbook H001: hotel test tenant (production database)

> ⛔ **PROPOSAL, NOT APPLIED. THE OWNER APPROVES EACH STEP BEFORE IT IS RUN.**
> This change is **data only**: it creates one isolated test company and its synthetic rows in the production database. No table, column, function, trigger, n8n workflow, gateway or frontend file is created or changed, so there is no deploy order between layers and nothing depends on a frontend release. The `proposals` folder is not part of any build.
> Placeholders: `<DB_CONTAINER>`, `<DB_NAME>`, `<DB_USER>`, `<OWNER_ACCOUNT>`. Fill them in the shell, never in a file in the repository.

## 1. Purpose and scope
There is no development database: the test tenant lives in the production database as an isolated company, like the agro QA tenants. It lets the hotel screens be tried with synthetic data (rooms `T-101..T-112`, guests `test.guestN@example.invalid` with doc ids `TEST-000N` and phones `TEST-PHONE-N`, bookings `TEST-B01..B08`, tickets and inspections prefixed `[TEST]`) without touching real hotel data. Company `[TEST] Hotel Demo` (industry "Hotelera") is flagged `metadata.qa_tenant = true`; its id comes from the table sequence; every row sets the company explicitly.

Members: two synthetic accounts, ADMIN and EDITOR, created **only** through `sp_access_add_user`. The owner account gets a **temporary** ADMIN membership of the test company while that procedure runs (it needs an active ADMIN of the target company as actor and a new company has none); the script then deactivates that membership with an audit row and verifies that an active synthetic ADMIN remains. Booking dates follow the format live rows have today (midnight UTC); the 15:00 / 12:00 America/Mexico_City convention is in a comment of the seed for after the pending data migration.

## 2. Prerequisites
- Shell on the VPS with Docker access to the database container (the same access the other database runbooks use), and this folder copied there (outside any web root).
- An existing owner account (`<OWNER_ACCOUNT>`) and a **login value of at least 16 characters** for the two synthetic accounts, generated for this purpose and stored in a password manager. Use only letters, digits, `-` and `_` (psql `\set` reads the rest of the line).
- A quiet hour, **outside check-in and check-out times** (the seed and the rollback each hold short row locks and give up after 5 seconds instead of waiting).

## 3. Backup of the whole database (mandatory; take it right before applying)
1. `docker exec <DB_CONTAINER> pg_dump -U <DB_USER> -Fc <DB_NAME> > /root/backups/hosting3m_db_preH001_$(date +%F_%H%M).dump` (a path outside the repository; the dump holds real data).
2. Check it is not empty and is readable: `ls -lh` on the file and `docker exec -i <DB_CONTAINER> pg_restore --list < /root/backups/<FILE>.dump | head`.
3. **Restore it once in a throwaway container before the first apply**, to prove it is restorable: its own name, published on the loopback address only (`-p <LOOPBACK>:<FREE_PORT>:5432`), **no volumes** (use a memory filesystem for the data directory), then `pg_restore` into it and a row count of a few tables. This restored copy holds real data: handle it as such and **remove the container afterwards**. Optional but recommended: run sections 5 and 6 against the restored copy first. Do not run `H001_tests.sql` there; it refuses real databases by design.
4. Never restore a dump over the production database as part of this procedure (see section 9).

## 4. Passing the values (no command line, no shell history)
`owner_email` and the login value go in as `\set` lines on standard input, read silently, so they never appear in a process list or in history:

```bash
read -r -s -p 'Login value (16+ chars): ' H001_PW; echo
OWNER='<OWNER_ACCOUNT>'          # typed in the shell, not saved
run_h001() {   # usage: run_h001 <sql-file> '<extra \set lines>'
  { printf '\\set owner_email %s\n' "$OWNER"; printf '\\set test_password %s\n' "$H001_PW"; printf '%s\n' "$2"; cat "$1"; } \
    | docker exec -i <DB_CONTAINER> psql -X -U <DB_USER> -d <DB_NAME> -v ON_ERROR_STOP=1 -f -
}
```
`printf` is a shell built-in, so the values are not visible in `ps`. Unset them when done: `unset H001_PW OWNER`. The state check needs no values: `docker exec -i <DB_CONTAINER> psql -X -U <DB_USER> -d <DB_NAME> -v ON_ERROR_STOP=1 -v expect=before -f - < H001_state_check.sql`.

## 5. Order (each step needs the owner's go-ahead)
1. **Backup** (section 3).
2. **State check:** `expect=before` must print `STATE OK: before`. Write down the fingerprint line.
3. **Dry run:** `run_h001 H001_hotel_test_tenant.sql ''`. It must end with `H001 DRY RUN: rolled back, nothing changed`. Any `ABORT:` line means a guard failed: stop and investigate.
4. **Rehearsal:** `run_h001 H001_hotel_test_tenant.sql '\set rehearse true'`. It runs the whole apply path inside the transaction and rolls it back (the last line says `REHEARSAL`). **It consumes a sequence value**, so the real company id will skip one number. It cannot be combined with `apply=true` (the script aborts).
5. **Apply (MUTATES the database):** `run_h001 H001_hotel_test_tenant.sql '\set apply true'`. The last lines must say `H001: fingerprint of everything outside the test tenant is unchanged` and `*** H001 COMMITTED ***`.
6. **State check:** `expect=applied` must print `STATE OK: applied`.
7. **Verify with the synthetic accounts only:** sign in as the synthetic ADMIN (and later the EDITOR), choose `[TEST] Hotel Demo`, and confirm that only `T-` rooms and `[TEST]` data appear and that no real room, guest or booking appears. **Never sign in with the owner account and never switch company in the interface**: the hotel gateway pins the company at login and keeps the login company's role until the next login.

## 6. How the checks work (and what the cross-session fingerprint means)
- The seed and the rollback run in one transaction at REPEATABLE READ. Before the first write they take a fingerprint of every row that is not the test tenant's (rooms, guests, bookings, tickets, inspections, memberships, companies and non-synthetic users) and compare it **just before COMMIT**; they abort and roll back if it differs. This in-transaction check is the **authoritative** one. Under REPEATABLE READ it detects changes made by the script itself (for example a hidden trigger); it does not see other sessions' commits, which do not affect the script's correctness.
- The fingerprint printed by `H001_state_check.sql` is computed in a separate session and is **informational on a live database**: real hotel activity (bookings, check-ins, expenses) changes the covered rows between sessions, so a different value at different times is normal. It is only a useful comparison when taken at a quiet moment.
- The seed refuses to run unless the transaction is REPEATABLE READ (it opens it itself).

## 7. Verification summary
`STATE OK: applied`; the synthetic ADMIN and EDITOR can sign in; the owner has no active membership in the test company (an inactive row and two audit rows remain, `USER_ADDED` and `USER_DEACTIVATED`); real data is not visible from the test company.

## 8. Rollback (soft deactivation only)
1. Dump again if hours have passed, then dry run: `run_h001 H001_rollback.sql ''` (the same function; the rollback only uses `owner_email`, as the actor recorded in the audit rows, and ignores the other `\set` line).
2. **MUTATES (database):** the same with `'\set apply true'`. It deactivates the company, its memberships, the two synthetic accounts, rooms, guests and bookings, marks the tickets `DELETED`, prints the counts of what changed and runs the same in-transaction fingerprint check. Nothing is deleted.
3. `expect=rolled_back` must print `STATE OK: rolled_back`.

## 9. What not to do
- **A dump is never restored over the production database.** Restoring a full dump would erase every real booking, payment and check-in made since the backup.
- **A deactivated tenant stays in place.** Re-seeding it is not supported: the seed aborts, because `room_number`, guest e-mail and `doc_id` are globally unique and their `T-` / `TEST-` values stay taken. A company is never deleted (its memberships cascade on delete).
- Do not run `H001_tests.sql` against production or a restored copy of it; it refuses to run (database name or more than 100 bookings in the first company).

## 10. Not covered
Hardening changes (dropping column defaults, NOT NULL, foreign keys, per-company uniqueness), new roles, and use of the test tenant by the `next` UI are separate decisions and are not part of this runbook.
