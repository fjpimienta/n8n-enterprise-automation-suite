import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import { parseCfdi, MAX_XML_BYTES } from '../lib/cfdi-parser/index.js';
import { createApp } from '../src/app.js';

// ---------------------------------------------------------------------------------------------------------------------
// Synthetic palm-sale voucher generator. Every value is fictional: obviously fake UUID, RFCs and names, dummy seals ("FAKE").
// Defaults: type I, MXN, PUE, form 03, one concept KGM, 7900.000000 x 3.940000 = 31126.000000, IVA rate 0%, ObjetoImp 02.
// ---------------------------------------------------------------------------------------------------------------------
const FAKE_UUID = '00000000-0000-4000-8000-0000000000AA';
const SEAL_ATTRS = ['Certificado', 'NoCertificado', 'Sello', 'SelloCFD', 'SelloSAT', 'NoCertificadoSAT', 'RfcProvCertif'];

function concepto(c = {}) {
  const o = {
    claveProdServ: '50307008', claveUnidad: 'KGM', cantidad: '7900.000000', valorUnitario: '3.940000', importe: '31126.000000',
    descripcion: 'Fruto fresco de palma de aceite (ticket 4521)', ...c,
  };
  const attr = (name, v) => (v === null || v === undefined ? '' : ` ${name}="${v}"`);
  return `    <cfdi:Concepto${attr('ClaveProdServ', o.claveProdServ)}${attr('Cantidad', o.cantidad)}${attr('ClaveUnidad', o.claveUnidad)}${attr('Descripcion', o.descripcion)}${attr('ValorUnitario', o.valorUnitario)}${attr('Importe', o.importe)} ObjetoImp="02" />`;
}

function saleXml(o = {}) {
  const v = {
    tipo: 'I', moneda: 'MXN', metodoPago: 'PUE', formaPago: '03', serie: null, folio: '77', descuento: null,
    subTotal: '31126.00', total: '31126.00', rate: '0.000000', taxBase: '31126.00', taxAmount: '0.00',
    receptorNombre: 'COMPRADOR FICTICIO SA DE CV', uuid: FAKE_UUID, conceptos: [concepto()], extraRoot: '', ...o,
  };
  const attr = (name, val) => (val === null || val === undefined ? '' : ` ${name}="${val}"`);
  return `<?xml version="1.0" encoding="utf-8"?>
<cfdi:Comprobante Version="4.0"${attr('Serie', v.serie)}${attr('Folio', v.folio)} Fecha="2026-11-10T09:30:00"${attr('FormaPago', v.formaPago)}${attr('MetodoPago', v.metodoPago)} SubTotal="${v.subTotal}"${attr('Descuento', v.descuento)} Moneda="${v.moneda}" Total="${v.total}" TipoDeComprobante="${v.tipo}" Exportacion="01" LugarExpedicion="00000" Certificado="FAKE-CERT" NoCertificado="FAKE-NOCERT" Sello="FAKE-SEAL" xmlns:cfdi="http://www.sat.gob.mx/cfd/4" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <cfdi:Emisor Rfc="AAA010101AAA" Nombre="PRODUCTOR FICTICIO SPR" RegimenFiscal="612" />
  <cfdi:Receptor Rfc="CCC040404CCC"${attr('Nombre', v.receptorNombre)} DomicilioFiscalReceptor="00000" RegimenFiscalReceptor="601" UsoCFDI="G01" />
  <cfdi:Conceptos>
${v.conceptos.join('\n')}
  </cfdi:Conceptos>
  <cfdi:Impuestos TotalImpuestosTrasladados="${v.taxAmount}">
    <cfdi:Traslados>
      <cfdi:Traslado Base="${v.taxBase}" Impuesto="002" TipoFactor="Tasa" TasaOCuota="${v.rate}" Importe="${v.taxAmount}" />
    </cfdi:Traslados>
  </cfdi:Impuestos>
  <cfdi:Complemento>
    <tfd:TimbreFiscalDigital xmlns:tfd="http://www.sat.gob.mx/TimbreFiscalDigital" Version="1.1" UUID="${v.uuid}" FechaTimbrado="2026-11-10T09:31:00" RfcProvCertif="FAKE-RFC" SelloCFD="FAKE-SELLO-CFD" NoCertificadoSAT="FAKE-NOCERT-SAT" SelloSAT="FAKE-SELLO-SAT" />
  </cfdi:Complemento>
  <cfdi:Addenda><x:Dato xmlns:x="urn:fake">FAKE-ADDENDA</x:Dato></cfdi:Addenda>
</cfdi:Comprobante>${v.extraRoot}`;
}

const sale = (xml) => parseCfdi(xml, { profile: 'sale' });
const okSale = (xml) => {
  const res = sale(xml);
  assert.equal(res.ok, true, res.message);
  return res.data;
};

const CONTRACT_TOP = [
  'conceptos', 'descuentoCents', 'emisor', 'fechaEmision', 'fechaTimbrado', 'folio', 'formaPago', 'metodoPago', 'moneda', 'receptor',
  'retenciones', 'serie', 'sourceSha256', 'subtotalCents', 'tipoComprobante', 'totalCents', 'traslados', 'uuid',
];
const CONTRACT_CONCEPT = ['cantidad', 'claveProdServ', 'claveUnidad', 'descripcion', 'importeCents', 'valorUnitario'];

describe('sale profile (library)', () => {
  test('default sample: contract keys, exact decimal strings and integer cents', () => {
    const d = okSale(saleXml());
    assert.equal(d.tipoComprobante, 'I');
    assert.equal(d.moneda, 'MXN');
    assert.equal(d.metodoPago, 'PUE');
    assert.equal(d.formaPago, '03');
    assert.equal(d.uuid, FAKE_UUID);
    assert.equal(d.folio, '77');
    assert.equal(d.serie, null);
    assert.equal(d.fechaEmision, '2026-11-10T09:30:00');
    assert.equal(d.fechaTimbrado, '2026-11-10T09:31:00');
    assert.equal(d.subtotalCents, 3112600);
    assert.equal(d.descuentoCents, 0);
    assert.equal(d.totalCents, 3112600);
    assert.deepEqual(d.traslados, [{ impuesto: '002', tipoFactor: 'Tasa', tasaOCuota: '0.000000', baseCents: 3112600, importeCents: 0 }]);
    assert.deepEqual(d.retenciones, []);
    assert.equal(d.conceptos.length, 1);
    const c = d.conceptos[0];
    assert.deepEqual(Object.keys(c).sort(), CONTRACT_CONCEPT);
    assert.deepEqual(c, {
      claveProdServ: '50307008', claveUnidad: 'KGM', cantidad: '7900.000000', valorUnitario: '3.940000',
      descripcion: 'Fruto fresco de palma de aceite (ticket 4521)', importeCents: 3112600,
    });
    assert.equal(typeof c.cantidad, 'string');
    assert.equal(typeof c.valorUnitario, 'string');
    assert.ok(Number.isInteger(c.importeCents));
  });

  test('quantity x unit price agrees with the concept amount for the default sample (7900 x 3.94 = 31126.00)', () => {
    const c = okSale(saleXml()).conceptos[0];
    // Exact integer arithmetic on the decimal strings: micro-units x micro-units = 1e-12 units.
    const micro = (s) => { const [i, f = ''] = s.split('.'); return BigInt(i + f.padEnd(6, '0')); };
    const product = micro(c.cantidad) * micro(c.valorUnitario); // in 1e-12
    assert.equal(product / 10n ** 10n, BigInt(c.importeCents));
  });

  test('ticket present, missing and changed pattern are all plain description text for the parser', () => {
    assert.match(okSale(saleXml()).conceptos[0].descripcion, /\(ticket 4521\)$/);
    assert.equal(okSale(saleXml({ conceptos: [concepto({ descripcion: 'Fruto fresco de palma de aceite' })] })).conceptos[0].descripcion, 'Fruto fresco de palma de aceite');
    assert.equal(okSale(saleXml({ conceptos: [concepto({ descripcion: 'Fruto, boleta 77' })] })).conceptos[0].descripcion, 'Fruto, boleta 77');
  });

  test('two concepts are parsed as given (the database decides)', () => {
    const d = okSale(saleXml({ conceptos: [concepto({ importe: '15563.000000', cantidad: '3950.000000' }), concepto({ importe: '15563.000000', cantidad: '3950.000000' })] }));
    assert.equal(d.conceptos.length, 2);
    for (const c of d.conceptos) assert.deepEqual(Object.keys(c).sort(), CONTRACT_CONCEPT);
  });

  test('USD and type E are rejected as before; PPD is parsed as given', () => {
    assert.equal(sale(saleXml({ moneda: 'USD' })).code, 'UNSUPPORTED_CURRENCY');
    assert.equal(sale(saleXml({ tipo: 'E' })).code, 'UNSUPPORTED_TYPE');
    assert.equal(sale(saleXml({ tipo: 'T' })).code, 'UNSUPPORTED_TYPE');
    assert.equal(okSale(saleXml({ metodoPago: 'PPD' })).metodoPago, 'PPD');
  });

  test('16% IVA: tax line and total are taken from the voucher', () => {
    const d = okSale(saleXml({ rate: '0.160000', taxAmount: '4980.16', total: '36106.16' }));
    assert.equal(d.totalCents, 3610616);
    assert.deepEqual(d.traslados, [{ impuesto: '002', tipoFactor: 'Tasa', tasaOCuota: '0.160000', baseCents: 3112600, importeCents: 498016 }]);
    // Totals still reconcile to the cent.
    assert.equal(sale(saleXml({ rate: '0.160000', taxAmount: '4980.16', total: '36106.15' })).code, 'AMOUNTS_MISMATCH');
  });

  test('discount', () => {
    const d = okSale(saleXml({ descuento: '126.00', total: '31000.00', taxBase: '31000.00' }));
    assert.equal(d.descuentoCents, 12600);
    assert.equal(d.totalCents, 3100000);
  });

  test('concept amounts with more than 2 decimals round half up to the cent (exact string arithmetic)', () => {
    assert.equal(okSale(saleXml({ conceptos: [concepto({ importe: '31126.004999' })] })).conceptos[0].importeCents, 3112600);
    assert.equal(okSale(saleXml({ conceptos: [concepto({ importe: '31126.005000' })] })).conceptos[0].importeCents, 3112601);
    assert.equal(okSale(saleXml({ conceptos: [concepto({ importe: '31126.005' })] })).conceptos[0].importeCents, 3112601);
    assert.equal(okSale(saleXml({ conceptos: [concepto({ importe: '31126' })] })).conceptos[0].importeCents, 3112600);
  });

  test('missing optional attributes become null (never undefined or omitted keys)', () => {
    const d = okSale(saleXml({ formaPago: null, metodoPago: null, serie: null, folio: null, receptorNombre: null }));
    assert.equal(d.formaPago, null);
    assert.equal(d.metodoPago, null);
    assert.equal(d.serie, null);
    assert.equal(d.folio, null);
    assert.equal(d.receptor.nombre, null);
    assert.deepEqual(Object.keys(d).filter((k) => CONTRACT_TOP.includes(k)).sort(), CONTRACT_TOP);
    const c = okSale(saleXml({ conceptos: [concepto({ claveUnidad: null, claveProdServ: null })] })).conceptos[0];
    assert.equal(c.claveUnidad, null);
    assert.equal(c.claveProdServ, null);
  });

  test('quantity and unit price must be exact decimals with at most 6 decimals (sale profile only)', () => {
    for (const bad of ['1e3', '1.1234567', '-1', '', '.5', 'abc', '1,000']) {
      const xml = saleXml({ conceptos: [concepto({ cantidad: bad })] });
      assert.equal(sale(xml).code, 'INVALID_AMOUNT', `cantidad "${bad}"`);
      assert.equal(sale(saleXml({ conceptos: [concepto({ valorUnitario: bad })] })).code, 'INVALID_AMOUNT', `valorUnitario "${bad}"`);
    }
    assert.equal(sale(saleXml({ conceptos: [concepto({ cantidad: null })] })).code, 'INVALID_AMOUNT');
    assert.equal(sale(saleXml({ conceptos: [concepto({ valorUnitario: null })] })).code, 'INVALID_AMOUNT');
    // The default profile does not look at them: the expense flow keeps accepting what it always accepted.
    assert.equal(parseCfdi(saleXml({ conceptos: [concepto({ cantidad: '1.1234567' })] })).ok, true);
  });

  test('unknown profile is refused', () => {
    assert.deepEqual(parseCfdi(saleXml(), { profile: 'other' }), { ok: false, code: 'INVALID_PROFILE', message: 'unknown parse profile' });
  });

  test('seals, certificates and the Addenda never appear (keys or values)', () => {
    const d = okSale(saleXml());
    const out = JSON.stringify(d);
    assert.ok(!/certificad|sello|nocertificado|rfcprovcertif|addenda|FAKE/i.test(out), out);
    const keys = [];
    const walk = (x) => { if (x && typeof x === 'object') for (const [k, v] of Object.entries(x)) { keys.push(k); walk(v); } };
    walk(d);
    for (const k of SEAL_ATTRS) assert.ok(!keys.some((x) => x.toLowerCase() === k.toLowerCase()), `unexpected key ${k}`);
  });

  test('hostile input is rejected exactly as in the default profile', () => {
    const base = saleXml();
    const cases = {
      DOCTYPE_FORBIDDEN: [base.replace('<cfdi:Comprobante', '<!DOCTYPE x [<!ENTITY a "b">]><cfdi:Comprobante'), base.replace('<?xml version="1.0" encoding="utf-8"?>', '<?xml version="1.0"?><!DOCTYPE lol [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;&a;">]>')],
      INVALID_CHARS: [base.replace('palma de aceite', 'palma\u0001de aceite')],
      TOO_LARGE: [`<?xml version="1.0"?>${' '.repeat(MAX_XML_BYTES)}`],
      NOT_XML: ['%PDF-1.7', base.slice(0, base.length - 20)],
    };
    for (const [code, list] of Object.entries(cases)) {
      for (const xml of list) {
        const res = sale(xml);
        assert.equal(res.ok, false, `expected ${code}`);
        assert.equal(res.code, code);
        assert.equal(parseCfdi(xml).code, code, 'default profile answers the same');
      }
    }
    // A second root element is refused (same answer in both profiles).
    const twoRoots = saleXml({ extraRoot: '<cfdi:Comprobante Version="4.0" />' });
    assert.equal(sale(twoRoots).ok, false);
    assert.equal(sale(twoRoots).code, parseCfdi(twoRoots).code);
    // More than 200 concepts.
    const many = saleXml({ conceptos: Array.from({ length: 201 }, () => concepto()) });
    assert.equal(sale(many).code, 'TOO_MANY_CONCEPTS');
  });

  test('entities in text are decoded only from the five predefined ones (no expansion)', () => {
    const d = okSale(saleXml({ conceptos: [concepto({ descripcion: 'Fruto &amp; palma &lt;(ticket 9)&gt;' })] }));
    assert.equal(d.conceptos[0].descripcion, 'Fruto & palma <(ticket 9)>');
  });
});

describe('expense behavior is unchanged', () => {
  const fixtures = ['038BA478-7C33-46E4-9315-38CDDE3FDBAB', 'BD673276-380F-405B-B565-2D9ED4C73D84'];
  const read = (n) => readFileSync(new URL(`./fixtures/${n}.xml`, import.meta.url), 'utf8');
  const NEW_TOP = ['tipoComprobante', 'formaPago', 'metodoPago'];
  const NEW_CONCEPT = ['claveUnidad', 'cantidad', 'valorUnitario'];

  test('default profile output has no new key, on the existing fixtures and on the sale sample', () => {
    for (const xml of [...fixtures.map(read), saleXml()]) {
      const d = parseCfdi(xml).data;
      for (const k of NEW_TOP) assert.ok(!(k in d), `top-level ${k}`);
      for (const c of d.conceptos) {
        assert.deepEqual(Object.keys(c).sort(), ['claveProdServ', 'descripcion', 'importeCents']);
      }
    }
  });

  test('the sale profile is a strict superset: every default value is identical', () => {
    for (const xml of [...fixtures.map(read), saleXml()]) {
      const def = parseCfdi(xml);
      const ext = parseCfdi(xml, { profile: 'sale' });
      if (!def.ok) { assert.equal(ext.ok, false); continue; }
      if (!ext.ok) { assert.equal(ext.code, 'INVALID_AMOUNT'); continue; } // a fixture whose Cantidad is not a plain decimal
      const strip = (d) => {
        const o = { ...d, conceptos: d.conceptos.map((c) => Object.fromEntries(Object.entries(c).filter(([k]) => !NEW_CONCEPT.includes(k)))) };
        for (const k of NEW_TOP) delete o[k];
        return o;
      };
      assert.deepEqual(strip(ext.data), def.data);
    }
  });
});

describe('/parse with the sale profile (service)', () => {
  const TOKEN = 'test-token-not-a-secret';
  let storageRoot; let server; let base; let logs;
  const b64 = (s) => Buffer.from(s).toString('base64');

  before(async () => {
    storageRoot = mkdtempSync(path.join(tmpdir(), 'cfdi-sale-'));
    logs = [];
    server = createApp({ token: TOKEN, storageRoot, fetch: async () => { throw new Error('no network in tests'); }, satTimeoutMs: 50, log: (l) => logs.push(l) });
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => { server.close(); rmSync(storageRoot, { recursive: true, force: true }); });

  async function parse(body) {
    const res = await fetch(`${base}/parse`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-internal-token': TOKEN }, body: JSON.stringify(body) });
    return { status: res.status, json: await res.json() };
  }

  test('profile "sale" returns exactly the contract keys; without profile the response is the legacy one', async () => {
    const xml = saleXml();
    const ext = await parse({ xmlBase64: b64(xml), profile: 'sale' });
    assert.equal(ext.status, 200);
    assert.deepEqual(Object.keys(ext.json).sort(), CONTRACT_TOP);
    assert.deepEqual(Object.keys(ext.json.receptor).sort(), ['nombre', 'rfc']);
    assert.deepEqual(Object.keys(ext.json.emisor).sort(), ['nombre', 'rfc']);
    assert.deepEqual(Object.keys(ext.json.conceptos[0]).sort(), CONTRACT_CONCEPT);
    assert.equal(ext.json.conceptos[0].cantidad, '7900.000000');
    assert.equal(ext.json.conceptos[0].valorUnitario, '3.940000');
    assert.equal(ext.json.conceptos[0].importeCents, 3112600);
    assert.equal(ext.json.sourceSha256, createHash('sha256').update(xml).digest('hex'));

    const legacy = await parse({ xmlBase64: b64(xml) });
    assert.equal(legacy.status, 200);
    assert.deepEqual(Object.keys(legacy.json).sort(), CONTRACT_TOP.filter((k) => !['tipoComprobante', 'formaPago', 'metodoPago'].includes(k)));
    assert.deepEqual(Object.keys(legacy.json.conceptos[0]).sort(), ['claveProdServ', 'descripcion', 'importeCents']);
  });

  test('every value of the contract has the documented type', async () => {
    const { json: d } = await parse({ xmlBase64: b64(saleXml()), profile: 'sale' });
    for (const k of ['tipoComprobante', 'uuid', 'fechaEmision', 'fechaTimbrado', 'moneda', 'formaPago', 'metodoPago', 'sourceSha256']) assert.equal(typeof d[k], 'string', k);
    for (const k of ['subtotalCents', 'descuentoCents', 'totalCents']) assert.ok(Number.isInteger(d[k]), k);
    assert.match(d.fechaEmision, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/);
    assert.match(d.fechaTimbrado, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/);
    assert.ok(Array.isArray(d.traslados) && Array.isArray(d.retenciones) && Array.isArray(d.conceptos));
    assert.deepEqual(Object.keys(d.traslados[0]).sort(), ['baseCents', 'importeCents', 'impuesto', 'tasaOCuota', 'tipoFactor']);
  });

  test('no seal or certificate key or value in the response, and nothing sensitive in the logs', async () => {
    const r = await parse({ xmlBase64: b64(saleXml()), profile: 'sale' });
    assert.ok(!/certificad|sello|nocertificado|rfcprovcertif|addenda|FAKE/i.test(JSON.stringify(r.json)));
    assert.ok(logs.length > 0);
    for (const l of logs) {
      assert.deepEqual(Object.keys(l).sort(), ['bytes', 'method', 'ms', 'route', 'status']);
      assert.ok(!/FAKE|CCC040404CCC|AAA010101AAA|COMPRADOR|PRODUCTOR/.test(JSON.stringify(l)));
    }
  });

  test('unknown profile is a 422 INVALID_BODY; errors keep their shape', async () => {
    assert.deepEqual(await parse({ xmlBase64: b64(saleXml()), profile: 'other' }), { status: 422, json: { status: 'invalid', code: 'INVALID_BODY' } });
    assert.deepEqual(await parse({ xmlBase64: b64(saleXml({ moneda: 'USD' })), profile: 'sale' }), { status: 422, json: { status: 'invalid', code: 'UNSUPPORTED_CURRENCY' } });
    assert.deepEqual(await parse({ xmlBase64: b64(saleXml({ conceptos: [concepto({ cantidad: '1e3' })] })), profile: 'sale' }), { status: 422, json: { status: 'invalid', code: 'INVALID_AMOUNT' } });
    const evil = saleXml().replace('<cfdi:Comprobante', '<!DOCTYPE x [<!ENTITY a "b">]><cfdi:Comprobante');
    assert.deepEqual(await parse({ xmlBase64: b64(evil), profile: 'sale' }), { status: 422, json: { status: 'invalid', code: 'DOCTYPE_FORBIDDEN' } });
  });

  test('/store ignores the profile and keeps its answer', async () => {
    const xml = saleXml();
    const sha = createHash('sha256').update(xml).digest('hex');
    const res = await fetch(`${base}/store`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-internal-token': TOKEN },
      body: JSON.stringify({ tenantId: '7', xmlBase64: b64(xml), sha256: sha, profile: 'sale' }) });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { originalPath: `7/2026/11/${sha}.xml` });
  });
});
