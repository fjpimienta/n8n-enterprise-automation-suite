#!/usr/bin/env python3
"""108_gateway_tests.py: negative and isolation tests of migration 108 against the REAL v6/CRUD gateway of a LOCAL n8n.

LOCAL ONLY, synthetic data only (108_gateway_setup.sql creates two fictitious companies GW108 A / B and fictitious users).
It never prints a token or a password, and it never touches a company other than the two fictitious ones.
Prerequisites (see 108_RUNBOOK.md, "Gateway tests"): 108_gateway_setup.sql applied, 108_palpation_views.sql applied, LOCAL n8n up with the
v6/CRUD workflow active. If the gateway is not reachable the script REPORTS it and exits 2: it does not improvise.

Usage: python3 -I 108_gateway_tests.py [--base URL] [--login URL] [--container n8n-enterprise-db] [--db hosting3m_db]
"""
import argparse, json, subprocess, sys, urllib.request, urllib.error

PW = 'SyntheticPw-108'          # synthetic password of the synthetic users (setup SQL stores its SHA-256)
ap = argparse.ArgumentParser()
ap.add_argument('--base', default='http://127.0.0.1:5678/webhook/586606bc-e1df-4c02-bf37-10e0a87d4bfd/crud/v6')
ap.add_argument('--login', default='http://127.0.0.1:5678/webhook/v3/genera-token')
ap.add_argument('--container', default='n8n-enterprise-db')
ap.add_argument('--db', default='hosting3m_db')
ap.add_argument('--after-rollback', action='store_true',
                help='only check that both models deny every role after 108_rollback.sql was applied (no seeding)')
args = ap.parse_args()
if 'localhost' not in args.base and '127.0.0.1' not in args.base:
    sys.exit('ABORT: this script only runs against a LOCAL gateway.')


def sql(q):
    out = subprocess.run(['docker', 'exec', '-i', args.container, 'psql', '-X', '-A', '-t', '-U', 'n8n_user', '-d', args.db, '-c', q],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit('DB error: ' + out.stderr.strip()[:200])
    return out.stdout.strip()


def call(url, body, headers=None, timeout=60):
    data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method='POST', headers={'Content-Type': 'application/json', **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            code = r.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        code = e.code
    except Exception as e:           # gateway down / unreachable
        return None, str(e)
    try:
        return code, json.loads(raw) if raw.strip() else None
    except ValueError:
        return code, raw


# Environment guard: the herd of company 5 exists only in production. This script inserts data (bulk events): never run it there.
if sql("SELECT (EXISTS (SELECT 1 FROM public.companys WHERE id_company = 5) OR EXISTS (SELECT 1 FROM public.cattle_livestock WHERE tenant_id = 5))") != 'f':
    sys.exit('ABORT: this database looks like production (company 5 or animals of company 5 exist, or the check failed). LOCAL databases only.')

ids = sql("SELECT string_agg(company_name || '=' || id_company, ',' ORDER BY company_name) FROM companys WHERE company_name IN ('GW108 Company A','GW108 Company B')")
m = dict(p.split('=') for p in ids.split(',')) if ids else {}
if len(m) != 2:
    sys.exit('ABORT: run 108_gateway_setup.sql first (the two GW108 companies were not found).')
A, B = m['GW108 Company A'], m['GW108 Company B']
if sql("SELECT to_regclass('public.vw_palpation_events') IS NOT NULL AND (SELECT count(*) FROM crud_models WHERE model_name IN ('vw_palpation_events','vw_palpation_herd'))=2") != 't':
    sys.exit('ABORT: apply 108_palpation_views.sql in this LOCAL database first.')

code, body = call(args.base + '/vw_palpation_events', {'operation': 'getall'})
if code is None:
    print('GATEWAY NOT AVAILABLE:', body)
    sys.exit(2)

tokens = {}
# jwt-service limits logins (20 per 15 minutes per address): log in only the users the selected mode needs.
for who in (('admin-a', 'editor-a') if args.after_rollback else ('admin-a', 'editor-a', 'cust-a', 'admin-b')):
    cid = B if who == 'admin-b' else A
    code, r = call(args.login, {'user': f'gw108-{who}@example.invalid', 'pass': PW, 'system_id': 'agro_erp', 'id_company': int(cid)})
    tok = None
    d = r
    for _ in range(3):                      # the login answer wraps the payload twice: {data: {data: {token}}}
        if isinstance(d, dict) and isinstance(d.get('token'), str):
            tok = d['token']
            break
        d = d.get('data') if isinstance(d, dict) else None
    if not tok:
        print(f'LOGIN FAILED for {who} (HTTP {code}); cannot continue.')
        sys.exit(2)
    tokens[who] = tok

if args.after_rollback:
    # After 108_rollback.sql both models must deny every role (allowed_ops '{}', roles NONE): 403 and no rows, for getall and getone.
    res = []
    for who in ('admin-a', 'editor-a'):
        for model in ('/vw_palpation_events', '/vw_palpation_herd'):
            for op in ({'operation': 'getall'}, {'operation': 'getone', 'id': '00000000-0000-0000-0000-000000000000'}):
                hd = {'Authorization': 'Bearer ' + tokens[who], 'x-tenant-id': str(A)}
                c, r = call(args.base + model, op, hd)
                ok = c == 403 and not (isinstance(r, dict) and isinstance(r.get('data'), list) and any(isinstance(x, dict) and x for x in r['data']))
                res.append(ok)
                print(('PASS  ' if ok else 'FAIL  ') + f"after rollback: {who} {op['operation']} {model[1:]} -> 403, no rows  [HTTP {c}, code={r.get('code') if isinstance(r, dict) else None}]")
    print(f'\n{sum(res)}/{len(res)} checks passed')
    sys.exit(0 if all(res) else 1)

ev_b = sql(f"SELECT e.health_log_id FROM vw_palpation_events e WHERE e.id_company = {B} LIMIT 1")
animal_b = sql(f"SELECT livestock_id FROM vw_palpation_herd WHERE id_company = {B} LIMIT 1")

results = []


def h(who, tenant):
    hd = {'Authorization': 'Bearer ' + tokens[who]}
    if tenant is not None:
        hd['x-tenant-id'] = str(tenant)
    return hd


def rows(r):
    d = r.get('data') if isinstance(r, dict) else None
    return [x for x in (d if isinstance(d, list) else []) if isinstance(x, dict) and x]   # data:[{}] is an empty collection


def check(name, ok, detail):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + name + '  [' + detail + ']')


def summarize(code, r):
    if isinstance(r, dict):
        return f"HTTP {code}, error={r.get('error')}, code={r.get('code')}, rows={len(rows(r))}"
    return f"HTTP {code}, body={'empty' if not r else 'non-JSON'}"


E, HERD = '/vw_palpation_events', '/vw_palpation_herd'
GA = {'operation': 'getall'}

# 1. no token
c, r = call(args.base + E, GA)
check('no token -> denied (401)', c == 401, summarize(c, r))
# 2. valid token, NO x-tenant-id header
c, r = call(args.base + E, GA, h('admin-a', None))
check('token without x-tenant-id -> 403 and no rows', c == 403 and not rows(r), summarize(c, r))
# 3. member of A asks for company B
c, r = call(args.base + E, GA, h('admin-a', B))
check('foreign company header -> 403 and no rows', c == 403 and not rows(r), summarize(c, r))
c, r = call(args.base + HERD, GA, h('admin-a', B))
check('foreign company header on the herd model -> 403 and no rows', c == 403 and not rows(r), summarize(c, r))
# 4. admin A, own company: only company A rows
c, r = call(args.base + E, GA, h('admin-a', A))
rs = rows(r)
check('own company -> only company A rows (3)', c == 200 and len(rs) == 3 and all(str(x.get('id_company')) == A for x in rs), summarize(c, r))
# 5. client-supplied filter for company B is overridden by the verified header
for payload in ({'operation': 'getall', 'filter': {'id_company': int(B)}},
                {'operation': 'getall', 'fields': {'id_company': int(B)}},
                {'operation': 'getall', 'id_company': int(B), 'tenant_id': int(B)}):
    c, r = call(args.base + E, payload, h('admin-a', A))
    rs = rows(r)
    check('body asks for company B (' + ','.join(payload.keys() - {'operation'}) + ') -> still only A', c == 200 and all(str(x.get('id_company')) == A for x in rs) and len(rs) == 3, summarize(c, r))
# 6. herd model, admin A
c, r = call(args.base + HERD, GA, h('admin-a', A))
rs = rows(r)
check('herd model -> only company A animals (3)', c == 200 and len(rs) == 3 and all(str(x.get('id_company')) == A for x in rs), summarize(c, r))
# 7. getone of a company B event / animal with company A header
c, r = call(args.base + E, {'operation': 'getone', 'health_log_id': ev_b}, h('admin-a', A))
check('getone of an event of B with header A -> empty', c == 200 and not rows(r) and not (isinstance(r, dict) and isinstance(r.get('data'), dict) and r['data'].get('health_log_id')), summarize(c, r))
c, r = call(args.base + HERD, {'operation': 'getone', 'livestock_id': animal_b}, h('admin-a', A))
check('getone of an animal of B with header A -> empty', c == 200 and not rows(r) and not (isinstance(r, dict) and isinstance(r.get('data'), dict) and r['data'].get('livestock_id')), summarize(c, r))
# 8. writes denied
for op, extra in (('insert', {'fields': {'health_log_id': '00000000-0000-0000-0000-000000000000'}}),
                  ('update', {'health_log_id': '00000000-0000-0000-0000-000000000000', 'fields': {'result': 'VACÍA'}}),
                  ('delete', {'health_log_id': '00000000-0000-0000-0000-000000000000'})):
    c, r = call(args.base + E, {'operation': op, **extra}, h('admin-a', A))
    check(f'{op} by ADMIN -> 403', c == 403, summarize(c, r))
c, r = call(args.base + HERD, {'operation': 'insert', 'fields': {'livestock_id': '00000000-0000-0000-0000-000000000000'}}, h('admin-a', A))
check('insert on the herd model by ADMIN -> 403', c == 403, summarize(c, r))
# 9. roles
c, r = call(args.base + E, GA, h('editor-a', A))
check('EDITOR of A -> 3 rows of A', c == 200 and len(rows(r)) == 3 and all(str(x.get('id_company')) == A for x in rows(r)), summarize(c, r))
c, r = call(args.base + HERD, GA, h('editor-a', A))
check('EDITOR of A on the herd model -> 3 rows of A', c == 200 and len(rows(r)) == 3, summarize(c, r))
c, r = call(args.base + E, GA, h('cust-a', A))
check('CUSTOMER of A -> 403 and no rows', c == 403 and not rows(r), summarize(c, r))
c, r = call(args.base + HERD, GA, h('cust-a', A))
check('CUSTOMER of A on the herd model -> 403 and no rows', c == 403 and not rows(r), summarize(c, r))
# 10. admin B only sees B
c, r = call(args.base + E, GA, h('admin-b', B))
check('ADMIN of B -> only the 2 rows of B', c == 200 and len(rows(r)) == 2 and all(str(x.get('id_company')) == B for x in rows(r)), summarize(c, r))
# 11. strange sort_by: clean error, no data
for bad in ('created_at; DROP TABLE companys', 'id_company) --', '"x"', 'nonexistent_col'):
    c, r = call(args.base + E, {'operation': 'getall', 'sort_by': bad}, h('admin-a', A))
    check(f'sort_by {bad!r} -> no data', not rows(r), summarize(c, r))
alive = sql("SELECT to_regclass('public.companys') IS NOT NULL")
check('the strange sort_by did not damage anything (companys still exists)', alive == 't', 'to_regclass check')
# 12. pagination limit equal to the number of rows (the client treats rows == limit as truncated)
c, r = call(args.base + E, {'operation': 'getall', 'limit': 2}, h('admin-a', A))
check('limit 2 over 3 rows -> exactly 2 rows (truncation visible: rows == limit)', c == 200 and len(rows(r)) == 2, summarize(c, r))
# 13. the 1500 default limit: seed 1500 synthetic extra events for company A, expect exactly 1500 back while 1503 exist
sql(f"INSERT INTO cattle_health_logs (livestock_id, event_type, event_date, medicines_json) "
    f"SELECT (SELECT id FROM cattle_livestock WHERE tenant_id = {A} ORDER BY rfid_siniiga LIMIT 1), 'PALPACION', '2026-11-11 08:00', '{{\"result\":\"VACIA\",\"gw108_bulk\":\"1\"}}'::jsonb "
    f"FROM generate_series(1, 1500)")
total = sql(f"SELECT count(*) FROM vw_palpation_events WHERE id_company = {A}")
c, r = call(args.base + E, GA, h('admin-a', A))
check(f'default limit: {total} rows exist, the gateway returns exactly 1500 (client must show "truncated")', c == 200 and len(rows(r)) == 1500 and int(total) == 1503, summarize(c, r) + f', db_rows={total}')
c, r = call(args.base + E, {'operation': 'getall', 'limit': 2000}, h('admin-a', A))
check('limit 2000 -> all 1503 rows, all of company A', c == 200 and len(rows(r)) == 1503 and all(str(x.get('id_company')) == A for x in rows(r)), summarize(c, r))

print(f'\n{sum(results)}/{len(results)} checks passed')
sys.exit(0 if all(results) else 1)
