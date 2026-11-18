#!/usr/bin/env python3
"""108_prod_checks.py: READ-ONLY production checks of migration 108 (runbook, Part 3). Prints COUNTS ONLY.

Run by the owner AFTER Parts 1 and 2 of 108_RUNBOOK.md. It sends only `getall` reads to the two palpation models. It writes nothing, seeds nothing, and never
prints a response body, a row, an identifier or the token. The token comes from the environment (PALP_TOKEN), never from an argument or a file.

Who may run it: a user that is a member of company 3 ("Rancho El Palomar", test company) and is NOT a member of company 5. Company 5 data is never read:
the request with the header of company 5 must be denied (403); if it is not, the script does not even look at the answer, it stops and tells you.

Usage (the token is typed hidden, so it never reaches an argument, the shell history or the screen):
  read -rs PALP_TOKEN; export PALP_TOKEN
  python3 -I 108_prod_checks.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6 [--company 3] [--foreign 5]
  unset PALP_TOKEN
After 108_rollback.sql was applied, the same user must be denied for his own company: add --after-rollback (2 checks, expected 403 on both models).

Exit codes: 0 all checks passed, 1 a check failed, 2 cannot run, 3 STOP (a row of another company, or a foreign company was served).
"""
import argparse, json, os, sys, urllib.request, urllib.error

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True, help='gateway base URL ending in /crud/v6 (no default on purpose)')
ap.add_argument('--company', default='3', help='company the user belongs to (default 3, test company)')
ap.add_argument('--foreign', default='5', help='company the user must NOT belong to (default 5)')
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
if args.company == '5':
    sys.exit('Cannot run: company 5 must never be the tested company.')

MODELS = ('vw_palpation_events', 'vw_palpation_herd')
LIMIT = 1500
failures = []


def post(model, tenant):
    """Only `getall` is ever sent. Returns (http_status, parsed_json_or_None). The body is never printed."""
    headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token}
    if tenant is not None:
        headers['x-tenant-id'] = str(tenant)
    req = urllib.request.Request(f'{args.base}/{model}', data=json.dumps({'operation': 'getall'}).encode(), method='POST', headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw, code = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        raw, code = e.read().decode(), e.code
    except Exception as e:
        sys.exit(f'Cannot reach the gateway: {type(e).__name__}')
    try:
        return code, (json.loads(raw) if raw.strip() else None)
    except ValueError:
        return code, None


def rows(j):
    d = j.get('data') if isinstance(j, dict) else None
    return [x for x in (d if isinstance(d, list) else []) if isinstance(x, dict) and x]   # data:[{}] is an empty collection


def report(name, ok, counts):
    print(('PASS  ' if ok else 'FAIL  ') + name + '  [' + counts + ']')
    if not ok:
        failures.append(name)


if args.after_rollback:
    for model in MODELS:
        code, j = post(model, args.company)
        report(f'{model}: after the rollback, header of company {args.company} -> 403, no rows', code == 403 and not rows(j), f'http={code}, rows={len(rows(j))}')
    print(f'\n{2 - len(failures)}/2 checks passed')
    sys.exit(0 if not failures else 1)

for model in MODELS:
    # 1. no tenant header -> 403, no rows
    code, j = post(model, None)
    report(f'{model}: no x-tenant-id -> 403', code == 403 and not rows(j), f'http={code}, rows={len(rows(j))}')

    # 2. the foreign company -> 403. A 200 means the user belongs to it or the filter failed: do NOT inspect the answer.
    code, j = post(model, args.foreign)
    if code == 200:
        print(f'STOP  {model}: header of company {args.foreign} was served (HTTP 200). The answer was not inspected. '
              f'Either this user belongs to company {args.foreign} or the gateway is not enforcing membership. Tell the owner; roll back if needed.')
        sys.exit(3)
    report(f'{model}: header of company {args.foreign} -> 403, no rows', code == 403 and not rows(j), f'http={code}, rows={len(rows(j))}')

    # 3. own company: rows of any other company must be 0 (counts only; if not 0, stop without showing anything)
    code, j = post(model, args.company)
    rs = rows(j)
    other = sum(1 for x in rs if str(x.get('id_company')) != str(args.company))
    if other:
        print(f'STOP  {model}: {other} row(s) of another company in the answer for company {args.company}. Content NOT shown. Tell the owner now; roll back (108_rollback.sql).')
        sys.exit(3)
    empty_body = j is None
    report(f'{model}: header of company {args.company} -> 200, rows of other companies = 0',
           code == 200 and not empty_body and (isinstance(j, dict) and j.get('error') is not True),
           f'http={code}, rows={len(rs)}, rows_of_other_companies={other}, truncated={len(rs) >= LIMIT}')
    if len(rs) >= LIMIT:
        print(f'NOTE  {model}: {len(rs)} rows = the gateway limit ({LIMIT}); the list is truncated, not complete.')

print(f'\n{6 - len(failures)}/6 checks passed')
sys.exit(0 if not failures else 1)
