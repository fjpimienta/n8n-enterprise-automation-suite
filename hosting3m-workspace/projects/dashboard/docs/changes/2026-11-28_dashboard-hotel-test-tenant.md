# Change record: hotel test tenant proposal (option B of the foundations work)

Date: 2026-11-28. Branch: `chore/dashboard-hotel-test-tenant` (local; not pushed, no PR). Revised after the owner's review of the first version (changes listed in section 3).

## 1. Goal and context

Follow-up to `2026-11-28_dashboard-foundations.md`. With the owner's redacted read-only results of the live structure (they are not live access), this phase designs a **hotel test tenant** as files only, so the new UI can later be tried with synthetic data instead of real hotel data. There is no development database: the proposal targets the production database as an **isolated company**, like the agro QA tenants. Nothing is applied to any shared database.

## 2. What changed

### Files in the repo (status: file only, not applied anywhere)
All under `hosting3m-workspace/projects/dashboard/database/proposals/` (a folder that no build, deploy or workflow applies):
- `README.md`: what the folder is (proposals applied by hand, `H###_` prefix; migrations 094, 095 and 106 stay in the agro-erp project as history).
- `H001_hotel_test_tenant.sql`: idempotent synthetic seed with three modes: dry run (default, writes nothing), rehearsal (full apply path, then rollback; consumes a sequence value) and apply.
- `H001_tests.sql`: tests; refuse to run on a real database; one transaction; ends in ROLLBACK.
- `H001_rollback.sql`: soft deactivation of the test tenant only (updates; no drop, no delete, no truncate).
- `H001_state_check.sql`: read-only state report (unchanged since its first version).
- `H001_RUNBOOK.md`: procedure for the production database, opens with the "proposal, not applied, owner approves each step, data only" box.
- `.gitignore` (repository root): one negation line so the SQL files of this folder are versioned (the rest of `*.sql` stays ignored).
- This record.

### Design of the seed
Company `[TEST] Hotel Demo`, industry "Hotelera", flagged as a QA tenant in its metadata; its id comes from the table sequence. Every insert sets the company explicitly (no column default is relied on). Synthetic data: 12 rooms (`T-101` to `T-112`), 6 guests (reserved `.invalid` e-mail domain, `TEST-000N` doc ids and distinct invalid `TEST-PHONE-N` phones, because a live function matches guests by phone), 8 bookings across the pending, confirmed, checked-in, checked-out and cancelled states, 4 maintenance tickets, 3 inspections. Room states cover the scenarios of the boards (blocked room, room with open faults that is not blocked, resolved ticket); this is documented in comments.

Members: the synthetic ADMIN and EDITOR are created only through `sp_access_add_user`. The owner's existing account gets a **temporary** ADMIN membership of the test company only while the procedure runs (only if the company is flagged); afterwards the seed deactivates it with an audit row and verifies that an active synthetic ADMIN remains.

Safety added in this revision: one transaction at REPEATABLE READ with a fingerprint of everything outside the test tenant compared just before COMMIT (the run aborts if it differs; this detects changes made by the script itself, not other sessions' commits); a login value of at least 16 characters outside the test harness (8 inside it, and the harness mode is refused on the production database name); booking dates in the format live rows use today (midnight UTC), with the approved 15:00 / 12:00 America/Mexico_City convention kept as a comment for after the pending data migration.

### Database changes
- **Applied: none** in LOCAL, DEV or PRODUCTION. No schema change is proposed; the seed only inserts data.
- **Applied in a throwaway local database only** (section 4): the seed, the rehearsal, the tests and the rollback.

### n8n workflows, MCP tools, frontend, build configuration, environment files, PWA files
none changed in this phase.

### Outside the repo (private notes, not published)
The redacted results, the throwaway database definition and helper scripts, a read-only inventory of code paths that write to the hotel tables, a list of what each possible hardening change would affect (no SQL written), notes about a live-only database function, and the readiness report. A security-relevant review of these was carried out and is tracked privately.

### Left untouched on purpose
Classic and `next` UI, `core-auth`, `ui-chat`, `ui-pdf-export`, `sw.js`, `manifest.webmanifest`, `angular.json`, environment files, CI, every workflow and gateway, money / IVA / ISH / CFDI logic, `ARCHITECTURE.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`. No hardening SQL was written (defaults, NOT NULL, foreign keys, per-company uniqueness).

## 3. Business rules decided (owner, 2026-11-28)

- Test company: name `[TEST] Hotel Demo`, industry "Hotelera", id from the sequence, members only through `sp_access_add_user`; rows never have NULL or the first company as company; rooms prefixed `T-`, guests with the reserved e-mail domain, `TEST-` doc ids and `TEST-PHONE-` phones.
- Cleanup by soft deactivation only; a company is never deleted; a deactivated tenant stays in place and is not re-seeded.
- The test tenant lives in the production database as an isolated company (no development database exists). A database dump is never restored over production.
- The owner membership is scaffolding only and is deactivated after the synthetic members exist.
- Rehearsal mode is required, and consumes a sequence value (the real id will skip one).
- Run at a quiet hour, outside check-in and check-out times; synthetic accounts only for verification; never the owner account and never a company switch in the interface.
- Booking dates mirror the live format (midnight UTC) until the pending data migration.
- Hardening changes are only described, not written, until approved.

**Open questions:** approval of each hardening change; whether and when to run the runbook; earlier items (public reviews, new roles) unchanged.

## 4. How to test

Real hotel data was never read or written; the live structure was used only through the owner's redacted result files. Dates in the format section: the repo evidence for the midnight-UTC shape is the root `CLAUDE.md` note on booking dates and the demo data comment that mirrors it (read in full for those parts).

Environment used (done): a throwaway Postgres 15 container with its own name, loopback only, data on a memory filesystem (no volumes), schema rebuilt from the redacted live structure plus synthetic rows, then **removed** (`docker ps -a` afterwards lists only the three pre-existing containers, which were not touched).

`H001_tests.sql`, final run, REPEATABLE READ, exit status 0 (all PASS):

| Test | What it proves |
|---|---|
| T-1 | The guard accepts the throwaway database and refuses the production database name or a database whose first company has more than 100 bookings (also shown by running the tests in a database with that name, and with 101 bookings: both refused) |
| T0 | Dry run writes nothing (rows, fingerprint and sequence unchanged) |
| T0b | Rehearsal runs the full apply path (12 rooms exist inside), leaves nothing behind, consumes a sequence value |
| T0c | `apply` together with `rehearse` aborts |
| T0d | A change outside the test tenant (simulated hidden trigger) makes the run abort through the in-transaction fingerprint check |
| T1 | Company created from the sequence, flagged, industry Hotelera |
| T2 | Two active synthetic members created through `sp_access_add_user`; owner scaffolding deactivated with an audit row; an active synthetic ADMIN remains; no clear-text login value stored |
| T3 | Every test row carries the test company; none has NULL or the first company |
| T4 | Only reserved markers in the globally unique columns; 6 distinct invalid phones |
| T5 | No booking, ticket or inspection references a room or guest of another company, in either direction |
| T6 | A company-scoped read sees only its rows; the first company sees none of them |
| T7, T7b | Everything outside the tenant unchanged; all booking dates are midnight UTC |
| T8 | A second apply is a no-op (rows, memberships, audit rows, companies) |
| T9 | Aborts on a same-name unflagged company, a `T-` room, a test guest or a `TEST-PHONE` phone in another company, a too-short login value, an unknown owner |
| T10 | Rollback dry run changes nothing; apply deactivates only the test tenant, deletes no row, leaves the first company and the owner account untouched |
| T11 | A deactivated tenant is not re-seeded |

Standalone runs through standard input, as the runbook prescribes, in the throwaway database (all as expected): a 12-character login value aborts (16 required); a 16-character value passes the dry run; `apply` plus `rehearse` aborts; the rehearsal ends in a real ROLLBACK (state stays `before`, the sequence advanced); apply commits with the in-transaction fingerprint message; state check reports `applied` then `rolled_back` with an identical outside-tenant fingerprint throughout; the rollback prints the counts it changed (1 company, 2 memberships, 2 synthetic accounts, 12 rooms, 6 guests, 8 bookings, 4 tickets); the harness mode is refused on a database named like production. **`sp_access_add_user` works under REPEATABLE READ** (verified in the throwaway container); no fallback is needed. A text check found no destructive statement outside comments in the seed, rollback and state check. The offline gateway test `test_hotel_models_fields.mjs` passed 81 of 81 in the previous run; not re-run now (no workflow changed). The other two gateway tests need an npm install and were not run.

Not run: anything against production or a copy of it; the application against the test tenant; the seed through the real n8n nodes (it uses none); concurrent sessions (the fingerprint check cannot see them by design); dates near midnight (the seed takes the run date in America/Mexico_City, no `toISOString()`; not exercised separately).

Standard checklist cases (values with quotes, commas, "null"/"undefined" text, leading zeros, `data:[{}]`, HTTP 200 with `error:true`, numerics as strings, ADMIN vs non-ADMIN menu): **not applicable** (no user input and no UI in this phase). Cross-tenant attempts: covered at data level by T5 to T7; through the real gateway **not verified**. SQL policy: no string concatenation of caller values; values reach the script as session settings read inside the block. Visual-MVP policy: **followed** (no frontend, build or PWA file changed).

## 5. Rollback

Repo: revert the commits. Database (if ever applied): `H001_rollback.sql` (soft deactivation, no delete). **A dump is never restored over production.** Nothing was applied outside the throwaway database, which no longer exists.

## 6. Known gaps and risks, and follow-ups

- **Not applied and not run against production or a restored copy.** The runbook requires a whole-database dump taken right before applying, verified with a listing, and restored once in a throwaway container first.
- The throwaway schema was rebuilt from result files that omit column lengths; differences from the live definitions are possible (inferred). The access procedures used in the tests are the repo versions (the live ones were read only by their role lines).
- The seed cannot reactivate a deactivated tenant (by design; unique values stay taken).
- Rehearsal consumes a sequence value, so the real company id skips a number.
- The in-transaction check cannot detect other sessions' commits; the cross-session fingerprint of the state check is informational on a live database.
- Hardening changes are **not written**. Their impact on existing writers was assessed and is tracked privately; per-company uniqueness in particular needs workflow changes first.
- A read-only inventory of code paths that write to the hotel tables was carried out and is tracked privately. Writers that exist only in the live system could not be read.
- Follow-ups: approval and execution of the runbook; hardening proposals; option C (gateway migration plan); earlier items (roles, public reviews, CI builds, failing specs) unchanged.

## 7. Objects that exist in the live DB or n8n but not in the repo

Checked by searching the repo for table definitions, function names and workflow nodes, and by comparing with the owner's redacted live results.
- Definitions of the nine hotel tables, constraints and indexes: **live only** (the repo has migrations that alter two of them and test fixtures with partial definitions).
- The gateway's configuration rows for the nine hotel models: **live only**.
- A database function that writes to hotel tables exists live with **no definition and no caller in the repo**; its saved definition is in the private notes. It must be read from the live system before any change that touches those tables.
- Code that syncs external calendars is **not in the repo** although related columns exist; any live workflow doing so must be read from n8n.
- Which version of the hotel MCP server is live: not verified.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and the DB schema docs

`ARCHITECTURE.md` and the dashboard `CLAUDE.md` were read in full in the previous phase; the agro-erp `DATABASE_SCHEMA.md` was read **by keyword search only** (hotel sections).
- `ARCHITECTURE.md` section 1 does not list `database/proposals/`.
- `ARCHITECTURE.md` and `CLAUDE.md` do not mention that the hotel structure is defined only in the live database, or the test tenant proposal.
- The agro-erp `DATABASE_SCHEMA.md` describes the hotel only through migrations 094, 095 and 106; it does not document the nine tables or the live-only function.
- The root `CLAUDE.md` says the dashboard's reservation dates arrive at midnight UTC and proposes the 15:00 / 12:00 convention after a data migration; the seed follows the first and keeps the second as a comment.
