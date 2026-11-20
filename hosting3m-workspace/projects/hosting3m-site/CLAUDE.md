# hosting3m-site: Hosting3M public marketing site

Angular 21 (standalone, Signals), Tailwind CSS v4 (CSS-first tokens in `src/styles.css`; no `tailwind.config.js`).
Replaces the Sitejet export at https://hosting3m.com. Public, static, client-side only.

## Hard rules
- The browser only calls two public endpoints: `POST {n8n}/webhook/v6/contact` and `POST .../v6/news` (phase 2).
  Never request JWTs, never call `genera-token`, never call `/crud/...`, never query a database.
- Tenant context is fixed on the server (`id_company = 1`). Never send or trust a tenant id from the browser.
- No secrets in the repo or the build. Only the public Turnstile sitekey is allowed (phase 2).
- Never render remote strings with `innerHTML`; use Angular bindings and validate `http/https` URLs.
- Do not touch `hotel-website`, n8n, `jwt-service`, Docker, Plesk or Cloudflare from this app.
- Plans and prices live in `src/app/data/plans.json`. Unapproved values stay `TODO_*`: never invent prices, clients,
  testimonials, certifications or SLA claims ("uptime", "24/7", "enterprise security" are removed until an SLA exists).
- `/webcard` and `/g` are Sitejet asset folders on the server: no routes, no redirects.
- Code, comments, commits in English; UI copy in es-MX.

## Commands (from `hosting3m-workspace/`)
- `ng serve hosting3m-site`
- `ng test hosting3m-site --watch=false`
- Build off the VPS: `ng build hosting3m-site && node projects/hosting3m-site/scripts/postbuild.mjs`
  (output: `dist/hosting3m-site/browser/`).

## Docs
- `docs/phase-1.md`: phase 1 report. `docs/nginx-legacy-redirects.conf`: nginx snippet (manual paste).
