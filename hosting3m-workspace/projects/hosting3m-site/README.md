# hosting3m-site

Public site for Hosting3M (VPS, managed n8n, domains and email, open-source automation suite).
See `CLAUDE.md` for rules and commands, and `docs/` for per-phase reports and runbooks.

- Change record (rebuild and launch, 2026-11-20 to 2026-11-27): [`docs/changes/2026-11-27_hosting3m-site-rebuild-and-launch.md`](docs/changes/2026-11-27_hosting3m-site-rebuild-and-launch.md)
- Git-based deploy (CI builds the artifact on `main` and publishes `deploy/prod`; server script, rollback; production only): [`docs/deploy/README.md`](docs/deploy/README.md)
- Production cutover runbook (Cloudflare, headers, SEO, smoke tests): [`docs/phase-4/cutover-runbook.md`](docs/phase-4/cutover-runbook.md)
- Beta runbook (historical: the beta environment was removed on 2026-11-27): [`docs/phase-3/beta-runbook.md`](docs/phase-3/beta-runbook.md)

Quick start (from `hosting3m-workspace/`): `npm ci`, then `ng serve hosting3m-site` (simulated API) or
`PLANS_SKIP_FETCH=1 node projects/hosting3m-site/scripts/build.mjs --configuration production`.
