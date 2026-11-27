# hosting3m-site: Hosting3M public marketing site

Angular 21 (standalone, Signals), Tailwind CSS v4 (CSS-first tokens in `src/styles.css`; no `tailwind.config.js`).
Replaces the Sitejet export at https://hosting3m.com. Public, static, client-side only.
Beta: https://beta.hosting3m.com (private by `noindex`, a server header).

## Hard rules
- The browser only calls three public endpoints on the n8n host: `POST {apiBase}/v6/contact` (`core/contact.ts`), `POST .../v6/news` (`core/news.ts`) and
  `POST .../v6/plans` with body `{}` (`core/plans.ts`). `apiBase` is `RUNTIME.apiBase` in `core/runtime-config.ts`.
  Never request JWTs, never call `genera-token`, never call `/crud/...`, never query a database.
- Tenant context is fixed on the server (`id_company = 1`). Never send or trust a tenant id from the browser.
- No secrets in the repo or the build. Only the public Turnstile sitekey is allowed.
- Never render remote strings with `innerHTML`; use Angular bindings and validate `http/https` URLs.
- Do not touch `hotel-website`, n8n, `jwt-service`, Docker, Plesk or Cloudflare from this app.
- `/webcard` and `/g` are Sitejet asset folders on the server: no routes, no redirects, never deployed, never deleted.
- Code, comments, commits in English; UI copy in es-MX.

## Content rules
- No invented prices, clients, testimonials, certifications or SLA claims. "uptime", "24/7" and "enterprise security" stay out until an SLA exists.
  Unapproved copy stays `TODO_*` (the production build fails on it).
- No third-party logos. Only the owner's own brand assets and photo are used.
- Demo screens (`data/systems-demo.ts`) use fictitious data and are labeled **"Ejemplo ilustrativo"**; they never call an ERP API.
- Contacts, legal entity, address and hours come only from `core/business.ts` (single source; `LEGAL_LAST_UPDATED` is the publication date of the legal texts).
- The invoicing-claim section (`data/cfdi-claim.ts`) stays hidden until that service exists.
- `data/*.ts` (and `app.routes.ts`) carry `// MARKETING-REVIEW: <what>` comments for copy that marketing has not reviewed yet (50 in `src/app` on 2026-11-27, list in
  `docs/redesign-d-report.md`). They are plain comments: no guard checks them and they never reach the build. Keep them when you edit that copy; remove one only when the review is done.

## Legal pages and the guard
- Routes `/aviso-de-privacidad`, `/politica-de-cookies`, `/terminos-y-condiciones` (title "Condiciones de servicio") and `/eliminardatosusuarios` render structured data in
  `src/app/data/legal/*.ts` through one `LegalPage` component. Legacy URLs are redirected by `docs/nginx-legacy-redirects.conf`.
- Unreviewed legal text carries an editorial marker (`[VERIFICAR]`, `[DECIDIR]`, `[REVISAR]`, `[FECHA DE PUBLICACIÓN]`). `scripts/check-legal-markers.mjs` makes a **production** build fail while one is
  in the output (beta/development only warn); `scripts/check-todo.mjs` does the same for `TODO_` tokens. Both have tests and run in `build.mjs` and in CI. Never weaken them to get a build through.
- Changing legal text, contacts or the entity needs a new legal-date review (`LEGAL_LAST_UPDATED`). The legal text was reported approved as-is by the owner (not verifiable in the repo).
- Analytics is consent-gated (`core/consent.ts`, Consent Mode v2 default denied; only `analytics_storage` is granted on Accept). Do not add any tag or script that loads before consent.

## Plans (catalog) and the snapshot
- Plans and prices come from the public catalog `POST /v6/plans`. `scripts/fetch-plans.mjs` writes `src/app/data/plans-snapshot.json` at build time (never fails the build; an empty answer,
  an error or a timeout keeps the committed file) and the app refreshes it once after hydration. `data/plans.json` only holds the quote cards shown while the catalog is empty.
- Never write a price in a template or data file, and never invent one.
- Refreshing the snapshot is a **reviewed commit of its own** (`chore(hosting3m-site): refresh the plans snapshot ...`), made before a release (`docs/phase-4/cutover-runbook.md`, section 6).
  Read the script's message: "keeping the committed snapshot" means you did not get fresh data.
- CI never fetches the catalog: it sets `PLANS_SKIP_FETCH=1`, builds from the committed snapshot and fails if the build changes it. Use `PLANS_SKIP_FETCH=1` for any local build that should not touch the file.

## Commands (from `hosting3m-workspace/`)
- Install: plain `npm ci` (no `--legacy-peer-deps` since #1158).
- `ng serve hosting3m-site`
- `npm test -- hosting3m-site --watch=false` (the plain-Node guard tests: `node --test projects/hosting3m-site/scripts/check-todo.test.mjs` and `.../check-legal-markers.test.mjs`)
- Official build (off the VPS): `PLANS_SKIP_FETCH=1 node projects/hosting3m-site/scripts/build.mjs --configuration production|beta|development`
  (output: `dist/hosting3m-site/browser/`). `production` FAILS on any `TODO_*` token or legal marker; `beta`/`development` warn.
- `ng serve` uses `runtime-config.development.ts`: the API is simulated (CORS only allows production and beta origins).
- Deploy-script tests (from the repo root): `bash tests/deploy/test_deploy_site.sh`; ShellCheck covers `docs/deploy/deploy-site.sh`, `scripts/package-artifact.sh` and the test.

## Deploy flow (git-based; details in `docs/deploy/README.md`)
- GitHub Actions (`.github/workflows/hosting3m-site-artifact.yml`) runs on push to `develop` and `main` only: tests, both guards, build, then force-pushes **only the built output**
  (plus `SHA256SUMS` and `BUILD_INFO`) as an orphan commit to `deploy/beta` (from `develop`, beta configuration) or `deploy/prod` (from `main`, production configuration).
- Never commit to `deploy/*` by hand and never put source or secrets on those branches.
- The hosting panel pulls the artifact branch in **manual** mode into a staging directory; its one-line post-deploy action calls the root-owned `deploy-site.sh` (template in `docs/deploy/`,
  installed by hand, never run from the repo). It verifies the checksums, backs up the docroot, copies with `rsync` **without `--delete`** (excluding `/webcard` and `/g`) and prints the rollback.
- Beta first, then production. The manual `rsync` of the cutover runbook is the fallback until the new flow is proven.
- The panel's Git for `hotel-website`, `agro-erp` and the dashboard works differently (automatic pull of `main`, build on the VPS); see section 7 of `docs/deploy/README.md`.

## Docs
- `docs/changes/2026-11-27_hosting3m-site-rebuild-and-launch.md` (change record), `docs/deploy/README.md` (git-based deploy runbook) and `docs/deploy/deploy-site.sh` (server script template).
- `docs/phase-1-report.md`, `docs/phase-2/report.md`, `docs/phase-2/TODO.md` and `docs/phase-3/TODO.md` (pending content); `docs/phase-3/beta-runbook.md` (beta deploy);
  `docs/phase-4/cutover-runbook.md` (production cutover); `docs/nginx-*.conf` (manual paste in Plesk).
