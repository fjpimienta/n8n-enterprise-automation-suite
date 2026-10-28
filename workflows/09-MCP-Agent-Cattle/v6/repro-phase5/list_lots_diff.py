#!/usr/bin/env python3
"""Phase 5 - proves that the change to the existing tool `list_lots` is ADDITIVE.

`list_lots` now returns two new keys per row (lot_id, production_unit_id). This script writes ONE read-only SQL file that runs the OLD query and
the NEW query for one company and one member's e-mail and prints:  rows_old, rows_new, only_in_old (must be 0), only_in_new (must be 0, compared
on the three old columns upp / lote / animales), and how many NEW rows have a NULL lot_id (a production unit without lots: expected, not an error).

The generated SQL is plain SELECTs. THE SQL IT GENERATES IS UNTESTED until you run it on LOCAL first; this script itself only builds text.

Usage:
  python3 list_lots_diff.py --tenant 3 --email <a member of that company> [--old-ref develop | --old-file <export.json>] > list_lots_diff.sql
  psql -v ON_ERROR_STOP=1 -X -f list_lots_diff.sql
  (--old-ref reads the MCP export from git; once the change is merged into develop use --old-file with the export taken from the live n8n BEFORE the import.)
"""
import argparse, json, os, re, subprocess, sys

V6 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = 'workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json'


def query_of(doc):
    n = [x for x in doc['nodes'] if x['name'] == 'list_lots']
    assert len(n) == 1
    return n[0]['parameters']['query']


def bind(q, tenant, email):
    assert '$1' in q and '$2' in q
    return q.replace('$1', "'%d'" % tenant).replace('$2', "'%s'" % email.replace("'", "''"))


def strip_order(q):
    q = q.strip().rstrip(';')
    i = q.rfind('ORDER BY')
    assert i > 0
    return q[:i].rstrip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tenant', type=int, required=True)
    ap.add_argument('--email', required=True)
    ap.add_argument('--old-ref', default='develop')
    ap.add_argument('--old-file')
    a = ap.parse_args()
    if a.old_file:
        old = json.load(open(a.old_file, encoding='utf-8'))
        if isinstance(old, list):
            old = old[0]
    else:
        old = json.loads(subprocess.check_output(['git', '-C', V6, 'show', '%s:%s' % (a.old_ref, REL)]))
    new = json.load(open(os.path.join(V6, 'v6_MCP_Server_Cattle.json'), encoding='utf-8'))
    qo, qn = strip_order(bind(query_of(old), a.tenant, a.email)), strip_order(bind(query_of(new), a.tenant, a.email))
    if qo == qn:
        sys.exit('the old and the new query are identical: nothing to compare (is --old-ref already the new version? use --old-file)')
    print('-- list_lots_diff.sql  (UNTESTED; read-only; company %d)' % a.tenant)
    print('WITH o AS (\n%s\n), n AS (\n%s\n)' % (qo, qn))
    print("""SELECT 'rows_old' AS what, count(*)::text AS value FROM o
UNION ALL SELECT 'rows_new', count(*)::text FROM n
UNION ALL SELECT 'only_in_old (must be 0)', count(*)::text FROM (SELECT upp, lote, animales FROM o EXCEPT SELECT upp, lote, animales FROM n) x
UNION ALL SELECT 'only_in_new (must be 0)', count(*)::text FROM (SELECT upp, lote, animales FROM n EXCEPT SELECT upp, lote, animales FROM o) y
UNION ALL SELECT 'new rows with NULL lot_id (a UPP without lots; expected)', count(*)::text FROM n WHERE lot_id IS NULL
UNION ALL SELECT 'new rows with NULL production_unit_id (must be 0)', count(*)::text FROM n WHERE production_unit_id IS NULL;""")


if __name__ == '__main__':
    main()
