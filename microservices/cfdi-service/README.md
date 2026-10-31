# cfdi-service

Small internal HTTP sidecar (Node 20, no framework) that parses CFDI 4.0 "Ingreso" XML, checks the SAT status of a
UUID and stores the original XML. It is **not** exposed to the internet: only n8n on the Docker internal network
calls it. The parser lives in [`lib/cfdi-parser/`](lib/cfdi-parser/README.md) (moved here from `tools/cfdi-parser`).

All endpoints take and return JSON (UTF-8). Every endpoint except `/health` requires the header
`x-internal-token` (constant-time compare against `CFDI_SERVICE_TOKEN`).

| Endpoint | Body | Response |
|---|---|---|
| `GET /health` | – | `{"ok":true}` |
| `POST /parse` | `{"xmlBase64"}` | `uuid, serie, folio, fechaEmision, fechaTimbrado, emisor{rfc,nombre}, receptor{rfc,nombre}, moneda, subtotalCents, descuentoCents, totalCents, traslados[], retenciones[], conceptos[<=20], sourceSha256` (integer cents) |
| `POST /sat-status` | `{"uuid","emisorRfc","receptorRfc","totalCents"}` | `{"status":"VIGENTE"\|"CANCELADO"\|"NO_ENCONTRADO"\|"ERROR"}` |
| `POST /store` | `{"tenantId","xmlBase64","sha256"}` | `{"originalPath":"<tenantId>/<yyyy>/<mm>/<sha256>.xml"}` |

Errors: `422 {"status":"invalid","code":"UPPER_SNAKE"}` (parser codes such as `DOCTYPE_FORBIDDEN`, `NOT_XML`,
`AMOUNTS_MISMATCH`, plus `INVALID_BODY`, `INVALID_TENANT`, `SHA256_MISMATCH`), `401`, `404`, `405`, `409 CONFLICT`
(`/store`: a different file already exists at that path), `413` (body > 7.5 MB), `500`.

## Behaviour worth knowing
- `sourceSha256` is the SHA-256 of the **raw bytes received**, not of re-encoded text. `/store` requires `sha256` to
  equal it. The XML must be valid UTF-8 and start (after an optional BOM) with `<?xml` or `<cfdi:Comprobante`.
- The output never contains the Addenda, Certificado, Sello or raw XML. Receptor `usoCfdi` is dropped on purpose.
- `/sat-status` calls the SAT SOAP service (`Consulta`, 10 s timeout, one retry on timeout/network/5xx). Any
  unexpected `Estado`, timeout or 5xx is `ERROR` (HTTP 200): callers must not treat `ERROR` as "invalid CFDI".
- `/store` writes under `STORAGE_ROOT` (mode 0640, dirs 0750) through a temp file + `link()`, so it never overwrites;
  identical content is a no-op (idempotent), different content is `409`. Year/month come from `fechaEmision`.
- Logs contain only method, route, status, request size and duration. No bodies, RFCs or headers.

## Environment
| Variable | Required | Notes |
|---|---|---|
| `CFDI_SERVICE_TOKEN` | yes | the service exits at startup if unset. Never paste the value in chats or logs |
| `STORAGE_ROOT` | yes | absolute path, outside any web root; must be writable by uid 1000 (`node`) |
| `PORT` | no | default `4100` |

## Docker Compose snippet (for the later deployment piece; not applied)
```yaml
  cfdi-service:
    build: ../microservices/cfdi-service
    restart: unless-stopped
    environment:
      CFDI_SERVICE_TOKEN: ${CFDI_SERVICE_TOKEN}
      STORAGE_ROOT: /data/cfdi
    volumes:
      - cfdi_storage:/data/cfdi      # chown 1000:1000 once, e.g. on first run
    networks:
      - n8n_network                  # same internal network as n8n; no `ports:` on purpose
    read_only: true
    tmpfs: [/tmp]
    security_opt: ["no-new-privileges:true"]
# volumes:
#   cfdi_storage:
```
n8n then calls `http://cfdi-service:4100/...` with the `x-internal-token` header (store the token as an n8n credential,
not inline in workflows). The service needs outbound HTTPS to `consultaqr.facturaelectronica.sat.gob.mx` for `/sat-status`.

## Nginx note
Do **not** add a `location` or upstream for this service: it must stay unreachable from the public vhosts. If a
reverse-proxy rule is ever added, restrict it to the internal network and keep the token check.

## Tests
`npm install && npm test` (node:test, Node >= 20). Fixtures are the sanitized CFDIs in `test/fixtures/`. The SAT call is
always mocked in tests.
