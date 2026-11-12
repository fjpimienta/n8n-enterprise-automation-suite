#!/usr/bin/env node
// LOCAL end-to-end check of the palm sale route WITHOUT n8n: a tiny interpreter runs the real nodes of the exports (the expressions, the code
// nodes, the IF conditions, the HTTP calls and the Postgres call) against
//   * a cfdi-service started in-process (real parser, real routes; the SAT call is mocked),
//   * a THROWAWAY database (its name must contain "test" or "rehearsal") that already has migration 104, a palm test company and a FAKE issuer RFC.
// It is not n8n: it proves that the exported JSON, wired as written, produces the right reply and database rows. It never touches production.
// Manual use only (needs docker + a throwaway database); the offline test (test_palm_sale_route.mjs) is the one that runs in CI.
//
// Prerequisites (all synthetic): database E2E_DB with 104 applied; company E2E_PALM (palm, flagged is_test, fake issuer RFC = AAA010101AAA),
//   E2E_CATTLE (a non-palm company), users admin.e2e@example.invalid (ADMIN of both) and editor.e2e@example.invalid (EDITOR of the palm company).
// Usage:  E2E_DB=rehearsal_x [E2E_CONTAINER=n8n-enterprise-db] [E2E_PALM=10] [E2E_CATTLE=11] node e2e_palm_sale_local.mjs
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createApp } from '../../../../microservices/cfdi-service/src/app.js';

const V6 = path.resolve(import.meta.dirname, '..');
const DB = process.env.E2E_DB ?? '';
const CONTAINER = process.env.E2E_CONTAINER ?? 'n8n-enterprise-db';
const PALM = Number(process.env.E2E_PALM ?? 10);
const CATTLE = Number(process.env.E2E_CATTLE ?? 11);
if (!/(test|rehearsal)/.test(DB)) { console.log('SKIP: set E2E_DB to a throwaway database (name must contain "test" or "rehearsal")'); process.exit(0); }

const chat = JSON.parse(fs.readFileSync(path.join(V6, 'v6_ai_chat_cattle.json'), 'utf8'));
const sub = JSON.parse(fs.readFileSync(path.join(V6, 'v6_palm_sale_from_xml.json'), 'utf8'));
const find = (wf, name) => wf.nodes.find((n) => n.name === name);

let pass = 0; let fail = 0;
const ok = (c, name, detail) => { if (c) { pass++; console.log('  PASS', name); } else { fail++; console.log('  FAIL', name, detail ? `\n        ${detail}` : ''); } };

// ---------------------------------------------------------------- database (psql through docker, client-side parameter formatting like pg-promise)
const literal = (v) => (typeof v === 'number' ? String(v) : `'${String(v).replace(/'/g, "''")}'`);
const format = (query, values) => query.replace(/\$(\d+)/g, (_, n) => literal(values[Number(n) - 1]));
const psql = (sql) => execFileSync('docker', ['exec', '-i', CONTAINER, 'psql', '-X', '-U', 'n8n_user', '-d', DB, '-At', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).trim();
const queryRow = (query, values) => JSON.parse(psql(`SELECT row_to_json(t) FROM (${format(query, values).replace(/;\s*$/, '')}) t;`));

// ---------------------------------------------------------------- cfdi-service (in-process; SAT mocked)
let satStatus = 'Vigente';
const calls = [];
const satReply = () => new Response(`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><ConsultaResponse xmlns="http://tempuri.org/"><ConsultaResult xmlns:a="http://schemas.datacontract.org/2004/07/Sat.Cfdi.Negocio.ConsultaCfdi.Servicio" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><a:Estado>${satStatus}</a:Estado></ConsultaResult></ConsultaResponse></s:Body></s:Envelope>`, { status: 200 });
const TOKEN = 'local-e2e-token-not-a-secret';
const logs = [];
const server = createApp({ token: TOKEN, storageRoot: mkdtempSync(path.join(tmpdir(), 'palm-e2e-')), fetch: async () => satReply(), satTimeoutMs: 500, log: (l) => { logs.push(l); calls.push(l.route); } });
await new Promise((r) => server.listen(0, '127.0.0.1', r));
let port = server.address().port;

// ---------------------------------------------------------------- tiny interpreter
const expr = (e, scope) => {
  if (typeof e !== 'string' || !e.startsWith('={{')) return e;
  return new Function('$', '$json', `return (${e.replace(/^=\{\{/, '').replace(/\}\}$/, '')});`)(scope.$, scope.json);
};
async function runWorkflow(wf, startName, inputItem) {
  const ctx = {};
  const $ = (name) => ({
    first: () => { if (!ctx[name]) throw new Error(`no execution data for ${name}`); return ctx[name].items[0]; },
    get isExecuted() { return !!ctx[name]; },
  });
  const queue = [[startName, [inputItem]]];
  let last = null;
  while (queue.length) {
    const [name, items] = queue.shift();
    const n = find(wf, name);
    const scope = { $, json: items[0]?.json ?? {} };
    let out; let branch = 0;
    switch (n.type) {
      case 'n8n-nodes-base.executeWorkflowTrigger': out = items; break;
      case 'n8n-nodes-base.code': out = new Function('$', '$input', n.parameters.jsCode)($, { first: () => items[0] }); break;
      case 'n8n-nodes-base.if': { const c = n.parameters.conditions.conditions[0]; const v = expr(c.leftValue, scope); branch = v ? 0 : 1; out = items; break; }
      case 'n8n-nodes-base.httpRequest': {
        const url = n.parameters.url.replace('http://cfdi-service:4100', `http://127.0.0.1:${port}`);
        const body = expr(n.parameters.jsonBody, scope);
        try {
          const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-internal-token': TOKEN }, body, signal: AbortSignal.timeout(n.parameters.options.timeout) });
          const text = await res.text();
          let json; try { json = JSON.parse(text); } catch { json = { error: { message: 'non-json response' } }; }
          out = [{ json }];
        } catch (e) { out = [{ json: { error: { message: String(e.message).slice(0, 80) } } }]; }
        break;
      }
      case 'n8n-nodes-base.postgres': {
        const values = expr(n.parameters.options.queryReplacement, scope);
        out = [{ json: queryRow(n.parameters.query, values) }];
        break;
      }
      default: throw new Error(`unsupported node type ${n.type}`);
    }
    ctx[name] = { items: out };
    last = out;
    const groups = wf.connections[name]?.main ?? [];
    for (const t of groups[branch] ?? []) queue.push([t.node, out]);
  }
  return last[0].json;
}

// ---------------------------------------------------------------- parent hand-off: the real IF expression and Execute Workflow mapping
async function chatRoute({ body, role = 'ADMIN', company = PALM, email = 'admin.e2e@example.invalid' }) {
  const nodes = {
    Webhook: { json: { body } },
    'Resolver Empresa Chat': { json: { id_company: company, role, business_domain: 'PALM' } },
    'Validar Token': { json: { data: { user: { user: email, role: 'ADMIN' } } } },
  };
  const $ = (name) => ({ first: () => ({ json: nodes[name].json }) });
  const scope = { $, json: {} };
  const isXml = expr(find(chat, 'Palma: XML adjunto').parameters.conditions.conditions[0].leftValue, scope);
  if (!isXml) return { routed: false };
  const mapping = find(chat, 'Venta Palma XML').parameters.workflowInputs.value;
  const input = Object.fromEntries(Object.entries(mapping).map(([k, v]) => [k, expr(v, scope)]));
  const reply = await runWorkflow(sub, 'When Executed by Another Workflow', { json: input });
  const fb = new Function('$', '$input', find(chat, 'Palma: respuesta de venta').parameters.jsCode)($, { first: () => ({ json: reply }) });
  return { routed: true, output: fb[0].json.output };
}

// ---------------------------------------------------------------- synthetic vouchers (fictional values, dummy seals)
const voucher = ({ uuid, desc = 'Fruto fresco de palma (ticket 4521)', emisor = 'AAA010101AAA', metodo = 'PUE', moneda = 'MXN' }) => `<?xml version="1.0" encoding="utf-8"?>
<cfdi:Comprobante Version="4.0" Folio="77" Fecha="2026-11-10T09:30:00" FormaPago="03" MetodoPago="${metodo}" SubTotal="31126.00" Moneda="${moneda}" Total="31126.00" TipoDeComprobante="I" Exportacion="01" Certificado="FAKE" Sello="FAKE" xmlns:cfdi="http://www.sat.gob.mx/cfd/4">
  <cfdi:Emisor Rfc="${emisor}" Nombre="PRODUCTOR FICTICIO" RegimenFiscal="612" />
  <cfdi:Receptor Rfc="CCC040404CCC" Nombre="COMPRADOR FICTICIO" UsoCFDI="G01" />
  <cfdi:Conceptos>
    <cfdi:Concepto ClaveProdServ="50307008" Cantidad="7900.000000" ClaveUnidad="KGM" Descripcion="${desc}" ValorUnitario="3.940000" Importe="31126.000000" ObjetoImp="02" />
  </cfdi:Conceptos>
  <cfdi:Impuestos TotalImpuestosTrasladados="0.00"><cfdi:Traslados><cfdi:Traslado Base="31126.00" Impuesto="002" TipoFactor="Tasa" TasaOCuota="0.000000" Importe="0.00" /></cfdi:Traslados></cfdi:Impuestos>
  <cfdi:Complemento><tfd:TimbreFiscalDigital xmlns:tfd="http://www.sat.gob.mx/TimbreFiscalDigital" Version="1.1" UUID="${uuid}" FechaTimbrado="2026-11-10T09:31:00" SelloCFD="FAKE" SelloSAT="FAKE" /></cfdi:Complemento>
</cfdi:Comprobante>`;
const file = (xml, name = 'venta.xml', type = 'text/xml') => ({ chatInput: 'registra esta venta por favor', sessionId: 's', tenant_id: 999, file: { name, type, size: xml.length, base64: Buffer.from(xml).toString('base64') } });
const U = (n) => `00000000-0000-4000-8000-0000000C${String(n).padStart(4, '0')}`;
const tenantRows = (u) => psql(`SELECT count(*) FROM agri_sale_invoices WHERE uuid = '${u}'`);

console.log(`local end-to-end (database ${DB}, palm company ${PALM}, non-palm company ${CATTLE})`);
const t0 = calls.length;

let r = await chatRoute({ body: file(voucher({ uuid: U(1) })) });
ok(r.routed && /^✅ Venta registrada\./.test(r.output) && r.output.includes('Ticket: 4521') && r.output.includes('7,900 kg a $3.94/kg') && r.output.includes('Total: $31,126.00 MXN'), 'ADMIN + XML with a ticket: sale registered', r.output);
ok(!/00000000-0000|Sello|FAKE|AAA010101AAA|CCC040404CCC|<\?xml/.test(r.output), 'the reply carries no UUID, RFC, seal or XML');
ok(tenantRows(U(1)) === '1' && psql(`SELECT ticket_ref||'/'||total_cents||'/'||quantity||'/'||is_test||'/'||registered_by_email FROM agri_sale_invoices WHERE uuid='${U(1)}'`) === '4521/3112600/7900.000000/true/admin.e2e@example.invalid', 'row stored from the voucher and the verified session');
ok(calls.slice(t0).join() === '/parse,/sat-status,/store', 'cfdi-service called in order: parse, sat-status, store', calls.slice(t0).join());

r = await chatRoute({ body: file(voucher({ uuid: U(2), desc: 'Fruto fresco de palma' })) });
ok(/Venta registrada/.test(r.output) && /Avisos:\n• No encontré el número de ticket/.test(r.output), 'no ticket: registered with the warning in the same message', r.output);
r = await chatRoute({ body: file(voucher({ uuid: U(1) })) });
ok(/ya estaba registrada/.test(r.output) && tenantRows(U(1)) === '1', 'same voucher again: already registered, no new row', r.output);

const before = calls.length;
r = await chatRoute({ body: file(voucher({ uuid: U(3) })), role: 'EDITOR', email: 'editor.e2e@example.invalid' });
ok(/administrador/.test(r.output) && calls.length === before && tenantRows(U(3)) === '0', 'EDITOR: fixed text, cfdi-service not called, nothing written', r.output);
r = await chatRoute({ body: file(voucher({ uuid: U(4) })), company: CATTLE });
ok(/no es de palma/.test(r.output) && tenantRows(U(4)) === '0', 'non-palm company: the procedure answers NOT_PALM', r.output);
r = await chatRoute({ body: file(voucher({ uuid: U(5), emisor: 'ZZZ999999ZZZ' })) });
ok(/RFC emisor de la factura no corresponde/.test(r.output) && tenantRows(U(5)) === '0', 'issuer RFC not in the company list', r.output);
r = await chatRoute({ body: file(voucher({ uuid: U(6), metodo: 'PPD' })) });
ok(/solo se acepta pago en una sola exhibición/.test(r.output), 'PPD voucher: reason shown', r.output);
r = await chatRoute({ body: file(voucher({ uuid: U(7), moneda: 'USD' })) });
ok(/Solo registro facturas CFDI 4.0 de ingreso en pesos/.test(r.output), 'USD voucher: parser error text', r.output);
r = await chatRoute({ body: file('<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "b">]><cfdi:Comprobante/>') });
ok(/contenido no permitido/.test(r.output), 'hostile XML refused by the parser', r.output);
r = await chatRoute({ body: file('not an xml at all') });
ok(/no es una factura CFDI 4.0/.test(r.output), 'a .xml file that is not XML', r.output);
satStatus = 'Cancelado';
r = await chatRoute({ body: file(voucher({ uuid: U(8) })) });
ok(/cancelada ante el SAT/.test(r.output) && tenantRows(U(8)) === '0', 'SAT says cancelled: refused even in the test company', r.output);
satStatus = 'Vigente';

// void then reload (void done by the procedure, as the dashboard will)
const saleId = psql(`SELECT id FROM agri_sale_invoices WHERE uuid='${U(1)}' AND status='ACTIVE'`);
psql(`SELECT sp_agri_void_sale(${PALM}, 'admin.e2e@example.invalid', '${saleId}', 'Voided by the end-to-end check')`);
r = await chatRoute({ body: file(voucher({ uuid: U(1) })) });
ok(/Venta registrada/.test(r.output) && /había sido anulada antes/.test(r.output) && psql(`SELECT count(*)||'/'||count(*) FILTER (WHERE status='ACTIVE') FROM agri_sale_invoices WHERE uuid='${U(1)}'`) === '2/1', 'voided voucher can be loaded again (new row, warning)', r.output);

r = await chatRoute({ body: { chatInput: 'hola', file: { name: 'x.pdf', type: 'application/pdf', size: 3, base64: 'AAAA' } } });
ok(r.routed === false, 'a PDF is not routed to the sale route (today\'s behavior)');
ok(logs.every((l) => Object.keys(l).sort().join() === 'bytes,method,ms,route,status') && !JSON.stringify(logs).match(/FAKE|COMPRADOR|AAA010101AAA/), 'cfdi-service logged nothing but method, route, status, size and time');

// service unreachable
server.close();
await new Promise((res) => setTimeout(res, 100));
r = await chatRoute({ body: file(voucher({ uuid: U(9) })) });
ok(/servicio de facturas no está disponible/.test(r.output) && tenantRows(U(9)) === '0', 'cfdi-service unreachable: fixed text, nothing written', r.output);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
