# Production cutover runbook: https://hosting3m.com

Replaces the Sitejet export with the Angular build of `hosting3m-site`. This file only documents the procedure: Claude does not
run anything against the VPS, Plesk or Cloudflare. **You run every command.** Each block is tagged:

- **[laptop]**: run on the workstation that built the artifact (or in a browser).
- **[servidor]**: run on the VPS (over `ssh`, or typed inside an ssh session).

Placeholders: `<SSH_USER>`, `<VPS_IPV4>`, `<PLESK_SYS_USER>`. Production docroot: `/var/www/vhosts/hosting3m.com/httpdocs`
(confirm it in Plesk > Websites & Domains > hosting3m.com > Hosting Settings > Document root before the first command).
Beta docroot (already in use): `/var/www/vhosts/hosting3m.com/beta.hosting3m.com`.

**Hard rules for this runbook:** copy before changing, dry-run (`rsync -n`) before every real run, never `--delete` and never
`rm -rf` on the first deploy, never touch `/webcard` or `/g` (Sitejet asset folders), never paste a token in a chat or a file.
Every rollback below restores from a backup; none deletes anything.

Related files: `docs/phase-3/beta-runbook.md` (beta deploy, CORS, Turnstile, test-data cleanup), `docs/nginx-legacy-redirects.conf`,
`docs/nginx-security-headers.conf`, `docs/nginx-beta-only.conf`.

---

## 0. Go / no-go gate (all must be true before touching the server)

| # | Gate | How to check | Status |
|---|------|--------------|--------|
| 1 | Beta smoke tests of `beta-runbook.md` section 8 passed on the same commit that will be released | see section 7 | ☐ |
| 2 | The CSP on beta showed **zero violations** in Report-Only (section 8) | section 8 | ☐ |
| 3 | Legal pages carry the lawyer-reviewed text, no editorial markers (section 5) | `build.mjs --configuration production` passes | ☐ |
| 4 | No `TODO_` token in the build (TODO guard) | same build | ☐ |
| 5 | Catalog snapshot refreshed against the production API and committed (section 6) | `git log -1 -- .../plans-snapshot.json` | ☐ |
| 6 | URL map and redirects reviewed (section 4) | section 4 | ☐ |
| 7 | CORS in n8n already allows `https://hosting3m.com` (it does since beta; re-check section 3.5 of the beta runbook) | curl preflight below | ☐ |
| 8 | Maintenance window chosen: weekday, within support hours (Mon-Fri 9:00-17:00 Central Mexico) so someone can watch for 48 h | | ☐ |

CORS re-check **[laptop]** (expect `access-control-allow-origin: https://hosting3m.com`):
```sh
curl -si -X OPTIONS https://n8n.hosting3m.com/webhook/v6/contact \
  -H 'Origin: https://hosting3m.com' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type' | grep -iE '^HTTP|access-control'
```

## 1. Build the release artifact **[laptop]**

Build from a clean checkout of the release commit (not from a working tree with local edits):
```sh
git fetch origin && git switch --detach <release-commit>      # the exact commit validated on beta (or its tag)
cd hosting3m-workspace && npm ci --legacy-peer-deps
node projects/hosting3m-site/scripts/build.mjs --configuration production
```
The production build **fails by design** while a `TODO_` token or a legal marker remains. It also prints
`plans snapshot: N plan(s) ...` (the catalog fetched from `POST /webhook/v6/plans`, see section 6).

Record what you are about to ship:
```sh
cd dist/hosting3m-site/browser
find . -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/prod-sha.txt
wc -l /tmp/prod-sha.txt; grep -c 'TODO_' index.html || true      # the second command must print 0
du -sh .
```

## 2. Backup of the current production docroot and rollback

### 2.1 Backup (copy, never delete) **[servidor]**
```sh
ssh <SSH_USER>@<VPS_IPV4>
STAMP=$(date +%F-%H%M)
mkdir -p /root/backups/hosting3m-docroot-$STAMP
rsync -a /var/www/vhosts/hosting3m.com/httpdocs/ /root/backups/hosting3m-docroot-$STAMP/
du -sh /root/backups/hosting3m-docroot-$STAMP && ls /root/backups/hosting3m-docroot-$STAMP | head
find /var/www/vhosts/hosting3m.com/httpdocs -type f | wc -l ; find /root/backups/hosting3m-docroot-$STAMP -type f | wc -l   # the two numbers must match
chmod -R go-rwx /root/backups/hosting3m-docroot-$STAMP
echo $STAMP        # write it down: the rollback uses it
```
Also keep a copy of the current nginx directives of the domain (Plesk > hosting3m.com > Apache & nginx Settings > Additional
nginx directives): paste them into a dated text file next to the backup.

### 2.2 Dry run (writes nothing) **[laptop]**
```sh
cd hosting3m-workspace
rsync -avn --no-owner --no-group \
  dist/hosting3m-site/browser/ <SSH_USER>@<VPS_IPV4>:/var/www/vhosts/hosting3m.com/httpdocs/
```
Read the list: only site files (`index.html`, `404.html`, route folders, hashed `chunk-*.js`, `main-*.js`, `styles-*.css`, `fonts/`,
`images/`, `favicon*`, `apple-touch-icon.png`, `sitemap.xml`, `robots.txt`). Lines for `webcard/` or `g/` mean something is wrong: stop.
New files overwrite old ones with the same name (for example the old `index.html`, `politica-de-privacidad/index.html`);
Sitejet files that have no equivalent stay where they are (there is **no `--delete`**).

### 2.3 Real run, only after you confirm the dry run **[laptop]**
```sh
rsync -av --no-owner --no-group \
  dist/hosting3m-site/browser/ <SSH_USER>@<VPS_IPV4>:/var/www/vhosts/hosting3m.com/httpdocs/
```
Ownership **[servidor]** (compare with `ls -ln`; only if new files are not owned by the domain's system user):
```sh
ls -ln /var/www/vhosts/hosting3m.com/httpdocs | head
chown -R <PLESK_SYS_USER>:psacln /var/www/vhosts/hosting3m.com/httpdocs      # ownership only, nothing is removed
```
Verify the copy against the build checksums **[laptop]** then **[servidor]**:
```sh
scp /tmp/prod-sha.txt <SSH_USER>@<VPS_IPV4>:/tmp/
ssh <SSH_USER>@<VPS_IPV4> 'cd /var/www/vhosts/hosting3m.com/httpdocs && sha256sum -c /tmp/prod-sha.txt | grep -v ": OK$"; echo "check finished"'
```
Expected: no line other than `check finished`.

### 2.4 Rollback **[servidor]**
Use it when a smoke test in section 7 fails and cannot be fixed in minutes. It restores the backup over the docroot, still without deleting:
```sh
STAMP=<the-stamp-from-2.1>
rsync -avn /root/backups/hosting3m-docroot-$STAMP/ /var/www/vhosts/hosting3m.com/httpdocs/     # dry run first, read it
rsync -av  /root/backups/hosting3m-docroot-$STAMP/ /var/www/vhosts/hosting3m.com/httpdocs/
```
Then: restore the nginx directives you saved in 2.1 (Plesk > Additional nginx directives), purge the Cloudflare cache (section 3.1) and
repeat the first three checks of section 7 against the old site.
Notes: files that did not exist before the cutover (new hashed chunks, `fonts/`, `images/`) stay in place; they are harmless because the
restored `index.html` does not reference them. Removing them is a separate, deliberate step with its own backup and is **not** part of
this runbook. Plesk's own backup (Tools & Settings > Backup Manager) is an extra safety net if you prefer it.

---

## 3. Cloudflare and headers

### 3.1 Purge the cache after the deploy **[laptop]** (dashboard)
Cloudflare > hosting3m.com > Caching > Configuration > **Purge Cache** > *Purge Everything* (the site is small; do it once per release).
Why: unhashed files (`favicon.ico`, `index.html`, `sitemap.xml`, `robots.txt`, `apple-touch-icon.png`, images) can be served stale; the
beta served an old `favicon.ico` after the logo change. Targeted alternative: purge by URL for `/`, `/favicon.ico`, `/favicon-32.png`,
`/favicon-48.png`, `/apple-touch-icon.png`, `/sitemap.xml`, `/robots.txt` and the six page URLs.
API form (optional; keep the token in an environment variable, never in a file or a chat):
```sh
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' --data '{"purge_everything":true}'
```
Verify the new file is served (the logo favicon is ~7.9 kB): `curl -sI https://hosting3m.com/favicon.ico | grep -iE 'content-length|cf-cache-status|etag'`.

### 3.2 Zone checks **[laptop]** (dashboard, read first, change only what is wrong)
- **SSL/TLS > Overview:** mode **Full (strict)** (the origin has a valid Plesk certificate). *Flexible* causes redirect loops; *Full* without strict accepts bad certificates.
- **SSL/TLS > Edge Certificates:** *Always Use HTTPS* on. Do **not** enable HSTS yet; enable it only after 48 h of clean monitoring (section 9), and start with a short max-age.
- **Rules > Page Rules / Redirect Rules / Cache Rules / Transform Rules:** list them. Remove or disable any rule left from the Sitejet era
  that redirects, caches `/*`, rewrites paths, adds headers or forces a different host. Do not delete a rule you do not recognise: disable it and note it.
- **DNS:** `hosting3m.com` and `www` proxied to the VPS; the `beta` record stays (beta is private by `noindex`). Decide how `www` behaves
  (recommended: 301 to the apex). Check it in 3.4.
- **Speed/optimization:** Brotli on. *Rocket Loader* and *Auto Minify* **off** (they rewrite scripts and can break the CSP and hydration).
- **WAF/Bot settings:** the contact endpoint is on `n8n.hosting3m.com`, not on this zone; make sure no rule blocks `challenges.cloudflare.com` traffic.

### 3.3 Turnstile allows the production hostname **[laptop]** (dashboard)
Cloudflare > Turnstile > the widget with sitekey `0x4AAAAAACaIUH9TvGOgcFq7` > Hostname Management: both `hosting3m.com` and
`beta.hosting3m.com` must be listed. (No new secret: the secret key stays in the n8n container as `CLOUDFREE_SECRET_KEY`.)
Proof: in section 7 the widget renders on `https://hosting3m.com` without error `110200`.

### 3.4 Redirect and host checks **[laptop]**
```sh
curl -sI http://hosting3m.com/        | grep -iE '^HTTP|^location'       # 301 -> https://hosting3m.com/
curl -sI https://www.hosting3m.com/   | grep -iE '^HTTP|^location'       # decide: 301 -> https://hosting3m.com/ (or the host you chose)
curl -sI https://hosting3m.com/       | grep -iE '^HTTP|^server|^cf-cache-status'
```

---

## 4. SEO migration

### 4.1 Inventory of the old URLs **[laptop]**
Sources: `~/hosting3m-snapshot` (copy of the live Sitejet site, includes its `sitemap.xml`) and `~/h3m-old-site` (an earlier single-page draft;
its links are a subset). Regenerate the list at any time:
```sh
cat ~/hosting3m-snapshot/sitemap.xml | grep -o '<loc>[^<]*</loc>' | sed 's/<[^>]*>//g'
grep -rhoE 'href="/[^"#]*"' ~/hosting3m-snapshot ~/h3m-old-site --include=*.html | sort -u
find ~/hosting3m-snapshot -maxdepth 2 -name 'index.html' | sed 's#.*/hosting3m-snapshot##'
```
Also run the live site's own sitemap and Search Console > Pages (indexed URLs) so nothing indexed is missed.
Note: the old `sitemap.xml` lists relative `<loc>` values (one is empty), so Google probably never used it; the new one has absolute URLs.

### 4.2 URL map (old -> new)

| Old URL (Sitejet) | New route | Action | Where |
|---|---|---|---|
| `/` | `/` | same URL | n/a |
| `/portfolio` | `/portfolio` | same URL, new content | n/a |
| `/fjpimienta` | `/fjpimienta` | same URL, new content | n/a |
| `/politica-de-privacidad` | `/politica-de-privacidad` | same URL | n/a |
| `/condiciones-de-servicio` | `/condiciones-de-servicio` | same URL | n/a |
| `/eliminardatosusuarios` | `/eliminardatosusuarios` | same URL | n/a |
| `/privacy` | `/politica-de-privacidad` | **301** | `nginx-legacy-redirects.conf` |
| `/news` | `/` | **301** (the home has a news section, `#noticias`; Google ignores fragments, so the target is `/`) | `nginx-legacy-redirects.conf` |
| `/noticias-elemento` | `/` | **301** | `nginx-legacy-redirects.conf` |
| `/noticias-elemento/blog-post-1` ... `blog-post-6` | `/` | **301** (the six posts were empty builder placeholders: "Blog Post N") | `nginx-legacy-redirects.conf` |
| `/noticias/1406506303.xml` (RSS) | none | **410 Gone** (feed retired) | `nginx-legacy-redirects.conf` |
| `/webcard/*`, `/g/*` | untouched | **no rule**: Sitejet asset folders, must keep answering as today | never add rules |
| any other path | n/a | real **404** with the site's page (`404.html`) | `error_page 404 /404.html` |

Decisions to confirm (they are assumptions in the redirects file): `/news` -> `/` and the blog posts -> `/`. If you prefer a dedicated
news page later, change the targets then; a 301 to `/` is the safe default today.

### 4.3 Install and verify the redirects **[servidor]** (Plesk) then **[laptop]**
Paste `docs/nginx-legacy-redirects.conf` and `docs/nginx-security-headers.conf` into the production domain's *Additional nginx directives*
(Plesk validates the syntax on save; **Proxy mode must be OFF**; do not define `location /`). Do **not** paste `nginx-beta-only.conf`.
```sh
for p in privacy news noticias-elemento noticias-elemento/blog-post-1 noticias-elemento/blog-post-6; do
  printf '%s -> ' "/$p"; curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "https://hosting3m.com/$p"; done
curl -s -o /dev/null -w '/noticias/1406506303.xml -> %{http_code}\n' https://hosting3m.com/noticias/1406506303.xml     # 410
curl -s -o /dev/null -w '/no-existe -> %{http_code}\n' https://hosting3m.com/no-existe                                 # 404
for p in "" portfolio fjpimienta politica-de-privacidad condiciones-de-servicio eliminardatosusuarios; do
  printf '%s -> ' "/$p"; curl -s -o /dev/null -w '%{http_code}\n' "https://hosting3m.com/$p"; done                       # all 200
curl -s -o /dev/null -w '/webcard/ -> %{http_code}\n' https://hosting3m.com/webcard/                                    # same as before the cutover (403 was the old answer)
```

### 4.4 Sitemap, robots, canonical **[laptop]**
```sh
curl -s https://hosting3m.com/sitemap.xml | grep -o '<loc>[^<]*</loc>'                                   # six URLs
curl -s https://hosting3m.com/sitemap.xml | grep -o '<loc>[^<]*</loc>' | grep -vc '^<loc>https://hosting3m.com/'   # must print 0: no beta., www. or relative URL
curl -s https://hosting3m.com/robots.txt                                           # Allow: / and Sitemap: https://hosting3m.com/sitemap.xml
for p in "" portfolio fjpimienta; do curl -s "https://hosting3m.com/$p" | grep -o '<link rel="canonical"[^>]*>'; done   # https://hosting3m.com/...
curl -s https://hosting3m.com/ | grep -ic 'name="robots"'                          # must be 0: no robots meta tag
```
If any new route is added later, add it to `public/sitemap.xml` before the release.

### 4.5 Google Search Console **[laptop]** (browser)
1. Add the property **hosting3m.com** (Domain property, verified with a DNS TXT record in Cloudflare) or the URL-prefix property `https://hosting3m.com/`.
2. Sitemaps > add `https://hosting3m.com/sitemap.xml` > Submit. Status must become *Success* with 6 discovered URLs.
3. URL Inspection > `https://hosting3m.com/` > *Test live URL* > *Request indexing* (repeat for `/portfolio` and `/fjpimienta`).
4. After 48 h: Pages report: look for *Not found (404)*, *Page with redirect* and *Excluded by noindex*. The last one must be empty.
5. Rich results: test `https://hosting3m.com/` in the Rich Results Test (LocalBusiness; address and hours are present).
6. Do not use *Removals* for the old URLs: the 301/410 rules handle them.

---

## 5. Legal texts (privacy, cookies, terms, data deletion)

Pages: `src/app/pages/legal/privacy.ts` (privacy), `terms.ts` (terms), `deletion.ts` (data deletion). **There is no separate cookies page.**
What exists today is the Sitejet text migrated verbatim (dates 30/08/2025 and 29/08/2025), **not** lawyer-reviewed.

Checklist (owner + lawyer):
- [ ] Replace the text of the three pages with the lawyer-reviewed version, with the real publication date in "Última actualización".
- [ ] **Cookies / analytics:** at the time of writing `privacy.ts` does **not** mention cookies or Google Analytics, yet the cookie banner links
  to it. The reviewed text must describe: GA4 (measurement id in `core/site.config.ts`) loaded only after "Aceptar", Consent Mode v2 with all signals
  denied by default, only `analytics_storage` granted, how to change the choice ("Preferencias de cookies" in the footer), Cloudflare Turnstile on the form,
  and the retention period. Either put it inside the privacy page or add a cookies page (then add the route, the sitemap entry and a footer link).
- [ ] The legal entity (`Francisco Jesus Perez Pimienta`), address and hours come from `src/app/core/business.ts`; make the reviewed text consistent with them.
- [ ] Data deletion page: the contact channel and response time stated there must be the ones you can honour.

**Build guard (already added):** `scripts/check-legal-markers.mjs` (+ `check-legal-markers.test.mjs`, run in CI). Same style as `check-todo`:
a **production** build fails while the output contains `[VERIFICAR]`, `[DECIDIR]`, `[REVISAR]` or `[FECHA DE PUBLICACIÓN]` (case-insensitive,
optional detail inside the brackets, e.g. `[VERIFICAR: domicilio]`); beta/development only warn. While drafting, put those markers in the legal
components so nobody can ship an unreviewed paragraph by accident. Check by hand **[laptop]**:
```sh
node projects/hosting3m-site/scripts/check-legal-markers.mjs dist/hosting3m-site/browser fail ; echo "exit=$?"     # 0 = clean
node --test projects/hosting3m-site/scripts/check-legal-markers.test.mjs
```

---

## 6. Catalog (plans and prices)

The site shows prices from `POST https://n8n.hosting3m.com/webhook/v6/plans`: prerendered from `src/app/data/plans-snapshot.json` and refreshed once in the browser.
No price is written in templates or data files.

1. Refresh the snapshot from the production API **[laptop]** and review it:
   ```sh
   cd hosting3m-workspace
   node projects/hosting3m-site/scripts/fetch-plans.mjs        # prints: plans snapshot: N plan(s) written ... / unchanged / keeping the committed snapshot
   git diff --stat projects/hosting3m-site/src/app/data/plans-snapshot.json
   curl -s -X POST https://n8n.hosting3m.com/webhook/v6/plans -H 'Content-Type: application/json' -d '{}' | python3 -m json.tool | head -40
   ```
   The script never fails the build: on a network error or an empty answer it keeps the committed snapshot. **Read its message**: "keeping the committed snapshot" means you
   did **not** get fresh data. Check in the API output that every plan is the one you intend to publish (name, `price_amount`, `managed_amount`, `tax_included`, `valid_until`, `price_checked_at`).
2. Commit it **in its own chore commit**, with explicit paths, before building the release:
   ```sh
   git add hosting3m-workspace/projects/hosting3m-site/src/app/data/plans-snapshot.json
   git commit -m "chore(hosting3m-site): refresh the plans snapshot from the production API"
   ```
3. Build (section 1). Prices are now in the prerendered HTML:
   ```sh
   grep -o '\$[0-9][0-9,]*\(\.[0-9][0-9]\)\?' dist/hosting3m-site/browser/index.html | sort -u
   ```
4. **After the deploy**, verify on the live site **[laptop]**: the same amounts as the API output (jq version: `... | jq -r '.[] | [.plan_key,.price_amount,.managed_amount,.tax_included] | @tsv'`),
   "MXN / año + IVA" vs "IVA incluido" wording, the Autoadministrado / Administrado toggle, "Precios vigentes al <date>", and the "Desde ..." line of the selector.
5. Plans whose `valid_until` has passed disappear from the API by themselves; the snapshot would still contain them until refreshed, so refresh it for every release.

---

## 7. Smoke tests after the deploy **[laptop]** (browser with DevTools open, plus curl)

Use a private window with cleared site data. Keep Console and Network visible.

1. **Pages:** `/`, `/portfolio`, `/fjpimienta`, `/politica-de-privacidad`, `/condiciones-de-servicio`, `/eliminardatosusuarios` open directly (no 404); `/no-existe` shows the site's 404 page with status 404.
2. **Cookie banner and Consent Mode:**
   - Fresh profile: the banner appears; Network has **no** `googletagmanager.com` / `google-analytics.com` request and `document.cookie` has no `_ga*`.
   - **Rechazar:** still no `gtag/js`; reload: banner stays closed.
   - Clear site data > **Aceptar**: `gtag/js?id=G-MVJRDZ7TD8` loads and a `g/collect` request appears; footer link **Preferencias de cookies** reopens the banner and takes focus.
   - Console: `dataLayer` starts with `consent default` (all four signals `denied`) then `consent update` with only `analytics_storage: granted`.
3. **Contact form (real submissions use the `PRUEBA BETA` convention of the beta runbook, section 7, adapted to `PRUEBA PROD`, so they can be marked `status='test'` later; never DELETE):**
   - Empty submit: inline errors, nothing sent. Turnstile renders (no error `110200`).
   - Valid submit with a normal service: success message in the status region; request `POST /webhook/v6/contact` -> 200 `{success:true}` with `Access-Control-Allow-Origin: https://hosting3m.com`; the email arrives; the row appears in `contact_requests` (`id_company = 1`).
   - **Demo-request services:** from `/` (Míralo en acción) click *Pedir demo del ERP hotelero* and *Pedir demo del Agro ERP*, and *Pedir demo* on `/portfolio`: the page scrolls to the form, the select shows `ERP hotelero (solicitud de demo)` / `Agro ERP (solicitud de demo)`, the message is prefilled, an edited message is not overwritten, and the submit succeeds (the server accepts the service text; check it in the stored row).
   - Selector `01 Elige` and each `Cotizar <plan>` button preselect the matching service. After success: no validation errors visible, Turnstile has a fresh token.
4. **WhatsApp:** header, hero, contact section and the floating button open `https://wa.me/5219993902625?text=...` with the prefilled message; "Cotiza por WhatsApp" on a quote-only plan too.
5. **Structured data:**
   ```sh
   curl -s https://hosting3m.com/ | python3 -c "import sys,re,json; h=sys.stdin.read(); j=json.loads(re.search(r'<script id=\"jsonld-site\"[^>]*>(.*?)</script>',h,re.S).group(1)); b=[n for n in j['@graph'] if n['@type']=='LocalBusiness'][0]; print(b['address'], b['openingHours'], b['image'])"
   ```
   then the Rich Results Test (4.5) on the live URL. Also `og:image` / `twitter:image` (1200x630, absolute `https://hosting3m.com/images/og-image.jpg`) with a social debugger.
6. **PageSpeed mobile:** https://pagespeed.web.dev/ on `https://hosting3m.com/` (3 runs). Reference from the local Lighthouse runs: performance 93-96, accessibility 100, SEO 100, CLS 0, LCP 1.6-1.9 s
   (the 1.2 s target was **not** met in the simulated profile; record the real-network numbers here: ______). Check the LCP element is the hero image and `fetchpriority=high` is present.
7. **Mobile menu:** at 390 px the hamburger opens and closes (`aria-expanded`), Escape closes it and returns focus, each link scrolls to its section, no horizontal scroll.
8. **Headers:** `curl -sI https://hosting3m.com/ | grep -iE 'content-security|x-robots|nosniff|referrer|permissions|x-frame'` (no `x-robots-tag`, see section 8.1).
9. **Fonts and images:** Network shows `fonts/*.woff2` from `hosting3m.com` (no `fonts.googleapis.com`), `images/hero-440.webp` on mobile, `logo-112.webp`, favicon from the new logo.

---

## 8. Indexing headers and CSP

### 8.1 `X-Robots-Tag`: noindex on beta, **absent** on production **[laptop]**
Beta keeps `X-Robots-Tag: noindex, nofollow, noarchive` (from `nginx-beta-only.conf`); the production vhost must not send it (never paste that file there).
```sh
echo "== beta (must show the header)"
curl -sI https://beta.hosting3m.com/ | grep -i '^x-robots-tag'          # x-robots-tag: noindex, nofollow, noarchive
echo "== production (must print nothing)"
curl -sI https://hosting3m.com/ | grep -i '^x-robots-tag' || echo "OK: no x-robots-tag on production"
curl -sI https://hosting3m.com/robots.txt | grep -i '^x-robots-tag' || echo "OK"
```
Run this **before** and **after** the cutover and again after any nginx change. If production shows the header, remove the line from the production directives (or check
Cloudflare Transform Rules for a response-header rule), then repeat. A `noindex` header on production silently removes the site from Google.

### 8.2 CSP: enforce only after beta shows zero violations
Rollout order: beta Report-Only (already pasted) > zero violations > production **Report-Only** or enforcing > monitor.
1. **[laptop]** On beta, with DevTools Console filtered by "Content Security Policy" and "Report-Only", visit every page: `/`, `/portfolio`, `/fjpimienta`, the three legal pages, `/no-existe`.
2. On `/` run the flows that load third parties: Turnstile (scroll to the form), **Aceptar** (GA4), submit the form, switch the three tabs of *Míralo en acción*, toggle a plan's mode.
3. **Zero** `Refused to ...` / `[Report Only] Refused to ...` lines on every page. Any line means: fix the policy (`docs/nginx-security-headers.conf`, one origin at a time, only what is strictly necessary) and repeat.
4. Quick automated pass **[laptop]**: `curl -s https://beta.hosting3m.com/ | grep -ciE '<style|style="| on[a-z]+="'` must print 0 (the build emits no inline style or handler; `type="application/json"` data blocks are fine).
5. Only then use the enforcing line (the commented `Content-Security-Policy` in `nginx-security-headers.conf`) on production; never keep Report-Only and enforcing at the same time.
6. After enabling: repeat section 7 items 2-3 (they are the ones that load Google and Cloudflare scripts). Rollback = put the Report-Only line back (Plesk directives are the only thing to change).
Note: HSTS is **not** part of this cutover (see 3.2).

---

## 9. Monitoring and the 48-hour watch list

Deploy time = T0. Someone checks at T0+1 h, +4 h, +24 h and +48 h (more often during support hours).

| What | Where / command | Healthy | Act when |
|---|---|---|---|
| Contact workflow runs | n8n > Executions > `v6/contact` | each real submission is a success; no failed run | a failed run answers HTTP 200 with an empty body and the visitor sees an error: fix and follow up with the visitor |
| New leads stored | `contact_requests`, `id_company = 1` (via your normal read-only access) | rows match the emails received | emails without rows or rows without emails |
| Global error alerts | the alert channel of the Global Error Handler | silence | any alert from `v6/contact`, `v6/news`, `v6/plans` |
| Catalog endpoint | `curl -s -o /dev/null -w '%{http_code}\n' -X POST https://n8n.hosting3m.com/webhook/v6/plans -H 'Content-Type: application/json' -d '{}'` | 200 (the page keeps its prerendered prices if it fails) | 503 or timeouts |
| Origin access log **[servidor]** | Plesk: Websites & Domains > hosting3m.com > Logs, or `tail -f /var/www/vhosts/system/hosting3m.com/logs/access_ssl_log` (confirm the path) | few 404s | 404 bursts on old URLs: add a redirect to the URL map |
| 404 count **[servidor]** | `grep -c '" 404 ' /var/www/vhosts/system/hosting3m.com/logs/access_ssl_log` | low and stable | growth after T0 |
| Origin error log **[servidor]** | `tail -n 50 /var/www/vhosts/system/hosting3m.com/logs/error_log` | quiet | nginx or file-permission errors |
| Cloudflare Analytics | dashboard > Analytics & Logs | 2xx dominates, no 5xx spike | 5xx or a sudden drop in requests: check DNS/SSL mode |
| Turnstile | dashboard > Turnstile > the widget | solve rate normal | many failures: check hostnames and ad-blockers |
| Search Console | Pages, Sitemaps, Core Web Vitals | sitemap *Success*, no *noindex* exclusions | any *Excluded by noindex* (see 8.1) |
| Uptime | any external monitor on `https://hosting3m.com/` (1-5 min) | up | down more than one check |
| Web vitals | PageSpeed mobile at T0+24 h and T0+48 h | within the section 7 numbers | LCP regression |
| GA4 | Realtime, only visitors who pressed Aceptar | events arrive after consent | events before consent (must never happen) |
| Cookie / consent regression | repeat section 7 item 2 at T0+24 h | unchanged | any `gtag` request without Aceptar: treat as an incident |

**Rollback triggers:** contact form failing for real visitors, `x-robots-tag` on production, a CSP block of Turnstile or the form, wrong prices on the live page, legal text issue.
Rollback = 2.4 + restore the saved nginx directives + purge Cloudflare (3.1) + repeat the first checks of section 7.

**Day-2 follow-ups (not part of the cutover):** HSTS after a clean 48 h; remove superseded hashed files with their own backup; delete the beta records if no longer needed (`beta-runbook.md` section 9);
re-measure LCP on real traffic.

---

## 10. Cutover order (summary)

1. Section 0 gate. 2. Build (1). 3. Backup (2.1). 4. Dry run (2.2) and your go. 5. Real rsync + ownership + checksum (2.3).
6. nginx directives: redirects + security headers, **no** `nginx-beta-only.conf` (4.3, 8.2). 7. Purge Cloudflare (3.1). 8. Header and redirect checks (3.4, 4.3, 8.1).
9. Smoke tests (7). 10. Search Console (4.5). 11. Watch list for 48 h (9).

## 11. What could not be verified from the repository
- The real docroot path, nginx log paths and Plesk screens (confirm on the server).
- Cloudflare zone settings (SSL mode, rules, Turnstile hostnames): read them in the dashboard.
- The lawyer-reviewed legal text (not in the repo) and the real-network PageSpeed numbers.
- Which URLs Google has indexed (Search Console > Pages).
