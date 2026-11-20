# n8n v6 public workflows: hosting3m.com site

Sanitized exports of the two public webhooks used by the `hosting3m-site` Angular app.

| File | Workflow | Webhook |
|------|----------|---------|
| [`02-leads-contact/v6/contact.json`](02-leads-contact/v6/contact.json) | `v6/contact` | `POST /webhook/v6/contact` |
| [`03-rag-news-intelligence/v6/news.json`](03-rag-news-intelligence/v6/news.json) | `v6/news` | `POST /webhook/v6/news` |

Base URL: `https://n8n.hosting3m.com/webhook`. Both endpoints are public (no JWT). The browser never calls
`genera-token` or `/crud/...`.

## Sanitization applied to these exports

- Credential ids are `REPLACE_ME` (names are kept as hints). Re-select the Postgres and SMTP credentials after importing.
- `meta.instanceId`, every `webhookId` and `pinData` were removed. Node logic, parameters and connections are unchanged.
- No secret is stored in the JSON: the Turnstile secret is read from the n8n environment variable `CLOUDFREE_SECRET_KEY`.
- The internal copy address of the `SendMailContact` node (`ccEmail`) is `REPLACE_ME@example.com`; the real copy address is
  configured in n8n and must be set again after importing.
- The workflow `id`, `versionId` and `settings.errorWorkflow` were left as exported. Adjust `errorWorkflow` if the target
  instance has a different error handler.

## `POST /webhook/v6/contact`

Request: `Content-Type: application/json`.

| Field | Required | Server limit | Notes |
|-------|----------|--------------|-------|
| `names` | yes | 100 | |
| `lastname` | yes | 100 | |
| `middlename` | no | 100 | |
| `email` | yes | 150 | Lower-cased, must look like an email |
| `message` | yes | 2000 | |
| `phone` | no | 30 | |
| `service` | no | 60 | |
| `cf-turnstile-response` | yes | n/a | Turnstile token |
| `empresa` | must be empty | 50 | Honeypot: any value makes the request invalid |

Control characters are replaced by spaces, values are trimmed and truncated. The tenant is fixed in the workflow
(`id_company = 1`); no tenant id is accepted from the client.

| Status | Body | Meaning |
|--------|------|---------|
| 200 | `{"success": true, "mensaje": "..."}` | Stored in `contact_requests`; the visitor and `contacto@` were emailed |
| 400 | `{"mensaje": "Datos invalidos"}` | Missing required field, invalid email or honeypot filled |
| 401 | `{"mensaje": "Acceso denegado"}` | Turnstile verification failed |

Order of checks: Turnstile first (401), then validation (400). If a node after validation fails (database or SMTP),
n8n answers HTTP 200 with an empty body, so clients must treat only `success === true` as success.

## `POST /webhook/v6/news`

Request body: `{}`. Response: HTTP 200 with a JSON array of at most 6 items
`{title, url, source, image, published_at}` from `news_articles` where `is_active = true`, newest first. The array is
`[]` when there are no rows. Clients must validate and escape every value.

## CORS rule

Set it on the Webhook node: **Options > Allowed Origins (CORS)**. The value is a single string of origins separated by
commas, with **no spaces**:

```
https://hosting3m.com,https://beta.hosting3m.com
```

Do not add a fixed `Access-Control-Allow-Origin` response header: it would override the per-request origin match and
break one of the sites. The extra response headers in the exports (`Allow-Methods`, `Allow-Headers`,
`Allow-Credentials`) are kept as they are. Do not add `localhost` or other origins to production.

## Turnstile server-side validation

`Validate CloudFlare` sends `POST https://challenges.cloudflare.com/turnstile/v0/siteverify` (form-urlencoded) with:

- `secret`: `{{$env["CLOUDFREE_SECRET_KEY"]}}`, set only in the n8n container environment, never in the repo or the browser.
- `response`: the `cf-turnstile-response` field of the request.

`Success CloudFlare` continues only when the answer has `success: true`; otherwise `Respond Denegate` returns 401.
Tokens are single use, so the widget must be reset after every submit. The widget's allowed hostnames in Cloudflare
must include every site that renders it (`hosting3m.com`, `beta.hosting3m.com`). The public sitekey lives in the
Angular app; the secret does not.

## Import

Follow the n8n 2.x runbook in the repository root `CLAUDE.md` (back up, compare by fingerprint, import from the editor,
Save, Publish, re-download and compare). Do not use `n8n import:workflow`.
