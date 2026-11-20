# Phase 3: performance, accessibility, security headers, beta runbook

## What changed
- **Hydration** (`provideClientHydration`, no event replay): the prerendered DOM is reused instead of rebuilt (no repaint, better LCP).
- **CSP-friendly output:** critical-CSS inlining is off for `production` and `beta` (it adds an inline `onload` handler). The build now emits no inline script, style or event handler; only the two JSON data blocks (`ng-state`, JSON-LD), which CSP does not treat as scripts.
- **Accessibility pass:** focus moves to `<main>` after each route change (not on anchors), field errors are linked with `aria-describedby`, errors announced with `role="alert"`, skip link, labelled landmarks, AA contrast tokens. Lighthouse accessibility: **100** on home and privacy.
- **Security headers:** `docs/nginx-security-headers.conf` (CSP rollout Report-Only first, nosniff, Referrer-Policy, Permissions-Policy, X-Frame-Options, optional HSTS, hashed-asset caching), `docs/nginx-beta-only.conf` (noindex). `docs/nginx-legacy-redirects.conf` no longer redefines `location /` (Plesk owns it).
- **Beta runbook:** `docs/phase-3/beta-runbook.md`: Cloudflare + Plesk subdomain, exact n8n edits for both workflows, Turnstile hostname, Plesk Git deploy, smoke tests, rollback.
- **TODO tokens** for `og:image`, street address and opening hours, as requested.

## Measurements (Lighthouse 13, mobile profile, local static server, uncompressed)
| Page | Performance | Accessibility | Best practices | SEO | LCP | CLS |
|---|---|---|---|---|---|---|
| `/` | 87 | 100 | 96 | 100 | 0.9 s | 0 |
| `/politica-de-privacidad` | 96 | 100 | 100 | 100 | 1.1 s | 0 |
- The only console error is the CORS rejection of `localhost` by n8n, which confirms the beta origin must be whitelisted (section 3 of the runbook).
- Total Blocking Time is 490 ms on home (simulated 4x CPU): Angular boot plus hydration. Real devices and Cloudflare Brotli will do better; re-measure on beta.
- **Bundle:** initial JS 323 kB raw / 90 kB gzip (was 311 / 86 before hydration). I could not get below 300 kB raw: `@angular/core` (128 kB), `router` (74 kB), `common` (40 kB) and rxjs (19 kB) are the floor, app code is 13 kB. The 300 kB warning was arbitrary; budgets are now warn 350 kB / error 450 kB raw, and gzip size (about 90 kB) is what matters for LCP.
- **Images:** the new site ships no raster images (system fonts, no logo or photos yet), so there was nothing to convert; the ~9 MB of the old site is not carried over. News images are lazy, `async`-decoded, with width/height. When the logo and `og:image` arrive: WebP/AVIF with explicit width/height for page images, JPG/PNG 1200x630 for `og:image`, and never `loading="lazy"` on the LCP element.

## How to test
```sh
cd hosting3m-workspace
ng test hosting3m-site --watch=false
node projects/hosting3m-site/scripts/build.mjs --configuration beta
```
Then follow `docs/phase-3/beta-runbook.md`.

## What you must do on the server
Everything in the beta runbook, sections 2 to 6 (Cloudflare record, Plesk subdomain and certificate, the two n8n workflows, Turnstile hostname, nginx directives, deploy).

## Open questions
- The `v6/contact` and `v6/news` workflow JSON is not in the repo. After section 3, please export both and let me add them under `workflows/02-leads-contact/v6` and `workflows/03-rag-news-intelligence/v6` in their own PR.
- Dist repository for Plesk Git (`<DIST_REPO>`): a separate private repo is proposed; tell me if you prefer a branch of this repo.
- Pending content: `TODO.md`.
