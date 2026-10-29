#!/usr/bin/env python3
"""Phase 5 - adds the 24 tool nodes of repro-phase1..4 to v6_MCP_Server_Cattle.json and wires them to the MCP trigger.

What it changes (and ONLY this):
  1. appends the 24 nodes (phase order) after the existing ones, placed on a grid BELOW the existing nodes;
  2. adds one `ai_tool` connection per new node to the node "MCP Server Cattle";
  3. the existing node `list_lots`: its SQL gains two NEW columns at the END of the select list (lot_id, production_unit_id; additive,
     same tenant filter, no column removed or renamed) and its toolDescription says they are internal (never shown);
  4. the toolDescription (ONLY that parameter) of three more existing nodes:
       register_birth_event        -> prefixed "OBSOLETA: no la uses. Usa register_birth_checked, que NO acepta lot_name ni production_unit_name ..."
       log_palpation_event_batch   -> prefixed "OBSOLETA: no la uses. Usa log_palpation_with_condition."
       log_palpation_event         -> gets the single-animal-with-a-code rule appended
     (their SQL, parameters and everything else stay byte-identical; the proof shows it).
Everything else (the other existing nodes, the trigger, meta, settings, pinData, versionId, active) must stay byte-identical: the
script PROVES it before writing and refuses to write otherwise. Idempotent: if the new nodes are already there it only re-verifies
(to apply a changed script on top of a file that already has the nodes, rebuild from the "before" file: `--baseline <before.json>`).

Run `update_tool_descriptions.py` first (it fixes the descriptions inside the phase files that this script copies).

Usage (from anywhere):
  python3 add_repro_tools.py            # apply and print the proof
  python3 add_repro_tools.py --check    # change nothing; verify the repo file is in the "after" state (built from --ref, default 14dd60c) and print the proof
  python3 add_repro_tools.py --baseline <file>   # build from another "before" file (e.g. the live export) instead of the repo file
"""
import json, os, sys, copy, subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from update_tool_descriptions import SINGLE_RULE   # one source of truth for the sentence

HERE = os.path.dirname(os.path.abspath(__file__))
V6 = os.path.dirname(HERE)
MCP = os.path.join(V6, 'v6_MCP_Server_Cattle.json')
PHASES = [os.path.join(V6, 'repro-phase%d' % p, 'repro_phase%d_tools.json' % p) for p in (1, 2, 3, 4)]
BEFORE_REF = '14dd60c'       # COMMIT_BEFORE_PHASE5 of the runbook: the MCP server export without the 24 nodes
TRIGGER = 'MCP Server Cattle'
GRID_X0, GRID_DX, GRID_PER_ROW, GRID_DY = 1056, 352, 6, 224

LOTS_OLD_SELECT = "SELECT pu.ranch_name AS upp, lot.lot_name AS lote,\n       (SELECT count(*) FROM cattle_livestock l WHERE l.lot_id = lot.id AND l.tenant_id = pu.id_company) AS animales\nFROM production_units pu"
LOTS_NEW_SELECT = "SELECT pu.ranch_name AS upp, lot.lot_name AS lote,\n       (SELECT count(*) FROM cattle_livestock l WHERE l.lot_id = lot.id AND l.tenant_id = pu.id_company) AS animales,\n       lot.id AS lot_id, pu.id AS production_unit_id\nFROM production_units pu"
LOTS_DESC_ADD = (" Cada fila trae también lot_id y production_unit_id (UUID): son INTERNOS, úsalos solo para pasarlos a otra herramienta "
                 "(por ejemplo register_birth_checked) cuando el nombre del lote o de la UPP coincide EXACTO con lo que dijo el usuario; NUNCA los muestres. "
                 "Si el nombre coincide con más de un lote, pregunta cuál. lot_id viene vacío en una UPP sin lotes.")


OBSOLETE = {
    'register_birth_event': ('OBSOLETA: no la uses. Usa register_birth_checked, que NO acepta lot_name ni production_unit_name: solo lot_id y production_unit_id '
                             'tomados de list_lots. Ignora el resto de esta descripción (habla de nombres de lote/UPP que register_birth_checked no tiene).\n\n'),
    'log_palpation_event_batch': 'OBSOLETA: no la uses. Usa log_palpation_with_condition.\n\n',
}
DESC_ONLY = ['register_birth_event', 'log_palpation_event_batch', 'log_palpation_event']     # existing nodes whose ONLY change is toolDescription


def load(path):
    return json.load(open(path, encoding='utf-8'))


def dump(path, d):
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps(d, indent=2, ensure_ascii=False))


def build(before):
    after = copy.deepcopy(before)
    names = {n['name'] for n in after['nodes']}
    new_nodes = []
    for f in PHASES:
        new_nodes += load(f)['nodes']
    assert len(new_nodes) == 24, len(new_nodes)
    assert not (names & {n['name'] for n in new_nodes}), 'a new node name already exists in the MCP server'
    assert not ({n['id'] for n in after['nodes']} & {n['id'] for n in new_nodes}), 'a new node id already exists'
    y0 = max(n['position'][1] for n in after['nodes']) + GRID_DY
    for i, n in enumerate(new_nodes):
        n = copy.deepcopy(n)
        n['position'] = [GRID_X0 + (i % GRID_PER_ROW) * GRID_DX, y0 + (i // GRID_PER_ROW) * GRID_DY]
        after['nodes'].append(n)
        after['connections'][n['name']] = {'ai_tool': [[{'node': TRIGGER, 'type': 'ai_tool', 'index': 0}]]}
    lots = [n for n in after['nodes'] if n['name'] == 'list_lots']
    assert len(lots) == 1
    q = lots[0]['parameters']['query']
    assert q.count(LOTS_OLD_SELECT) == 1, 'list_lots SQL is not the expected one (edited by hand?)'
    lots[0]['parameters']['query'] = q.replace(LOTS_OLD_SELECT, LOTS_NEW_SELECT)
    lots[0]['parameters']['toolDescription'] += LOTS_DESC_ADD
    for n in after['nodes']:
        if n['name'] in OBSOLETE:
            assert not n['parameters']['toolDescription'].startswith('OBSOLETA')
            n['parameters']['toolDescription'] = OBSOLETE[n['name']] + n['parameters']['toolDescription']
        elif n['name'] == 'log_palpation_event':
            assert SINGLE_RULE not in n['parameters']['toolDescription']
            n['parameters']['toolDescription'] += '\n\n' + SINGLE_RULE
    return after


def prove(before, after, out):
    ok = True

    def check(label, cond, detail=''):
        nonlocal ok
        ok = ok and bool(cond)
        out.append('%s  %s%s' % ('OK  ' if cond else 'FAIL', label, ('  ' + detail) if detail else ''))

    bn = {n['name']: n for n in before['nodes']}
    an = {n['name']: n for n in after['nodes']}
    check('node count', len(after['nodes']) == len(before['nodes']) + 24, '%d -> %d' % (len(before['nodes']), len(after['nodes'])))
    check('connection count', len(after['connections']) == len(before['connections']) + 24, '%d -> %d' % (len(before['connections']), len(after['connections'])))
    check('names unique', len(an) == len(after['nodes']))
    check('ids unique', len({n['id'] for n in after['nodes']}) == len(after['nodes']))
    changed = sorted(k for k in bn if bn[k] != an.get(k))
    expected_changed = sorted(['list_lots'] + DESC_ONLY)
    check('existing nodes changed: exactly %s' % json.dumps(expected_changed), changed == expected_changed, str(changed))
    check('removed nodes: none', not (set(bn) - set(an)))
    n_same = sum(1 for k in bn if bn[k] == an.get(k))
    check('the other %d existing nodes (the MCP trigger included) byte-identical' % (len(bn) - len(expected_changed)), n_same == len(bn) - len(expected_changed), '%d identical' % n_same)
    for k in DESC_ONLY:
        b, a = bn[k], an[k]
        same_rest = ({x: y for x, y in b.items() if x != 'parameters'} == {x: y for x, y in a.items() if x != 'parameters'}
                     and {x: y for x, y in b['parameters'].items() if x != 'toolDescription'} == {x: y for x, y in a['parameters'].items() if x != 'toolDescription'})
        db, da = b['parameters']['toolDescription'], a['parameters']['toolDescription']
        grew = (da == OBSOLETE[k] + db) if k in OBSOLETE else (da == db + '\n\n' + SINGLE_RULE)
        check('%s: ONLY toolDescription changed (SQL, parameters, credentials, position untouched) and only by %s' % (k, 'the OBSOLETA prefix' if k in OBSOLETE else 'the appended rule'),
              same_rest and grew)
    unchanged_conn = all(after['connections'].get(k) == v for k, v in before['connections'].items())
    check('existing connections unchanged', unchanged_conn)
    new = [k for k in an if k not in bn]
    check('new nodes are the 24 expected', len(new) == 24)
    check('every new node is connected to the MCP trigger', all(after['connections'].get(k) == {'ai_tool': [[{'node': TRIGGER, 'type': 'ai_tool', 'index': 0}]]} for k in new))
    check('every connection source and target exists', all(k in an and all(t['node'] in an for br in v.values() for lst in br for t in lst) for k, v in after['connections'].items()))
    for key in ('name', 'pinData', 'active', 'settings', 'versionId', 'meta'):
        check('top-level "%s" unchanged' % key, before.get(key) == after.get(key))
    check('new nodes use the same credential as the existing tools',
          {json.dumps(an[k].get('credentials'), sort_keys=True) for k in new} == {json.dumps(bn['find_calf_by_dam'].get('credentials'), sort_keys=True)})
    q_b, q_a = bn['list_lots']['parameters']['query'], an['list_lots']['parameters']['query']
    check('list_lots SQL: only the select list grew (2 new keys at the end)', q_a.replace(',\n       lot.id AS lot_id, pu.id AS production_unit_id', '') == q_b)
    check('list_lots other parameters unchanged', {k: v for k, v in bn['list_lots']['parameters'].items() if k not in ('query', 'toolDescription')} ==
          {k: v for k, v in an['list_lots']['parameters'].items() if k not in ('query', 'toolDescription')})
    check('list_lots toolDescription only grew at the end', an['list_lots']['parameters']['toolDescription'].startswith(bn['list_lots']['parameters']['toolDescription']))
    check('JSON round-trips', json.loads(json.dumps(after)) == after)
    return ok


def main(argv):
    check_only = '--check' in argv
    base_path = argv[argv.index('--baseline') + 1] if '--baseline' in argv else MCP
    repo = load(MCP)
    out = []
    if check_only:
        # the repo file must already be the "after" state: rebuild from the committed "before" and compare
        # the "before" file is the one at COMMIT_BEFORE_PHASE5 (develop already holds the new nodes since phase 5 was merged)
        ref = argv[argv.index('--ref') + 1] if '--ref' in argv else BEFORE_REF
        try:
            raw = subprocess.check_output(['git', '-C', V6, 'show', '%s:workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json' % ref], stderr=subprocess.DEVNULL)
            before = json.loads(raw)
        except Exception:
            print('cannot read the "before" file from git (ref %s); use --ref <commit> or --baseline <file>' % ref)
            return 2
        after = repo
        try:
            out.append('%s  the repo file equals what this script builds from the "before" file and the phase files' % ('OK  ' if build(before) == repo else 'FAIL'))
            if build(before) != repo:
                print('\n'.join(out)); print('\nPROOF FAILED: the repo file is not what the script builds'); return 1
        except AssertionError as e:
            print('cannot rebuild:', e); return 1
    else:
        before = load(base_path)
        if any(n['name'] == 'register_birth_checked' for n in before['nodes']):
            print('the new nodes are already in this file: nothing to do (use --check for the proof)')
            return 0
        after = build(before)
    ok = prove(before, after, out)
    print('\n'.join(out))
    if not ok:
        print('\nPROOF FAILED: nothing written')
        return 1
    if not check_only:
        dump(MCP, after)
        print('\nwritten: %s' % MCP)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
