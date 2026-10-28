#!/usr/bin/env python3
"""Offline tests of compare_workflow_export.py on SYNTHETIC workflow exports (no network, no database, no repo workflow is read).
Usage:  python3 test_compare_workflow_export.py          (exit 0 when every test passes)
"""
import copy, json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'compare_workflow_export.py')


def node(name, nid, **extra):
    n = {'id': nid, 'name': name, 'type': 'n8n-nodes-base.set', 'typeVersion': 3, 'position': [100, 200],
         'parameters': {'value': name.lower(), 'other': 1}}
    n.update(extra)
    return n


def conn(src, dst):
    return {src: {'main': [[{'node': dst, 'type': 'main', 'index': 0}]]}}


def base():
    c = {}
    c.update(conn('Trigger', 'Set A'))
    c.update(conn('Set A', 'Set B'))
    return {'name': 'wf', 'active': True, 'settings': {'executionOrder': 'v1'}, 'versionId': 'v-1', 'meta': {'instanceId': 'x'},
            'nodes': [node('Trigger', 'id-t'), node('Set A', 'id-a'), node('Set B', 'id-b')], 'connections': c}


def regen_ids(wf, prefix='new'):
    w = copy.deepcopy(wf)
    for i, n in enumerate(w['nodes']):
        n['id'] = '%s-%d' % (prefix, i)
    return w


class Compare(unittest.TestCase):
    def run_cmp(self, a, b, *flags):
        with tempfile.TemporaryDirectory() as d:
            pa, pb = os.path.join(d, 'a.json'), os.path.join(d, 'b.json')
            for path, data in ((pa, a), (pb, b)):
                with open(path, 'w', encoding='utf-8') as fh:
                    json.dump(data, fh)
            r = subprocess.run([sys.executable, SCRIPT, *flags, pa, pb], capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    # ---- the cases of the brief
    def test_ids_only_is_identical_with_the_info_line(self):
        rc, out = self.run_cmp(base(), regen_ids(base()))
        self.assertEqual(rc, 0, out)
        self.assertIn('RESULT: IDENTICAL', out)
        self.assertIn('info: node ids differ in 3 nodes (volatile)', out)
        self.assertNotIn('DIFFERENT', out)

    def test_changed_parameter_is_different(self):
        b = regen_ids(base()); b['nodes'][1]['parameters']['value'] = 'changed'
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('RESULT: DIFFERENT', out)
        self.assertIn("Set A: ['parameters'] parameters: ['value']", out)

    def test_node_missing_on_one_side_is_different(self):
        b = base(); b['nodes'] = [n for n in b['nodes'] if n['name'] != 'Set B']
        b['connections'].pop('Set A')
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('ONLY IN A (1): Set B', out)
        rc2, out2 = self.run_cmp(b, base())
        self.assertEqual(rc2, 1, out2)
        self.assertIn('ONLY IN B (1): Set B', out2)

    def test_changed_connection_is_different(self):
        b = regen_ids(base()); b['connections'] = conn('Trigger', 'Set A')            # Set A -> Set B removed
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('CONNECTIONS DIFFER for (1): Set A', out)

    def test_renamed_node_is_different(self):
        b = base()
        b['nodes'][2]['name'] = 'Set C'
        b['connections'] = {}
        b['connections'].update(conn('Trigger', 'Set A')); b['connections'].update(conn('Set A', 'Set C'))
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('ONLY IN A (1): Set B', out)
        self.assertIn('ONLY IN B (1): Set C', out)

    def test_strict_ids_with_ids_only_is_different(self):
        rc, out = self.run_cmp(base(), regen_ids(base()), '--strict-ids')
        self.assertEqual(rc, 1, out)
        self.assertIn('RESULT: DIFFERENT', out)
        self.assertIn("['id']", out)
        self.assertNotIn('node ids differ', out)

    def test_position_only_is_identical(self):
        b = base(); b['nodes'][0]['position'] = [999, 999]
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 0, out)
        self.assertIn('RESULT: IDENTICAL', out)
        self.assertIn('only moved (position)', out)
        self.assertNotIn('node ids differ', out)

    # ---- everything else stays strict
    def test_type_typeversion_credentials_disabled_are_strict(self):
        for key, value in (('type', 'n8n-nodes-base.if'), ('typeVersion', 4), ('disabled', True),
                           ('credentials', {'postgres': {'id': 'c-1', 'name': 'Postgres account'}})):
            b = regen_ids(base()); b['nodes'][1][key] = value
            rc, out = self.run_cmp(base(), b)
            self.assertEqual(rc, 1, '%s: %s' % (key, out))
            self.assertIn("'%s'" % key, out)

    def test_credentials_reference_change_is_strict_even_with_same_node_id(self):
        a, b = base(), base()
        a['nodes'][1]['credentials'] = {'postgres': {'id': 'c-1', 'name': 'P'}}
        b['nodes'][1]['credentials'] = {'postgres': {'id': 'c-2', 'name': 'P'}}
        rc, out = self.run_cmp(a, b)
        self.assertEqual(rc, 1, out)

    def test_ids_plus_a_real_change_is_different_and_still_reports_the_ids(self):
        b = regen_ids(base()); b['nodes'][0]['parameters']['other'] = 2
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('node ids differ in 3 nodes', out)
        self.assertIn('RESULT: DIFFERENT', out)

    def test_duplicated_node_names_are_different(self):
        b = base(); b['nodes'].append(node('Set B', 'id-b2'))
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 1, out)
        self.assertIn('DUPLICATE NODE NAME(S) in B: Set B', out)

    def test_connections_are_compared_by_name_not_by_id(self):
        # same node ids, but the connection points at a different NAME: different
        a = base()
        b = base(); b['connections'] = {}
        b['connections'].update(conn('Trigger', 'Set A')); b['connections'].update(conn('Set A', 'Set A'))
        rc, out = self.run_cmp(a, b)
        self.assertEqual(rc, 1, out)

    def test_top_level_settings_difference_is_strict_but_version_id_is_not(self):
        b = regen_ids(base()); b['versionId'] = 'v-2'
        rc, out = self.run_cmp(base(), b)
        self.assertEqual(rc, 0, out)
        self.assertIn('info: top-level "versionId" differs (volatile)', out)
        c = regen_ids(base()); c['settings'] = {'executionOrder': 'v0'}
        rc2, out2 = self.run_cmp(base(), c)
        self.assertEqual(rc2, 1, out2)
        self.assertIn('TOP-LEVEL "settings" DIFFERS', out2)

    def test_no_info_line_when_the_ids_are_equal(self):
        rc, out = self.run_cmp(base(), base())
        self.assertEqual(rc, 0, out)
        self.assertNotIn('node ids differ', out)

    def test_a_workflow_wrapped_in_a_list_is_accepted_and_bad_input_exits_2(self):
        rc, out = self.run_cmp([base()], regen_ids(base()))
        self.assertEqual(rc, 0, out)
        rc2, out2 = self.run_cmp({'nodes': []}, base())
        self.assertEqual(rc2, 2, out2)

    def test_usage_errors_exit_2(self):
        r = subprocess.run([sys.executable, SCRIPT, '--bogus', 'a', 'b'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        r = subprocess.run([sys.executable, SCRIPT, 'only_one.json'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
