// Offline test of the "Build Query" node of v6-crud.json for the call_sp entry sp_register_livestock_panel (migration 102).
// No dependencies, no database, no n8n: it runs the real jsCode of the node with the two upstream nodes stubbed.
// Usage: node workflows/06-dynamic-crud-engine/v6/tests/test_v6_panel_sp.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const wf = JSON.parse(fs.readFileSync(path.resolve(import.meta.dirname, '../v6-crud.json'), 'utf8'));
const code = wf.nodes.find(n => n.name === 'Build Query').parameters.jsCode;

function run(config, body, headers) {
  const nodes = { 'Security Validation': config, WebhookCRUD: { body, headers } };
  const $ = name => ({ first: () => ({ json: nodes[name] }) });
  const req = m => (m === 'crypto' ? crypto : (() => { throw new Error('unexpected require ' + m); })());
  return new Function('$', 'require', code)($, req)[0].json;
}

let pass = 0, fail = 0;
const ok = (c, name) => { if (c) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name); } };

const cfg = { model_name: 'register_livestock_panel', table_name: 'sp_register_livestock_panel', operation: 'call_sp',
  sp_requires_tenant: true, user_email: 'jwt-actor@example.test', user_role: 'EDITOR',
  allowed_fields: ['upp', 'confirmed'] };
const body = { action: 'call_sp', fields: { upp: 'Finca Uno', species: 'BOVINO', category: 'VACA', business_model: 'CRIA',
  ear_tag: 'S/N', confirmed: 'false', preview_hash: 'abc', force_duplicate: 'true', actor_email: 'attacker@example.test' } };

const r = run(cfg, body, { 'x-tenant-id': '3' });
const placeholders = Array.from({ length: 19 }, (_, i) => '$' + (i + 1)).join(', ');
ok(r.query === `SELECT sp_register_livestock_panel(${placeholders}) AS resultado;`, 'SQL is SELECT sp_register_livestock_panel($1..$19) AS resultado;');
ok(r.values.length === 19, '19 values: the tenant plus the 18 arguments');
ok(r.values[0] === 3 && typeof r.values[0] === 'number', 'the tenant goes first, as a number');
ok(r.values[18] === 'jwt-actor@example.test' && !r.values.includes('attacker@example.test'), 'the actor e-mail is the JWT one; the client value is overwritten');
ok(r.values[1] === 'Finca Uno' && r.values[3] === 'BOVINO' && r.values[4] === 'VACA' && r.values[5] === 'CRIA' && r.values[6] === 'S/N',
  'arguments land in signature positions (upp, species, category, business_model, ear_tag)');
ok(r.values[15] === 'false' && r.values[16] === 'abc' && r.values[17] === 'true', 'confirmed, preview_hash and force_duplicate travel (allowed_fields does not filter call_sp)');
ok([2, 7, 8, 9, 10, 11, 12, 13, 14].every(i => r.values[i] === null), 'absent fields travel as null');
ok(r.operation === 'call_sp' && r.is_transactional === false, 'operation stays call_sp (not wrapped as a write)');

const r2 = run(cfg, { action: 'call_sp', fields: { upp: 'x' } }, { 'x-tenant-id': '3' });
ok(r2.values[18] === 'jwt-actor@example.test', 'the JWT e-mail is used even when the client sends none');

const throws = (fn, re) => { try { fn(); return false; } catch (e) { return re.test(e.message); } };
ok(throws(() => run(cfg, body, {}), /tenant_id requerido/), 'a missing x-tenant-id is refused');
ok(throws(() => run({ ...cfg, user_email: null }, body, { 'x-tenant-id': '3' }), /email is required/), 'a missing JWT e-mail is refused');

const old = run({ ...cfg, table_name: 'sp_agri_void_expense', model_name: 'agri_void_expense' },
  { fields: { expense_id: 'e', reason: 'r', actor_email: 'x' } }, { 'x-tenant-id': '7' });
ok(old.query === 'SELECT sp_agri_void_expense($1, $2, $3, $4) AS resultado;' && old.values[0] === 7 && old.values[3] === 'jwt-actor@example.test',
  'an existing entry (sp_agri_void_expense) still builds the same query');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
