# Change record: dashboard ERP visual MVP (`next` UI, demo build only)

Date: 2026-11-27. Branch: `feat/dashboard-erp-mvp-ui` (local, from `develop`; not pushed, no PR).

## 1. Goal and context

Start evolving the hotel dashboard into a modern, professional hotel ERP interface that can later be
showcased. This task is visual only: a new presentation layer ("`next`") for the operations panel, shell,
login and company selector. The new UI is built and runnable **only** with a new `demo` build
configuration backed by a mock that returns synthetic data. The default and production configurations keep
the existing ("classic") UI. No backend, workflow, database, money, tax or tenant logic was touched.

## 2. What changed

Status of every item below: **file only, not applied** (nothing was deployed; the work exists on a local
branch). Verification was done locally with the `demo` configuration (see section 4).

### Frontend (new files, `hosting3m-workspace/projects/dashboard/src/`)
- `app/ui-variant/ui-variant.ts`: build-time seam (classic). Re-exports the existing login, home and layout
  components; exposes no extra interceptors or providers.
- `app/ui-variant/ui-variant.next.ts`: replaces the file above only in the `demo` configuration. Exports the
  `next` components, registers the mock interceptor and adds the `theme-hotel` body class at startup.
- `app/demo/demo-data.ts`, `app/demo/demo-mock.interceptor.ts` (+ spec): synthetic data (18 rooms: 5 Sencilla,
  4 King, 8 Doble, 1 Triple; guests as initials; synthetic tenant ids) and an HTTP interceptor that answers every
  request and never forwards one. Optional scenarios by URL (`?demo=empty`, `?demo=error`).
- `environments/environment.demo.ts`: placeholder endpoints only.
- `theme-hotel/theme-hotel.scss` and `theme-hotel/fonts/*`: tokens (light and dark), shared styles scoped under
  `body.theme-hotel`; self-hosted Inter (400-600) and Space Grotesk (500-700), latin and latin-ext subsets, with
  both SIL OFL 1.1 license texts.
- `app/shared/ui/h-icon/h-icon.component.ts`: inline SVG icon set (decorative icons, text labels alongside).
- `app/next/logic/*` (+ spec): pure helpers: room view adapter, status labels, es-MX date formatting, KPI
  computation, "today" lists, navigation model.
- `app/next/ui/*` (+ spec): presentational components (KPI card, status chip, compact room card, filter bar,
  Today panel, maintenance panel, sidebar, bottom navigation, expense button).
- `app/next/shell/*`, `app/next/home/*`, `app/next/login/*`: `next` layout, operations panel and login. The
  home and login components extend the existing classic classes, so every existing handler (check-in,
  check-out, walk-in, extend stay, report failure, round, expense) is reused unchanged.

### Frontend (existing files modified)
- `app/app.routes.ts`: the three page components are now imported through the seam (same classes in classic).
- `app/app.config.ts`: interceptor and provider lists are spread from the seam (empty in classic).

### Documentation (Spanish, existing style)
- `README.md`: new "Modo demo" section. `CHANGELOG.md`: new "Sin publicar" heading (no version bump) with the
  approved text. Status: file only, not applied.

### Infra / config
- `hosting3m-workspace/angular.json`: added a `demo` configuration to the dashboard `build` and `serve`
  targets (file replacements, extra styles and font assets). `production` and `development` are unchanged.

### Left untouched on purpose
Backend, n8n workflows and gateways, database and migrations (none); `sw.js`; `manifest.webmanifest`
(`start_url` kept; the file has no `id` field); `index.html`; `core-auth`, `ui-chat`, `ui-pdf-export`;
interceptors, guards, routes and roles; every existing service; `ARCHITECTURE.md`, `CLAUDE.md`; classic
templates and styles; money, IVA, ISH and CFDI logic.

MVP content actually delivered: KPI strip (occupancy, arrivals today, departures today, rooms to clean, rooms
with an open maintenance report), compact Room Rack with counters, Today panel, maintenance panel (room numbers
only), shell with grouped sidebar and mobile bottom navigation, floating buttons repositioned, login and
company selector refresh, Spanish status labels and es-MX dates inside the new components.
**Not delivered by decision:** cash-of-the-day card (needs a new request and money calculation).

## 3. Business rules decided

- Occupancy % uses all rooms as the denominator and is shown as "X de N habitaciones". The rule lives in one
  function. Whether rooms in maintenance should be excluded is **still open**.
- A KPI whose data is missing or whose response carried `error: true` shows "—" (unknown), never 0.
- No global locale: es-MX formatting applies only inside the new components. Registering it globally is a
  follow-up (it would change what current users see).
- The `next` UI is off in production: the production configuration keeps the classic seam. Enabling it for
  real users needs a separate, explicit decision.
- Cash card dropped from the MVP; the maintenance panel lists room numbers only.
- Sidebar roles, classic versus `next`: the classic menu lists Personal and Inventario to every role (only the
  route guard stops non-ADMIN users); the `next` menu hides Personal, Inventario and Caja y gastos from
  non-ADMIN users. Hiding menu entries is presentation only and is **not** access control: the route guards
  are unchanged and remain the client-side control, and they do not restrict the API.
- Fonts path decision: the self-hosted fonts live in `src/theme-hotel/fonts`, not `public/assets/fonts`,
  because everything under `public/` is copied to the production output and the production build must stay
  identical. Only the `demo` configuration copies them. Moving them to a published path is part of the future
  decision to enable `next` in production.
- Floating buttons (`next`): on tablet and desktop both sit on the right, stacked, so neither covers the menu
  or the end of lists; on mobile the expense action is the central "+" of the bottom navigation and the chat
  button sits above it. The chat position is overridden with CSS scoped under `theme-hotel` (no change to the
  shared chat library).

## 4. How to test

LOCAL only, never against real hotel data. There is no hotel test tenant yet.
`npx ng serve dashboard --configuration=demo --port 4300`, then sign in with any password and user `admin`
(ADMIN), `editor` (non-ADMIN) or `multi` (company selector step).

| Case | Expected | Result |
|---|---|---|
| Demo build starts with no outbound API call | Only static stylesheets from the page's existing public links load; no API host contacted | Observed (browser request log, 8 sessions) |
| Rack with the synthetic data | 18 rooms, KPIs 39% (7 de 18), 2 arrivals, 3 departures, 2 to clean, 2 with report | Observed |
| `?demo=empty` (collections as `data:[{}]`) | No crash; KPIs "—"; filter counters "—"; empty message | Observed |
| `?demo=error` (HTTP 200 with `error:true`) | KPIs "—", panels "Sin datos", no crash | Observed |
| Numerics as strings; room numbers with leading zeros | Parsed explicitly; "007" stays "007" | Unit tests |
| Values "null" / "undefined" as text, missing dates | Date shows "—" | Unit tests |
| Dates around midnight (America/Mexico_City) | Day taken from the date text or local calendar fields; never `toISOString()` | Unit tests (23:30 and 00:05 local) |
| ADMIN vs non-ADMIN menu | Non-ADMIN sees 4 entries; ADMIN sees 7 | Observed in demo; unit tested |
| Non-ADMIN opens the finance route directly | Redirected to the unauthorized page (existing guard) | Observed |
| Open a room, open the expense dialog from the floating button | Existing dialogs open | Observed (opening only; demo rejects writes with `error:true`) |
| Search and filters with quotes, commas or very long text | Not exercised | **Not verified** |
| Cross-tenant attempts | Not applicable in demo (no tenant data is read or written) | Not applicable |
| Real check-in/out, payments, expense save | The demo mock refuses writes by design | **Not verified** (classic flows were not modified) |

Unit and component tests: `npx ng test dashboard --watch=false`. Result on this branch: 67 tests, 62 pass,
5 fail. The same 5 fail on `develop` before any change (4 spec files, a missing test provider); 39 tests are new
and all pass.

Build checks:
- `npx ng build dashboard --configuration=production`: succeeds. Same 17 output files as `develop`; only the main
  bundle differs (1,065,283 to 1,065,311 bytes, new hash).
- Parity proof for that difference (later review). Both `develop` and this branch were built from detached
  git worktrees with an identical layout, CLI flags only: `--configuration=development --optimization=false
  --output-hashing=none --source-map=false`. The `production` configuration could not be used for this
  comparison because, unoptimised, it exceeds its own 2 MB initial-size budget and writes no output; the
  `development` configuration differs from `production` only in budgets, hashing and optimization, which the
  flags neutralise (inferred from `angular.json`). Result: 16 files each; only `main.js` differs (3,088,957
  versus 3,089,105 bytes). After normalising the worktree directory name that Angular embeds in two
  component-style comments, the whole remaining difference is: (a) the new seam module (two empty
  arrays, `uiHttpInterceptors` and `uiProviders`) and (b) in the application config, the interceptor list and
  the provider list now spread those arrays. No other code differs: no `next`, demo or font code is present.
  The earlier "minifier renames" explanation was only a guess and is withdrawn; in the optimised build the
  identifier shuffle is a consequence of those few added lines (inferred, not separately proven).
  A first attempt that built `develop` from a worktree but the branch from the main checkout differed in
  source-path comments and chunk names; that was a build-layout artefact, not a code difference.
- Search of the production output for demo and `next` identifiers, fonts, and demo strings: no hits.
- Demo token: the demo session token is assembled at runtime in the mock (the app decodes it, so it needs a
  JWT shape); no JWT-shaped literal exists in the changed files (pattern search, no hits). A secret scanner
  (gitleaks) is not installed on this machine, so it was **not run**.
- `sw.js` and `manifest.webmanifest`: byte-identical to the sources and unchanged versus `develop`.
- `git diff develop` shows no change under `core-auth`, `ui-chat`, `ui-pdf-export`, `public/`, `index.html` or
  any existing file in `core`, `features` and `shared` (one new file was added under `shared`).
- `npx ng build dashboard --configuration=demo`: succeeds.

Visual and accessibility checks (headless Chromium, demo): 1440x900 and 390x844, light and dark; no horizontal
overflow at either width; no interactive element under 44x44 px on the home route; color pairs of the
tokens computed against 4.5:1 (all pass after one fix to the dark-mode sidebar active color). Not done:
screen reader pass, manual keyboard focus-order review, real devices, Safari/iOS.

## 5. Rollback

No rollback file exists. Nothing is applied anywhere, so rollback is discarding the local branch (or reverting
the branch's commits after merge). The change is additive: removing the `demo` configuration, the `ui-variant`
seam and the new folders restores the previous state; no data or infrastructure is involved.

## 6. Known gaps and risks

- PWA update test **not performed**. `sw.js` and the manifest are unchanged, so no new risk is expected
  (inferred).
- The classic and `next` UIs are separate view layers over shared logic; a future switch to `next` in
  production needs its own review, the fonts moved to a path that is also published, and a global locale decision.
- Fonts live under `src/theme-hotel/fonts` (not `public/assets/fonts`) so the production output stays
  identical; they are copied only by the `demo` configuration.
- The Today panel shows guest names (initials in the demo). Same data the classic room dialog already shows.
- The demo configuration must never be used for a deployable build.
- Existing behavior observed and **not changed** (tracked separately, neutral wording): some read paths do not
  distinguish an empty answer from a failed one; a read path ignores the error flag; one loading flag can stay
  on when there is no stored session; external stylesheets referenced by the page are not version-pinned.
- No lint target exists; the gate used here is the strict TypeScript build. Adding a linter and a CI unit-test
  job for the dashboard are follow-ups (CI currently only builds the development configuration).
- Follow-up: build both the `demo` and the `production` configurations in CI, so a break in either (including
  the production size budget) is caught before a merge.
- Follow-up: fix the 5 pre-existing failing specs (4 spec files; the test setup lacks the auth environment
  configuration provider). They fail identically on `develop` and were not touched.
- Occupancy denominator rule (rooms in maintenance) is an open business decision.

Follow-ups, out of scope for this MVP: hotel migration to the newer CRUD gateway; money logic in SQL; hotel
demo/test tenant seed; dashboard unit-test CI job and linter; dev environment pointing to production;
repository privacy and license (the dashboard README states a different license than the root MIT file; not
re-checked in this session, reported by the owner); date-convention data migration (check-in 15:00 / check-out
12:00, America/Mexico_City); global es-MX locale; pinning external stylesheets; hotel database schema
documentation from the live database.

Pending in this work: opening a PR (waits for review).

## 7. Objects that exist in the live DB or n8n but not in the repo

None identified. This work does not read or change the database or n8n; checked by inspection of the diff
(frontend, `angular.json` and docs only). The dashboard's live schema was not consulted.

## 8. Mismatches with ARCHITECTURE.md, CLAUDE.md and schema docs

- `ARCHITECTURE.md` section 1 (structure) does not list the new `ui-variant`, `demo`, `next` and `theme-hotel`
  folders, and section 5 says "both dashboard environment configurations point to production"; only one
  environment file is tracked locally (the real one is generated and ignored by git) plus the new demo file.
- `ARCHITECTURE.md` mentions a header in the shell; `HeaderComponent` exists but no template uses it
  (verified by search for its selector).
- `CLAUDE.md` build commands do not mention the `demo` configuration; its guidance that `ng serve dashboard`
  runs the dev server is correct, but that default configuration reaches production endpoints.
- The dashboard `ARCHITECTURE.md` baseline is v0.11.0 while this branch adds new files; no version was bumped
  (the CHANGELOG entry is under "Sin publicar").
- No database schema doc was read for this task.
