# Change record: dashboard housekeeping board ("Limpieza", `next` UI, demo build only)

Date: 2026-11-27. Branch: `feat/dashboard-housekeeping` (local, from `develop` at the Phase 1 squash commit; not pushed, no PR).

## 1. Goal and context

First ERP module on top of the Phase 1 `next` UI (see `2026-11-27_dashboard-erp-mvp-ui.md`): a Housekeeping board that
ranks rooms by cleaning priority and lets staff mark a free, dirty room as clean. It exists only in the `demo` build
configuration, verified locally with the synthetic mock. The classic UI and the production configuration are unchanged.
Scope approved by the owner: a read-only board plus one minimal action (in memory in the demo only). New data (staff
assignment, checklists, timestamps, audit) is a written proposal only (section 6).

## 2. What changed

Status of every item: **file only, not applied** (nothing deployed; local branch). Verified locally with the `demo`
configuration (section 4).

### Frontend, new files (`hosting3m-workspace/projects/dashboard/src/`)
- `app/next/logic/housekeeping.ts` (+ spec): pure rules. Priority groups, the one allowed transition, counters.
- `app/next/housekeeping/housekeeping-next.component.{ts,html}` (+ spec): the "Limpieza" page.
- `app/next/ui/housekeeping-row.component.ts`: presentational row (chips, note, "Finalizar limpieza" button).
- `app/demo/demo-store.ts` (+ spec): in-memory demo store for the single permitted write.

### Frontend, existing files modified
- `app/demo/demo-mock.interceptor.ts` (+ spec): accepts the cleaning update through the store; new scenario
  `?demo=writeerror` (reads normal, every write answers HTTP 200 with `error: true`). All other writes still refused.
- `app/demo/demo-data.ts`: two extra synthetic bookings (a same-day turnover in a room that leaves today, and a dirty
  room with an arrival today). The demo arrivals KPI on the Panel changes from 2 to 3; no other Phase 1 figure changes.
- `app/next/logic/nav.ts` (+ spec): "Limpieza" menu entry and page title (visible to every role, like the classic page).
- `app/ui-variant/ui-variant.ts`: new export `uiChildRoutes: Routes = []` (classic: empty).
- `app/ui-variant/ui-variant.next.ts`: `uiChildRoutes` with the `limpieza` route (demo only).
- `app/app.routes.ts`: `...uiChildRoutes` spread at the end of the `dashboard` children (empty array in production).
- `theme-hotel/theme-hotel.scss`: `.h-hk*` styles (included only by the `demo` configuration).

### Database, n8n workflows and gateways
none. No migration, SQL, workflow, gateway or MCP tool was added or changed.

### Infra / config
none. `angular.json`, `app.config.ts`, `sw.js`, `manifest.webmanifest`, `index.html` and environment files are unchanged.

### Left untouched on purpose
Classic components, services, guards, routes and styles (nothing under `features/`, `core/`, `shared/`); `core-auth`,
`ui-chat`, `ui-pdf-export`; `public/`; `ARCHITECTURE.md`, `CLAUDE.md`; money, IVA, ISH and CFDI logic.
`ARCHITECTURE.md` and `CLAUDE.md` were not edited.

### Documentation (Spanish, existing style; text approved by the owner)
- `README.md`: "Modo demo" section now mentions `/dashboard/limpieza`, the `?demo=writeerror` scenario and the single
  in-memory write. `CHANGELOG.md`: one bullet under "Sin publicar" (no version bump). Status: file only, not applied.

### Data-write policy of this task
- **No real write path was added or touched.** The page calls the existing classic method
  `BookingService.updateCleaningStatus(roomId, 'clean')` unchanged (it already applies the Silent Error Shield). No new
  endpoint, payload shape or model is introduced.
- Demo isolation: in the `demo` build every request is answered by the mock, which never forwards one. The only accepted
  write is `hotel_rooms` / `update` whose `fields` hold exactly `cleaning_status`, set to `clean`, `dirty` or `inspected`,
  on a synthetic room id. It lives in module memory and disappears on reload. No `localStorage`, `sessionStorage`,
  `IndexedDB` or service-worker cache is used by it (unit-tested and observed, section 4).
- No real hotel data was read or written during this work; there is no hotel test tenant.

## 3. Business rules decided (owner, 2026-11-27)

- Priority order: (1) same-day turnover (occupied, leaves today, a booking arrives today); (2) dirty and arriving today;
  (3) other dirty rooms; (4) departures today still occupied (upcoming, not actionable); (5) ready; (6) blocked by
  maintenance. Ties use natural room-number order for text numbers ("007" before "10"), then id. Documented in
  `housekeeping.ts` and tested.
- Transition: only free (`available`) and dirty becomes clean, enforced in the logic layer; the UI only offers the button
  when it holds, and the page re-checks before calling. "inspected" is never written. No "in progress" state in this MVP.
- "Ready" means clean or inspected (same predicate as the rack's "Disponibles").
- Who may mark a room clean: same as the classic app (any authenticated role; only ADMIN and EDITOR exist).
- Stay-overs (occupied, clean, not leaving today): only a count ("En estancia"), no list.
- Occupied and dirty rooms: shown with a "Revisar datos" marker and no action button. **Interpretation to confirm:** such a
  room is listed in "Salidas de hoy" (with the marker) if it leaves today, otherwise in a final "Revisar datos" group.
  Unknown status or cleaning values go to the same final group.
- Rooms in maintenance: shown as blocked, no action.
- The rondín (`hotel_room_inspections`) is out of this MVP.
- Spanish naming: page "Limpieza", button "Finalizar limpieza".
- Without reservation data (an empty list cannot be told apart from a failed load) the counts that depend on arrivals,
  departures and stays show "—" and the page warns; unknown data shows "—", never 0.

Decided after review (owner, 2026-11-27): the "Revisar datos" placement above is accepted as built; the one-tap action
stays as is in the demo; "Limpieza" stays under "Más" in the mobile bar (follow-up below).

Open: a housekeeping role (future, option C).

## 4. How to test

LOCAL only, never against real hotel data. `npx ng serve dashboard --configuration=demo`, sign in with user `admin`
(ADMIN) or `editor` (non-ADMIN), open "Limpieza". A plain `ng serve` points to production endpoints: do not use it.
Scenarios by URL: `?demo=empty`, `?demo=error`, `?demo=writeerror`.

| Case | Expected | Result |
|---|---|---|
| Normal data (18 rooms) | Urgentes 1, Por limpiar 2, Salidas por liberar 3, Listas 8, En estancia 4; groups in priority order | Observed (scripted browser run) |
| "Finalizar limpieza" on room 103 | Success message; list and counters refresh from the reloaded data (Por limpiar 2 to 1, Listas 8 to 9) | Observed |
| Reload after that action | Back to the seed state (no persistence) | Observed |
| `?demo=writeerror`, click the action | Error message, counters and buttons unchanged, button enabled again | Observed; unit tested |
| No optimistic update | The list changes only after the service reloads; a fake service that never reloads leaves it unchanged | Unit tested |
| Double activation while pending | One call only; button disabled and "Guardando…" | Unit tested |
| Occupied dirty / maintenance / ready room | No action offered; programmatic call refused without calling the service | Unit tested |
| `?demo=empty` (collections as `data:[{}]`) | No crash; empty state; every KPI "—" | Observed (all 5 widths x 2 themes) |
| `?demo=error` (HTTP 200 with `error:true`) | Same as above | Observed |
| Numerics as strings; room numbers "007", "10", "9", "7"/"007" tie | Parsed explicitly; text order 007, 9, 10; tie by id | Unit tested |
| Cleaning values "null"/"undefined" as text, empty, unknown | Group "Revisar datos", no action | Unit tested |
| Dates around midnight (America/Mexico_City) | The board takes arrival/departure flags from the existing rack data (calendar day from the date text); the header date uses the local calendar fields through the existing formatter; no `toISOString()` for date keys | Header formatter reused from Phase 1 (unit tested there); flags inherited, not re-tested here |
| Demo store accepts only `cleaning_status`; refuses other fields, other values, unknown or invalid ids, other operations, other models, and every write in `empty`/`error`/`writeerror` | Refused, state unchanged | Unit tested (22 tests) |
| ADMIN vs non-ADMIN menu | "Limpieza" visible to both; ADMIN-only entries unchanged | Unit tested; admin observed in the browser run |
| Mobile: "Limpieza" reachable | Through the "Más" menu | Observed at 390 px |
| Quotes, commas or very long text in inputs | Not applicable (the page has no text input) | Not applicable |
| Cross-tenant attempts | Not applicable in demo (synthetic data only) | Not applicable |
| Real write (classic app, real gateway) | Not exercised | **Not verified** |

Unit and component tests: `npx ng test dashboard --watch=false`. Baseline on `develop` before any change: 69 tests,
64 pass, 5 fail. After: 132 tests, 127 pass, the same 5 fail (4 spec files; the test setup lacks the auth environment
configuration provider; pre-existing, not touched). 63 tests are new and all pass (logic 29, demo store and mock 22,
board component 12); one existing nav spec was updated for the new entry.

Build and parity checks (baseline built from a detached worktree of `develop`; the branch from a detached worktree of
the branch head with an identical layout; the environment file was copied into both):
- `ng build dashboard --configuration=production`: succeeds, 15 files in `browser/` for both. File names and sizes are
  identical except `main`: 1,065,311 to 1,065,323 bytes (+12), new hash. Angular's initial transfer estimate: 279.32 to
  279.48 kB.
- Unoptimised parity build (same CLI flags as Phase 1: development configuration, no optimisation, no hashing, no source
  maps). After normalising the worktree path, the whole difference in `main.js` is 4 lines: `var uiChildRoutes = [];` and
  `...uiChildRoutes` in the dashboard children. No `next`, demo, mock or housekeeping code is in the production output.
- Leak search of the production output for `housekeeping`, `demo-store`, `demoMock`, `withCleaningOverrides`,
  `applyRoomUpdate`, `theme-hotel`, `uiChildRoutes`, `HousekeepingNext`, `writeerror`, "Modo demostración": no hits. Two
  looser terms hit the **baseline too** ("Finalizar Limpieza" in the classic room dialog, and an unrelated `h-hk`
  substring), with the same count in both builds, so they are not new.
- `sw.js` and `manifest.webmanifest`: byte-identical to the baseline output and to the sources.
- `git diff --name-only develop..HEAD`: 17 files, all under `dashboard/src/`. Sensitive files changed: `app.routes.ts`,
  `ui-variant.ts` and `ui-variant.next.ts` only (as approved). `angular.json` and `app.config.ts` are not in the list;
  nothing under `features/`, `core/`, `shared/`, `public/`, `core-auth`, `ui-chat` or `ui-pdf-export`.
- `ng build dashboard --configuration=demo`: succeeds.

Scripted browser run (headless Chromium against the served demo build; this is a script, not a human review): 5 widths
(390, 768, 1280, 1440, 1920) x light and dark x 4 scenarios = 40 configurations. Per configuration it checks horizontal
overflow, interactive elements under 44x44 px, rows or children outside their container, unlabelled controls, text
contrast (4.5:1, 3:1 for large text; computed from rendered colours, 85 text elements per normal page), and page errors.
Result: 0 of 40 failed. Network: the demo made no request to any API host; the probe aborted the page's two existing
external stylesheet links (not pinned, pre-existing) and no non-GET request reached the server. Screenshots of 390 light
and 1440 dark (normal scenario) were looked at; other combinations were covered by the script only. One visual defect
found and fixed during this run (title-cased date line).

## 5. Rollback

No rollback file exists. Nothing is applied anywhere. Discard the local branch, or revert the branch commits after a
merge. The change is additive: removing `uiChildRoutes` (3 files), the new folders and the demo store restores the
previous state. No data or infrastructure is involved.

## 6. Known gaps and risks, and proposal for new data

- Not verified: screen reader, keyboard focus order, real devices, Safari/iOS, PWA update test, and any real write.
- Enabling `next` in production remains a separate decision. At that point the cleaning action becomes a real write from
  a new screen: a confirmation step or undo should be considered (one-tap button on phones). Gateway-side rules for who may
  perform it were not checked (tracked privately).
- Cleaning changes carry no timestamp and no actor (existing behavior, not changed).
- Inherited behavior observed and **not changed** (neutral wording):
  - the maintenance-finish flow writes the room as clean while its confirmation message says it was sent to cleaning;
  - `HotelService.updateRoomStatus` (and `DashboardComponent.markAsClean`) look unused (no template binding found, by
    search) and differ from the used path: other payload keys and no error-flag check;
  - `inspected` exists in the type and in the rack's "available" predicate, but no UI path writes it;
  - `loadRooms` returns without clearing its loading flag when there is no stored session, and an empty answer cannot be
    told apart from a failed one (the board shows "Sin datos de habitaciones" in both cases);
  - `loadReservations` shows a browser alert after its retries;
  - stored arrival and departure dates are midnight UTC, so no arrival or departure time is available for ordering.
- The classic room dialog emits the room id from an output typed without a payload (harmless; not changed).
- **Follow-ups before enabling `next` for real users** (none is started):
  1. a confirmation step or a short "Deshacer" for "Finalizar limpieza" (one-tap action on phones);
  2. verify the gateway-side role rules for `hotel_rooms` updates (not checked in this task);
  3. create a hotel test tenant, so the real write path can be exercised without real hotel data;
  4. run the PWA update test (not performed in Phase 1 or here).
- Follow-up: mobile bottom bar. "Limpieza" is reachable only through "Más"; whether it deserves a bar slot is undecided.
- The Phase 1 follow-ups (CI builds for both configurations, fixing the 5 failing specs, global es-MX locale) are unchanged.

**Proposal, not built: option C (new data).** Possible shape: a cleaning log (company, room, previous and new status,
acting user, start and finish times), staff assignment per room and day, reuse of the existing rondín checklist, and a
housekeeping role; writes through the hotel's migration to the newer gateway. Prerequisites: a hotel test tenant, DEV
copies of the workflows, `H###_` migrations with rollback, parameterized SQL tested with the real n8n node (values with
quotes), unit and integration tests, and a runbook that opens with the "do not merge before parts 1 and 2" box. No file
for this exists and nothing is scheduled.

## 7. Objects that exist in the live DB or n8n but not in the repo

None identified. This work reads and changes no database or n8n object; checked by inspecting the diff (frontend and
styles only). The live schema and the gateway's per-model role rules were not consulted.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and the DB schema docs

- `README.md` ("Modo demo") and `CHANGELOG.md` ("Sin publicar") were updated for this module; nothing else in them conflicts.
- `ARCHITECTURE.md` section 1 does not list `ui-variant`, `demo`, `next` and `theme-hotel`, and its routes table does not
  mention `/dashboard/limpieza` (demo build only). Section 5 says both environment configurations point to production;
  see also the Phase 1 record.
- `CLAUDE.md` build commands do not mention the `demo` configuration.
- Its "Verified Pitfalls" and Silent Error Shield notes list `updateCleaningStatus` as throwing on `error: true`; that
  matches the code read in this session. No mismatch found there.
- No database schema doc was read for this task.
