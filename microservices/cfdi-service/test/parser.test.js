import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { MAX_XML_BYTES, ROUNDING_TOLERANCE_CENTS, parseCfdi } from '../lib/cfdi-parser/index.js';

const fixture = (name) => readFileSync(new URL(`./fixtures/${name}.xml`, import.meta.url), 'utf8');
const DIESEL = fixture('038BA478-7C33-46E4-9315-38CDDE3FDBAB');
const AGRO = fixture('BD673276-380F-405B-B565-2D9ED4C73D84');

function mutate(xml, from, to) {
  assert.ok(xml.includes(from), `fixture does not contain ${from}`);
  return xml.replace(from, to);
}

function assertRejects(xml, code) {
  const res = parseCfdi(xml);
  assert.equal(res.ok, false, `expected ${code}`);
  assert.equal(res.code, code, res.message);
}

test('tolerance is exact', () => {
  assert.equal(ROUNDING_TOLERANCE_CENTS, 0);
});

test('diesel invoice', () => {
  const res = parseCfdi(DIESEL);
  assert.equal(res.ok, true);
  const d = res.data;
  assert.equal(d.uuid, '038BA478-7C33-46E4-9315-38CDDE3FDBAB');
  assert.equal(d.serie, 'CFDI3');
  assert.equal(d.folio, '146730');
  assert.equal(d.fechaEmision, '2026-10-30T08:49:01');
  assert.equal(d.fechaTimbrado, '2026-10-30T08:49:13');
  assert.deepEqual(d.emisor, { rfc: 'OES010209154', nombre: 'OPERADORA DE ESTACIONES DE SERVICIO VIDA' });
  assert.deepEqual(d.receptor, { rfc: 'XAXX010101000', nombre: 'PERSONA DE PRUEBA', usoCfdi: 'G03' });
  assert.equal(d.moneda, 'MXN');
  assert.equal(d.subtotalCents, 345842);
  assert.equal(d.descuentoCents, 0);
  assert.equal(d.totalCents, 400013);
  assert.deepEqual(d.traslados, [
    { impuesto: '002', tipoFactor: 'Tasa', tasaOCuota: '0.160000', baseCents: 338569, importeCents: 54171 },
  ]);
  assert.deepEqual(d.retenciones, []);
  assert.deepEqual(d.conceptos, [{ claveProdServ: '15101505', descripcion: 'DIESEL', importeCents: 345842 }]);
  assert.equal(d.sourceSha256, createHash('sha256').update(DIESEL, 'utf8').digest('hex'));
});

test('agricultural supplies invoice', () => {
  const res = parseCfdi(AGRO);
  assert.equal(res.ok, true);
  const d = res.data;
  assert.equal(d.uuid, 'BD673276-380F-405B-B565-2D9ED4C73D84');
  assert.equal(d.subtotalCents, 30400);
  assert.equal(d.descuentoCents, 1774);
  assert.equal(d.totalCents, 30630);
  assert.deepEqual(d.traslados, [
    { impuesto: '002', tipoFactor: 'Tasa', tasaOCuota: '0.000000', baseCents: 30630, importeCents: 0 },
    { impuesto: '003', tipoFactor: 'Tasa', tasaOCuota: '0.070000', baseCents: 28626, importeCents: 2004 },
  ]);
  assert.equal(d.conceptos.length, 2);
  assert.equal(d.conceptos[0].descripcion, 'TacsaEster; 950 mls.');
});

test('accepts a BOM and returns the UUID uppercase', () => {
  const lower = mutate(DIESEL, 'UUID="038BA478-7C33-46E4-9315-38CDDE3FDBAB"', 'UUID="038ba478-7c33-46e4-9315-38cdde3fdbab"');
  const res = parseCfdi(`﻿${lower}`);
  assert.equal(res.ok, true);
  assert.equal(res.data.uuid, '038BA478-7C33-46E4-9315-38CDDE3FDBAB');
});

test('Exento traslado has no importe and is excluded from the sums', () => {
  let xml = mutate(
    DIESEL,
    '<cfdi:Impuestos TotalImpuestosTrasladados="541.71"><cfdi:Traslados><cfdi:Traslado Base="3385.69" Importe="541.71" Impuesto="002" TasaOCuota="0.160000" TipoFactor="Tasa"/>',
    '<cfdi:Impuestos><cfdi:Traslados><cfdi:Traslado Base="3458.42" Impuesto="002" TipoFactor="Exento"/>',
  );
  xml = mutate(xml, 'Total="4000.13"', 'Total="3458.42"');
  const res = parseCfdi(xml);
  assert.equal(res.ok, true);
  assert.deepEqual(res.data.traslados, [
    { impuesto: '002', tipoFactor: 'Exento', tasaOCuota: null, baseCents: 345842, importeCents: null },
  ]);
});

test('retenciones are subtracted', () => {
  const xml = mutate(
    mutate(DIESEL, '</cfdi:Traslados></cfdi:Impuestos><cfdi:Complemento>', '</cfdi:Traslados><cfdi:Retenciones><cfdi:Retencion Base="3385.69" Impuesto="001" TipoFactor="Tasa" TasaOCuota="0.100000" Importe="100.00"/></cfdi:Retenciones></cfdi:Impuestos><cfdi:Complemento>'),
    'Total="4000.13"',
    'Total="3900.13"',
  );
  const res = parseCfdi(xml);
  assert.equal(res.ok, true);
  assert.equal(res.data.retenciones[0].importeCents, 10000);
});

test('rejects DOCTYPE', () => {
  assertRejects(mutate(DIESEL, '?><cfdi:', '?><!DOCTYPE foo><cfdi:'), 'DOCTYPE_FORBIDDEN');
  assertRejects(mutate(DIESEL, '?><cfdi:', '?><!doctype foo><cfdi:'), 'DOCTYPE_FORBIDDEN');
});

test('rejects an entity-expansion payload', () => {
  const bomb =
    '<!DOCTYPE lolz [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;"><!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>';
  const xml = mutate(mutate(DIESEL, '?><cfdi:', `?>${bomb}<cfdi:`), 'Descripcion="DIESEL"', 'Descripcion="&c;"');
  assertRejects(xml, 'DOCTYPE_FORBIDDEN');
});

test('rejects oversize input', () => {
  assertRejects(`${DIESEL}<!--${'x'.repeat(MAX_XML_BYTES)}-->`, 'TOO_LARGE');
});

test('rejects input that is not XML', () => {
  assertRejects('hello world', 'NOT_XML');
  assertRejects('{"a":1}', 'NOT_XML');
  assertRejects(`  ${DIESEL}`, 'NOT_XML');
  assertRejects(DIESEL.slice(0, 600), 'NOT_XML');
  assertRejects(undefined, 'NOT_XML');
});

test('rejects unsupported version, namespace, type and currency', () => {
  assertRejects(mutate(DIESEL, 'Version="4.0"', 'Version="3.3"'), 'UNSUPPORTED_VERSION');
  assertRejects(mutate(DIESEL, 'xmlns:cfdi="http://www.sat.gob.mx/cfd/4"', 'xmlns:cfdi="http://www.sat.gob.mx/cfd/3"'), 'UNSUPPORTED_VERSION');
  assertRejects(mutate(DIESEL, 'TipoDeComprobante="I"', 'TipoDeComprobante="E"'), 'UNSUPPORTED_TYPE');
  assertRejects(mutate(DIESEL, 'Moneda="MXN"', 'Moneda="USD"'), 'UNSUPPORTED_CURRENCY');
});

test('rejects invoices without a valid single stamp', () => {
  assertRejects(DIESEL.replace(/<cfdi:Complemento>.*<\/cfdi:Complemento>/, ''), 'NOT_STAMPED');
  assertRejects(mutate(DIESEL, 'UUID="038BA478-7C33-46E4-9315-38CDDE3FDBAB"', 'UUID="038BA478-7C33-46E4-9315-38CDDE3FDBA"'), 'NOT_STAMPED');
  const stamp = DIESEL.match(/<tfd:TimbreFiscalDigital .*?\/>/)[0];
  assertRejects(mutate(DIESEL, stamp, stamp + stamp), 'NOT_STAMPED');
});

test('rejects invalid RFC', () => {
  assertRejects(mutate(DIESEL, 'Rfc="OES010209154"', 'Rfc="OES01020915"'), 'INVALID_RFC');
  assertRejects(mutate(DIESEL, 'Rfc="XAXX010101000"', 'Rfc="XAXX01010100!"'), 'INVALID_RFC');
});

test('rejects a total off by one cent, with the numbers in the message', () => {
  for (const total of ['4000.14', '4000.12']) {
    const res = parseCfdi(mutate(DIESEL, 'Total="4000.13"', `Total="${total}"`));
    assert.equal(res.ok, false);
    assert.equal(res.code, 'AMOUNTS_MISMATCH');
    assert.match(res.message, /400013/);
    assert.match(res.message, new RegExp(total.replace('.', '')));
  }
});

test('rejects TotalImpuestos that do not match their lines', () => {
  assertRejects(mutate(DIESEL, 'TotalImpuestosTrasladados="541.71"', 'TotalImpuestosTrasladados="541.72"'), 'AMOUNTS_MISMATCH');
});

test('rejects malformed amounts', () => {
  assertRejects(mutate(DIESEL, 'SubTotal="3458.42"', 'SubTotal="3458.420"'), 'INVALID_AMOUNT');
  assertRejects(mutate(DIESEL, 'SubTotal="3458.42"', 'SubTotal="abc"'), 'INVALID_AMOUNT');
  assertRejects(mutate(DIESEL, 'SubTotal="3458.42"', 'SubTotal="-3458.42"'), 'INVALID_AMOUNT');
  assertRejects(mutate(DIESEL, 'SubTotal="3458.42"', 'SubTotal="1e3"'), 'INVALID_AMOUNT');
  assertRejects(mutate(AGRO, 'Descuento="17.74"', 'Descuento="17.745"'), 'INVALID_AMOUNT');
});

test('rejects more than 200 conceptos and accepts exactly 200', () => {
  const concepto = DIESEL.match(/<cfdi:Concepto .*?<\/cfdi:Concepto>/)[0];
  const withN = (n) => DIESEL.replace(concepto, concepto.repeat(n));
  assertRejects(withN(201), 'TOO_MANY_CONCEPTS');
  const res = parseCfdi(withN(200));
  assert.equal(res.ok === false && res.code === 'TOO_MANY_CONCEPTS', false);
});

test('rejects control characters in a Descripcion', () => {
  assertRejects(mutate(DIESEL, 'Descripcion="DIESEL"', 'Descripcion="DIE\u0001SEL"'), 'INVALID_CHARS');
  assertRejects(mutate(DIESEL, 'Descripcion="DIESEL"', 'Descripcion="DIE\u0000SEL"'), 'INVALID_CHARS');
});

test('strips encoded control characters and caps descripcion at 200 chars', () => {
  const res = parseCfdi(mutate(DIESEL, 'Descripcion="DIESEL"', `Descripcion="DIE&#1;SEL &amp; ${'A'.repeat(300)}"`));
  assert.equal(res.ok, true);
  const { descripcion } = res.data.conceptos[0];
  assert.equal(descripcion.length, 200);
  assert.ok(descripcion.startsWith('DIESEL & AAA'));
});

test('never leaks Addenda, Certificado or Sello', () => {
  const sealed = mutate(
    DIESEL,
    'NoCertificado="00001000000727082423"',
    'NoCertificado="00001000000727082423" Certificado="CERT_SECRET_VALUE" Sello="SELLO_SECRET_VALUE"',
  ).replace('Version="1.1"', 'Version="1.1" SelloCFD="SELLOCFD_SECRET" SelloSAT="SELLOSAT_SECRET"');
  const res = parseCfdi(sealed);
  assert.equal(res.ok, true);
  const out = JSON.stringify(res);
  for (const needle of ['egas', 'extraInfo', 'requestId', 'B986449E', 'Addenda', 'CERT_SECRET_VALUE', 'SELLO_SECRET_VALUE', 'SELLOCFD_SECRET', 'SELLOSAT_SECRET', 'Certificado', 'Sello"']) {
    assert.ok(!out.includes(needle), `output leaks ${needle}`);
  }
  assert.ok(!Object.keys(res.data).some((k) => /addenda|certificado|sello/i.test(k)));
});
