# Phase 1: skeleton, tokens, layout, routes, redirects, plans.json

## What changed
- New app `hosting3m-site` registered in `angular.json` (only shared file touched). Initial bundle ~264 kB raw / ~73 kB gzip (budget 500 kB error).
- Tailwind v4 design tokens (provisional brand palette, AA-checked), header, footer, WhatsApp button (replaces the chat widget).
- Routes: `/`, `/portfolio`, `/fjpimienta`, `/politica-de-privacidad`, `/condiciones-de-servicio`, `/eliminardatosusuarios`, `**` (404).
  Client-side redirects `/privacy`, `/news`, `/noticias-elemento/:post` are a safety net; nginx does the real 301s.
- `src/app/data/plans.json` + typed loader (no API); every price/spec is a `TODO_*`.
- `scripts/postbuild.mjs` writes the SPA shell into each route folder and `404.html`, so rsync (without `--delete`) overwrites legacy Sitejet pages.
- `docs/nginx-legacy-redirects.conf`: snippet for you to paste in Plesk.

## How to test
```sh
cd hosting3m-workspace
ng test hosting3m-site --watch=false
ng build hosting3m-site && node projects/hosting3m-site/scripts/postbuild.mjs
npx http-server dist/hosting3m-site/browser -p 4300   # or: ng serve hosting3m-site
```

## What you must do on the server
Nothing yet. Beta deploy is phase 3.

## Open questions / TODOs
- `TODO_PRICE`, `TODO_FEATURES`, `TODO_BILLING`, `TODO_COPY` for the 4 packages; hero promise.
- `TODO_BRAND`: logo, palette, typography. `TODO_LEGAL_ENTITY`: razón social for terms.
- `TODO_PORTFOLIO`: real, approved cases. `TODO_PROFILE`: should `/fjpimienta` keep a public CV?
- Confirm `/news` -> `/` (assumed; you only specified `/privacy` and the blog posts).
- Request: add `npx ng build hosting3m-site` to `.github/workflows/ci.yml` (outside this app).
- Request: approve adding `@angular/platform-server` to enable build-time prerender (better SEO per route); until then the app is a client-rendered SPA with route shells.
