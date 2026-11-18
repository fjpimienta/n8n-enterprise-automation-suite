#!/usr/bin/env python3
"""108_prod_checks.py: READ-ONLY production checks of migration 108 (runbook, Part 3). Prints COUNTS ONLY.

Run by the owner AFTER Parts 1 and 2 of 108_RUNBOOK.md. It sends only `getall` reads to the two palpation models. It writes nothing, seeds nothing, and never
prints a response body, a row, an identifier or the token. The token comes from the environment (PALP_TOKEN), never from an argument or a file.

Who may run it: a user that is a member of company 3 ("Rancho El Palomar", test company) and is NOT a member of company 5. Company 5 data is never read:
the request with the header of company 5 must be denied (403); if it is not, the script does not even look at the answer, it stops and tells you.

Usage (the token is typed hidden, so it never reaches an argument, the shell history or the screen):
  read -rs PALP_TOKEN; export PALP_TOKEN
  python3 -I 108_prod_checks.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6 [--foreign 5] [--expect-herd-rows N]
  unset PALP_TOKEN
--company only accepts 3 (the test company). --expect-herd-rows N (optional) adds one check: vw_palpation_herd must return exactly N rows for company 3
(N = SELECT count(*) FROM cattle_livestock WHERE tenant_id = 3, recounted just before; and fewer than the gateway limit of 1500).
After 108_rollback.sql was applied, the same user must be denied for his own company: add --after-rollback (2 checks, expected 403 on both models).

A 403 counts only when it is the GATEWAY's own denial: application/json, body with error:true and status:403 (v6-crud.json:
"Respond Tenant Forbidden" code TENANT_FORBIDDEN; "Security Validation" code SECURITY_VALIDATION, or no code for a disabled operation).
A 403 of any other shape (text/plain, HTML, a CDN page) was blocked BEFORE the gateway: the script prints FAIL "blocked before the gateway" and exits 3.
A missing token is answered 401 by the gateway ("Respond Denegate"), not 403.

The script identifies itself with User-Agent "hosting3m-108-prod-check/1.0" (it does not impersonate a browser or another client).
A run that produces no new executions in n8n proves nothing: after the run, count the new executions of the workflow in the n8n editor
(expected: one per request that reached the webhook; the 404 for a path without a model, if sent, creates none).

Exit codes: 0 all checks passed, 1 a check failed, 2 cannot run, 3 STOP (a 403 blocked before the gateway, a row of another company, or a foreign company was served).
"""
import argparse, json, os, re, sys, urllib.request, urllib.error

USER_AGENT = 'hosting3m-108-prod-check/1.0'

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True, help='gateway base URL ending in /crud/v6 (no default on purpose)')
ap.add_argument('--company', default='3', choices=['3'], help='company the user belongs to: only 3 (test company) is accepted')
ap.add_argument('--foreign', default='5', help='company the user must NOT belong to (default 5)')
ap.add_argument('--expect-herd-rows', type=int, default=None, metavar='N',
                help='expected number of rows of vw_palpation_herd for the company (one extra PASS/FAIL check)')
ap.add_argument('--after-rollback', action='store_true',
                help='after 108_rollback.sql: only check that getall with the header of --company is denied (403, no rows) on both models')
args = ap.parse_args()

token = os.environ.get('PALP_TOKEN', '')
if not token:
    sys.exit('Cannot run: set PALP_TOKEN in the environment (never as an argument).')
if not args.base.startswith('https://'):
    sys.exit('Cannot run: --base must be an https:// URL.')
if args.company == args.foreign:
    sys.exit('Cannot run: --company and --foreign must differ.')
if args.after_rollback and args.expect_herd_rows is not None:
    sys.exit('Cannot run: --expect-herd-rows does not apply to --after-rollback.')

MODELS = ('vw_palpation_events', 'vw_palpation_herd')
LIMIT = 1500
failures = []


def post(model, tenant):
    """Only `getall` is ever sent. Returns (http_status, parsed_json_or_None, content_type). The body is never printed."""
    headers = {'Content-Type': 'application/json', 'Accept': 'application/json',
               'Authorization': 'Bearer ' + token, 'User-Agent': USER_AGENT}
    if tenant is not None:
        headers['x-tenant-id'] = str(tenant)
    req = urllib.request.Request(f'{args.base}/{model}', data=json.dumps({'operation': 'getall'}).encode(), method='POST', headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw, code, ctype = r.read().decode('utf-8', 'replace'), r.status, (r.headers.get('Content-Type') or '')
    except urllib.error.HTTPError as e:
        raw, code, ctype = e.read().decode('utf-8', 'replace'), e.code, ((e.headers.get('Content-Type') if e.headers else '') or '')
    except Exception as e:
        sys.exit(f'Cannot reach the gateway: {type(e).__name__}')
    try:
        j = json.loads(raw) if raw.strip() else None
    except ValueError:
        j = None
    return code, j, ctype


def rows(j):
    d = j.get('data') if isinstance(j, dict) else None
    return [x for x in (d if isinstance(d, list) else []) if isinstance(x, dict) and x]   # data:[{}] is an empty collection


def gateway_denial(code, ctype, j):
    """True only for the gateway's own JSON 403 (see the module docstring)."""
    is_json = (ctype or '').split(';')[0].strip().lower() == 'application/json'
    return code == 403 and is_json and isinstance(j, dict) and j.get('error') is True and j.get('status') == 403


def gateway_code(j):
    """The gateway's error code, printed only if it is a plain identifier; '-' when the denial carries none."""
    c = j.get('code') if isinstance(j, dict) else None
    return c if isinstance(c, str) and re.fullmatch(r'[A-Z_]{1,40}', c) else '-'


def classify(code, ctype, j):
    if code == 403:
        return 'gateway' if gateway_denial(code, ctype, j) else 'non-gateway'
    return 'json' if (ctype or '').split(';')[0].strip().lower() == 'application/json' else 'non-json'


def stop_if_blocked(name, code, ctype, j):
    """A 403 that is not the gateway's: blocked before the gateway. Nothing after it means anything: stop."""
    if code == 403 and not gateway_denial(code, ctype, j):
        print(f'FAIL  {name}: blocked before the gateway (HTTP 403, class=non-gateway, content-type={(ctype or "-").split(";")[0]}). '
              f'The request did not reach the gateway; the result proves nothing. Stopping.')
        sys.exit(3)


def report(name, ok, counts):
    print(('PASS  ' if ok else 'FAIL  ') + name + '  [' + counts + ']')
    if not ok:
        failures.append(name)


print(f'User-Agent: {USER_AGENT}')

if args.after_rollback:
    for model in MODELS:
        code, j, ctype = post(model, args.company)
        stop_if_blocked(f'{model} after the rollback', code, ctype, j)
        ok = gateway_denial(code, ctype, j) and not rows(j)
        report(f'{model}: after the rollback, header of company {args.company} -> gateway 403, no rows', ok,
               f'http={code}, class={classify(code, ctype, j)}, code={gateway_code(j)}, rows={len(rows(j))}')
    print(f'\n{2 - len(failures)}/2 checks passed')
    sys.exit(0 if not failures else 1)

for model in MODELS:
    # 1. no tenant header -> gateway 403, no rows
    code, j, ctype = post(model, None)
    stop_if_blocked(f'{model} no x-tenant-id', code, ctype, j)
    report(f'{model}: no x-tenant-id -> gateway 403, no rows', gateway_denial(code, ctype, j) and not rows(j),
           f'http={code}, class={classify(code, ctype, j)}, code={gateway_code(j)}, rows={len(rows(j))}')

    # 2. the foreign company -> gateway 403. A 200 means the user belongs to it or the filter failed: do NOT inspect the answer.
    code, j, ctype = post(model, args.foreign)
    if code == 200:
        print(f'STOP  {model}: header of company {args.foreign} was served (HTTP 200). The answer was not inspected. '
              f'Either this user belongs to company {args.foreign} or the gateway is not enforcing membership. Tell the owner; roll back if needed.')
        sys.exit(3)
    stop_if_blocked(f'{model} foreign header', code, ctype, j)
    report(f'{model}: header of company {args.foreign} -> gateway 403, no rows', gateway_denial(code, ctype, j) and not rows(j),
           f'http={code}, class={classify(code, ctype, j)}, code={gateway_code(j)}, rows={len(rows(j))}')

    # 3. own company: rows of any other company must be 0 (counts only; if not 0, stop without showing anything)
    code, j, ctype = post(model, args.company)
    stop_if_blocked(f'{model} own company', code, ctype, j)
    rs = rows(j)
    other = sum(1 for x in rs if str(x.get('id_company')) != str(args.company))
    if other:
        print(f'STOP  {model}: {other} row(s) of another company in the answer for company {args.company}. Content NOT shown. Tell the owner now; roll back (108_rollback.sql).')
        sys.exit(3)
    empty_body = j is None
    report(f'{model}: header of company {args.company} -> 200, rows of other companies = 0',
           code == 200 and not empty_body and (isinstance(j, dict) and j.get('error') is not True),
           f'http={code}, class={classify(code, ctype, j)}, rows={len(rs)}, rows_of_other_companies={other}, truncated={len(rs) >= LIMIT}')
    if len(rs) >= LIMIT:
        print(f'NOTE  {model}: {len(rs)} rows = the gateway limit ({LIMIT}); the list is truncated, not complete.')
    if model == 'vw_palpation_herd' and args.expect_herd_rows is not None:
        report(f'{model}: rows for company {args.company} = {args.expect_herd_rows} (expected)',
               len(rs) == args.expect_herd_rows and len(rs) < LIMIT, f'rows={len(rs)}, expected={args.expect_herd_rows}')

total = 6 + (1 if args.expect_herd_rows is not None else 0)
print(f'\n{total - len(failures)}/{total} checks passed')
sys.exit(0 if not failures else 1)
