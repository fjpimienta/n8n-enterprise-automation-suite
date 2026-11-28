# Change record: dashboard maintenance board ("Mantenimiento", `next` UI, demo build only)

Date: 2026-11-28. Branch: `feat/dashboard-maintenance` (local, from `develop` at the Phase 2 squash commit; not pushed, no PR).

## 1. Goal and context

Second ERP module on the `next` UI (see `2026-11-27_dashboard-erp-mvp-ui.md` and `2026-11-27_dashboard-housekeeping.md`): a
**read-only** maintenance board that lists open tickets by priority and age and shows which rooms they affect. It exists only
in the `demo` build configuration, verified locally with the synthetic mock. The classic UI and the production configuration
are unchanged. Scope approved by the owner: option A (read-only board). Resolve/report actions (option B) and new data
(option C) are written follow-ups only (sections 3 and 6).

## 2. What changed

Status of every item: **file only, not applied** (nothing deployed; local branch). Verified locally with the `demo`
configuration (section 4).

### Frontend, new files (`hosting3m-workspace/projects/dashboard/src/`)
- `app/next/logic/maintenance.ts` (+ spec): pure rules. Priority groups, review reasons, age in whole days, counters.
- `app/next/maintenance/maintenance-next.component.{ts,html}` (+ spec): the "Mantenimiento" page.
- `app/next/ui/maintenance-row.component.ts`: presentational, read-only row (chips, description, age).

### Frontend, existing files modified
- `app/ui-variant/ui-variant.next.ts`: `uiChildRoutes` gains the `mantenimiento` route (demo only).
- `app/app.routes.ts`: the `...uiChildRoutes` spread moved from the end of the `dashboard` children to the START, so that in
  `next` the new page replaces the classic page at `/dashboard/mantenimiento`. In classic the array is empty, so behaviour is
  unchanged (evidence in section 4).
- `app/demo/demo-data.ts`: synthetic tickets enriched (types, descriptions, priorities, ages around the 3-day threshold, one
  without an id, one without description and type, one with an unknown priority, one resolved). New helper `ticketStamp`.
- `app/demo/demo-mock.interceptor.spec.ts`: 3 new tests for the synthetic tickets.
- `theme-hotel/theme-hotel.scss`: `.h-mt*` styles (included only by the `demo` configuration).

### Database, n8n workflows and gateways
none. No migration, SQL, workflow, gateway or MCP tool was added or changed. No SQL exists in this work.

### Infra / config
none. `angular.json`, `app.config.ts`, `ui-variant.ts` (classic), `sw.js`, `manifest.webmanifest`, `index.html` and environment
files are unchanged.

### Left untouched on purpose
Classic components, services, guards and styles (nothing under `features/`, `core/`, `shared/`); `MaintenanceService` and
`HotelService` (the page only calls the existing `MaintenanceService.loadTickets()`; no new service or endpoint);
`next/logic/nav.ts` (the "Mantenimiento" menu entry and title already pointed at `/dashboard/mantenimiento`);
`demo/demo-store.ts` and the mock's write rules (still only the in-memory `cleaning_status` update from Phase 2);
`core-auth`, `ui-chat`, `ui-pdf-export`; `public/`; `ARCHITECTURE.md`, `CLAUDE.md`; money, IVA, ISH and CFDI logic.

### Documentation (Spanish, existing style)
`README.md` and `CHANGELOG.md`: not edited yet. A proposed text was handed to the owner for approval. Status: pending.

### Data-write policy of this task
- **No write path was added or touched, real or demo.** The page has no buttons besides "Actualizar", no inputs, and no
  call to any mutating method (unit-tested: the only button is "Actualizar", there are no `input`, `textarea` or `select`
  elements, and `alert()` and `confirm()` are never called).
- The only request the page adds is the read `MaintenanceService.loadTickets()` (a `getall`), which the classic monitor
  already makes, plus the existing rooms load. In the demo both are answered by the mock, which never forwards a request.
- The demo store was not extended (owner condition). No real hotel data was read or written; there is no hotel test tenant.

## 3. Business rules decided (owner, 2026-11-28)

- Route: in `next`, the new page replaces the classic monitor at `/dashboard/mantenimiento` (spread moved before the classic
  routes). **Precondition before enabling `next` for real users:** the next Maintenance page must reach at least parity with
  the classic monitor's resolve flow (option B or a hybrid).
- Priorities kept as `CRITICAL`, `NORMAL`, `LOW`, shown as Crítica, Normal, Baja. Unknown priorities go to "Revisar datos".
- Order inside a group: oldest first (then ticket id; unknown age last). A ticket older than 3 days is "Antiguo" (constant
  `MT_OLD_AFTER_DAYS`, 3; "older" means strictly more than 3 whole days, so exactly 3 is not old).
- Age = whole calendar days between the America/Mexico_City dates of `created_at` and now. The ISO instant is converted to
  its Mexico City date before comparing; no `toISOString()` is used for date keys.
- Only open (`PENDING`) tickets are shown. Resolved tickets are not shown and there is no "resueltos hoy" counter. Cost is
  not shown; `solution_details` does not apply.
- A room with an open ticket whose status is not maintenance shows "Con falla pendiente"; a room in maintenance shows
  "Bloqueada".
- Issue types: PLOMERIA = Plomería, ELECTRICO = Eléctrico, AIRE_ACONDICIONADO = Aire acondicionado, ALBAÑILERIA = Albañilería,
  MOBILIARIO = Mobiliario, TECNOLOGIA = Tecnología. Unknown or missing = "Otro" (not a review reason).
- "Revisar datos" holds (never hidden, with a count and a reason per row): no id, no description and no type, unknown
  priority, unknown status (anything other than `PENDING` or `RESOLVED`), no room.
- Counters: open (consistent data only), critical, old (any group), review, rooms blocked, rooms with a pending fault.
  Unknown shows "—", never 0.
- The ticket service hides `error:true` (it returns an empty list), so a list with no readable row at all is shown as unknown
  ("—") with "Sin datos de fallas". A list holding only resolved tickets is a real "No hay fallas abiertas" (zero).
  A thrown request error shows an alert banner. **Inferred** from reading the service; confirmed by unit tests with fakes.
- No `alert()`, `confirm()` or emoji in the `next` UI.

**Open business questions (option B, not decided):**
5. After resolving the last open ticket of a room, what is the room's state? Owner's leaning: dirty (so it goes through
   Limpieza). Today the classic flow sets it free and clean.
6. Should a room stay blocked while other open tickets exist? Owner's leaning: yes. Today the classic flow frees it anyway.
7. Who may resolve a ticket? Owner's leaning: any role (as today in the client).

## 4. How to test

LOCAL only, never against real hotel data. `npx ng serve dashboard --configuration=demo`, sign in with user `admin` (ADMIN)
or `editor` (non-ADMIN), open "Mantenimiento" (the menu entry or `/dashboard/mantenimiento`). A plain `ng serve` points to
production endpoints: do not use it. Scenarios by URL: `?demo=empty`, `?demo=error`, `?demo=writeerror`.

Synthetic data (all invented): 10 open tickets and 1 resolved. All open tickets sit on rooms 105 (in maintenance) and 204
(available), so the rooms flagged by the tickets radar stay exactly those two (Panel KPI and Housekeeping unchanged).

| Case | Expected | Result |
|---|---|---|
| Normal data | KPIs 7 / 2 / 4 / 1 / 1 (open, critical, old, blocked rooms, rooms with a pending fault); sections Crítica 2, Normal 3, Baja 2, Revisar datos 3 | Observed (scripted browser run) |
| Ages around the threshold | 3 days = not old, 4 days = old; "Hoy", "Ayer", "Hace N días" | Unit tested; observed |
| Midnight America/Mexico_City | 23:59 and 00:00 local fall on different days; 3 vs 4 days around the threshold at 23:59 | Unit tested (logic and demo stamps) |
| Empty collection `data:[{}]` (`?demo=empty`) | No crash; "Sin datos de fallas"; ticket KPIs "—" | Observed (5 widths x 2 themes); unit tested |
| HTTP 200 with `error:true` (`?demo=error`) | Same as above (the service returns an empty list) | Observed; unit tested through the empty-list path |
| Request that throws | Alert banner, KPIs "—" | Unit tested (fake service) |
| Only resolved tickets | "No hay fallas abiertas", KPIs 0 (a real zero) | Unit tested |
| Numerics as strings (ids, room ids) | Parsed explicitly; invalid ids treated as missing | Unit tested |
| Priority or status unknown, no id, no description and no type, no room | "Revisar datos" with count and reason; counted apart | Unit tested; observed |
| Unknown or missing issue type | "Otro" | Unit tested; observed |
| Ticket without id | Kept, distinct stable list keys | Unit tested; observed |
| Cost present in the data | Never displayed | Unit tested |
| No rooms loaded | Room-derived KPIs "—", ticket KPIs still shown | Unit tested |
| Read-only | Only "Actualizar"; no inputs; `alert()`/`confirm()` never called | Unit tested |
| `?demo=writeerror` | Reads normal, page unaffected (it never writes) | Not exercised separately |
| Room numbers with leading zeros, text with quotes or commas | Room numbers come from the rooms data and are rendered as text; free text is rendered by interpolation, wraps and is never parsed | Not applicable as input (no input field); rendering of long text not exercised with quotes/commas, **not verified** |
| ADMIN vs non-ADMIN menu | Entry visible to both (unchanged from Phase 1; no new role rule) | Unchanged; admin observed |
| Cross-tenant attempts | Not applicable in demo (synthetic data only) | Not applicable |
| Real read or write (classic app, real gateway) | Not exercised | **Not verified** |

Unit and component tests: `npx ng test dashboard --watch=false`. Baseline on `develop` before any change: 132 tests, 127 pass,
5 fail (4 spec files; the test setup lacks the auth environment configuration provider; pre-existing, not touched).
After: 173 tests, 168 pass, the same 5 fail in the same 4 files. 41 tests are new and all pass (logic 26, page 12, mock 3).

Build and parity checks (baseline built from a detached worktree of `develop`, the branch from a detached worktree of its
head; node modules and the environment file were linked or copied into both):
- `ng build dashboard --configuration=production`: succeeds, 15 files in `browser/` for both (12 at the top level plus the 3
  images under `assets/`). Compared recursively by SHA-256, with the content hashes in file names normalised: the three
  images, `favicon.ico`, `manifest.webmanifest`, `sw.js` and every lazy chunk are identical in content. `main` differs (same
  size, 1,065,323 bytes, new content because of the moved spread), and `index.html` differs only in the hashed file names it
  references (identical after normalising them). One lazy chunk has a different byte hash only because it imports another
  chunk by its hashed name (identical after normalising it). Files outside `browser/`: same list. Angular's initial transfer
  estimate: 279.40 to 279.43 kB. (An earlier count of "13" in this session was a top-level listing that counted the `assets/`
  folder as one entry and did not look inside it; it is superseded by this paragraph.)
- Unoptimised parity build (development configuration, no optimisation, no hashing, no source maps), worktree path
  normalised: the whole difference in `main.js` is the moved empty-array spread (`...uiChildRoutes,` added at the start of
  the dashboard children, `...uiChildRoutes` removed from the end, and the trailing comma of the previous line).
- Leak search of the production `main` for: `MaintenanceNext`, `MaintenanceRow`, `maintenance-next`, `buildMaintenanceItems`,
  `MT_OLD_AFTER`, `ticketStamp`, `buildDemoTickets`, `demoMock`, `theme-hotel`, `h-mt__`, "Fallas abiertas", "Revisar datos",
  `HousekeepingNext`, `writeerror`, "Modo demostración": 0 hits.
- `sw.js` and `manifest.webmanifest`: byte-identical to the baseline output.
- `git diff --name-only develop..HEAD`: 11 files, all under `dashboard/src/`. Sensitive files changed: `app.routes.ts` and
  `ui-variant.next.ts` only. `ui-variant.ts`, `angular.json` and `app.config.ts` are not in the list; nothing under
  `features/`, `core/`, `shared/`, `public/`, `core-auth`, `ui-chat` or `ui-pdf-export`.
- `ng build dashboard --configuration=demo`: succeeds.

Scripted browser run (headless Chromium against the served demo build; a script, not a human review): 5 widths (390, 768,
1280, 1440, 1920) x light and dark x 3 scenarios (normal, empty, error) = 30 configurations. Per configuration it checks
horizontal overflow, interactive elements under 44x44 px, children outside the container, unlabelled controls, text contrast
(4.5:1, 3:1 for large text; computed from rendered colours, 90 text elements in the normal scenario) and page errors.
Result: 0 of 30 failed. Network: the only external requests were GETs for the page's two existing external stylesheet links
(aborted by the probe; pre-existing); no non-GET request left the browser. Screenshots of 390 light and 1440 dark (normal
scenario) were looked at; the other combinations were covered by the script only. In the 390 px full-page screenshot the
fixed bottom bar overlaps the list; this is an artifact of full-page capture (fixed elements), **not verified** on a real
scroll.

## 5. Rollback

No rollback file exists. Nothing is applied anywhere. Discard the local branch, or revert the branch commits after a merge.
The change is additive except the moved spread in `app.routes.ts`: reverting that single line restores the previous order
(the array is empty in production, so behaviour is the same either way). No data or infrastructure is involved.

## 6. Known gaps and risks, and follow-ups

- Not verified: screen reader, keyboard focus order, real devices, Safari/iOS, PWA update test, any real read or write,
  the format of `created_at` as returned by the real gateway (the code assumes an ISO instant with a zone; a value without a
  zone would be read in the device's zone, inferred), and the gateway-side role rules for tickets.
- **Precondition before enabling `next` for real users:** the page replaces the classic monitor at `/dashboard/mantenimiento`
  but cannot resolve tickets. Staff would lose the resolve flow until option B (or a hybrid) exists.
- The board's "Bloqueada" / "Con falla pendiente" states come from the rooms data and the open tickets; the Panel's tickets
  radar counts only `PENDING` rows, while the board also lists unknown statuses under "Revisar datos", so counts can differ
  by design.
- The type list of the classic report form was read by search only: six values were found (the six above); whether the form
  can store other values was **not verified**.
- Inherited behaviour observed and **not changed** (neutral wording):
  - the finish-maintenance flow writes the room as free and clean while its confirmation message says it was sent to cleaning;
  - it frees the room even when other open tickets exist for it (inferred from the code);
  - it skips the dirty state (the room is clean with no cleaning step);
  - two room-status write methods (`updateRoomMaintenance`, `finishMaintenance`) do not check for `error:true` in the answer;
  - tickets without an id (or without description and type) are hidden in the classic monitor;
  - the classic monitor and report form use `alert()`, `confirm()` and emoji;
  - tickets carry no reporter, resolver, assignment, photos or history; the cost field exists but is not shown in `next`;
  - the classic monitor shows the same ticket list as the board but with different grouping, so the two views can differ.
- A review of how the classic monitor scopes its ticket reads was carried out and is tracked privately.
- **Follow-up PR, option B (blocked on the owner's decisions 5 to 7):** resolve and report actions through the writes the
  classic app already uses, in the demo against an in-memory store (extending the Phase 2 store with the same validation
  approach), with confirmation or undo before any real use. Not started.
- **Proposal, not built: option C (new data).** Possible shape: assignment per ticket, cost, photos, an audit history with the
  acting user and times, and a ticket status model with more than two states; writes through the hotel's migration to the
  newer gateway. Prerequisites: a hotel test tenant, DEV copies of the workflows, `H###_` migrations with rollback,
  parameterized SQL tested with the real n8n node (values with quotes), unit and integration tests, and a runbook that opens
  with the "do not merge before parts 1 and 2" box. No file for this exists and nothing is scheduled.
- The Phase 1 and 2 follow-ups (CI builds for both configurations, the 5 failing specs, global es-MX locale, PWA update test,
  hotel test tenant) are unchanged.

## 7. Objects that exist in the live DB or n8n but not in the repo

None identified. This work reads and changes no database or n8n object; checked by inspecting the diff (frontend and styles
only). The live schema, the ticket model's allowed fields and the gateway's per-model role rules were not consulted.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and the DB schema docs

`ARCHITECTURE.md` and `CLAUDE.md` of the dashboard were read in full in this session; no database schema doc was read.
- `ARCHITECTURE.md` routes table lists `/dashboard/mantenimiento` as the classic "Maintenance monitor"; in the `demo` build it
  is now the read-only board (the classic page is replaced only there).
- `ARCHITECTURE.md` section 1 does not list `ui-variant`, `demo`, `next` and `theme-hotel`; section 5 says both environment
  configurations point to production (see also the Phase 1 record).
- `ARCHITECTURE.md` says the maintenance tickets are part of the room rack data; the board reads the full ticket list
  through `MaintenanceService`, which is accurate but not described there.
- `CLAUDE.md` build commands do not mention the `demo` configuration. Its "Known deviation (#1039)" list of `toISOString()`
  uses still includes the maintenance service and monitor; unchanged by this work (the board uses `Intl` parts for date keys).
- `README.md` ("Modo demo") and `CHANGELOG.md` ("Sin publicar") do not yet mention the Mantenimiento page (pending owner text).
