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
- **MetaCRUD Silent Error Shield — implementation location:** `BookingService`
  intercepts `HTTP 200 OK` responses carrying `error: true` and throws them as real
  exceptions at the UI boundary. The pattern itself is suite-wide (root `CLAUDE.md`); this
  is where it's actually implemented in this app.

## Verified Pitfalls (pulled forward from CHANGELOG.md — don't repeat these)

- **Payload root-level ID (v0.11.0):** the update ID for `INSERT`/`UPDATE` requests must
  sit at the **root** of the REST payload, not nested inside a sub-object. Nesting it
  caused schema collisions and HTTP 500s that surfaced as CORS errors in the browser,
  which is misleading — the real cause was payload shape, not CORS config.
- **Walk-in Decoupling (v0.11.0):** if a room has a future reservation (e.g. in 3 days),
  the system must let staff check in a walk-in guest **today** without overwriting the
  future reservation's ID. This broke once in `room-detail-modal` — the walk-in flow and
  the future-reservation flow must stay decoupled.

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
