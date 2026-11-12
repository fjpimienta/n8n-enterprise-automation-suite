// Offline test of the "Build Query" node of v6-crud.json for the palm-sale call_sp entries (migration 107):
//   sp_agri_void_sale and sp_agri_sales_balance.
// No dependencies, no database, no n8n: it runs the REAL jsCode of the node from the export with the two upstream nodes stubbed.
// The parameter order is pinned against the real signatures, parsed from migration 104 (not retyped here).
// Usage: node workflows/06-dynamic-crud-engine/v6/tests/test_agri_sale_sp.mjs
// Optional overrides (used by the mutation checks): V6_CRUD_JSON=<export>, SQL_104=<migration 104>, SQL_107=<migration 107>.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const here = import.meta.dirname;
const repoRoot = path.resolve(here, '../../../..');
const exportPath = process.env.V6_CRUD_JSON ?? path.resolve(here, '../v6-crud.json');
const migrations = path.join(repoRoot, 'hosting3m-workspace/projects/agro-erp/database/migrations');
const sql104 = fs.readFileSync(process.env.SQL_104 ?? path.join(migrations, '104_agri_sale_invoices.sql'), 'utf8');
const sql107 = fs.readFileSync(process.env.SQL_107 ?? path.join(migrations, '107_agri_sale_gateway_sp.sql'), 'utf8');

const wf = JSON.parse(fs.readFileSync(exportPath, 'utf8'));
const code = wf.nodes.find((n) => n.name === 'Build Query').parameters.jsCode;

let pass = 0; let fail = 0;
const ok = (c, name, extra = '') => { if (c) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, extra); } };

// The real node code with the two upstream nodes stubbed. Returns { out } or { threw }.
function run(table, body, headers, security = {}) {
  const nodes = {
    'Security Validation': { model_name: table, table_name: table, operation: 'call_sp', sp_requires_tenant: true, user_email: 'jwt-admin@example.invalid', user_role: 'ADMIN', allowed_fields: [], ...security },
    WebhookCRUD: { body, headers },
  };
  const $ = (name) => ({ first: () => ({ json: nodes[name] }) });
  const req = (m) => (m === 'crypto' ? crypto : (() => { throw new Error(`unexpected require ${m}`); })());
  try { return { out: new Function('$', 'require', code)($, req)[0].json }; } catch (e) { return { threw: e.message }; }
}

// Real signatures from migration 104 -------------------------------------------------------------------------------------------------
function signature(name) {
  const m = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(([^)]*)\\)`).exec(sql104);
  if (!m) throw new Error(`signature of ${name} not found in migration 104`);
  return m[1].split(',').map((a) => a.trim().split(/\s+/)[0]).map((a) => a.replace(/^p_/, ''));
}
const PROCS = ['sp_agri_void_sale', 'sp_agri_sales_balance'];
const SIG = Object.fromEntries(PROCS.map((p) => [p, signature(p)]));

console.log('signatures parsed from migration 104');
ok(SIG.sp_agri_void_sale.join() === 'tenant_id,actor_email,sale_id,reason', 'void signature is (tenant_id, actor_email, sale_id, reason)', SIG.sp_agri_void_sale.join());
ok(SIG.sp_agri_sales_balance.join() === 'tenant_id,date_from,date_to,grain,plantation_id,lot_id,actor_email', 'balance signature is (tenant_id, date_from, date_to, grain, plantation_id, lot_id, actor_email)', SIG.sp_agri_sales_balance.join());

const HOSTILE = "11111111-1111-4111-8111-111111111111'); DROP TABLE agri_sale_invoices;--";
for (const proc of PROCS) {
  const sig = SIG[proc];
  const args = sig.slice(1); // everything after the tenant
  console.log(proc);
  // every client argument carries its own marker, so the position of each value identifies the argument
  const fields = Object.fromEntries(args.map((a) => [a, `MARK_${a}`]));
  const body = { operation: 'call_sp', tenant_id: 99, id_company: 99, p_tenant_id: 99, actor_email: 'attacker@example.invalid',
    fields: { ...fields, actor_email: 'attacker@example.invalid', tenant_id: 99, id_company: 99, p_tenant_id: 99, company: 7, extra: 'zzz-extra', status: 'OK' } };
  const r = run(proc, body, { 'x-tenant-id': '5' });
  ok(!r.threw && r.out, `${proc}: the node builds a statement`, r.threw);
  if (r.threw) continue;
  const { query, values } = r.out;
  const placeholders = Array.from({ length: sig.length }, (_, i) => `$${i + 1}`).join(', ');
  ok(query === `SELECT ${proc}(${placeholders}) AS resultado;`, `${proc}: SQL is SELECT ${proc}($1..$${sig.length}) AS resultado;`, query);
  ok(values.length === sig.length, `${proc}: ${sig.length} values (the tenant plus ${args.length} arguments)`, JSON.stringify(values));
  ok(values[0] === 5 && typeof values[0] === 'number', `${proc}: the tenant goes first, as a number, from the header`, JSON.stringify(values[0]));
  sig.forEach((arg, i) => {
    if (i === 0) return;
    if (arg === 'actor_email') ok(values[i] === 'jwt-admin@example.invalid', `${proc}: position ${i + 1} (${arg}) is the e-mail of the verified token`, JSON.stringify(values[i]));
    else ok(values[i] === `MARK_${arg}`, `${proc}: position ${i + 1} is ${arg} (signature order from migration 104)`, JSON.stringify(values[i]));
  });
  const all = JSON.stringify(values);
  ok(!all.includes('99') && !all.includes('attacker@example.invalid') && !all.includes('zzz-extra') && !all.includes('"OK"'),
    `${proc}: a client tenant, actor or extra keys never reach the statement`, all);

  // the tenant comes only from the header
  const other = run(proc, body, { 'x-tenant-id': '7' });
  ok(other.out?.values[0] === 7, `${proc}: a different header gives a different company`, JSON.stringify(other));
  const noHeader = run(proc, body, {});
  ok(noHeader.threw && /tenant_id requerido/.test(noHeader.threw), `${proc}: a missing tenant header makes the node fail`, JSON.stringify(noHeader));
  const emptyHeader = run(proc, body, { 'x-tenant-id': '' });
  ok(emptyHeader.threw && /tenant_id requerido/.test(emptyHeader.threw), `${proc}: an empty tenant header makes the node fail`, JSON.stringify(emptyHeader));

  // the actor comes only from the verified token
  const noEmail = run(proc, body, { 'x-tenant-id': '5' }, { user_email: null });
  ok(noEmail.threw && /email is required/.test(noEmail.threw), `${proc}: a missing token e-mail makes the node fail (the body e-mail is not used)`, JSON.stringify(noEmail));
  const emptyEmail = run(proc, body, { 'x-tenant-id': '5' }, { user_email: '' });
  ok(emptyEmail.threw && /email is required/.test(emptyEmail.threw), `${proc}: an empty token e-mail makes the node fail`, JSON.stringify(emptyEmail));
  const otherEmail = run(proc, body, { 'x-tenant-id': '5' }, { user_email: 'other-admin@example.invalid' });
  ok(otherEmail.out?.values[sig.indexOf('actor_email')] === 'other-admin@example.invalid', `${proc}: the actor follows the token`, JSON.stringify(otherEmail));

  // a hostile value stays a bound parameter: the statement text never contains it
  const hostile = Object.fromEntries(args.filter((a) => a !== 'actor_email').map((a) => [a, `${HOSTILE}-${a}`]));
  const h = run(proc, { operation: 'call_sp', fields: hostile }, { 'x-tenant-id': '5' });
  ok(h.out && h.out.query === `SELECT ${proc}(${placeholders}) AS resultado;`, `${proc}: a hostile value leaves the statement text unchanged`, JSON.stringify(h));
  ok(h.out && args.filter((a) => a !== 'actor_email').every((a) => h.out.values[sig.indexOf(a)] === `${HOSTILE}-${a}`), `${proc}: the hostile value is a bound parameter`, JSON.stringify(h.out?.values));
  ok(h.out && !/DROP|agri_sale_invoices/i.test(h.out.query), `${proc}: no part of the hostile text is in the query string`, h.out?.query);
  // an object value is sent as JSON text, never as SQL
  const obj = run(proc, { operation: 'call_sp', fields: { [args[0] === 'actor_email' ? args[1] : args[0]]: { a: "'); DROP TABLE x;--" } } }, { 'x-tenant-id': '5' });
  ok(obj.out && !/DROP/i.test(obj.out.query), `${proc}: an object value does not reach the query string`, JSON.stringify(obj));
}

console.log('models without an entry fail as before');
for (const t of ['sp_agri_void_sale_x', 'sp_does_not_exist', 'agri_sale_void', 'agri_sale_balance', 'sp_agri_sales_balances']) {
  const r = run(t, { operation: 'call_sp', fields: {} }, { 'x-tenant-id': '5' });
  ok(r.threw && r.threw.startsWith('No hay configuración de parámetros para el procedimiento'), `no entry for "${t}" fails`, JSON.stringify(r));
}

console.log('existing entries keep their behavior');
{
  const r = run('sp_agri_void_expense', { operation: 'call_sp', fields: { expense_id: 'E1', reason: 'R1', actor_email: 'attacker@example.invalid' } }, { 'x-tenant-id': '5' });
  ok(r.out && JSON.stringify(r.out.values) === JSON.stringify([5, 'E1', 'R1', 'jwt-admin@example.invalid']), 'sp_agri_void_expense still builds (tenant, expense_id, reason, token e-mail)', JSON.stringify(r));
  const b = run('sp_agri_expense_balance', { operation: 'call_sp', fields: { date_from: 'D1' } }, { 'x-tenant-id': '5' });
  ok(b.out && b.out.values.length === 8 && b.out.values[0] === 5 && b.out.values[1] === 'D1' && b.out.values[7] === 'jwt-admin@example.invalid', 'sp_agri_expense_balance still builds', JSON.stringify(b));
}

console.log('migration 107 model rows agree with the gateway entries');
{
  const rows = [...sql107.matchAll(/\('([a-z_]+)', '(sp_[a-z_]+)', '([a-z_]+)',\s*'(\[[^']*\])'/g)].map((m) => ({ model: m[1], table: m[2], pk: m[3], fields: JSON.parse(m[4]) }));
  ok(rows.length === 2, 'migration 107 registers two models', JSON.stringify(rows));
  for (const proc of PROCS) {
    const row = rows.find((r) => r.table === proc);
    const args = SIG[proc].slice(1);
    ok(!!row, `a model row serves ${proc}`);
    if (!row) continue;
    ok([...row.fields].sort().join() === [...args].sort().join(), `${row.model}: allowed_fields are the procedure arguments after the tenant`, `${row.fields} vs ${args}`);
    ok(row.fields.includes(row.pk), `${row.model}: the primary key is one of the arguments`);
  }
  ok(/allowed_roles_insert[\s\S]*'NONE', 'ADMIN', 'NONE', 'NONE'/.test(sql107) && !/'ADMIN,OWNER'/.test(sql107), 'migration 107 grants the call to ADMIN only');
}

console.log('change control: only the two new entries differ from the base');
{
  const entries = (src) => [...src.matchAll(/^ {12}'(sp_[a-z0-9_]+)': \{/gm)].map((m) => m[1]);
  let baseText = null; let baseRef = null;
  for (const ref of ['origin/develop', 'origin/main']) {
    try {
      const rel = path.relative(repoRoot, path.resolve(here, '../v6-crud.json'));
      const base = execFileSync('git', ['-C', repoRoot, 'merge-base', 'HEAD', ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
      baseText = execFileSync('git', ['-C', repoRoot, 'show', `${base}:${rel}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 });
      baseRef = `${ref} @ ${base.slice(0, 7)}`; break;
    } catch { /* try the next reference */ }
  }
  if (!baseText) {
    console.log('  SKIP no git base reference available (origin/develop); the pinned checks above still ran');
  } else {
    const base = JSON.parse(baseText);
    const strip = (w) => ({ ...w, nodes: w.nodes.filter((n) => n.name !== 'Build Query') });
    ok(JSON.stringify(strip(base)) === JSON.stringify(strip(wf)), `every other node, the connections and the workflow settings are identical to ${baseRef}`);
    const bn = base.nodes.find((n) => n.name === 'Build Query'); const cn = wf.nodes.find((n) => n.name === 'Build Query');
    const { jsCode: bj, ...bRest } = bn.parameters; const { jsCode: cj, ...cRest } = cn.parameters;
    ok(JSON.stringify({ ...bn, parameters: bRest }) === JSON.stringify({ ...cn, parameters: cRest }), 'Build Query: only jsCode differs (id, name, type, version, position, other parameters)');
    const added = entries(cj).filter((e) => !entries(bj).includes(e)).sort();
    const removed = entries(bj).filter((e) => !entries(cj).includes(e));
    ok(removed.length === 0, 'no existing spConfigByModel entry was removed', removed.join());
    ok(added.length === 0 || added.join() === 'sp_agri_sales_balance,sp_agri_void_sale', 'the only entries added are sp_agri_void_sale and sp_agri_sales_balance', added.join());
    const stripped = cj.replace(/ {12}\/\/ Palm sales \(migration 107\)[\s\S]*?(?= {12}\/\/ Panel livestock intake)/, '');
    ok(cj === bj || stripped === bj, 'Build Query: removing the two new entries gives back the base code byte for byte');
  }
}

console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
