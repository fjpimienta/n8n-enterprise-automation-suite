# Change record: dashboard foundations (readiness analysis and local serve configuration)

Date: 2026-11-28. Branch: `chore/dashboard-foundations` (local, from `develop`; not pushed, no PR). Phase 4 of the hotel ERP work.

## 1. Goal and context

Phase 4 prepares what blocks using the `next` UI with real data: a readiness analysis of the hotel's data and gateway layer, a hotel test tenant, separation of the development environment from production, and the hotel's move to the newer CRUD gateway. The owner approved only two options: **A** (readiness report and read-only query pack, kept in private notes) and **D1** (a committed local serve configuration). Options B (test tenant files) and C (gateway migration plan) are deferred until the readiness results are back. No live system was contacted in this session.

## 2. What changed

### Files in the repo
- `hosting3m-workspace/angular.json`: new `local` build configuration for `dashboard` (development-like options plus a file replacement of `environment.ts` by `environment.local.ts`); new `local` serve configuration; the dashboard serve default changes from `development` to `local`. Status: **file only, committed locally, not pushed**; verified locally (section 4).
- `hosting3m-workspace/projects/dashboard/src/environments/environment.local.ts`: new, committed. Placeholder endpoints that point at this machine only. Status: same as above.
- `hosting3m-workspace/projects/dashboard/docs/changes/2026-11-28_dashboard-foundations.md`: this record.

Commit on the branch: `chore(dashboard): add a local serve configuration that cannot reach production`. This record is not committed yet.

### Outside the repo (private notes, not published)
A readiness report and a read-only query pack (10 files plus a README, one query per file, each wrapped in a read-only transaction with a statement timeout and a rollback) were written to the owner's private notes folder. **Not executed anywhere** (no database was approved for options A and D); their syntax is not verified.

### Database
none. No migration, SQL file, table, column, function or trigger was added or changed. No SQL was run.

### n8n workflows and MCP tools
none. No workflow was changed, imported or exported.

### Frontend
none. No component, service, guard, route, style or `sw.js`/manifest file changed.

### Infra / config
- Build and serve configurations: see `angular.json` above.
- Environment files: `environment.local.ts` added. The generated, git-ignored `environment.ts` and the way CI creates it are **unchanged**.
- CI workflow: unchanged (it builds `dashboard` with the default configuration, which is still `production`).

### Left untouched on purpose
Classic components, guards and routes; `sw.js`; `manifest.webmanifest`; the `production`, `development` and `demo` configurations; the CI workflow; `core-auth`, `ui-chat`, `ui-pdf-export`; `proxy.conf.json` (present in the project, not referenced by `angular.json`); money, IVA, ISH and CFDI logic; `ARCHITECTURE.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`.

## 3. Business rules decided (owner, 2026-11-28)

- Scope: options A and D1 now; B and C after the readiness results.
- Roles stay ADMIN and EDITOR; no new roles are added now.
- Admin-only resolve of a maintenance fault and admin-only view of repair cost are accepted as UI-level rules for now; the limitation and its follow-up are recorded in the private notes.
- Hotel migrations belong to the dashboard project in a `database/proposals/` folder with `H###_` prefixes (nothing is applied from there); the existing hotel migrations in the agro-erp project stay as history.
- Test tenant cleanup, when built, is soft deactivation only. A throwaway local database for dry-runs is approved for option B only.
- Reported by the owner: no reporter, resolver or timestamps will be recorded for maintenance faults, so no schema change is needed for that.

**Open questions:** the test tenant's company id (to be chosen at B after the readiness results); what happens with the public reviews of the public site (decided at C); the results of the query pack.

## 4. How to test

LOCAL only, never against real hotel data. No application code changed, so `ng test` was **not run** in this session.

Evidence of the D1 change (baseline built from a detached worktree of `develop`, the change from a second worktree with the two changed files; the git-ignored environment file was copied into both):

| Check | Result |
|---|---|
| `ng build dashboard --configuration=production`, before and after | Both succeed. `diff -r` of the whole output folder: **no difference** (byte for byte, hashed file names included). |
| `sw.js` and `manifest.webmanifest`, before vs after | Identical (same SHA-256 prefix for each pair). |
| Leak search of the production output for the local placeholder host and `environment.local` | 0 files. |
| `ng build dashboard --configuration=local` | Succeeds. 0 files contain the host of the generated environment file; 2 files contain the local placeholder. |
| Plain `ng serve dashboard` (default now `local`), served on a spare port | HTTP 200 for the index; the served main bundle contains the local placeholder (5 matches) and 0 matches of the production host. The server was stopped afterwards. |
| `git diff --name-only` for the change | `hosting3m-workspace/angular.json` and the new `environment.local.ts` only. |

**Fresh checkout (no generated `environment.ts`):** every configuration, including `production`, `development` and `demo` (already the case before this change), and the new `local`, fails with "Could not resolve the environment import". A file replacement needs its source file to exist. Observed workaround (verified): copy `environment.local.ts` to `environment.ts` (git-ignored) once; `ng serve dashboard` then starts and serves. Making a fresh checkout work without that step would need another committed file or a path change, which was outside the approved scope.

Demo-configuration cases for the existing `next` UI (quotes, commas, leading-zero room numbers, `data:[{}]`, HTTP 200 with `error:true`, numerics as strings, midnight in America/Mexico_City, ADMIN vs non-ADMIN menu, cross-tenant attempts) are unchanged by this work and are recorded in the earlier phase records. For this phase: **not applicable** (no data path or UI changed).

Visual-MVP policy: **followed**. The new UI and the mock are still absent from the production output (leak search above, 0 hits), `sw.js` and the manifest are identical, and no money or fiscal logic was touched. Hotel data in this session: none read or written.

## 5. Rollback

D1: revert the single commit (it restores the previous serve default and removes the `local` configurations and the placeholder file). The production build is unaffected either way (identical output, above). The query pack and report live outside the repo and can simply be deleted. No database or n8n rollback exists because nothing was applied.

## 6. Known gaps and risks, and follow-ups

- **Not verified, owner to confirm:** the command the hosting panel runs after downloading `main` (it lives only in the panel). If it builds with the `development` configuration or runs `ng serve`, this change could matter; the CI workflow, the only build step visible in the repo, uses the default configuration.
- A developer who relied on a plain `ng serve` reaching the real services now gets the local placeholder; a local n8n is needed, or the previous behaviour with an explicit `--configuration=development`.
- Fresh-checkout limitation described in section 4 (pre-existing for every configuration).
- The readiness query pack has not been executed; the live schema, per-model gateway configuration, constraints, triggers and counts remain unread.
- Option B (test tenant files, a throwaway local database for dry-runs) and option C (gateway migration plan) are pending the query results and the owner's choices. Known follow-ups from earlier phases are unchanged (CI builds for both configurations, failing specs, locale, PWA update test).
- A review of role enforcement and exposure in the hotel gateway was carried out and is tracked privately.

## 7. Objects that exist in the live DB or n8n but not in the repo

The hotel tables' definitions, constraints, triggers, functions and the gateway's per-model configuration rows are not defined by any migration or schema file in the repo (checked by searching the repo for table definitions and configuration inserts, and by reading the hotel-related migrations and gateway workflow export; the hotel migrations found only alter existing objects). They **must be read from the live system** before any change; the private query pack is the means.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and the DB schema docs

`ARCHITECTURE.md` and the dashboard `README.md` sections on limitations and commands were read in full for this record; the dashboard `CLAUDE.md` was read in full earlier in the session. No database schema doc was read in full.
- `ARCHITECTURE.md` section 5 says both environment configurations point to production; the new `local` configuration does not (it is the default for `ng serve`).
- `CLAUDE.md` ("Run local dev server: `ng serve dashboard`") and `README.md` ("Servidor local") do not mention that the default is now the `local` configuration, the placeholder file, or the generated-file requirement.
- `README.md` limitation 7 says the environment files are not in the checkout; `environment.demo.ts` and now `environment.local.ts` are committed, only `environment.ts` is generated and git-ignored.
- `ARCHITECTURE.md` section 1 does not list the `environments` folder, `ui-variant`, `demo`, `next` or `theme-hotel` (unchanged from earlier records).
