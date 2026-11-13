# 🏛️ CLAUDE.md - AdminHotel Dashboard

## Scope of This File
This file only covers what's specific to `dashboard` or adds to the suite root
`CLAUDE.md`. Suite-wide rules (production safety, multi-tenant isolation, the Meta-CRUD
error pattern, secrets handling, Conventional Commits) live in the root `CLAUDE.md` and
already apply here — don't assume they're off just because they're not repeated below.

Architecture overview, tech stack, and data-flow diagram: @ARCHITECTURE.md

## Guardrails Specific to Dashboard

- **Timezone Armor:** NEVER use native `toISOString()` for checkin/checkout date
  calculations. Always use local time evaluators (`getFullYear()`, `getMonth()`, etc.) —
  operations run on UTC-6 (CDMX/Mérida), and `toISOString()` silently skips a day after
  18:00 hrs local time. This already caused a real bug (see CHANGELOG v0.11.0).
  - **Known deviation (#1039):** `toISOString()` is still used in 16 places under `src/`.
    Date-only keys (`toISOString().split('T')[0]`, UTC day):
    [expense-form-modal.component.ts](src/app/features/finance/components/expense-form-modal/expense-form-modal.component.ts) L36, L135;
    [data-utils.service.ts](src/app/shared/services/data-utils.service.ts) L9, L18;
    [hotel.service.ts](src/app/features/dashboard/services/hotel.service.ts) L92, L119, L142;
    [checkin-form.component.ts](src/app/features/booking/components/checkin-form/checkin-form.component.ts) L137.
    Full timestamps (`check_in`/`check_out`, `created_at`, `now`):
    [booking.service.ts](src/app/features/booking/services/booking.service.ts) L338, L354, L392, L450;
    [maintenance.service.ts](src/app/features/dashboard/services/maintenance.service.ts) L70;
    [dashboard.component.ts](src/app/features/dashboard/components/dashboard/dashboard.component.ts) L497, L505;
    [maintenance-monitor-modal.component.ts](src/app/features/dashboard/components/maintenance-monitor-modal/maintenance-monitor-modal.component.ts) L123.
    The rule above is unchanged; the code does not yet follow it.
- **MetaCRUD Silent Error Shield — implementation location:** `BookingService`
  intercepts `HTTP 200 OK` responses carrying `error: true` and throws them as real
  exceptions at the UI boundary. The pattern itself is suite-wide (root `CLAUDE.md`); this
  is where it's actually implemented in this app.
  - **Known deviation (#1039):** the `error` flag is checked only in `processCheckin`
    ([booking.service.ts](src/app/features/booking/services/booking.service.ts) L348, L380, L404, L418)
    and `processCheckout` (L460, L494). Not checked: `createFutureReservation` (booking insert
    L619–636 is awaited and ignored; the guest insert L610 is only read to pick an ID, so a failed
    guest insert fails indirectly at L617), `updateCleaningStatus` (L504), `updateReservation`
    (L666), `registerPayment` (L712), `cancelReservation` (L763) and `confirmPendingReservation`
    (L783). On those paths an HTTP 200 with `error: true` resolves as success.

## Verified Pitfalls (pulled forward from CHANGELOG.md — don't repeat these)

- **Payload root-level ID (v0.11.0):** the update ID for `INSERT`/`UPDATE` requests must
  sit at the **root** of the REST payload, not nested inside a sub-object. Nesting it
  caused schema collisions and HTTP 500s that surfaced as CORS errors in the browser,
  which is misleading — the real cause was payload shape, not CORS config.
- **Walk-in Decoupling (v0.11.0):** if a room has a future reservation (e.g. in 3 days),
  the system must let staff check in a walk-in guest **today** without overwriting the
  future reservation's ID. This broke once in `room-detail-modal` — the walk-in flow and
  the future-reservation flow must stay decoupled.

## Known Debt (reported, not fixed here)

- 🔴 **`UserListComponent` role gating (state checked 2026-11-13).**
  - The "Manage Users" button described earlier does not exist. `room-filters.component.html`
    has no such control, and `RoomFiltersComponent.onManageUsers`
    ([room-filters.component.ts](src/app/features/dashboard/components/room-filters/room-filters.component.ts))
    is never emitted. Its only binding is `dashboard.component.html` → `openUserManagement()`,
    so the `viewMode === 'user_mgmt'` branch is unreachable from the UI.
  - The reachable entry point is `/dashboard/personal`
    ([app.routes.ts](src/app/app.routes.ts) L27), which has `roleGuard(['ADMIN'])` on top of the
    parent `authGuard`. `UserListComponent` itself has no role check and calls
    `adminService.loadUsers()` on init. The route guard runs in the browser; it does not restrict
    the API.
  - Data layer: `v5/CRUD` builds its SELECT as `${table}.*` with no column projection
    ([v5-crud.json](../../../workflows/06-dynamic-crud-engine/v5/v5-crud.json)), so any model the
    gateway serves returns every column, including the password hash. The suite-level note says
    `users` is blocked in `v5` since v1.17.1; the live `crud_models` state is TODO(verify).
  - Still open: a server-side role and tenant gate for `users` must come with the `v6/CRUD`
    migration. The route guard alone does not close the gateway path. Closing the gateway path
    needs a server-side role restriction, not a `crud_models` change: `users`' `allowed_roles_select`
    already includes roles below ADMIN for other legitimate reasons. The `roleGuard(['ADMIN'])` on
    `/dashboard/personal` is client-side and already in place. Not fixed here; this note only
    records the state.
  - Tenant on the list call: `loadUsers(id_company?: number)`
    ([admin.service.ts](src/app/features/admin/services/admin.service.ts) L115–123) sends
    `filter: { id_company }`. `UserListComponent` calls it with no argument
    ([user-list.component.ts](src/app/features/admin/components/user-list/user-list.component.ts) L23, L61);
    `id_company` is then `undefined`, which `JSON.stringify` drops, so the body sends `filter: {}`.
    There is no fallback to the active tenant in this service. `DashboardComponent` L371 passes
    `activeTenantId()` cast to `number`; that value is `_activeTenant()?.id_company || null`
    ([tenant.service.ts](../core-auth/src/lib/services/tenant.service.ts) L22), so it can send
    `id_company: null`. `v5` takes its scope from the token's `id_company` (`Extract Auth Context`,
    rejects a missing one with `NO_TENANT`). How the body `filter` is combined with that scope, and
    whether `users` is served at all, are TODO(verify) against the live gateway.

## Build & Development Commands
Always use these exact scripts:
- **Install dependencies:** `npm install`
- **Build core libraries (prerequisite, in this order):** `ng build ui-pdf-export && ng build ui-chat`
- **Run local dev server:** `ng serve dashboard`
- **Production build:** `ng build dashboard --configuration=production`

## Code Style — Patterns Specific to This App
- **Computed Reactivity:** totals/balances (e.g. in `ReportService`) are never calculated
  in templates — use `readonly total = computed(() => ...)`.
- **Async Critical Path:** `Room Rack (Grid)` renders first; defer secondary lookups
  (Reservations, Users, Guests) to protect Time-to-Interactive.
- **Polymorphic UI:** form modals like `AssetFormModal` detect contextual scope to switch
  between Global (Warehouse) and Local (Room assignment) logic — don't fork them into
  separate components.
