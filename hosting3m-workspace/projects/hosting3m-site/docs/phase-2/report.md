# Phase 2: sections, contact form, news, SEO, TODO guard

## What changed
- **Prerender** (separate commit): `@angular/platform-server@21.2.26` added to the workspace; only `hosting3m-site` uses `outputMode: static`. Production builds of `hotel-website` and `dashboard` are byte-identical before and after (sha256 of every dist file).
- **Home sections:** hero, services, packages (from `plans.json`), differentiators, process, suite open source (GitHub, MIT), FAQ, news, contact. Trust section renders only when real clients exist.
- **Contact form** (`POST /v6/contact`): client validation mirroring server limits, honeypot `empresa`, Turnstile (loaded lazily when the form is near the viewport), states `idle / isSubmitting / success / error`, double-submit guard, success only on `{success:true}` (a failed n8n run answers 200 empty). Plan buttons preselect the service via `?servicio=`.
- **News** (`POST /v6/news`): browser-only call, strict validation (http/https only, https for images, length caps, `[{}]` ignored), rendered with Angular bindings only; 3 own fallback cards when the answer is `[]` or fails.
- **SEO:** unique title and description per route, canonical, Open Graph, JSON-LD `LocalBusiness` + `Service` (prerendered), absolute `sitemap.xml`, `robots.txt`, one prerendered `index.html` per route.
- **Consent:** GA4 (`G-MVJRDZ7TD8`) loads only after "Aceptar"; footer link reopens preferences.
- **Legal pages** migrated; `TODO_LEGAL_ENTITY` replaces the unfilled company name.
- **TODO guard:** `scripts/build.mjs` is the official build. `production` fails on any `TODO_*` token; `beta`/`development` warn. CI runs the `beta` configuration and the unit tests.
- Local development (`ng serve hosting3m-site`) simulates the API (`runtime-config.development.ts`); no localhost is added to CORS.

## How to test
```sh
cd hosting3m-workspace
ng serve hosting3m-site                                                    # mock API, no network calls
ng test hosting3m-site --watch=false                                       # 16 tests
node projects/hosting3m-site/scripts/build.mjs --configuration beta        # warns about TODO_ tokens
node projects/hosting3m-site/scripts/build.mjs --configuration production  # must FAIL until TODO.md is resolved
```
Manual checks: submit with empty fields (inline errors); fill the form (mock success after ~600 ms); reject cookies then confirm no request to `googletagmanager.com`; view source of `dist/.../index.html` for title, canonical, JSON-LD.

## What you must do on the server
Nothing yet (beta host and CORS/Turnstile changes come with phase 3). When you pick up phase 3 I will give you the exact n8n and Turnstile changes for `https://beta.hosting3m.com`.

## Known limitations
- Not exercised against the real API: that needs the beta origin whitelisted (phase 3).
- Initial JS is ~311 kB raw / ~86 kB gzip (budget warning at 300 kB): reduce in the phase 3 performance pass.
- `/news` and `/privacy` are prerendered as redirect stubs; nginx 301s take precedence.

## Open questions
See `docs/phase-2/TODO.md`.
