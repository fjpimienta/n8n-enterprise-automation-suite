#!/usr/bin/env node
// Offline test of the XML router of the web chat (no n8n, no network, no database): structure, the one rewired connection, the real expressions
// and code of the new nodes run with stubbed inputs, and an exhaustive table of classifier answers -> route. The classifier itself (SQL 109)
// is NOT exercised here: this proves the routing and the fail-closed behaviour of the workflow, not the classification.
// Usage: node workflows/09-MCP-Agent-Cattle/v6/tests/test_xml_router.mjs [--baseline-ref origin/develop]
// Exit code 0 = every check passed, 1 = at least one FAIL.
import fs from 'node:fs';
import path from 'node:path';
import { diffExports, loadExport } from './diff_workflow_exports.mjs';

const V6 = path.resolve(import.meta.dirname, '..');
const REPO = path.resolve(V6, '../../..');
const CHAT_FILE = 'workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json';
const REF = process.argv.includes('--baseline-ref') ? process.argv[process.argv.indexOf('--baseline-ref') + 1] : 'origin/develop';

const raw = fs.readFileSync(path.join(V6, 'v6_ai_chat_cattle.json'), 'utf8');
const chat = JSON.parse(raw);

let pass = 0; let fail = 0; let skip = 0;
const ok = (cond, name, detail) => { if (cond) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, detail ? `\n        ${detail}` : ''); } };
const skipped = (name, why) => { skip++; console.log('  SKIP', name, `(${why})`); };
const node = (name) => chat.nodes.find((n) => n.name === name);
const targets = (from) => (chat.connections[from]?.main ?? []).map((g) => g.map((x) => x.node));

const XML = 'XML adjunto?'; const PREP = 'Preparar XML del router'; const PREP_OK = 'XML del router OK'; const PARSE = 'CFDI Parse del router';
const PARSE_OK = 'Parse del router OK'; const RFCS = 'RFC del comprobante'; const CLS = 'Clasificar comprobante'; const ROUTE = 'Ruta del comprobante';
const TEXT = 'Texto fijo del comprobante';
const NEW = [XML, PREP, PREP_OK, PARSE, PARSE_OK, RFCS, CLS, ROUTE, TEXT];

// --- stubs: the real expressions / code of the export run against these ---------------------------------------------------
const evalExpr = (expr, scope) => {
  if (!/^=\{\{[\s\S]*\}\}$/.test(expr)) throw new Error('not an expression: ' + String(expr).slice(0, 40));
  return new Function('$', '$json', `return (${expr.replace(/^=\{\{/, '').replace(/\}\}$/, '')});`)(scope.$, scope.json);
};
const mkScope = (nodes, json = {}) => ({
  json,
  $: (name) => {
    if (!(name in nodes)) throw new Error(`reference to a node that does not exist in the stub: ${name}`);
    const n = nodes[name];
    return { first: () => ({ json: n.json }), item: { json: n.json }, isExecuted: n.executed !== false };
  },
});
const runCode = (code, nodes, inputJson = {}) => new Function('$', '$input', code)(mkScope(nodes).$, { first: () => ({ json: inputJson }) });
const b64 = (s) => Buffer.from(s).toString('base64');
const RFC_RE = /[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}/;
const UUID_RE = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/i;

// =====================================================================================================================
console.log('structure');
{
  const names = chat.nodes.map((n) => n.name); const ids = chat.nodes.map((n) => n.id);
  ok(new Set(names).size === names.length && new Set(ids).size === ids.length, 'node names and ids are unique');
  ok(NEW.every((n) => node(n)), `the ${NEW.length} router nodes exist`);
  const conns = Object.entries(chat.connections).flatMap(([from, c]) => Object.values(c).flatMap((arr) => arr.flatMap((g) => g.map((x) => [from, x.node]))));
  ok(conns.every(([a, b]) => names.includes(a) && names.includes(b)), 'every connection joins existing nodes');
  const reach = new Set(conns.flatMap(([a, b]) => [a, b]));
  ok(chat.nodes.every((n) => reach.has(n.name)), 'no orphan node');
  ok(JSON.stringify(targets('Empresa Valida')) === JSON.stringify([[XML], ['Respond Empresa No Valida']]), '"Empresa Valida": valid company -> router IF, invalid company -> the same refusal as today');
  ok(JSON.stringify(targets('Dominio')) === JSON.stringify([['Palma: XML adjunto'], ['Trae Factura']]), '"Dominio" is unchanged (PALM / OTHER)');
  ok(JSON.stringify(targets(XML)) === JSON.stringify([[PREP], ['Dominio']]), 'no XML attached -> "Dominio" (today\'s path)');
  ok(JSON.stringify(targets(PREP_OK)) === JSON.stringify([[PARSE], ['Dominio']]) && JSON.stringify(targets(PARSE_OK)) === JSON.stringify([[RFCS], ['Dominio']]),
    'an XML that cannot be prepared or parsed -> "Dominio" (today\'s messages)');
  ok(JSON.stringify(targets(PREP)) === `[["${PREP_OK}"]]` && JSON.stringify(targets(PARSE)) === `[["${PARSE_OK}"]]` && JSON.stringify(targets(RFCS)) === `[["${CLS}"]]` && JSON.stringify(targets(CLS)) === `[["${ROUTE}"]]`, 'prepare -> parse -> RFCs -> classifier -> route');
  ok(JSON.stringify(targets(ROUTE)) === JSON.stringify([['Venta Palma XML'], ['Trae Factura'], ['Trae Factura'], [TEXT]]), 'route outputs: palm sale / livestock chain / livestock chain / fixed text');
  ok(JSON.stringify(targets(TEXT)) === '[["Respond to Webhook"]]', 'the fixed text is answered through the existing "Respond to Webhook"');
  // nothing reaches a registration path except through the route
  const into = (target) => conns.filter(([, b]) => b === target).map(([a]) => a).sort();
  ok(JSON.stringify(into('Venta Palma XML')) === JSON.stringify(['Palma: XML adjunto', ROUTE].sort()), '"Venta Palma XML" is reached by its existing IF and by the route only');
  ok(JSON.stringify(into('Trae Factura')) === JSON.stringify(['Dominio', ROUTE, ROUTE].sort()), '"Trae Factura" is reached by "Dominio" and by the route only');
  ok(JSON.stringify(into('Dominio')) === JSON.stringify(['Empresa Valida', XML, PREP_OK, PARSE_OK].filter((x) => x !== 'Empresa Valida').sort()), '"Dominio" is reached only by the IFs of the router (no-XML, unreadable, unparsed)');
  ok(JSON.stringify(into(XML)) === '["Empresa Valida"]', 'the router IF is reached only from "Empresa Valida"');
}

console.log('inputs and credentials');
{
  const cls = node(CLS);
  ok(cls.type === 'n8n-nodes-base.postgres' && cls.parameters.query === 'SELECT public.sp_cfdi_classify($1::text, $2::text, $3::text, $4::text) AS result;', 'the classifier is called through sp_cfdi_classify with four text parameters');
  const qr = cls.parameters.options.queryReplacement;
  ok(qr === "={{ [ String($('Resolver Empresa Chat').first().json.id_company), $('Validar Token').first().json.data.user.user, String($json.emisor_rfc ?? ''), String($json.receptor_rfc ?? '') ] }}", 'tenant and e-mail come from the verified session nodes, RFCs from the parsed voucher, as an array of query parameters');
  ok(!/chatInput|AI Agent|fromAI|Webhook/.test(JSON.stringify(cls.parameters)), 'the classifier never reads the message text, the model or the request body');
  ok(JSON.stringify(cls.credentials) === JSON.stringify(node('Crear Borrador Factura').credentials), 'same Postgres credential as the other nodes of the workflow (reference only)');
  ok(cls.onError === 'continueRegularOutput' && cls.alwaysOutputData === true, 'a database failure still produces an item (the route answers, fail closed)');
  const parse = node(PARSE); const orig = node('CFDI Parse');
  ok(JSON.stringify(parse.parameters) === JSON.stringify(orig.parameters) && JSON.stringify(parse.credentials) === JSON.stringify(orig.credentials) && !/profile/.test(JSON.stringify(parse.parameters)), 'the parse call is the existing one (default profile, same service and credential)');
  ok(JSON.stringify(node(XML).parameters.conditions.conditions[0].leftValue) === JSON.stringify(node('Palma: XML adjunto').parameters.conditions.conditions[0].leftValue), 'the XML check is the expression of "Palma: XML adjunto"');
  const code = NEW.map((n) => node(n)).filter((n) => n.parameters.jsCode).map((n) => n.parameters.jsCode).join('\n');
  ok(!/console\.|debugger|require\(|fetch\(/.test(code), 'no logging, require or network call in the new code nodes');
  ok(!/Bearer |eyJ[A-Za-z0-9]|sk-[A-Za-z0-9]|x-internal-token/i.test(JSON.stringify(NEW.map(node))), 'no token-like string in the new nodes');
  const noIds = JSON.stringify(NEW.map(node), (k, v) => (k === 'id' ? undefined : v));   // node and condition ids are random UUIDs by design
  ok(!RFC_RE.test(noIds) && !UUID_RE.test(noIds), 'no RFC or UUID literal in the new nodes (outside their own ids)');
  const creds = chat.nodes.flatMap((n) => Object.values(n.credentials ?? {}));
  ok(creds.every((c) => Object.keys(c).sort().join() === 'id,name'), 'credentials are references only (id and name)');
  const refs = [...JSON.stringify(NEW.map(node)).matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]);
  ok(refs.every((r) => chat.nodes.some((n) => n.name === r)), 'every $(\'...\') reference of the new nodes exists', [...new Set(refs)].join());
}

// =====================================================================================================================
console.log('XML attached? and preparation (real expression and code, stubbed inputs)');
{
  const expr = node(XML).parameters.conditions.conditions[0].leftValue;
  const f = (name, type) => ({ chatInput: 'x', file: { name, type, size: 10, base64: 'AAAA' } });
  const check = (body) => evalExpr(expr, mkScope({ Webhook: { json: { body } } }));
  ok(check(f('a.xml', 'text/xml')) === true && check(f('A.XML', 'application/xml')) === true && check(f('a.xml', 'application/octet-stream')) === true, 'an .xml attachment of an xml-like type');
  ok(check(f('a.pdf', 'application/pdf')) === false && check(f('a.png', 'image/png')) === false && check({ chatInput: 'x' }) === false && check(f('a.xml', 'application/pdf')) === false, 'PDF, image, no file and a mismatched type stay on today\'s path');
  const run = (file) => runCode(node(PREP).parameters.jsCode, { Webhook: { json: { body: { chatInput: 'x', file } } } })[0].json;
  ok(run({ type: 'text/xml', base64: b64('<a/>') }).file_ok === true && run({ type: 'application/xml', base64: b64('<a/>') }).xmlBase64 === b64('<a/>'), 'a valid XML passes and its base64 is cleaned');
  ok(run({ type: 'text/xml', base64: '***' }).file_ok === false && run({ type: 'text/xml', base64: '' }).file_ok === false && run({ type: 'text/xml' }).file_ok === false && run({ type: 'application/pdf', base64: 'AAAA' }).file_ok === false, 'bad base64, empty, missing and a wrong type do not pass');
  ok(run({ type: 'text/xml', base64: 'A'.repeat(7200004) }).file_ok === false, 'an oversize base64 is refused before any call');
  ok(run({ type: 'text/xml', base64: 'AA AA\nAA==' }).file_ok === true, 'white space inside the base64 is removed');
  const rf = (p) => runCode(node(RFCS).parameters.jsCode, {}, p)[0].json;
  ok(JSON.stringify(rf({ emisor: { rfc: ' abc010101aa1 ' }, receptor: { rfc: 'def010101bb2', nombre: 'X' }, totalCents: 5 })) === JSON.stringify({ emisor_rfc: 'ABC010101AA1', receptor_rfc: 'DEF010101BB2' }), 'only the two RFCs (upper case) are passed on');
  ok(rf({}).emisor_rfc === '' && rf({ emisor: null, receptor: null }).receptor_rfc === '', 'missing parties give empty RFCs (the classifier then answers UNKNOWN / INVALID_INPUT)');
}

// =====================================================================================================================
console.log('route and fixed texts: exhaustive table of classifier answers');
const R = node(ROUTE);
const route = (result) => {
  const scope = mkScope({}, { result });
  for (let i = 0; i < R.parameters.rules.values.length; i++) {
    const rule = R.parameters.rules.values[i];
    const all = rule.conditions.conditions.every((c) => {
      const l = evalExpr(c.leftValue, scope);
      return c.operator.operation === 'equals' ? l === c.rightValue : c.operator.operation === 'notEquals' ? l !== c.rightValue : (() => { throw new Error('operator'); })();
    });
    if (all) return i;
  }
  return R.parameters.rules.values.length;   // fallback output
};
const OUT = ['Venta Palma XML', 'Trae Factura', 'Trae Factura', TEXT];
const textOf = (result) => runCode(node(TEXT).parameters.jsCode, {}, { result })[0].json.output;
{
  ok(R.parameters.options.fallbackOutput === 'extra', 'the Switch has a fallback output (anything not listed)');
  const roles = ['SALE', 'EXPENSE', 'AMBIGUOUS', 'UNKNOWN', 'SURPRISE', '', 'sale'];
  const reasons = ['ISSUER_OWN', 'RECEPTOR_OWN', 'SELF_INVOICE', 'BOTH_ROLES', 'NEITHER', 'INVALID_INPUT', 'FORBIDDEN', 'DISABLED', ''];
  const doms = ['PALM', 'LIVESTOCK', '', 'OTHER', null];
  let n = 0; const wrong = [];
  for (const role of roles) for (const reason of reasons) for (const dom of doms) {
    n++;
    const out = OUT[route({ role, reason, company_domain: dom })];
    const d = dom ?? '';
    let want;
    if (role === 'SALE' && d === 'PALM') want = 'Venta Palma XML';
    else if (role === 'EXPENSE' && d !== 'PALM') want = 'Trae Factura';
    else if (role === 'UNKNOWN' && reason === 'NEITHER' && d !== 'PALM') want = 'Trae Factura';
    else want = TEXT;
    if (out !== want) wrong.push(`${role}/${reason}/${d} -> ${out}, expected ${want}`);
  }
  ok(wrong.length === 0, `${n} combinations of role x reason x domain route as designed`, wrong.slice(0, 5).join('; '));
  ok([undefined, null, {}, [], 'x', 5, { error: 'x' }, { role: null }].every((r) => OUT[route(r)] === TEXT), 'an empty, malformed or error answer goes to the fixed text (fail closed)');
  ok(OUT[route({ role: 'EXPENSE', reason: 'RECEPTOR_OWN', company_domain: 'LIVESTOCK' })] === 'Trae Factura' && OUT[route({ role: 'EXPENSE', reason: 'RECEPTOR_OWN', company_domain: null })] === 'Trae Factura', 'EXPENSE of a livestock or unknown-domain company -> the existing chain');
  // the texts
  const cases = [
    [{ role: 'SALE', reason: 'ISSUER_OWN', company_domain: 'LIVESTOCK' }, /venta/i, /no registra ventas/],
    [{ role: 'EXPENSE', reason: 'RECEPTOR_OWN', company_domain: 'PALM' }, /Gastos/, /facturado/],
    [{ role: 'AMBIGUOUS', reason: 'BOTH_ROLES', company_domain: 'LIVESTOCK' }, /emisora y como receptora/, /No registré nada/],
    [{ role: 'AMBIGUOUS', reason: 'SELF_INVOICE', company_domain: 'PALM' }, /emisora y como receptora/, /No registré nada/],
    [{ role: 'UNKNOWN', reason: 'NEITHER', company_domain: 'PALM' }, /no coinciden con ningún RFC configurado/, /No registré nada/],
    [{ role: 'UNKNOWN', reason: 'FORBIDDEN' }, /No pude clasificar/, /No registré nada/],
    [{ role: 'UNKNOWN', reason: 'INVALID_INPUT', company_domain: 'PALM' }, /No pude clasificar/, /No registré nada/],
    [{ role: 'UNKNOWN', reason: 'DISABLED' }, /No pude clasificar/, /No registré nada/],
    [undefined, /No pude clasificar/, /No registré nada/],
  ];
  const bad = cases.filter(([r, a, b]) => !(a.test(textOf(r)) && b.test(textOf(r)))).map(([r]) => JSON.stringify(r));
  ok(bad.length === 0, 'each case has its fixed Spanish text and says that nothing was registered', bad.join('; '));
  const all = new Set(cases.map(([r]) => textOf(r)));
  ok(all.size === 5, 'five distinct texts');
  ok([...all].every((t) => typeof t === 'string' && !RFC_RE.test(t) && !UUID_RE.test(t) && !/\d/.test(t) && !/<|>|`/.test(t)), 'no text carries an RFC, a UUID, a digit (amount) or markup');
  const echo = textOf({ role: 'SALE', reason: 'ISSUER_OWN', company_domain: 'LIVESTOCK', emisor_rfc: 'ABC010101AA1', nombre: 'ACME SA', uuid: 'AAAAAAAA-0000-4000-8000-000000000001' });
  ok(!/ABC010101AA1|ACME|AAAAAAAA/.test(echo), 'a classifier answer with extra fields is never echoed');
}

// =====================================================================================================================
console.log('diff against the baseline');
{
  let baseline = null;
  try { baseline = loadExport(`git:${REF}:${CHAT_FILE}`, REPO); } catch { /* handled below */ }
  if (!baseline) skipped('diff against the baseline', `git ref ${REF} not available`);
  else if (baseline.nodes.some((n) => n.name === XML)) skipped('diff against the baseline', `${REF} already contains the router`);
  else {
    const d = diffExports(baseline, chat);
    ok(JSON.stringify(d.added.sort()) === JSON.stringify([...NEW].sort()), `exactly the ${NEW.length} router nodes were added`, d.added.join(','));
    ok(d.removed.length === 0 && d.changedNodes.length === 0, 'no node removed or changed', JSON.stringify(d.changedNodes));
    ok(d.unchangedNodes === baseline.nodes.length, `all ${baseline.nodes.length} existing nodes are byte-identical (parameters, credentials, position, ids)`);
    const from = d.changedConnections.map((c) => c.from).sort();
    ok(JSON.stringify(from) === JSON.stringify(['Empresa Valida', ...NEW].sort()), 'connections: "Empresa Valida" plus the new sources only', from.join());
    const ev = d.changedConnections.find((c) => c.from === 'Empresa Valida');
    ok(JSON.stringify(ev.before.main[1]) === JSON.stringify(ev.after.main[1]) && ev.before.main[0][0].node === 'Dominio' && ev.after.main[0][0].node === XML, 'only the valid-company output of "Empresa Valida" was rewired');
    ok(d.changedTop.length === 0, 'settings, name, tags and ids unchanged', d.changedTop.join(','));
  }
}
ok(!/chatInput/.test(JSON.stringify(NEW.map(node))), 'the classifier path never reads chatInput');

console.log(`\n${pass} passed, ${fail} failed, ${skip} skipped`);
process.exit(fail ? 1 : 0);
