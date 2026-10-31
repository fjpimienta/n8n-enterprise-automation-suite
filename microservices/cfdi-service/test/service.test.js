import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import { createApp, MAX_BODY_BYTES } from '../src/app.js';
import { buildEnvelope, formatTotal, SAT_URL, SOAP_ACTION } from '../src/sat.js';

const TOKEN = 'test-token-not-a-secret';
const fixtureBytes = (name) => readFileSync(new URL(`./fixtures/${name}.xml`, import.meta.url));
const DIESEL = fixtureBytes('038BA478-7C33-46E4-9315-38CDDE3FDBAB');
const AGRO = fixtureBytes('BD673276-380F-405B-B565-2D9ED4C73D84');
const b64 = (buf) => buf.toString('base64');
const sha = (buf) => createHash('sha256').update(buf).digest('hex');

const satReply = (estado, status = 200) =>
  new Response(
    `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><ConsultaResponse xmlns="http://tempuri.org/"><ConsultaResult xmlns:a="http://schemas.datacontract.org/2004/07/Sat.Cfdi.Negocio.ConsultaCfdi.Servicio"><a:CodigoEstatus>S</a:CodigoEstatus><a:Estado>${estado}</a:Estado></ConsultaResult></ConsultaResponse></s:Body></s:Envelope>`,
    { status },
  );

let storageRoot;
let satFetch;
let logs;
let server;
let base;

before(async () => {
  storageRoot = mkdtempSync(path.join(tmpdir(), 'cfdi-store-'));
  logs = [];
  satFetch = async () => satReply('Vigente');
  server = createApp({ token: TOKEN, storageRoot, fetch: (...a) => satFetch(...a), satTimeoutMs: 200, log: (l) => logs.push(l) });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
  rmSync(storageRoot, { recursive: true, force: true });
});

async function call(route, body, { token = TOKEN, method = 'POST', raw } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers['x-internal-token'] = token;
  const res = await fetch(`${base}${route}`, { method, headers, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)) });
  return { status: res.status, json: await res.json() };
}

test('refuses to start without a token or storage root', () => {
  assert.throws(() => createApp({ storageRoot }), /CFDI_SERVICE_TOKEN/);
  assert.throws(() => createApp({ token: TOKEN }), /STORAGE_ROOT/);
});

describe('/health and auth', () => {
  test('health needs no token', async () => {
    const r = await call('/health', undefined, { method: 'GET', token: null });
    assert.deepEqual(r, { status: 200, json: { ok: true } });
  });

  test('wrong or missing token is 401 on every other route', async () => {
    for (const route of ['/parse', '/sat-status', '/store']) {
      assert.equal((await call(route, {}, { token: 'wrong' })).status, 401);
      assert.equal((await call(route, {}, { token: null })).status, 401);
    }
  });

  test('unknown route 404, wrong method 405', async () => {
    assert.equal((await call('/nope', {}, {})).status, 404);
    assert.equal((await call('/parse', undefined, { method: 'GET' })).status, 405);
  });
});

describe('/parse', () => {
  test('diesel: exact keys and totals reconcile', async () => {
    const r = await call('/parse', { xmlBase64: b64(DIESEL) });
    assert.equal(r.status, 200);
    const d = r.json;
    assert.deepEqual(Object.keys(d).sort(), [
      'conceptos', 'descuentoCents', 'emisor', 'fechaEmision', 'fechaTimbrado', 'folio', 'moneda', 'receptor',
      'retenciones', 'serie', 'sourceSha256', 'subtotalCents', 'totalCents', 'traslados', 'uuid',
    ]);
    assert.deepEqual(Object.keys(d.receptor).sort(), ['nombre', 'rfc']);
    assert.deepEqual(Object.keys(d.emisor).sort(), ['nombre', 'rfc']);
    assert.equal(d.uuid, '038BA478-7C33-46E4-9315-38CDDE3FDBAB');
    assert.equal(d.sourceSha256, sha(DIESEL));
    const taxes = d.traslados.reduce((a, t) => a + t.importeCents, 0) - d.retenciones.reduce((a, t) => a + t.importeCents, 0);
    assert.equal(d.subtotalCents - d.descuentoCents + taxes, d.totalCents);
    assert.equal(d.totalCents, 400013);
    for (const n of [d.subtotalCents, d.descuentoCents, d.totalCents, ...d.traslados.map((t) => t.baseCents)]) {
      assert.ok(Number.isInteger(n));
    }
  });

  test('mixed taxes with discount (IVA 0% + IEPS 7%)', async () => {
    const { json: d } = await call('/parse', { xmlBase64: b64(AGRO) });
    assert.equal(d.traslados.length, 2);
    assert.deepEqual(d.traslados.map((t) => t.impuesto), ['002', '003']);
    assert.equal(d.subtotalCents - d.descuentoCents + 0 + 2004, d.totalCents);
    assert.equal(d.conceptos.length, 2);
  });

  test('Addenda, Certificado and Sello never appear in the output', async () => {
    assert.ok(DIESEL.toString().includes('Addenda'), 'fixture must carry an Addenda');
    const { json } = await call('/parse', { xmlBase64: b64(DIESEL) });
    const out = JSON.stringify(json);
    assert.ok(!/addenda|certificado|sello/i.test(out));
  });

  test('conceptos summary is capped at 20', async () => {
    const xml = DIESEL.toString();
    const m = /<cfdi:Concepto [^>]*?(?:\/>|>[\s\S]*?<\/cfdi:Concepto>)/.exec(xml);
    assert.ok(m, 'fixture has a Concepto');
    // Concepto-level sums are not reconciled by the parser, so repeating the node keeps totals valid.
    const many = xml.replace(m[0], m[0].repeat(25));
    const { status, json } = await call('/parse', { xmlBase64: b64(Buffer.from(many)) });
    assert.equal(status, 200);
    assert.equal(json.conceptos.length, 20);
  });

  test('DOCTYPE is rejected with 422', async () => {
    const evil = Buffer.from(DIESEL.toString().replace(/(<cfdi:Comprobante)/, '<!DOCTYPE x [<!ENTITY a "b">]>$1'));
    const r = await call('/parse', { xmlBase64: b64(evil) });
    assert.deepEqual(r, { status: 422, json: { status: 'invalid', code: 'DOCTYPE_FORBIDDEN' } });
  });

  test('non-XML bytes, bad base64 and bad JSON are 422', async () => {
    assert.deepEqual((await call('/parse', { xmlBase64: b64(Buffer.from('%PDF-1.7 hello')) })).json, { status: 'invalid', code: 'NOT_XML' });
    assert.deepEqual((await call('/parse', { xmlBase64: b64(Buffer.from([0xff, 0xfe, 0x3c, 0x00])) })).json, { status: 'invalid', code: 'NOT_XML' });
    assert.equal((await call('/parse', { xmlBase64: '***' })).json.code, 'INVALID_BODY');
    assert.equal((await call('/parse', undefined, { raw: '{not json' })).status, 422);
  });

  test('tampered amounts are rejected by the parser', async () => {
    const bad = Buffer.from(DIESEL.toString().replace('Total="4000.13"', 'Total="4000.14"'));
    const r = await call('/parse', { xmlBase64: b64(bad) });
    assert.equal(r.status, 422);
    assert.equal(r.json.code, 'AMOUNTS_MISMATCH');
  });

  test('oversize body is 413', async () => {
    const r = await call('/parse', undefined, { raw: JSON.stringify({ xmlBase64: 'A'.repeat(MAX_BODY_BYTES + 10) }) });
    assert.equal(r.status, 413);
    assert.equal(r.json.code, 'PAYLOAD_TOO_LARGE');
  });
});

describe('/sat-status', () => {
  const query = { uuid: '038BA478-7C33-46E4-9315-38CDDE3FDBAB', emisorRfc: 'OES010209154', receptorRfc: 'XAXX010101000', totalCents: 400013 };

  test('request shape matches the WSDL contract', async () => {
    let seen;
    satFetch = async (url, init) => ((seen = { url, init }), satReply('Vigente'));
    await call('/sat-status', query);
    assert.equal(seen.url, SAT_URL);
    assert.equal(seen.init.headers.SOAPAction, SOAP_ACTION);
    assert.ok(seen.init.body.includes('<tem:expresionImpresa>?re=OES010209154&amp;rr=XAXX010101000&amp;tt=0000004000.130000&amp;id=038BA478-7C33-46E4-9315-38CDDE3FDBAB</tem:expresionImpresa>'));
  });

  test('total formatting is 17 chars without floats', () => {
    assert.equal(formatTotal(400013), '0000004000.130000');
    assert.equal(formatTotal(5), '0000000000.050000');
    assert.equal(formatTotal(10), '0000000000.100000');
    assert.equal(formatTotal(400013).length, 17);
    assert.ok(buildEnvelope({ ...query, emisorRfc: 'A&B010101AB1' }).includes('A&amp;B010101AB1'));
  });

  test('maps all four outcomes', async () => {
    const cases = [
      [() => satReply('Vigente'), 'VIGENTE'],
      [() => satReply('Cancelado'), 'CANCELADO'],
      [() => satReply('No Encontrado'), 'NO_ENCONTRADO'],
      [() => satReply('Algo raro'), 'ERROR'],
    ];
    for (const [reply, expected] of cases) {
      satFetch = async () => reply();
      assert.deepEqual(await call('/sat-status', query), { status: 200, json: { status: expected } });
    }
  });

  test('5xx and network failure retry once, then ERROR', async () => {
    let calls = 0;
    satFetch = async () => (calls++, satReply('Vigente', 503));
    assert.equal((await call('/sat-status', query)).json.status, 'ERROR');
    assert.equal(calls, 2);

    calls = 0;
    satFetch = async () => (++calls === 1 ? Promise.reject(new Error('ECONNRESET')) : satReply('Cancelado'));
    assert.equal((await call('/sat-status', query)).json.status, 'CANCELADO');
    assert.equal(calls, 2);
  });

  test('timeout is ERROR', async () => {
    satFetch = (url, init) => new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted'))));
    assert.equal((await call('/sat-status', query)).json.status, 'ERROR');
  });

  test('invalid input is 422 and never reaches SAT', async () => {
    let calls = 0;
    satFetch = async () => (calls++, satReply('Vigente'));
    for (const bad of [{ ...query, uuid: 'x' }, { ...query, emisorRfc: '<x>' }, { ...query, totalCents: 1.5 }, { ...query, totalCents: -1 }, { ...query, totalCents: '100' }]) {
      assert.equal((await call('/sat-status', bad)).status, 422);
    }
    assert.equal(calls, 0);
  });
});

describe('/store', () => {
  const diesel = { tenantId: '12', xmlBase64: b64(DIESEL), sha256: sha(DIESEL) };

  test('stores under tenant/yyyy/mm/sha.xml with mode 0640, idempotent re-store', async () => {
    const r = await call('/store', diesel);
    assert.equal(r.status, 200);
    assert.equal(r.json.originalPath, `12/2026/10/${sha(DIESEL)}.xml`);
    const file = path.join(storageRoot, r.json.originalPath);
    assert.deepEqual(readFileSync(file), DIESEL);
    assert.equal(statSync(file).mode & 0o777, 0o640);

    const again = await call('/store', diesel);
    assert.deepEqual(again, r);
  });

  test('never overwrites an existing file with different content', async () => {
    const target = path.join(storageRoot, '13/2026/10', `${sha(DIESEL)}.xml`);
    await call('/store', { ...diesel, tenantId: '13' });
    writeFileSync(target, 'tampered');
    const r = await call('/store', { ...diesel, tenantId: '13' });
    assert.equal(r.status, 409);
    assert.equal(readFileSync(target, 'utf8'), 'tampered');
  });

  test('sha mismatch is rejected and nothing is written', async () => {
    const r = await call('/store', { ...diesel, tenantId: '14', sha256: sha(AGRO) });
    assert.deepEqual(r, { status: 422, json: { status: 'invalid', code: 'SHA256_MISMATCH' } });
    assert.throws(() => statSync(path.join(storageRoot, '14')));
  });

  test('bad tenantId and path traversal are rejected', async () => {
    for (const tenantId of ['0', '01', '../x', '1/../../etc', '1.5', '12345678901', '', ' 1', 12, null]) {
      const r = await call('/store', { ...diesel, tenantId });
      assert.equal(r.status, 422, `tenantId ${JSON.stringify(tenantId)}`);
      assert.equal(r.json.code, 'INVALID_TENANT');
    }
    for (const sha256 of ['../../evil', `${sha(DIESEL)}/../x`]) {
      assert.equal((await call('/store', { ...diesel, sha256 })).status, 422);
    }
    assert.throws(() => statSync(path.join(storageRoot, '..', 'x')));
  });

  test('DOCTYPE and non-XML cannot be stored', async () => {
    const evil = Buffer.from(DIESEL.toString().replace(/(<cfdi:Comprobante)/, '<!DOCTYPE x>$1'));
    assert.equal((await call('/store', { tenantId: '15', xmlBase64: b64(evil), sha256: sha(evil) })).json.code, 'DOCTYPE_FORBIDDEN');
    const junk = Buffer.from('hello');
    assert.equal((await call('/store', { tenantId: '15', xmlBase64: b64(junk), sha256: sha(junk) })).json.code, 'NOT_XML');
  });
});

test('request logs contain only method, route, status, size and duration', async () => {
  logs.length = 0;
  await call('/parse', { xmlBase64: b64(DIESEL) });
  await call('/sat-status', { uuid: '038BA478-7C33-46E4-9315-38CDDE3FDBAB', emisorRfc: 'OES010209154', receptorRfc: 'XAXX010101000', totalCents: 1 });
  await new Promise((r) => setTimeout(r, 20));
  assert.ok(logs.length >= 2);
  for (const l of logs) {
    assert.deepEqual(Object.keys(l).sort(), ['bytes', 'method', 'ms', 'route', 'status']);
  }
  const all = JSON.stringify(logs);
  assert.ok(!all.includes('OES010209154') && !all.includes('XAXX010101000') && !all.includes(b64(DIESEL).slice(0, 40)));
});
