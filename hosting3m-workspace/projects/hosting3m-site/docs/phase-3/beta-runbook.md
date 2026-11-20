# Beta runbook: https://beta.hosting3m.com

You run every step; Claude edits no server, no n8n, no Cloudflare. Placeholders: `<VPS_IPV4>`, `<SSH_USER>`, `<PLESK_SYS_USER>`, `<DB_CONTAINER>`, `<DB_NAME>`, `<DB_USER>`.
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
The edit is the same in both workflows and only touches their **Webhook node**.

### 3.0 Backup and fingerprint (per CLAUDE.md workflow runbook, n8n 2.x)
1. Open the workflow in production > **⋯ > Download**; store the file outside the repo and `chmod 600 <file>`.
2. After the change, download again and compare both files by node name, `parameters` and `connections`
   (the snippet in `CLAUDE.md`, "Comparación con `main`"). The **only** difference must be in the Webhook node `parameters`
   (the Allowed Origins value and one removed response-header entry).
3. Do **not** use `n8n import:workflow` (it deactivates the workflow). Edit in the editor, **Save**, then **Publish**.

### 3.1 Webhook node > Options > **Allowed Origins (CORS)**
Set it to exactly:
```
https://hosting3m.com, https://beta.hosting3m.com
```
No wildcard. `https://hosting3m.com` stays.

### 3.2 Webhook node > Options > **Response Headers**: delete the fixed `Access-Control-Allow-Origin`
Delete **only** the entry `Access-Control-Allow-Origin: https://hosting3m.com`. It collides with the dynamic header n8n derives
from the Allowed Origins list (3.1), and a fixed value cannot hold two origins. Keep every other entry
(`Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, `Access-Control-Allow-Credentials`, ...) untouched.

### 3.3 Respond to Webhook nodes
`v6/news` has no response headers on its Respond node: nothing to change there.
For `v6/contact`, no edit is planned either. If you find a fixed `Access-Control-Allow-Origin` on any of its Respond nodes,
do **not** edit it: tell me the node name and its value first.

### 3.4 Turnstile hostname check inside the contact workflow
Open the node that calls `https://challenges.cloudflare.com/turnstile/v0/siteverify`. If it compares the response `hostname`
with `hosting3m.com` (an IF/Code node after the HTTP request), add `beta.hosting3m.com` to the accepted values.
If it does not check `hostname`, change nothing.

### 3.5 Verify the CORS change
**Preflight (no data sent)**, for both workflows:
```sh
for path in v6/contact v6/news; do
  for o in https://beta.hosting3m.com https://hosting3m.com https://evil.example; do
    echo "== $path  Origin: $o"
    curl -si -X OPTIONS "https://n8n.hosting3m.com/webhook/$path" \
      -H "Origin: $o" -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type' \
      | grep -i '^access-control-allow-origin'
  done
done
```
Expected: `beta` and `hosting3m.com` each echo **their own** origin (exactly one `Access-Control-Allow-Origin` line per answer);
`https://evil.example` gets no `Access-Control-Allow-Origin` line (never `evil.example`, never `*`).
Two lines or a fixed `https://hosting3m.com` for the beta origin means the entry of 3.2 is still there.

**Real POST**, checking the response headers:
```sh
# news: read-only public endpoint, safe to call with an empty body
curl -si -X POST https://n8n.hosting3m.com/webhook/v6/news \
  -H 'Origin: https://beta.hosting3m.com' -H 'Content-Type: application/json' -d '{}' \
  | grep -iE '^(HTTP/|access-control-allow-origin)'
# contact: an EMPTY body must be rejected before anything is stored or emailed
curl -si -X POST https://n8n.hosting3m.com/webhook/v6/contact \
  -H 'Origin: https://beta.hosting3m.com' -H 'Content-Type: application/json' -d '{}' \
  | grep -iE '^(HTTP/|access-control-allow-origin)'
```
Expected: news `200` with `Access-Control-Allow-Origin: https://beta.hosting3m.com`; contact `400` (or `401`) with the same header
(the browser needs it even on error answers). A `200` from contact with `{}` is **not** expected: stop and tell me, and check
`contact_requests` for a new row before continuing.

## 4. (c) Turnstile: add the hostname to the existing widget
1. Cloudflare dashboard > **Turnstile** > open the widget whose sitekey is `0x4AAAAAACaIUH9TvGOgcFq7`.
2. **Settings > Hostname Management** (hostnames the widget may run on) > **Add** `beta.hosting3m.com`. Keep `hosting3m.com`.
3. Save. The sitekey and the secret key do not change: **no new secret** and nothing to update in n8n.
Verification: the widget renders on the beta form (section 8). Error `110200` ("domain not allowed") means the hostname is missing.

## 5. Deploy to beta with rsync (same procedure as production; no Plesk Git, no `--delete`)
Run from the workstation that built the artifact. The beta docroot is `/var/www/vhosts/hosting3m.com/beta.hosting3m.com`.

1. **Backup on the VPS** (also when the docroot is still empty, to keep the habit and the file name):
   ```sh
   ssh <SSH_USER>@<VPS_IPV4> 'tar -czf /root/backup-beta-$(date +%F-%H%M).tar.gz -C /var/www/vhosts/hosting3m.com beta.hosting3m.com && ls -lh /root/backup-beta-*.tar.gz | tail -1'
   ```
2. **Dry-run** (`-n` writes nothing; there is **no** `--delete` anywhere):
   ```sh
   rsync -avn --no-owner --no-group \
     dist/hosting3m-site/browser/ <SSH_USER>@<VPS_IPV4>:/var/www/vhosts/hosting3m.com/beta.hosting3m.com/
   ```
   Review the list: only site files (`index.html`, `404.html`, route folders, hashed `chunk-*.js`, `main-*.js`, `styles-*.css`, `sitemap.xml`, `robots.txt`, `favicon.ico`).
3. **Real run**, only after you confirm the dry-run:
   ```sh
   rsync -av --no-owner --no-group \
     dist/hosting3m-site/browser/ <SSH_USER>@<VPS_IPV4>:/var/www/vhosts/hosting3m.com/beta.hosting3m.com/
   ```
4. **Ownership:** compare with `ls -ln` of the docroot. If new files are not owned by the subdomain's system user, fix only those paths:
   `ssh <SSH_USER>@<VPS_IPV4> 'chown -R <PLESK_SYS_USER>:psacln /var/www/vhosts/hosting3m.com/beta.hosting3m.com'` (no recursive delete, only ownership).
5. **Verify the copy** against the build checksums of section 1:
   ```sh
   scp /tmp/beta-sha.txt <SSH_USER>@<VPS_IPV4>:/tmp/ && ssh <SSH_USER>@<VPS_IPV4> 'cd /var/www/vhosts/hosting3m.com/beta.hosting3m.com && sha256sum -c /tmp/beta-sha.txt | grep -v ": OK$" ; echo "check finished"'
   ```
   Expected: no line other than `check finished`.

Note: without `--delete`, hashed files from older builds stay on the server (harmless: `index.html` no longer references them).
Removing them is a separate, deliberate step with its own backup; it is not part of this runbook.

## 6. nginx on the beta domain
Paste in the beta domain's *Additional nginx directives*, in this order:
1. `docs/nginx-legacy-redirects.conf` (301s, 410 for the RSS, `error_page 404`).
2. `docs/nginx-security-headers.conf` (CSP in **Report-Only** first).
3. `docs/nginx-beta-only.conf` (`X-Robots-Tag: noindex`).
Plesk validates the syntax on save; if it reports a duplicate `location`, remove that block and tell me which one.

## 7. Test data and cleanup (important)
`v6/contact` stores the request in `contact_requests` (company 1) and emails `contacto@hosting3m.com`: beta submissions are **real records and real emails**.
Every test message **must start with** `PRUEBA BETA` (for example `PRUEBA BETA 2026-11-21 - ignore`), use an obviously fake identity
(names `PRUEBA BETA`), and whoever reads `contacto@` must be told to ignore them.

### Cleanup: mark, never delete
Test rows are **marked**, not deleted. Run it only after the e2e tests are finished. Database access is yours; Claude does not run it.
1. **Confirm the schema** (already verified by the owner: `status` is `varchar(20) NOT NULL DEFAULT 'new'` with no CHECK, so `'test'` is accepted; `id_company` is `integer`, default 1). Re-check only if the table changed:
   ```sh
   docker exec -i <DB_CONTAINER> psql -U <DB_USER> -d <DB_NAME> -c '\d contact_requests'
   ```
   Every statement below is scoped to `id_company = 1` (this site's tenant, fixed on the server), fail-closed.
2. **Backup of the table** (custom format, restricted permissions):
   ```sh
   docker exec <DB_CONTAINER> pg_dump -U <DB_USER> -d <DB_NAME> -t contact_requests -Fc > /root/backup-contact_requests-$(date +%F-%H%M).dump
   chmod 600 /root/backup-contact_requests-*.dump
   ```
3. **Dry-run:** see exactly which rows would change.
   ```sql
   SELECT * FROM contact_requests WHERE message LIKE 'PRUEBA BETA%' AND id_company = 1;
   ```
4. **Update inside a transaction**, check the row count, then commit:
   ```sql
   BEGIN;
   UPDATE contact_requests SET status = 'test' WHERE message LIKE 'PRUEBA BETA%' AND id_company = 1;
   -- the reported count (UPDATE n) must equal the number of rows from step 3
   COMMIT;   -- or ROLLBACK; if the count is not the expected one
   ```
5. **Rollback** (if a wrong row was marked): restore the table from the dump of step 2 (`pg_restore` into a scratch table first and copy the old `status` values back). There is no `DELETE` in this procedure.

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
- **Site:** restore the backup of section 5 into a scratch folder and copy it back without deleting (`mkdir /root/restore-beta && tar -xzf /root/backup-beta-<stamp>.tar.gz -C /root/restore-beta && rsync -av /root/restore-beta/beta.hosting3m.com/ /var/www/vhosts/hosting3m.com/beta.hosting3m.com/`); to close the beta entirely, remove the nginx directives; delete the `beta` DNS record in Cloudflare; remove the subdomain in Plesk. No `rm -rf` is needed anywhere.
- Allowing the beta origin is purely additive: if you only want to close it, remove `https://beta.hosting3m.com` from 3.1 and restore the static header of 3.2/3.3.
