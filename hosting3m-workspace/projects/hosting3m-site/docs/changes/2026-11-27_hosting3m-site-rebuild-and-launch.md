# Change record: hosting3m-site rebuild and launch (2026-11-20 to 2026-11-27)

Documentation only. Reconstructed on 2026-11-27 from the repository (`origin/develop` at `6f2b140`, `origin/main` at `16454b0`) and
`gh pr list/view`. `git fetch origin` was refused in this session (access error), so local remote-tracking refs may lag; PR data from `gh` was
current. Nothing was run against any server, and no code, migration, workflow or existing doc was changed.

Status vocabulary: **merged to develop**, **merged to main**, **file only, not applied** (a file in the repo that someone must apply by hand),
**reported by owner, not verifiable in repo**, **not verified**, **proposed**, **pending**.

## 1. Goal and context

Replace the Sitejet export at the public domain with a new Angular 21 static site (`hosting3m-workspace/projects/hosting3m-site`): home with
service selector, catalog-driven packages, contact form, demo section, profile and portfolio pages, legal pages, and consent-gated analytics.
The site is client-side only and calls three public n8n webhooks. Tenant context is fixed on the server (company id 1).
Work ran from 2026-11-20 (first commit `8d2cba6`) to 2026-11-23 (last site commit `df5852c`).

## 2. What changed

### 2.1 Repo files, grouped by PR (all merged to develop; PR dates are merge dates)

| PR | Date | Purpose | Main paths |
|---|---|---|---|
| #1131 | 11-20 | App skeleton, design variables, routes, plans fallback, sections, contact form, news, SEO, TODO build guard, hydration, CSP-safe output; beta runbook and header docs | `src/app/**`, `scripts/check-todo.mjs`, `docs/phase-3/beta-runbook.md`, `docs/nginx-security-headers.conf`, `docs/nginx-beta-only.conf` |
| #1132 | 11-20 | Catalog loaded from `POST /webhook/v6/plans` (build-time snapshot plus one refresh after hydration); form/price UI fixes | `scripts/fetch-plans.mjs`, `src/app/core/plans.ts`, `src/app/data/plans-snapshot.json` |
| #1133 | 11-21 | Export of the `v6/plans` workflow | `workflows/02-leads-contact/v6/plans.json` |
| #1134 | 11-21 | Legal entity, address and opening hours | `src/app/core/business.ts` (later the single source for contacts) |
| #1135 | 11-21 | Analytics gated behind cookie consent (default denied) plus clean-storage regression tests | `src/app/core/consent.ts`, `consent.spec.ts`, `sections/cookie-banner.ts` |
| #1136 | 11-21 | Hero promise and first FAQ entry | `src/app/data/home-copy.ts`, `faq.ts` |
| #1137 | 11-21 | Invoicing-claim section hidden until that service exists | `src/app/data/cfdi-claim.ts` |
| #1138 | 11-21 | "Redesign D": dark header, hero, service selector, demo section, bento, steps/FAQ/news, contact section; redesign report and marketing review list | `src/app/sections/**`, `docs/redesign-d-report.md` |
| #1139 | 11-21 | Real logo, favicon, optimized hero, social preview image | `public/**` |
| #1140 | 11-21 | Profile page, portfolio page, fallback card summaries | `src/app/data/profile.ts`, `portfolio.ts`, `pages/*` |
| #1141 | 11-21 | Production cutover runbook; build guard that fails production builds while legal review markers remain (with test) | `docs/phase-4/cutover-runbook.md`, `scripts/check-legal-markers.mjs` |
| #1142 | 11-21 | Privacy notice, cookies policy and terms pages from structured data; footer, banner and form links | `src/app/data/legal/{privacy,cookies,terms}.ts`, `pages/legal/*` |
| #1143 | 11-22 | Data-deletion page aligned with the privacy notice; trailing-slash fixes for legacy redirects; external-console URL step added to the runbook | `src/app/data/legal/deletion.ts`, `docs/nginx-legacy-redirects.conf` |
| #1144 | 11-22 | Catalog snapshot refreshed (17 plans); group order follows `sort_order`; quote-only web and email plans with prefilled contact CTA | `plans-snapshot.json`, `plans-section.*` |
| #1145 | 11-22 | Package card polish (feature order, summary font, one date per group, 4-column grid) | `plans-section.*` |
| #1146 | 11-22 | Domains as tiles; quote-only plans merged into one section (made-to-measure services) | `plans-section.*` |
| #1147 | 11-22 | CSP enforcement plan and cache-header policy | `docs/nginx-security-headers.conf`, runbook sections 3.6 and 8.2 |
| #1157 | 11-23 | Analytics cookies cleared again on the next tick after consent is revoked; Person structured data on the profile page only | `core/consent.ts`, `core/seo.ts`, `seo-person.spec.ts` |
| #1155, #1158 | 11-23 | Dependency updates; Angular peer dependencies aligned so `npm ci` works without legacy flags (touches `package.json`, `package-lock.json`) | `hosting3m-workspace/package*.json` |
| #1154, #1159 | 11-22, 11-23 | Release PRs `develop` to `main` (titles do not mention the site; they carry site commits, see section 2.5) | n/a |

The commit-to-PR mapping for individual commits inside #1143 to #1147 was not checked one by one (inferred from dates and titles).

### 2.2 Data changes in the live catalog

All **reported by owner, not verifiable in repo.**
- Table `service_plans`, company id 1: 17 active plans (summaries, feature lists, prices, order, validity); edited with manual SQL after backups.
- Table `contact_requests`, company id 1: test submissions marked with status `'test'` (rows were never deleted).
- No migration file for `service_plans` or `contact_requests` exists in the repo (searched `*.sql` and `*.md`). The only schema mentions are in the runbooks.
- Repo evidence that is verifiable: `plans-snapshot.json` holds 17 plans (6 domain, 4 hosting, 4 VPS, 1 automation, 1 email, 1 web; the last three are quote-only), with the same field names the `v6/plans` workflow selects.

### 2.3 n8n webhooks the site calls (names only)

`v6/contact` (POST, form), `v6/news` (POST), `v6/plans` (POST, body `{}`). Exports: `workflows/02-leads-contact/v6/{contact,plans}.json`,
`workflows/03-rag-news-intelligence/v6/news.json`. Status: exports merged to develop; that the same versions are active in production is **not verified**.

### 2.4 Frontend behaviour (merged to develop)

- Contact payload carries no tenant or identity field; the form sends text fields, the service label, a bot-check response and a honeypot that is forced empty. Lengths are clipped to the server limits, unknown service values are dropped, and only an explicit `success: true` counts as success (an empty 200 is treated as failure).
- Consent Mode v2 default is all signals denied; analytics loads only after Accept; revoking removes the analytics cookies with a second pass on the next tick.
- Fonts and images are self-hosted; the build emits no inline script or style, so the CSP needs no `unsafe-inline`.
- Production build fails on any `TODO_` placeholder or legal review marker (`check-todo`, `check-legal-markers`, both with tests, run in CI).

### 2.5 Infra and configuration

| Item | Status |
|---|---|
| Production go-live on 2026-11-23 following the cutover runbook, from `main` at `7f9b0ca` (PR #1154) | Reported by owner, not verifiable in repo. Repo facts: `7f9b0ca` is a merge commit on `main` dated 2026-11-22; it does not contain #1157 (`cbdfbd0`, `df5852c`). |
| `main` later moved to `16454b0` (PR #1159), which contains #1157 and #1158; site files are identical between `origin/main` and `origin/develop` | Verified in repo. Checked on 2026-11-27 by the owner: the structured-data fields added in #1157 are NOT present on the live site, so production appears to still run the 7f9b0ca build (inferred). |
| Web-server directives from `docs/nginx-legacy-redirects.conf` and `docs/nginx-security-headers.conf` | Files merged to develop; applied by owner per report, **not verifiable in repo**. The headers file ships the Report-Only policy active and the enforcing line commented out. Verified on 2026-11-27 by the owner through a response-header check: the enforcing policy header is served (not Report-Only). |
| Search-console property and sitemap, social-platform privacy/terms/deletion URLs, analytics property with consent default denied | Reported by owner, not verifiable in repo. |
| Redirects: three legacy legal URLs, the old news paths to `/`, and a retired feed answering 410 | File only (`docs/nginx-legacy-redirects.conf`); target for the news paths is flagged in the file as an assumption. |
| Replace the manual file-copy release with a CI-built artifact branch pulled by the hosting panel's git feature | **Designed but not applied / proposed**; separate PR pending. Nothing of it exists in the repo. |

## 3. Business and content rules decided

Content rules (from `CLAUDE.md` of the project and the committed data files):
- No invented prices, clients, testimonials, certifications or SLA claims. Wording such as "uptime", "24/7" or "enterprise security" was removed until an SLA exists. Prices come only from the public catalog; no price is written in templates.
- Demo screens use fictitious data and are labeled as illustrative examples (`src/app/data/systems-demo.ts`); they never call an ERP API.
- Logos and photos: only the owner's own brand assets and photo are used; no third-party client logos.
- Support hours wording is a single source in `src/app/core/business.ts` (`hoursText`, `hoursShort`: weekdays and Saturday, Central Mexico time). Marketing copy may also state a first reply within one business day (`src/app/data/home-copy.ts`). Terms and privacy pages read the same data.
- Contacts, legal entity and address are read only from `business.ts`; the publication date constant is `LEGAL_LAST_UPDATED` in the same file.
- Legal retention and rights periods are those published in `src/app/data/legal/privacy.ts` (sections "Derechos ARCO y revocación" and "Conservación": contact data kept 24 months from last contact; billing data for the legally required period). Cookie details are in `legal/cookies.ts`; deletion channel and response time in `legal/deletion.ts`. They are not repeated here.
- Legal texts were approved as-is by the lawyer: reported by owner, not verifiable in repo.
- Invoicing-claim section stays hidden until that service launches.

Open questions:
- Marketing review of copy and design: 50 `MARKETING-REVIEW` markers remain in `src/app` (routes, profile, portfolio, home copy, plans fallback). Pending.
- The `/news` and old blog-post redirect target (`/`) is an assumption marked in the redirects file.
- Whether the response-time statement in the deletion page matches the ARCO period in the privacy page was a runbook checklist item; its sign-off is not recorded in the repo.
- Tenant: the news query (`v6/news`) has no company filter in the exported workflow; whether that is intended for a global news table is **not verified**.

## 4. How to test (beta only, never production data)

Site data belongs to company 1. There is no separate test tenant. Every test submission must start with a "PRUEBA BETA" style marker and be marked `status = 'test'` afterwards (never deleted), as in `docs/phase-3/beta-runbook.md`.

- Build and tests (from `hosting3m-workspace/`): `node projects/hosting3m-site/scripts/build.mjs --configuration beta`; `npm test -- hosting3m-site --watch=false`; the two guards: `node --test projects/hosting3m-site/scripts/check-todo.test.mjs` and `node --test projects/hosting3m-site/scripts/check-legal-markers.test.mjs`. CI runs these (`.github/workflows/ci.yml`). A `production` build must fail while markers remain; `beta` only warns. I did not run them in this session.
- Consent: unit tests exist for default denied, accept loads analytics and grants only the analytics signal, reject loads nothing, persistence, clean-storage regression, and cookie removal after revoke including the next-tick pass (`core/consent.spec.ts`). Manual browser check: runbook section 7, item 2.
- Contact form: unit tests cover payload shape, truncation and unknown services (`core/contact.spec.ts`) and success/default message (`sections/contact-form.spec.ts`). Manual cases to run on beta: empty submit, quotes and apostrophes, commas, leading zeros in the phone, the literal texts "null" and "undefined", an empty/null-like value, and text longer than the limits (names 100, phone 30, email 150, message 2000, service 60). Automated coverage of the quotes, commas, leading-zero, "null"/"undefined" and null cases: **not verified (no such tests found)**.
- Different company id from the browser: the payload test asserts the exact key set, so no tenant field is sent. The workflow export fixes the company id in SQL. There is **no automated test** that posts an extra company field to the endpoint; manually add one to a beta request and confirm the stored row has company 1 (**not verified**).
- Catalog: compare page prices to the `v6/plans` answer (runbook section 6).

## 5. Rollback

- Release (files, web-server directives, cache): runbook `docs/phase-4/cutover-runbook.md` section 2.4 (restore the docroot backup, restore the saved directives, purge the CDN cache, repeat the first smoke checks); CSP rollback in section 8.2. Triggers are listed at the end of runbook section 9.
- Repo changes: revert the relevant PR on develop; nothing else is invented here.
- Data changes in the live catalog: backups were taken by the owner (reported); **no rollback file exists in the repo**.
- Snapshot file: restore the previous committed `plans-snapshot.json` (git history); the build never fails on catalog errors and keeps the committed copy.

## 6. Known gaps, risks, pending work

- Pending: marketing review (section 3); next production release; 48-hour watch from runbook section 9; optional dependency audit follow-up; artifact-branch release PR (proposed).
- Catalog data lives only in the live database with no migration or seed; a rebuilt database would have an empty catalog and the site would show the committed snapshot or the quote cards.
- The committed snapshot can go stale; the runbook asks to refresh it before every release.
- Only the cache rules remain unverified in production; the enforcing policy was verified on 2026-11-27 by the owner via a response-header check. HSTS is intentionally not enabled.
- Contact data and the legal text are tied to one person's name and address in `business.ts`; changes need a new legal-date review.
- A security review/fix was carried out and is tracked privately.
- Accessibility and performance numbers in the runbook come from local lab runs; real-network numbers were left blank.

## 7. Objects in the live system that are not in the repo

Read them from the live system before changing anything:
- Rows of `service_plans` (17 active plans, prices, summaries, features, validity) and the schema of `service_plans` and `contact_requests`.
- The status value `'test'` on `contact_requests` and any other status values in use (the default is `'new'`; no constraint was reported).
- Web-server directives for the production and beta domains (redirects, headers, cache rules, error page) and the "proxy mode off" setting they depend on.
- CDN zone settings (TLS mode, rules, cache, bot-check hostnames) and the cached copies of unhashed files.
- Search-console property and submitted sitemap; analytics property settings; social-platform app URLs.
- The backups taken before the cutover and before the catalog edits.
- The active versions of the three n8n workflows (compare by fingerprint before importing, per the suite rules).

## 8. Mismatches with other docs (list only)

- `docs/ARCHITECTURE.md` and `docs/DATABASE_SCHEMA.md`: neither exists, at the repo root `docs/` or under the project `docs/`.
- Root `README.md`: no mention of `hosting3m-site` (module table, diagram, roadmap).
- `CHANGELOG.md`: no entry for the site or its launch.
- Root `CLAUDE.md`: the suite description lists four registered apps and the module map omits `hosting3m-site`; its deployment section describes `main` deployed from the hosting panel's git feature, while the cutover runbook describes a built artifact copied by hand (the proposed artifact-branch flow would be a third variant).
- Project `CLAUDE.md`: says "three public endpoints"; `runtime-config.ts` and the headers file comments say "two". Its Commands section does not mention the legacy-flag change of #1158.
- Cutover runbook: gate checkboxes and the Meta/console checklist items are unchecked; section 5 says the legal text is "not yet lawyer-approved"; build step still uses `npm ci --legacy-peer-deps` (changed by #1158); section 12 says the analytics cookie residue fix is "not done yet" (done in #1157); section references skip 3.5.
- `docs/nginx-security-headers.conf`: the file still labels the policy Report-Only (enforcing line commented out), while production serves the enforcing policy (verified 2026-11-27 by the owner).

## 9. Update 2026-11-27: git-based deploy, first releases and follow-ups

Added at the end of the same day. It supersedes the statements in 2.5 that call the artifact-branch flow "designed but not applied / proposed" and that say production still ran the `7f9b0ca` build.
Same status vocabulary as above. Facts about the server and the hosting panel are **reported by owner, not verifiable in repo**; repo facts were checked against `git log` and `origin/develop`.
`git fetch` and `git push` were not used in the session that wrote the draft.

### 9.1 What is in the repo (all merged)

| Item | Status | Evidence |
|---|---|---|
| CI workflow that builds the site and publishes only the built output (plus a checksum list and a build-info file) as an orphan commit to `deploy/beta` (from `develop`) and `deploy/prod` (from `main`); push-only trigger, read-only build job, write permission only on the publish job, third-party actions pinned to commit SHAs | **merged to develop** (#1166) | `.github/workflows/hosting3m-site-artifact.yml` |
| `scripts/package-artifact.sh` (artifact layout, build info, checksum list) | **merged to develop** (#1166) | file in repo |
| Catalog policy in CI: no live fetch, build from the committed snapshot, fail if the build rewrites it | **merged to develop** (#1166) | workflow step |
| `docs/deploy/deploy-site.sh`, server-side script template (verifies the pulled artifact before touching anything, dry run by default, tar backup, copy without `--delete` excluding `/webcard` and `/g`, post-copy check, prints the rollback command, never removes backups), with checks that refuse an artifact directory inside, equal to or above a docroot and require an absolute backup directory | **merged to develop** (#1166) | `tests/deploy/test_deploy_site.sh` |
| Stubbed script tests and ShellCheck in the CI "Shell checks" job | **merged to develop** (#1166) | `.github/workflows/ci.yml` |
| Deploy runbook `docs/deploy/README.md`; cutover runbook updated (pointer to the new flow, rsync steps kept as fallback, stale items fixed, status block, gate boxes left unticked) | **merged to develop** (#1166) | files in repo |
| Project `CLAUDE.md` and `README.md` (endpoint count fixed to three, deploy flow, content rules, legal guards, snapshot rules); root `README.md` (8 Angular projects: 5 applications, 3 libraries), `CHANGELOG.md` entry and `CLAUDE.md` deploy section | **merged to develop** (#1166) | files in repo |
| Plans snapshot refreshed with the project's own script from the public catalog: 17 plans, none added or removed; two plans gained summaries and the email plan gained its feature list; no price, date or order changed | **merged to develop** (#1167) | `plans-snapshot.json` |
| Site-only release to `main` (merge commit `0c10958`), cut from `main` with cherry-picks because unreviewed agro-erp work was sitting in `develop` | **merged to main** (#1168) | PR and merge commit as reported by the owner; not re-checked in this session |
| A security review/fix was carried out and is tracked privately | n/a | no details here |

Local checks run before the merges (site unit tests, guard tests, production build with the plans fetch skipped, script test, ShellCheck, actionlint) passed. Their CI results after merge are **not verified** here.

### 9.2 Operation (server, hosting panel, CI runs)

All of this is **reported by owner, not verifiable in repo**:

- The artifact workflow ran from `develop` and from `main`. `deploy/beta` and `deploy/prod` exist as single-commit orphan branches updated by force from CI.
- Beta was deployed twice with the new flow. Production was deployed on 2026-11-27 from the artifact built from `main` commit `0c10958` (production configuration). Before copying, the script made a verified backup; after copying, it verified the checksums.
- The owner checked the live site: the structured data added in #1157 is live. This supersedes the earlier inference that production still ran the `7f9b0ca` build.
- The rollback command was proven on beta; it was **not exercised on production**.
- Hosting panel: two git repositories for this site, both in manual mode and without post-deploy actions, one tracking `deploy/beta` on the beta host and one tracking `deploy/prod` on the production host. An earlier unused mirror repository was removed. Pulling the force-updated orphan branches evidently works, since beta and production were deployed from them (**inferred**).
- The other suite sites track `main` in automatic mode and build on the server, so a merge to `main` triggers their deploys. The deploy actions live only in the panel UI; the runbook summarizes steps only. Which project maps to two of those three sites is **inferred** from their names.
- The CDN rewrites HTML in transit (email obfuscation); this is the only difference between the origin and the public responses. Disabling it is optional (proposed).
- Release mechanics: while unreleased agro-erp work sits in `develop`, site releases use a branch cut from `main` plus cherry-picks (#1168). The "Agent workflow consistency" check was red on that PR as expected, and this was documented in the PR; it is not a regression of the site work.

### 9.3 Still open (follow-up PRs, status in brackets)

- Post-release watch window of cutover runbook section 9 (**pending**).
- Marketing review of the 50 review markers (**pending**, see section 3).
- An unrelated endpoint question raised during the release (**pending**; not part of this work, details not recorded here).
- Optional: disable the CDN email obfuscation, or account for it when comparing hashes of pages fetched through the CDN (**proposed**).
- Mark the cutover runbook's rsync steps as fully superseded now that the flow ran on production (**proposed**; they were kept as fallback and the rollback was not exercised on production).
- Panel mode of the other suite sites versus the root `CONTRIBUTING.md` and the root `CLAUDE.md` database/n8n runbook box, which still say `main` is deployed manually: align them with the owner's report (**pending**).
- Two code/config comments still say the site calls "two" endpoints (`core/runtime-config.ts` and the header of `docs/nginx-security-headers.conf`); that file also still labels the policy Report-Only although the enforcing policy is served (**pending, proposed**).
- Existing jobs in `ci.yml` still install with the legacy peer-deps flag that #1158 made unnecessary (**pending, proposed**).
- Backlog of the panel-git sites, not changed: the hotel action removes the document-root contents without a backup; builds run on the server with `npm install`; any merge to `main` triggers all three actions; one legacy site still auto-deploys; the actions are not versioned (**proposed**).
- Repository rules that could block force-pushes to `deploy/*`: the flow works, so none blocks CI today (**inferred** from the successful runs).
- Not verified: CI results of the #1166 checks after merge; the exact content of the two artifact branches in this session; whether the live `BUILD_INFO` file is reachable through the CDN.
