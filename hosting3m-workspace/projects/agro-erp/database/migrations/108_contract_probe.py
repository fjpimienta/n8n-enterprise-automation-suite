#!/usr/bin/env python3
"""108_contract_probe.py: READ-ONLY contract probe of the palpation views in production. It prints the SHAPE of the data only.

What it prints, and nothing else:
  - per model: the number of rows;
  - per field: the set of JSON types seen (null, boolean, number, string);
  - for event_date, last_event_date and created_at: only the time part of the text (for example "T06:00:00.000Z"), or
    "(date only)" when there is none, or "(unexpected format)" when the text is neither. The date itself is never printed;
  - the distinct values of category and current_status with the number of animals that carry each one (categories and statuses are
    vocabulary, not herd data).
It never prints a response body, a row, an identifier (livestock_id, health_log_id, rfid, fire number, brand) or the token.

Rules (same as 108_prod_checks.py): token from the environment (PALP_TOKEN), never an argument; only `getall` is sent; https is
mandatory; --company only accepts 3 (the test company); honest User-Agent "hosting3m-108-prod-check/1.0"; a 403 that is not the gateway's
own JSON denial stops the probe with exit 3.

Usage:
  read -rs PALP_TOKEN; export PALP_TOKEN
  python3 -I 108_contract_probe.py --base https://<n8n-host>/webhook/<webhook-id>/crud/v6
  unset PALP_TOKEN

Exit codes: 0 probe done, 2 cannot run, 3 stopped (a 403 blocked before the gateway, or a non-200 answer).
"""
import argparse, collections, json, os, re, sys, urllib.request, urllib.error

USER_AGENT = 'hosting3m-108-prod-check/1.0'
PAGE = 1500
MAX_PAGES = 10
TIME_FIELDS = ('event_date', 'last_event_date', 'created_at')
TIME_PART = re.compile(r'^\d{4}-\d{2}-\d{2}(T.*)$')
DATE_ONLY = re.compile(r'^\d{4}-\d{2}-\d{2}$')

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True, help='gateway base URL ending in /crud/v6 (no default on purpose)')
ap.add_argument('--company', default='3', choices=['3'], help='company the token belongs to: only 3 (test company)')
args = ap.parse_args()

token = os.environ.get('PALP_TOKEN', '')
if not token:
    sys.exit('Cannot run: set PALP_TOKEN in the environment (never as an argument).')
if not args.base.startswith('https://'):
    sys.exit('Cannot run: --base must be an https:// URL.')


def post(model, offset):
    """One getall page. Returns (status, content_type, parsed_json_or_None, gateway_403). The body is never printed."""
    headers = {'Content-Type': 'application/json', 'Accept': 'application/json',
               'Authorization': 'Bearer ' + token, 'User-Agent': USER_AGENT,
               'x-tenant-id': str(args.company)}
    body = {'operation': 'getall', 'sort_by': 'health_log_id' if model == 'vw_palpation_events' else 'livestock_id',
            'limit': PAGE, 'offset': offset}
    req = urllib.request.Request(f'{args.base}/{model}', data=json.dumps(body).encode(), method='POST', headers=headers)
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
    gateway_403 = code == 403 and ctype.split(';')[0].strip().lower() == 'application/json' \
        and isinstance(j, dict) and j.get('error') is True and j.get('status') == 403
    return code, ctype, j, gateway_403


def real_rows(j):
    d = j.get('data') if isinstance(j, dict) else None
    return [r for r in (d if isinstance(d, list) else []) if isinstance(r, dict) and r]


def jtype(v):
    if v is None: return 'null'
    if isinstance(v, bool): return 'boolean'
    if isinstance(v, (int, float)): return 'number'
    if isinstance(v, str): return 'string'
    return type(v).__name__


def time_part(v):
    if v is None:
        return 'null'
    if not isinstance(v, str):
        return f'(not text: {jtype(v)})'
    m = TIME_PART.match(v)
    if m:
        return m.group(1)
    if DATE_ONLY.match(v):
        return '(date only)'
    return '(unexpected format)'


def read_all(model):
    rows = []
    for page in range(MAX_PAGES):
        code, ctype, j, gw403 = post(model, page * PAGE)
        if code == 403 and not gw403:
            print(f'STOP  {model}: blocked before the gateway (HTTP 403, content-type={ctype.split(";")[0] or "-"}). Nothing else was read.')
            sys.exit(3)
        if code != 200:
            print(f'STOP  {model}: HTTP {code} (gateway denial: {gw403}). Nothing else was read.')
            sys.exit(3)
        got = real_rows(j)
        rows.extend(got)
        if len(got) < PAGE:
            return rows, False
    return rows, True


print(f'User-Agent: {USER_AGENT}')
events, ev_truncated = read_all('vw_palpation_events')
herd, hd_truncated = read_all('vw_palpation_herd')

print(f'\n== rows: vw_palpation_events = {len(events)}{" (truncated at the page cap)" if ev_truncated else ""}; '
      f'vw_palpation_herd = {len(herd)}{" (truncated at the page cap)" if hd_truncated else ""}')

for label, rows in (('vw_palpation_events', events), ('vw_palpation_herd', herd)):
    types = collections.OrderedDict()
    for r in rows:
        for k, v in r.items():
            types.setdefault(k, set()).add(jtype(v))
    print(f'\n== JSON types by field: {label}')
    for k, ts in types.items():
        print(f'   {k:24} {"|".join(sorted(ts))}')

print('\n== time part of the date and timestamp fields (the date itself is never printed)')
for label, rows in (('vw_palpation_events', events), ('vw_palpation_herd', herd)):
    seen = collections.Counter()
    for r in rows:
        for k in TIME_FIELDS:
            if k in r:
                seen[(k, time_part(r.get(k)))] += 1
    print(f'   {label}:')
    for (k, part), n in sorted(seen.items()):
        print(f'      {k:18} {part:22} {n}')

print('\n== herd vocabulary: category and current_status, number of animals (no identifiers)')
cats = collections.Counter(str(r.get('category')) for r in herd)
stats = collections.Counter(str(r.get('current_status')) for r in herd)
print('   category:')
for v, n in sorted(cats.items()):
    print(f'      {v:24} {n}')
print('   current_status:')
for v, n in sorted(stats.items()):
    print(f'      {v:24} {n}')
