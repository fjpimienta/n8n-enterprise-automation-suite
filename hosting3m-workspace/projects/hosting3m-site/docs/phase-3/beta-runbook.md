# Beta runbook: https://beta.hosting3m.com

You run every step; Claude edits no server, no n8n, no Cloudflare. Placeholders: `<VPS_IPV4>`, `<DIST_REPO>`.
Nothing here deletes anything on production. The beta stores **real** contact requests (see "Test data").

## 0. Preconditions
- PR of phases 1 to 3 merged to `develop`, CI green (the CI runs the `beta` build and the unit tests).
- Build **off the VPS** (your workstation or CI), never with `--max-old-space-size=4096` on the 2 vCPU / 3.8 GB VPS.

## 1. Build the beta artifact (workstation)
```sh
cd hosting3m-workspace
npm ci --legacy-peer-deps
node projects/hosting3m-site/scripts/build.mjs --configuration beta
```
The guard prints the pending `TODO_*` tokens as a warning (expected on beta; a `production` build must fail).
Output: `dist/hosting3m-site/browser/`. Keep its checksum for later comparison:
```sh
(cd dist/hosting3m-site/browser && find . -type f | sort | xargs sha256sum) > /tmp/beta-sha.txt
```

## 2. (a) Create `beta.hosting3m.com`

### 2.1 Cloudflare (DNS)
Single-level name: the free Universal SSL certificate covers `*.hosting3m.com`, not `*.beta.hosting3m.com`.
1. Cloudflare dashboard > `hosting3m.com` > **DNS** > **Add record**.
2. Type `A`, Name `beta`, IPv4 `<VPS_IPV4>` (the same origin IP as `hosting3m.com`), **Proxy status: Proxied** (orange cloud), TTL Auto. Save.
3. **SSL/TLS > Overview**: keep the mode already used by `hosting3m.com` (it should be **Full (strict)**). Do not lower it.

### 2.2 Plesk (subdomain and certificate)
1. **Websites & Domains > hosting3m.com > Add Subdomain**: subdomain name `beta`, document root `beta.hosting3m.com` (Plesk default). Leave PHP off if it is not needed.
2. **Hosting & DNS > Apache & nginx Settings** of `beta.hosting3m.com`: **Proxy mode OFF** and "Serve static files directly by nginx" ON.
3. Certificate (pick the method that matches the main domain, so Full (strict) keeps working):
   - **Let's Encrypt in Plesk:** while issuing, set the `beta` record to **DNS only** (grey cloud), issue the certificate from **SSL/TLS Certificates**, then switch the record back to **Proxied**. Or:
   - **Cloudflare Origin CA certificate** for `beta.hosting3m.com` installed in Plesk (same one used by the main domain, if it is a wildcard/multi-name origin certificate).
4. Paste the nginx directives (section 6) in **Additional nginx directives** of the beta domain.
5. Verify (nothing deployed yet, so a 403/404 from the empty docroot is fine):
   ```sh
   curl -sI https://beta.hosting3m.com/ | head -5     # TLS handshake OK, "server: cloudflare"
   ```

## 3. (b) n8n: allow `https://beta.hosting3m.com` without removing `https://hosting3m.com`

Two workflows: **`v6/contact`** (path `v6/contact`) and **`v6/news`** (path `v6/news`).
Current symptom (verified from a browser on a different origin): the preflight answers
`Access-Control-Allow-Origin: https://hosting3m.com`, so any other origin is blocked.

> The v6 exports are **not in this repo** (only v4 is: `workflows/02-leads-contact/v4`, `workflows/03-rag-news-intelligence/v4`).
> The edits below follow the v4 pattern, where CORS lives in **three places**. Open each v6 workflow and look for all three;
> the node names in v6 may differ from v4 (`Webhook Contact`, `Webhook Noticias`, `Respond to Webhook`).

### 3.0 Backup and fingerprint (per CLAUDE.md workflow runbook, n8n 2.x)
1. Open the workflow in production > **⋯ > Download**; store the file outside the repo and `chmod 600 <file>`.
2. After the change, download again and compare both files by node name, `parameters` and `connections`
   (the snippet in `CLAUDE.md`, "Comparación con `main`"). Only the CORS fields below may differ.
3. Do **not** use `n8n import:workflow` (it deactivates the workflow). Edit in the editor, **Save**, then **Publish**.

### 3.1 Webhook node > Options > **Allowed Origins (CORS)**
Current value: `https://hosting3m.com`
New value (comma separated, no spaces, no wildcard):
```
https://hosting3m.com,https://beta.hosting3m.com
```

### 3.2 Webhook node > Options > **Response Headers**
Typical v4 entries: `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, `Access-Control-Allow-Credentials`, `Access-Control-Allow-Origin`.
A static `Access-Control-Allow-Origin` cannot hold two origins. **Delete only that one entry** (`Access-Control-Allow-Origin: https://hosting3m.com`) on this node; keep the other three. n8n answers the preflight from the Allowed Origins list in 3.1.

### 3.3 Every **Respond to Webhook** node that sets `Access-Control-Allow-Origin` (Options > Response Headers)
This includes the success response and, in v4 news, one with `*`. Replace the static value with an allow-list expression (a fixed list, never a reflected arbitrary origin). Replace `<Webhook node name>` with the real name of the Webhook node of that workflow:
```
={{ ['https://hosting3m.com','https://beta.hosting3m.com'].includes($('<Webhook node name>').first().json.headers.origin) ? $('<Webhook node name>').first().json.headers.origin : 'https://hosting3m.com' }}
```
Also add the header `Vary` = `Origin` on those nodes, so Cloudflare never caches one origin's answer for another.
If a Respond node has `Access-Control-Allow-Origin: *` today, replace it with the same expression (this also tightens news to the two origins).
The error branches (400, 401, 500) must send the same header, otherwise the browser hides the error from the form and shows a generic failure.

### 3.4 Turnstile hostname check inside the contact workflow
Open the node that calls `https://challenges.cloudflare.com/turnstile/v0/siteverify`. If it compares the response `hostname` with `hosting3m.com` (an IF/Code node after the HTTP request), add `beta.hosting3m.com` to the accepted values. If it does not check `hostname`, change nothing.

### 3.5 Verify the CORS change (no data is sent; only a preflight)
```sh
for o in https://beta.hosting3m.com https://hosting3m.com https://evil.example; do
  echo "== $o"
  curl -si -X OPTIONS https://n8n.hosting3m.com/webhook/v6/contact \
    -H "Origin: $o" -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type' \
    | grep -i '^access-control-allow-origin'
done
```
Expected: the first two echo their own origin; `https://evil.example` returns **no** `Access-Control-Allow-Origin` (or only `https://hosting3m.com`, never `evil.example` or `*`). Repeat with `/webhook/v6/news`.
The real POST response must carry the header too: this is checked in the browser in section 8 (Network tab > response headers).

## 4. (c) Turnstile: add the hostname to the existing widget
1. Cloudflare dashboard > **Turnstile** > open the widget whose sitekey is `0x4AAAAAACaIUH9TvGOgcFq7`.
2. **Settings > Hostname Management** (hostnames the widget may run on) > **Add** `beta.hosting3m.com`. Keep `hosting3m.com`.
3. Save. The sitekey and the secret key do not change: **no new secret** and nothing to update in n8n.
Verification: the widget renders on the beta form (section 8). Error `110200` ("domain not allowed") means the hostname is missing.

## 5. Deploy to beta with Plesk Git (as agreed: Plesk Git only for beta)
Plesk Git deploys a repository into the docroot, so the beta needs a repository that contains only the built files.
Use a separate private repository `<DIST_REPO>` (for example `hosting3m-site-beta-dist`); it holds no secrets (the Turnstile sitekey is public).
```sh
git clone <DIST_REPO> /tmp/beta-dist && cd /tmp/beta-dist
rsync -a --exclude .git /ABS/PATH/hosting3m-workspace/dist/hosting3m-site/browser/ ./    # no --delete: see note
git add -A && git commit -m "beta build $(date +%F-%H%M)" && git push origin main
```
Note: with no `--delete`, files removed between builds stay in the dist repo. Hashed filenames change every release, so old
chunks accumulate harmlessly; clean the dist repo in a separate, deliberate commit when needed.

Plesk: `beta.hosting3m.com` > **Git** > **Add Repository** > *Remote Git hosting* > `<DIST_REPO>` URL, branch `main`,
deployment mode **Manual**, deploy into the subdomain document root (keep it empty on first use) > **Deploy now**.
(Alternative, same procedure as production: `rsync -avn` dry-run into the beta docroot, review, then without `-n`, never with `--delete`.)

## 6. nginx on the beta domain
Paste in the beta domain's *Additional nginx directives*, in this order:
1. `docs/nginx-legacy-redirects.conf` (301s, 410 for the RSS, `error_page 404`).
2. `docs/nginx-security-headers.conf` (CSP in **Report-Only** first).
3. `docs/nginx-beta-only.conf` (`X-Robots-Tag: noindex`).
Plesk validates the syntax on save; if it reports a duplicate `location`, remove that block and tell me which one.

## 7. Test data (important)
`v6/contact` stores the request in `contact_requests` (company 1) and emails `contacto@hosting3m.com`: beta submissions are **real records and real emails**.
Use an obviously fake identity, for example names `PRUEBA BETA`, message `PRUEBA BETA <date> - ignore`, and tell whoever reads `contacto@` to ignore them.
Cleanup of those rows is yours (database access is outside Claude's scope; take a backup first, per the suite rules).

## 8. Smoke tests on beta
Headers and redirects:
```sh
curl -sI https://beta.hosting3m.com/ | grep -iE 'content-security|x-robots|nosniff|referrer|permissions|x-frame'
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://beta.hosting3m.com/privacy                        # 301 -> /politica-de-privacidad
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://beta.hosting3m.com/noticias-elemento/blog-post-3   # 301 -> /
curl -s -o /dev/null -w '%{http_code}\n' https://beta.hosting3m.com/noticias/1406506303.xml                        # 410
curl -s -o /dev/null -w '%{http_code}\n' https://beta.hosting3m.com/no-existe                                       # 404
curl -s https://beta.hosting3m.com/robots.txt | head -3 ; curl -s https://beta.hosting3m.com/sitemap.xml | head -4
```
In the browser (DevTools open, Console + Network):
1. Home loads; **no CSP violation** in the console (Report-Only lists them as warnings). Fix the policy before enforcing.
2. Cookie banner appears; **Rechazar** => no request to `googletagmanager.com`. Clear site data, **Aceptar** => `gtag/js?id=G-MVJRDZ7TD8` loads.
3. Scroll to the form: Turnstile renders (no `110200`). Submit empty => inline errors. Submit valid test data => success message; the request is `POST /webhook/v6/contact` with the response header `Access-Control-Allow-Origin: https://beta.hosting3m.com`.
4. Check the received email and the `contact_requests` row (then handle them per section 7).
5. News: `POST /webhook/v6/news` returns 200; with `[]` the 3 own cards show.
6. `/politica-de-privacidad`, `/condiciones-de-servicio`, `/eliminardatosusuarios`, `/portfolio`, `/fjpimienta` open directly (no 404).
7. Lighthouse (mobile): LCP < 1.2 s, Accessibility and SEO >= 95.
Then switch the CSP line from Report-Only to enforcing and repeat steps 1 to 3.

## 9. Rollback (beta only; production is untouched)
- **n8n:** open each workflow, **⋯ > Import from file** the backup of 3.0, **Save**, **Publish**; re-download and compare with the backup.
- **Turnstile:** remove `beta.hosting3m.com` from Hostname Management.
- **Site:** Plesk Git > Remove repository, or put back an empty docroot; remove the nginx directives; delete the `beta` DNS record in Cloudflare; remove the subdomain in Plesk. No `rm -rf` is needed anywhere.
- Allowing the beta origin is purely additive: if you only want to close it, remove `https://beta.hosting3m.com` from 3.1 and restore the static header of 3.2/3.3.
