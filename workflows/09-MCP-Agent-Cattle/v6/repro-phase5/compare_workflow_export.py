#!/usr/bin/env python3
"""Phase 5 - compares two n8n workflow exports (e.g. the LIVE export taken from the editor vs the file in the repo).

Reports: node counts, nodes only in one side, nodes whose content differs (and which parameter keys), nodes that only moved (position),
connection differences, and the top-level keys that differ (volatile ones such as versionId / updatedAt are reported as INFO only).
Exit code 0 = nodes and connections are identical (positions may differ), 1 = a real difference, 2 = bad input.

Usage:  python3 compare_workflow_export.py <live_export.json> <repo_file.json>
Used by REPRO_PRODUCTION_RUNBOOK.md before the import (live must equal the repo file as it was on develop) and after it (live must equal the new repo file).
"""
import json, sys

VOLATILE = {'versionId', 'updatedAt', 'createdAt', 'id', 'shared', 'tags', 'triggerCount', 'meta', 'isArchived', 'staticData'}


def load(p):
    try:
        d = json.load(open(p, encoding='utf-8'))
    except Exception as e:
        print('cannot read %s: %s' % (p, e)); sys.exit(2)
    if isinstance(d, list) and len(d) == 1:
        d = d[0]
    if 'nodes' not in d or 'connections' not in d:
        print('%s is not a workflow export' % p); sys.exit(2)
    return d


def main(a_path, b_path):
    a, b = load(a_path), load(b_path)
    an = {n['name']: n for n in a['nodes']}
    bn = {n['name']: n for n in b['nodes']}
    real = 0
    print('nodes: A=%d  B=%d      connections: A=%d  B=%d' % (len(an), len(bn), len(a['connections']), len(b['connections'])))
    only_a, only_b = sorted(set(an) - set(bn)), sorted(set(bn) - set(an))
    if only_a: real += 1; print('ONLY IN A (%d): %s' % (len(only_a), ', '.join(only_a)))
    if only_b: real += 1; print('ONLY IN B (%d): %s' % (len(only_b), ', '.join(only_b)))
    moved, diff = [], []
    for k in sorted(set(an) & set(bn)):
        x, y = dict(an[k]), dict(bn[k])
        px, py = x.pop('position', None), y.pop('position', None)
        if x != y:
            keys = sorted({kk for kk in set(x) | set(y) if x.get(kk) != y.get(kk)})
            sub = []
            if 'parameters' in keys:
                pa, pb = x.get('parameters', {}), y.get('parameters', {})
                sub = sorted({kk for kk in set(pa) | set(pb) if pa.get(kk) != pb.get(kk)})
            diff.append((k, keys, sub))
        elif px != py:
            moved.append(k)
    if diff:
        real += 1
        print('NODES WITH DIFFERENT CONTENT (%d):' % len(diff))
        for k, keys, sub in diff:
            print('  - %s: %s%s' % (k, keys, (' parameters: %s' % sub) if sub else ''))
    if moved: print('info: %d node(s) only moved (position): %s' % (len(moved), ', '.join(moved[:10]) + (' ...' if len(moved) > 10 else '')))
    ca, cb = a['connections'], b['connections']
    cdiff = sorted(k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k))
    if cdiff: real += 1; print('CONNECTIONS DIFFER for (%d): %s' % (len(cdiff), ', '.join(cdiff)))
    top = sorted(k for k in (set(a) | set(b)) - {'nodes', 'connections'} if a.get(k) != b.get(k))
    for k in top:
        if k in VOLATILE: print('info: top-level "%s" differs (volatile)' % k)
        else: real += 1; print('TOP-LEVEL "%s" DIFFERS: A=%s  B=%s' % (k, json.dumps(a.get(k))[:100], json.dumps(b.get(k))[:100]))
    print('RESULT: %s' % ('IDENTICAL (nodes, connections, settings)' if not real else 'DIFFERENT'))
    return 1 if real else 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
