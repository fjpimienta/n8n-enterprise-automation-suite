#!/usr/bin/env node
// Offline test of the palm sale route of the web chat (no n8n, no network, no database): structure of both workflows, the one changed
// connection, the real jsCode / expressions of the nodes run with stubbed inputs, and reply-text coverage of every procedure status.
// Usage: node workflows/09-MCP-Agent-Cattle/v6/tests/test_palm_sale_route.mjs [--baseline-ref origin/develop]
// Exit code 0 = every check passed, 1 = at least one FAIL.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { diffExports, loadExport } from './diff_workflow_exports.mjs';

const V6 = path.resolve(import.meta.dirname, '..');
const REPO = path.resolve(V6, '../../..');
const CHAT_FILE = 'workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json';
const REF = process.argv.includes('--baseline-ref') ? process.argv[process.argv.indexOf('--baseline-ref') + 1] : 'origin/develop';

const chat = JSON.parse(fs.readFileSync(path.join(V6, 'v6_ai_chat_cattle.json'), 'utf8'));
const subRaw = fs.readFileSync(path.join(V6, 'v6_palm_sale_from_xml.json'), 'utf8');
const sub = JSON.parse(subRaw);
const sqlRaw = fs.readFileSync(path.join(REPO, 'hosting3m-workspace/projects/agro-erp/database/migrations/104_agri_sale_invoices.sql'), 'utf8');

let pass = 0; let fail = 0; let skip = 0;
const ok = (cond, name, detail) => { if (cond) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, detail ? `\n        ${detail}` : ''); } };
const skipped = (name, why) => { skip++; console.log('  SKIP', name, `(${why})`); };
const node = (wf, name) => wf.nodes.find((n) => n.name === name);
const targets = (wf, from) => (wf.connections[from]?.main ?? []).map((g) => g.map((x) => x.node));

// --- stubs: the real expressions / code of the exports run against these ----------------------------------------------
const evalExpr = (expr, scope) => {
  assertExpr(expr);
  const body = expr.replace(/^=\{\{/, '').replace(/\}\}$/, '');
  return new Function('$', '$json', `return (${body});`)(scope.$, scope.json);
};
const assertExpr = (e) => { if (!/^=\{\{[\s\S]*\}\}$/.test(e)) throw new Error('not an expression: ' + String(e).slice(0, 40)); };
const mkScope = (nodes, json = {}) => ({
  json,
  $: (name) => {
    if (!(name in nodes)) throw new Error(`reference to a node that does not exist in the stub: ${name}`);
    const n = nodes[name];
    return { first: () => ({ json: n.json }), item: { json: n.json }, isExecuted: n.executed !== false };
  },
});
const runCode = (code, nodes, inputJson = {}) => {
  const scope = mkScope(nodes);
  return new Function('$', '$input', code)(scope.$, { first: () => ({ json: inputJson }) });
};
const b64 = (s) => Buffer.from(s).toString('base64');

// =====================================================================================================================
console.log('sub-workflow v6/palm sale from xml: structure');
const SUB_TRIGGER = 'When Executed by Another Workflow';
const INPUTS = ['id_company', 'actor_email', 'role', 'file_name', 'file_type', 'file_size', 'xml_base64'];
{
  ok(sub.name === 'v6/palm sale from xml', 'name');
  ok(sub.settings.saveDataSuccessExecution === 'none' && sub.settings.saveDataErrorExecution === 'none', 'saves no execution data on success or error');
  ok(sub.settings.saveExecutionProgress === false, 'does not save execution progress');
  ok(sub.settings.errorWorkflow === chat.settings.errorWorkflow, 'keeps the global error workflow');
  ok(sub.settings.callerPolicy === 'workflowsFromSameOwner' && sub.settings.availableInMCP === false, 'only callable by workflows of the same owner, not an MCP tool');
  ok(sub.active === false, 'export is inactive until the owner publishes it');

  const types = sub.nodes.map((n) => n.type);
  ok(!types.some((t) => /langchain|agent|openai|mcp|memory|chatTrigger|webhook/i.test(t)), 'no LLM, agent, MCP, memory or webhook node', types.join(','));
  ok(!/\$fromAI|fromAI/.test(subRaw), 'no $fromAI anywhere');
  ok(!/console\.|debugger|require\(/.test(sub.nodes.filter((n) => n.parameters?.jsCode).map((n) => n.parameters.jsCode).join('\n')), 'no console / require in the code nodes');
  ok(!/chatInput|sessionId/.test(subRaw), 'the message text and session id are never read');

  const trig = node(sub, SUB_TRIGGER);
  ok(trig?.type === 'n8n-nodes-base.executeWorkflowTrigger' && trig.parameters.inputSource === 'workflowInputs', 'trigger declares its inputs');
  ok(JSON.stringify(trig.parameters.workflowInputs.values.map((v) => v.name)) === JSON.stringify(INPUTS), 'trigger inputs are exactly the seven expected', JSON.stringify(trig.parameters.workflowInputs.values));

  const names = new Set(sub.nodes.map((n) => n.name));
  ok(names.size === sub.nodes.length, 'node names are unique');
  const bad = Object.entries(sub.connections).flatMap(([from, c]) => [from, ...c.main.flat().map((x) => x.node)]).filter((n) => !names.has(n));
  ok(bad.length === 0, 'every connection refers to an existing node', bad.join(','));
  // reachability and a single exit
  const seen = new Set([SUB_TRIGGER]); const queue = [SUB_TRIGGER];
  while (queue.length) for (const t of targets(sub, queue.shift()).flat()) if (!seen.has(t)) { seen.add(t); queue.push(t); }
  ok(seen.size === names.size, 'every node is reachable from the trigger');
  const sinks = [...names].filter((n) => !(sub.connections[n]?.main ?? []).flat().length);
  ok(sinks.length === 1 && sinks[0] === 'Armar Respuesta', 'one exit: every path ends in "Armar Respuesta"', sinks.join(','));
  ok(JSON.stringify(targets(sub, 'Entrada OK')) === '[["CFDI Parse"],["Armar Respuesta"]]'
    && JSON.stringify(targets(sub, 'Parse OK')) === '[["CFDI SAT Status"],["Armar Respuesta"]]'
    && JSON.stringify(targets(sub, 'Store OK')) === '[["Registrar Venta"],["Armar Respuesta"]]', 'order: validate -> parse -> SAT -> store -> procedure');
  ok(JSON.stringify(targets(sub, 'CFDI Parse')) === '[["Parse OK"]]' && JSON.stringify(targets(sub, 'CFDI SAT Status')) === '[["CFDI Store"]]'
    && JSON.stringify(targets(sub, 'CFDI Store')) === '[["Store OK"]]', 'parse -> SAT -> store are chained');

  const http = sub.nodes.filter((n) => n.type === 'n8n-nodes-base.httpRequest');
  ok(JSON.stringify(http.map((n) => n.parameters.url).sort()) === JSON.stringify(['http://cfdi-service:4100/parse', 'http://cfdi-service:4100/sat-status', 'http://cfdi-service:4100/store']), 'HTTP calls: parse, sat-status, store on the internal service');
  ok(http.every((n) => n.credentials?.httpHeaderAuth?.name === 'CFDI Service Token' && n.parameters.authentication === 'genericCredentialType'), 'HTTP nodes use the existing credential, no header in the JSON');
  ok(http.every((n) => n.parameters.options.response.response.neverError === true && n.onError === 'continueRegularOutput' && n.parameters.options.timeout <= 30000), 'HTTP nodes: errors are data, timeouts <= 30 s');
  ok(!http.some((n) => n.parameters.sendHeaders || n.parameters.headerParameters), 'no header parameters (token only through the credential)');
  ok(JSON.parse(JSON.stringify(node(sub, 'CFDI Parse').parameters.jsonBody.replace(/^=\{\{|\}\}$/g, '').length > 0)) && /profile: 'sale'/.test(node(sub, 'CFDI Parse').parameters.jsonBody), 'parse is requested with profile "sale"');

  const pg = sub.nodes.filter((n) => n.type === 'n8n-nodes-base.postgres');
  ok(pg.length === 1 && pg[0].name === 'Registrar Venta', 'exactly one database node');
  ok(pg[0].parameters.query === 'SELECT public.sp_agri_register_sale($1::integer, $2::text, $3::jsonb, $4::text, $5::text, $6::text) AS result;', 'database node: constant query, six positional parameters');
  ok(!/\{\{|\$\(|\+|\|\|/.test(pg[0].parameters.query), 'the query text contains no expression or concatenation');
  ok(/^=\{\{ \[ Number\(/.test(pg[0].parameters.options.queryReplacement) && /\]\s*\}\}$/.test(pg[0].parameters.options.queryReplacement), 'values are passed as a typed array (queryReplacement)');
  ok(pg[0].credentials?.postgres?.name === 'Postgres account' && !pg[0].onError, 'existing Postgres credential; failures raise (error workflow alerts)');

  const creds = sub.nodes.flatMap((n) => Object.values(n.credentials ?? {}));
  ok(creds.length === 4 && creds.every((c) => Object.keys(c).sort().join() === 'id,name'), 'credentials are references only (id and name), no values');
  ok(!/Bearer |eyJ[A-Za-z0-9]|sk-[A-Za-z0-9]|x-internal-token/i.test(subRaw), 'no token-like string in the export');
  for (const n of sub.nodes.filter((x) => typeof x.parameters?.jsonBody === 'string' || x.parameters?.options?.queryReplacement)) {
    const refs = [...(JSON.stringify(n.parameters)).matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]);
    ok(refs.every((r) => names.has(r)), `${n.name}: every $('...') reference exists`, refs.filter((r) => !names.has(r)).join(','));
  }
}

// =====================================================================================================================
console.log('web chat workflow: the minimal change');
const IF = 'Palma: XML adjunto'; const EXEC = 'Venta Palma XML'; const FB = 'Palma: respuesta de venta';
{
  ok(JSON.stringify(targets(chat, 'Dominio')) === JSON.stringify([[IF], ['Trae Factura']]), 'Dominio: PALM -> XML check, OTHER -> Trae Factura (unchanged)');
  ok(JSON.stringify(targets(chat, IF)) === JSON.stringify([[EXEC], ['Catálogo Palma']]), 'XML attached -> sale route; anything else -> Catálogo Palma (today)');
  ok(JSON.stringify(targets(chat, EXEC)) === JSON.stringify([[FB]]) && JSON.stringify(targets(chat, FB)) === JSON.stringify([['Respond to Webhook']]), 'sale route ends in the existing Respond to Webhook');
  ok(JSON.stringify(targets(chat, 'Catálogo Palma')) === '[["AI Agent Palma"]]' && JSON.stringify(targets(chat, 'AI Agent Palma')) === '[["Respond to Webhook"]]', 'the palm agent path is untouched');
  const ex = node(chat, EXEC);
  ok(ex.onError === 'continueRegularOutput', 'Execute Workflow continues on error (the webhook always answers)');
  ok(ex.parameters.workflowId.cachedResultName === sub.name, 'Execute Workflow points to the sub-workflow by name');
  const mapped = Object.keys(ex.parameters.workflowInputs.value);
  ok(JSON.stringify(mapped) === JSON.stringify(INPUTS) && ex.parameters.workflowInputs.schema.map((s) => s.id).join() === INPUTS.join(), 'inputs mapped to the trigger fields, in order');
  const vals = ex.parameters.workflowInputs.value;
  ok(vals.id_company === "={{ Number($('Resolver Empresa Chat').first().json.id_company) }}", 'tenant comes from "Resolver Empresa Chat" (verified membership)');
  ok(vals.actor_email === "={{ $('Validar Token').first().json.data.user.user }}", 'actor e-mail comes from the verified token');
  ok(vals.role === "={{ $('Resolver Empresa Chat').first().json.role }}", 'role comes from the membership of the active company');
  const refs = [...JSON.stringify(ex.parameters).matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]);
  ok([...new Set(refs)].sort().join() === 'Resolver Empresa Chat,Validar Token,Webhook', 'only the session nodes and the webhook file are referenced', [...new Set(refs)].join());
  ok(!/chatInput|AI Agent|fromAI/.test(JSON.stringify(ex.parameters) + JSON.stringify(node(chat, IF).parameters)), 'neither the message text nor the model feed the route');
  ok(!JSON.stringify([node(chat, IF), ex, node(chat, FB)]).includes('console.'), 'no logging in the new nodes');
  ok(chat.settings.saveDataSuccessExecution === undefined && chat.settings.saveDataErrorExecution === undefined, 'the chat workflow keeps inheriting the instance retention (livestock flows keep their records)');
}

// proof: old vs new JSON
console.log('web chat workflow: diff against the baseline');
{
  let baseline = null;
  try { baseline = loadExport(`git:${REF}:${CHAT_FILE}`, REPO); } catch { /* handled below */ }
  if (!baseline) skipped('diff against the baseline', `git ref ${REF} not available`);
  else if (baseline.nodes.some((n) => n.name === IF)) skipped('diff against the baseline', `${REF} already contains the route`);
  else {
    const d = diffExports(baseline, chat);
    ok(JSON.stringify(d.added.sort()) === JSON.stringify([EXEC, FB, IF].sort()), 'exactly three nodes added', d.added.join(','));
    ok(d.removed.length === 0 && d.changedNodes.length === 0, 'no node removed or changed', JSON.stringify(d.changedNodes));
    ok(d.unchangedNodes === baseline.nodes.length, `all ${baseline.nodes.length} existing nodes are byte-identical (parameters, credentials, position, ids)`);
    ok(JSON.stringify(d.changedConnections.map((c) => c.from).sort()) === JSON.stringify(['Dominio', EXEC, FB, IF].sort()), 'connections: Dominio plus the three new sources', d.changedConnections.map((c) => c.from).join());
    const dom = d.changedConnections.find((c) => c.from === 'Dominio');
    ok(JSON.stringify(dom.before.main[1]) === JSON.stringify(dom.after.main[1]) && JSON.stringify(dom.before.main[0]) !== JSON.stringify(dom.after.main[0]), 'only the PALM output of Dominio changed');
    ok(d.changedTop.length === 0, 'settings, name, tags and ids unchanged', d.changedTop.join(','));
  }
}

// =====================================================================================================================
console.log('XML attached? (expression of the IF node, run on file shapes)');
{
  const expr = node(chat, IF).parameters.conditions.conditions[0].leftValue;
  const check = (body) => evalExpr(expr, mkScope({ Webhook: { json: { body } } }));
  const f = (name, type) => ({ chatInput: 'x', file: { name, type, size: 10, base64: 'AAAA' } });
  ok(check(f('factura.xml', 'text/xml')) === true, 'text/xml + .xml');
  ok(check(f('FACTURA.XML', 'application/xml')) === true, 'application/xml + .XML');
  ok(check(f('factura.xml', 'application/octet-stream')) === true, 'application/octet-stream + .xml');
  ok(check(f('factura.pdf', 'application/pdf')) === false, 'pdf stays on today\'s path');
  ok(check(f('foto.png', 'image/png')) === false, 'image stays on today\'s path');
  ok(check(f('factura.txt', 'text/xml')) === false, 'xml type without the .xml extension is not the sale route');
  ok(check(f('factura.xml', 'application/pdf')) === false, '.xml with a non-xml type is not the sale route');
  ok(check({ chatInput: 'registra la venta' }) === false, 'no file');
  ok(check({ chatInput: 'x', file: [{ name: 'a.xml', type: 'text/xml' }] }) === false, 'several files (array) stay on today\'s path');
  ok(check({ chatInput: 'x', file: 'a.xml' }) === false, 'file that is not an object');
  ok(evalExpr(expr, mkScope({ Webhook: { json: f('a.xml', 'text/xml') } })) === true, 'also works when the payload is not nested under body');
}

// =====================================================================================================================
console.log('Validar Entrada (role and input checks, run with stubs)');
const VE = node(sub, 'Validar Entrada').parameters.jsCode;
const entry = (o = {}) => ({ id_company: 10, actor_email: 'admin@example.invalid', role: 'ADMIN', file_name: 'v.xml', file_type: 'text/xml', file_size: 100, xml_base64: b64('<?xml version="1.0"?><a/>'), ...o });
{
  const run = (o) => runCode(VE, {}, entry(o))[0].json;
  ok(run().ok === true, 'ADMIN with a valid XML passes');
  ok(run({ role: 'EDITOR' }).ok === false && /administrador/.test(run({ role: 'EDITOR' }).output), 'EDITOR gets the fixed administrator-only text');
  ok(run({ role: 'CUSTOMER' }).ok === false && run({ role: undefined }).ok === false && run({ role: 'admin ' }).ok === false, 'any other role (or none) is refused; the comparison is strict');
  ok(run({ role: 'admin' }).ok === true, 'role case is normalized (membership roles are upper case)');
  ok(run({ id_company: 'abc' }).ok === false && run({ id_company: 0 }).ok === false && run({ id_company: 1.5 }).ok === false && run({ id_company: null }).ok === false, 'tenant must be a positive integer');
  ok(run({ actor_email: '' }).ok === false && run({ actor_email: 5 }).ok === false, 'actor e-mail is required');
  ok(run({ file_name: 'v.pdf' }).ok === false && run({ file_type: 'application/pdf' }).ok === false, 'only .xml with an xml-like type');
  ok(run({ file_type: 'application/octet-stream' }).ok === true, 'octet-stream with .xml is accepted');
  ok(run({ xml_base64: '***' }).ok === false && run({ xml_base64: '' }).ok === false && run({ xml_base64: 'QQ== ' }).ok === false, 'base64 must be clean');
  ok(run({ xml_base64: 'A'.repeat(7200004) }).ok === false, 'oversize base64 refused before any call');
  const bad = [run({ role: 'EDITOR' }), run({ xml_base64: '***' }), run({ id_company: 'abc' })];
  ok(bad.every((b) => typeof b.output === 'string' && !/<|>|`/.test(b.output)), 'refusals are plain text');
}

// =====================================================================================================================
console.log('Armar Respuesta (fixed texts for every answer)');
const AR = node(sub, 'Armar Respuesta').parameters.jsCode;
const UUID_RE = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/i;
const RFC_RE = /\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\b/;
const reply = (state) => {
  const nodes = {
    'Validar Entrada': { json: { ok: true } },
    'CFDI Parse': { json: state.parse ?? {}, executed: state.parse !== undefined },
    'CFDI SAT Status': { json: state.sat ?? {}, executed: state.sat !== undefined },
    'CFDI Store': { json: state.store ?? {}, executed: state.store !== undefined },
    'Registrar Venta': { json: state.sp !== undefined ? { result: state.sp } : {}, executed: state.sp !== undefined },
    ...(state.entry ? { 'Validar Entrada': { json: state.entry } } : {}),
  };
  const out = runCode(AR, nodes);
  return out[0].json.output;
};
const SUMMARY = { folio: '77', sale_date: '2026-11-10', buyer_name: 'COMPRADOR FICTICIO', total_amount: 31126, quantity_kg: 7900, unit_price: 3.94, ticket_ref: '4521', sat_status: 'VIGENTE' };
const OKR = (extra = {}, summary = {}) => ({ status: 'OK', sale_id: '11111111-1111-4111-8111-111111111111', warnings: [], summary: { ...SUMMARY, ...summary }, ...extra });
{
  const okText = reply({ sp: OKR() });
  ok(/^✅ Venta registrada\./.test(okText) && okText.includes('Folio 77 · 2026-11-10') && okText.includes('Comprador: COMPRADOR FICTICIO')
    && okText.includes('7,900 kg a $3.94/kg') && okText.includes('Total: $31,126.00 MXN') && okText.includes('Ticket: 4521') && !okText.includes('Avisos'), 'OK: folio, date, buyer, kg, price, total and ticket', okText);
  ok(!UUID_RE.test(okText) && !RFC_RE.test(okText) && !/sello|certificado|<\?xml/i.test(okText), 'OK: no uuid, RFC, seal or XML');
  const w = reply({ sp: OKR({ warnings: ['ticket_missing_or_unrecognized', 'ticket_already_used', 'previous_sale_voided'] }) });
  ok(w.includes('Avisos:') && w.includes('• No encontré el número de ticket') && w.includes('• El ticket 4521 ya está') && w.includes('• Esta factura había sido anulada antes'), 'warnings as a short list in the same message', w);
  ok(reply({ sp: OKR({}, { sat_status: 'SKIPPED_TEST' }) }).includes('Empresa de pruebas: el SAT no se verificó.'), 'test company note');
  ok(!reply({ sp: OKR({}, { ticket_ref: null }) }).includes('Ticket:'), 'no ticket line without a ticket');
  const hostile = reply({ sp: OKR({}, { buyer_name: 'A<script>[x](y)`z`\u0007B', folio: '1\n2' }) });
  ok(!/<|>|`|\[|\]|\u0007/.test(hostile), 'voucher text is sanitized (no markup characters, no control characters)', hostile);
  ok(/100,000.50/.test(reply({ sp: OKR({}, { total_amount: 100000.5 }) })), 'money is formatted with two decimals');

  // every status the procedure can answer must have an explicit text (taken from the SQL, so a new status forces a decision here)
  const fnBody = sqlRaw.slice(sqlRaw.indexOf('CREATE OR REPLACE FUNCTION public.sp_agri_register_sale('), sqlRaw.indexOf('CREATE OR REPLACE FUNCTION public.sp_agri_void_sale('));
  const statuses = [...new Set([...fnBody.matchAll(/'status', '([A-Za-z_]+)'/g), ...fnBody.matchAll(/sale_reject\(p_tenant_id, v_actor, '([A-Z_]+)'/g)].map((m) => m[1]))];
  const EXPECTED_STATUSES = ['ALREADY_REGISTERED', 'DUPLICATE', 'FORBIDDEN', 'INVALID_VOUCHER', 'ISSUER_RFC_MISMATCH', 'ISSUER_RFC_NOT_CONFIGURED', 'NOT_PALM', 'OK'];
  ok(JSON.stringify(statuses.sort()) === JSON.stringify(EXPECTED_STATUSES), 'the statuses of sp_agri_register_sale are the ones covered here', statuses.join(','));
  const T = {
    ALREADY_REGISTERED: /ya estaba registrada/, DUPLICATE: /^⚠️ No se pudo registrar la factura\.$/, FORBIDDEN: /administrador de la empresa/,
    ISSUER_RFC_MISMATCH: /RFC emisor de la factura no corresponde/, ISSUER_RFC_NOT_CONFIGURED: /no tiene un RFC emisor configurado/, NOT_PALM: /no es de palma/,
  };
  for (const [st, re] of Object.entries(T)) ok(re.test(reply({ sp: { status: st, message: 'ignored' } })), `status ${st}: fixed text`);
  ok(reply({ sp: { status: 'DUPLICATE', code: 'DUPLICATE_UUID', message: 'owner company 99' } }) === '⚠️ No se pudo registrar la factura.', 'DUPLICATE: generic text only, nothing from the answer is echoed');
  ok(/desactivado temporalmente/.test(reply({ sp: { status: 'disabled' } })) && /^⚠️/.test(reply({ sp: { status: 'something-new' } })), 'disabled and unknown statuses have a safe text');

  const reasons = [...new Set([...fnBody.matchAll(/v_reason := '([A-Z_]+)'/g)].map((m) => m[1]))];
  const GENERIC = ['UUID', 'ISSUER_RFC_FORMAT', 'BUYER_RFC_FORMAT', 'BUYER_NAME', 'PRODUCT_KEY', 'HASH', 'PATH', 'BAD_PAYLOAD'];
  const EXPLICIT = { TIPO: /tipo I/, CURRENCY: /MXN/, PAYMENT_METHOD: /PUE/, CONCEPT_COUNT: /un concepto/, UNIT: /KGM/, QUANTITY: /cantidad o el precio/, CONCEPT_AMOUNT: /importe del concepto/,
    AMOUNTS: /importes no son válidos/, AMOUNTS_MISMATCH: /no cuadran/, AMOUNTS_MISMATCH_CONCEPT: /cantidad × precio unitario/, DATE_FUTURE: /futura/, DATE_TOO_OLD: /365 días/,
    BUYER_IS_ISSUER: /comprador no puede ser el emisor/, PAYMENT_FORM: /forma de pago/ };
  const unknown = reasons.filter((r) => !GENERIC.includes(r) && !(r in EXPLICIT) && r !== 'SAT_NOT_VALID');
  ok(unknown.length === 0, 'every INVALID_VOUCHER reason of the SQL has a decided text', unknown.join(','));
  ok(Object.keys(EXPLICIT).every((r) => reasons.includes(r)) && GENERIC.every((r) => reasons.includes(r)), 'no stale reason in this test', reasons.join(','));
  for (const [r, re] of Object.entries(EXPLICIT)) ok(re.test(reply({ sp: { status: 'INVALID_VOUCHER', reason: r } })), `reason ${r}`);
  for (const r of GENERIC) ok(/datos del comprobante no válidos/.test(reply({ sp: { status: 'INVALID_VOUCHER', reason: r } })), `reason ${r}: generic text`);
  ok(/cancelada ante el SAT/.test(reply({ sat: { status: 'CANCELADO' }, sp: { status: 'INVALID_VOUCHER', reason: 'SAT_NOT_VALID' } })), 'SAT cancelled');
  ok(/el SAT no la encontró/.test(reply({ sat: { status: 'NO_ENCONTRADO' }, sp: { status: 'INVALID_VOUCHER', reason: 'SAT_NOT_VALID' } })), 'SAT not found');
  ok(/No pude verificar la factura con el SAT/.test(reply({ sat: { status: 'ERROR' }, sp: { status: 'INVALID_VOUCHER', reason: 'SAT_NOT_VALID' } })) && /No pude verificar/.test(reply({ sp: { status: 'INVALID_VOUCHER', reason: 'SAT_NOT_VALID' } })), 'SAT unavailable');

  // parser errors (codes of the service, see cfdi-service README) and service problems
  const codes = { NOT_XML: /no es una factura CFDI 4.0/, INVALID_STRUCTURE: /no es una factura CFDI 4.0/, INVALID_BODY: /no es una factura CFDI 4.0/, UNSUPPORTED_VERSION: /Solo registro facturas CFDI 4.0 de ingreso/,
    UNSUPPORTED_TYPE: /Solo registro facturas CFDI 4.0 de ingreso/, UNSUPPORTED_CURRENCY: /Solo registro facturas CFDI 4.0 de ingreso/, NOT_STAMPED: /no es válida \(timbre/, INVALID_RFC: /no es válida \(timbre/,
    INVALID_AMOUNT: /no es válida \(timbre/, AMOUNTS_MISMATCH: /no es válida \(timbre/, TOO_LARGE: /demasiado grande/, TOO_MANY_CONCEPTS: /demasiado grande/, PAYLOAD_TOO_LARGE: /demasiado grande/,
    DOCTYPE_FORBIDDEN: /contenido no permitido/, INVALID_CHARS: /contenido no permitido/ };
  for (const [c, re] of Object.entries(codes)) ok(re.test(reply({ parse: { status: 'invalid', code: c } })), `parser code ${c}`);
  ok(/no es una factura CFDI 4.0/.test(reply({ parse: { status: 'invalid', code: 'SOMETHING_NEW' } })), 'unknown parser code -> invalid file text');
  const UNAV = /servicio de facturas no está disponible/;
  ok(UNAV.test(reply({ parse: { error: { message: 'ECONNREFUSED' } } })) && UNAV.test(reply({ parse: { status: 'error', code: 'UNAUTHORIZED' } })) && UNAV.test(reply({ parse: {} })), 'service unreachable / unauthorized / empty');
  ok(/No pude guardar el archivo original/.test(reply({ parse: { uuid: 'x' }, sat: { status: 'VIGENTE' }, store: { status: 'invalid', code: 'SHA256_MISMATCH' } })) && /No pude guardar/.test(reply({ parse: { uuid: 'x' }, sat: {}, store: { status: 'error', code: 'CONFLICT' } })), 'store refused');
  ok(UNAV.test(reply({ parse: { uuid: 'x' }, sat: {}, store: { error: { message: 'timeout' } } })), 'store unreachable');
  ok(UNAV.test(reply({})), 'nothing ran -> safe text');
  ok(/administrador/.test(reply({ entry: { ok: false, output: '⛔ Solo un administrador de la empresa puede registrar ventas por chat.' } })), 'input refusals are passed through (cfdi-service was never called)');
  // nothing from the services is echoed
  const leak = reply({ parse: { status: 'invalid', code: 'NOT_XML', message: 'SECRET-DETAIL', uuid: undefined } });
  ok(!/SECRET-DETAIL/.test(leak), 'service error details are never echoed');
}

console.log('Palma: respuesta de venta (fallback when the sub-workflow fails)');
{
  const FBC = node(chat, FB).parameters.jsCode;
  const run = (json) => runCode(FBC, {}, json)[0].json.output;
  ok(run({ output: '✅ Venta registrada.' }) === '✅ Venta registrada.', 'passes the sub-workflow text through');
  ok(/servicio de facturas no está disponible/.test(run({ error: { message: 'Workflow could not be started' } })) && /servicio de facturas/.test(run({})), 'error item -> fixed text, the webhook always answers');
  ok(!/Workflow could not/.test(run({ error: { message: 'Workflow could not be started' } })), 'the error message is not echoed');
}

console.log(`\n${pass} passed, ${fail} failed, ${skip} skipped`);
process.exit(fail ? 1 : 0);
