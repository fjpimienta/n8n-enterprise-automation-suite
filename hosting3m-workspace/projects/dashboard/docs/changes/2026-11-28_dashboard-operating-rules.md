# Change record: operating rules in the `next` UI (phase 3.1)

Date: 2026-11-28. Branch: `feat/dashboard-operating-rules` (local; not pushed, no PR). Base: the squash of #1178.

## 1. Goal and context

The hotel staff decided ten operating rules (R1 to R10). This phase applies them in the `next` UI only, which exists only in the `demo` build configuration; production and the default configuration render the classic UI. It adds the first write of the `next` maintenance board (resolve a fault) and puts every rule behind pure, tested functions. No database, n8n, gateway, classic UI, `core-auth`, money or fiscal file was changed.

## 2. What changed

All paths are under `hosting3m-workspace/projects/dashboard/`. Status of every item: **file only, not applied anywhere** (nothing was deployed or run against a live system).

### Frontend, new files
- `src/app/next/logic/permissions.ts`: role-to-actions table (`ROLE_ACTIONS`) and `can(role, action)`; fail-closed; adding a role is a data change.
- `src/app/next/logic/resolution.ts`: pure rules for resolving a fault (`planResolution`, `otherOpenFaults`, `buildResolveFields`).
- `src/app/next/maintenance/ticket-resolution.service.ts`: the only writes of the board (fresh read of one room's tickets, resolve a ticket, update a room); applies the Silent Error Shield.
- Specs: `permissions.spec.ts`, `resolution.spec.ts`, `ticket-resolution.service.spec.ts`, `home/home-next.component.spec.ts`.

### Frontend, changed files
- `next/logic/maintenance.ts`: "Antiguo" thresholds by priority (R8); deleted tickets are not shown; `resolvable` flag per item; board rule text.
- `next/logic/room-view.ts`: inactive rooms (`is_active` false) are dropped (R7).
- `next/logic/kpis.ts`: comment only (the occupancy rule is now an owner decision).
- `next/logic/housekeeping.ts`: one hint text ("Limpias o inspeccionadas" became "Limpias", R5).
- `next/maintenance/maintenance-next.component.{ts,html}` and `next/ui/maintenance-row.component.ts`: "Resolver falla" with a visible confirmation panel (disclosure button with `aria-expanded`/`aria-controls`, confirmation text, "Confirmar resolución" and "Cancelar"; focus moves to the confirm button, Escape or Cancelar closes it and returns focus), ADMIN only (R1, R2, R3), feedback banners that scroll into view after every result, retry of the room step after a partial failure (focus moves to "Reintentar"). The row has local styles (it no longer reuses the housekeeping button classes).
- `next/housekeeping/housekeeping-next.component.{ts,html}` and `next/ui/housekeeping-row.component.ts`: "Finalizar limpieza" only for ADMIN and EDITOR (R4); role checked again inside `finish()`; the result banner scrolls into view.
- `next/home/home-next.component.{ts,html}`: three classic shortcuts that would bypass the rules were re-routed inside `next` only (see section 6, found during implementation): "Mantenimiento abierto" now opens the `next` board instead of the classic monitor modal (the modal was removed from this template); the room detail's classic "Finalizar mantenimiento" writes nothing and goes to the board; the room detail's classic "Finalizar limpieza" is refused for roles without permission.
- Specs updated: `maintenance.spec.ts`, `logic.spec.ts`, `housekeeping.spec.ts`, `maintenance-next.component.spec.ts`, `housekeeping-next.component.spec.ts`, `demo-store.spec.ts`, `demo-mock.interceptor.spec.ts`.

### Demo data and scenarios (demo build only)
- `src/app/demo/demo-data.ts`: demo ticket 3 changed from NORMAL to CRITICAL (still one day old) so a critical ticket at exactly one day exists. No row added or removed.
- `src/app/demo/demo-store.ts`: in-memory store extended to two kinds of write only (room `status` set to `available` and/or `cleaning_status`; ticket update with exactly `status: RESOLVED` and `resolved_at`).
- `src/app/demo/demo-mock.interceptor.ts`: routes those two writes in the normal scenario only; filters tickets by room when asked; new demo user `viewer` with a role that has no action in `next`. Scenarios `empty`, `error` and `writeerror` still refuse every write.

### Database, n8n workflows, MCP tools, build configuration, environment files, PWA files
none changed. Untouched on purpose: classic UI, `sw.js`, the manifest, `core-auth`, `ui-chat`, `ui-pdf-export`, `angular.json`, environment files, money / IVA / ISH / CFDI code, `ARCHITECTURE.md`, `CLAUDE.md`, README, CHANGELOG, the classic `MaintenanceService` and `HotelService`.

### Outside the repo (private notes, not published)
One private note records what the live model configuration allows for the operations used here, compared with the UI rules. A review of that was carried out and is tracked privately.

## 3. Business rules decided (owner, 2026-11-28)

- R1: resolving the last open fault of a room sends it to cleaning: status available and cleaning dirty; the message says so.
- R2: other open faults keep the room as it is; the message says how many remain. A ticket with an unknown or missing status counts as open; deleted never counts.
- R3: only ADMIN resolves a fault; other roles see the board read-only with an explanation.
- R4: ADMIN and EDITOR mark a room clean; other roles see no action.
- R5: no "Inspeccionada" step; an inspected room is shown as clean/ready and never written.
- R6: nothing to do (no change).
- R7: the occupancy denominator is every active room, rooms in maintenance included; inactive rooms are excluded from the denominator and every room list.
- R8: "Antiguo" from 1 day for CRITICAL and from 3 days for any other priority; the threshold itself counts as old (age >= threshold), in whole Mexico City calendar days. The board states both thresholds.
- R9: nothing records who reported or resolved a fault; the UI writes only `status` and `resolved_at`, with `resolved_at` as an ISO instant exactly like the classic flow (`new Date().toISOString()`). No solution text in this phase.
- R10: repair cost is ADMIN only; `next` shows no cost and none was added (a test fails if a ticket view ever carries a cost field).
- Design decisions made while implementing, inside those rules: an occupied room is never freed or changed when its last fault is resolved; the ticket is written first and the room second (a failure between them offers a retry of the room step only); a ticket without id, without room or with an unknown status has no resolve action.
- **Open questions:** authorization for these actions on the server is out of scope for this phase and is tracked in the private notes; whether the classic UI should get the same rules; exact wording of the Spanish messages (staff review); whether a HOUSEKEEPING or MAINTENANCE role will be added (one row in the permissions table).

## 4. How to test

Never against real hotel data. Use the `demo` configuration (synthetic mock). Sign in as `admin`, `editor` or `viewer` (any value for the other fields); `?demo=empty|error|writeerror` selects a scenario.

Run: `ng test dashboard --watch=false`.
- Baseline before this phase: 26 files, 173 tests, **168 passed, 5 failed** (the known failures: four specs missing the auth configuration provider, plus one more).
- After: 30 files, 251 tests, **246 passed, 5 failed** (the same five; run twice, stable). 78 more tests than the baseline; no existing test was removed (some expectations were changed on purpose, listed below).

Spec expectations that changed on purpose: the old-threshold test of `maintenance.spec.ts` (3 days not old) replaced by the new thresholds; the counts test (old 1 became 2, because a NORMAL ticket at exactly 3 days is now old); the age coverage test of `demo-mock.interceptor.spec.ts` (now checks CRITICAL at 0 and 1 day, NORMAL at 3, LOW at 2); `demo-store.spec.ts` (a `status`-only room update is now accepted, so the refusal cases use other fields; the ticket-update refusal now covers more shapes); the board and housekeeping component specs now provide a fake session and a fake resolution service, and the "read-only" test runs as a role without permission.

Cases covered by tests (all pass): last fault; several faults; occupied room; room not in the list; unknown, null and deleted ticket status; ticket without id; CRITICAL at 0, 1 and 2 days and NORMAL/LOW at 2, 3 and 4 days; midnight in America/Mexico_City (23:59 versus 00:00, no `toISOString()` date keys; `toISOString()` is used only for the `resolved_at` timestamp, as in the classic flow); roles ADMIN, EDITOR, CUSTOMER, unknown, empty, null and prototype-like names; HTTP 200 with `error:true` on each call; `data:[{}]` (empty collection) read as unknown; numerics as strings; failed read, failed ticket write, failed room write with retry; double click while pending; an inactive room; an inspected room; ADMIN versus non-ADMIN menu is unchanged (existing tests). Values with quotes, commas, "null"/"undefined" text and leading zeros in room numbers: covered by the existing adapter tests and unchanged; no new free-text input exists. Cross-tenant attempts: **not applicable in demo**; **not verified** against the real gateway.

Demo data after the change (computed from the data, not by looking at a screen): open tickets 7, critical 3 (was 2), old 6 (was 4); rooms flagged by open tickets stay {5, 9}, so the Panel and Housekeeping figures do not change. Room 5 holds four open faults (resolve them one by one to see "still in maintenance" and then "sent to cleaning"); room 9 keeps a ticket without id, so it always keeps open faults.

**Defect found after the first version, and its fix.** The first version of this phase shipped with a defect that the unit tests could not see: in a browser at 600 px and wider, clicking "Resolver falla" appeared to only turn the button into "Cancelar". Evidence from a headless Chromium run: both "Confirmar resolución" and "Cancelar" were in the DOM with identical boxes (same position and size), and a hit test at the centre of either button returned "Cancelar". Root cause: the row reused the housekeeping class `h-hk__action`, whose desktop rule (`grid-column: 2; grid-row: 1 / span 2`, in the shared theme stylesheet) pins every such button to the same grid cell, so the later button covered the earlier one; focus also fell back to the page body. The component tests passed because jsdom does not compute layout. Fix: the row has its own local styles and a disclosure pattern; no shared stylesheet was changed. A second defect found while checking the flows in the browser: at 390 px the result banners (and "Reintentar") were above the viewport while the user was working lower in the list, so the row simply disappeared with no visible message; every result now scrolls its banner into view and focuses "Reintentar" when it appears (both boards).

Browser run (headless Chromium, the demo build served locally, widths 390 and 1280, screenshots kept in the private notes folder, not in the repository). Observed, per state:
- Admin, Mantenimiento: confirmation panel visible, three controls with distinct boxes, none covered (hit test); focus on "Confirmar resolución"; Tab goes to "Cancelar"; Escape closes the panel and focus returns to "Resolver falla"; Enter on the confirm button resolves.
- Resolve with other faults open (room 105 has four): messages "sigue en mantenimiento: quedan 3 / 2 / queda 1 falla(s) pendiente(s)"; the board count goes down; the room stays blocked.
- Resolve the last fault: "se envió a limpieza"; the room leaves the board; the Limpieza board then counts one more room to clean (2 became 3).
- `?demo=writeerror`: "No se pudo resolver la falla. Sigue pendiente; intenta de nuevo."; the fault stays. "Reintentar" does NOT appear here, by design: the ticket write fails first, so the room step is never reached.
- "Reintentar": reproduced by switching the scenario between the ticket write and the room write (the demo reads the scenario on every request): message "La falla quedó resuelta, pero no se pudo enviar la habitación 105 a limpieza. Usa «Reintentar»."; focus on the button; after the scenario is back to normal, "Reintentar" sends the room to cleaning and the button disappears.
- "Finalizar limpieza": admin and editor both see it and succeed ("Habitación 103 marcada como limpia."); viewer sees none.
- Mantenimiento as editor and as viewer: no "Resolver falla", and the explanation banner "Solo un administrador puede resolver fallas. Aquí puedes consultarlas."
- No horizontal overflow at either width, no console errors, in any state. At 390 px the sticky header can cover the top of a row when the page scrolls to the focused confirm button (seen once in the run); the controls remain reachable.

Parity proof (Visual-MVP policy, **followed**), repeated after the fixes: `ng build dashboard --configuration=production` before and after on the same base: `diff -r` of the two output folders is empty and the hash of all file hashes is identical (56295436...); `sw.js` and `manifest.webmanifest` are byte-identical. The leak search in the production output found 0 hits for the demo strings and the new Spanish strings; four generic words appear (a placeholder host from the local environment file, a number inside a PDF library, "viewer" in a PDF library, `resolved_at` in the classic monitor), all present in the build before the change. `ng build dashboard --configuration=demo` succeeds and contains the new strings. Files changed outside `src/app/next`, `src/app/demo` and this record: none.

SQL policy: no SQL was written or changed. All requests are fixed shapes built in code, with no string concatenation of caller values.

## 5. Rollback

Revert the commit(s) of this branch. The change is file only; nothing was applied anywhere, so there is no data to restore. Ticket and room rows written through the new flow (once it is used in a real configuration, which the demo-only build prevents today) would have to be corrected by hand; no automatic undo exists.

## 6. Known gaps and risks, and follow-ups

- **UI-only restrictions.** Roles are checked in the browser. This record makes no claim about server-side enforcement; the details, from the owner's redacted results, are in the private notes.
- **Classic shortcuts found during implementation.** The `next` home page reused three classic flows that free a room after any single resolution and have no role check. They were re-routed inside `next` only. The classic UI itself is unchanged, so the two UIs disagree until a later phase decides what the classic UI should do. My first inventory said `next` had no way to resolve a fault; that was incomplete (the classic modal was reachable from the home page).
- Two requests, no transaction: if the room write fails after the ticket was resolved, the ticket stays resolved and the UI offers a retry. A room can be left blocked until the retry or a manual fix.
- The decision uses a fresh read of the room's tickets; a fault added by another session in the instant between the read and the writes is not detected.
- The room list used to decide may be slightly stale (loaded just before); a check-in in the same instant is not detected. The UI never frees an occupied room it knows about.
- The Spanish messages and the new demo user are new strings for staff review.
- Not verified: behaviour against the real gateway (request shapes were copied from the classic flow); other browsers than Chromium (Safari and iOS in particular); a screen reader (keyboard behaviour and focus were checked in the browser, spoken output was not); a role other than ADMIN, EDITOR or CUSTOMER against the real login.
- Follow-ups: authorization for these actions on the server is out of scope for this phase and is tracked in the private notes; apply the rules to the classic UI or retire its shortcuts; fault reporting form in `next`; option C of the earlier phase (gateway migration plan); earlier items (public reviews, CI builds, the five failing specs) unchanged.

## 7. Objects that exist in the live DB or n8n but not in the repo

Checked by reading the owner's redacted live results and searching the repo. The model configuration rows of the hotel tables and the table definitions are **live only** (the repo has no definition of them), as recorded in the previous record. This phase relies on the ticket columns `status` and `resolved_at` and on the room columns `status`, `cleaning_status` and `is_active`; their existence and the gateway acceptance were confirmed by the owner and by the redacted results, not by me against a live system. A live-only database function that writes to hotel tables (recorded earlier) was not touched.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and the DB schema docs

`ARCHITECTURE.md` and the dashboard `CLAUDE.md` were read in full in this session (the copies supplied to the session); the schema docs were not read in this phase.
- `ARCHITECTURE.md` and `CLAUDE.md` do not describe the `next` UI, its permissions table, or the new board write (they still describe only the classic structure).
- The dashboard `CLAUDE.md` lists the known `toISOString()` deviations (#1039) for ticket timestamps; the new `resolved_at` write uses the same full-timestamp format as the classic flow and is not listed there.
- `ARCHITECTURE.md` says maintenance tickets belong to the "Room rack / operations" flow through `MaintenanceService`; the `next` board now writes through its own service, which is not listed.
- The root `CLAUDE.md` describes the booking-date convention and the old room-freeing behaviour only for the classic flows; the rule "free a room only after its last fault" now exists in `next` but not in the classic UI.
