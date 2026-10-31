import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseCfdi } from '../lib/cfdi-parser/index.js';

// Synthetic CFDI 4.0 with concept-level amounts carrying 6 decimals, as many invoicing systems emit
// (SAT Anexo 20 allows up to 6 decimals per concept and rounds the comprobante totals to 2).
function cfdi({ importe = '4310.344000', traslado = '689.655040', subTotal = '4310.34', total = '5000.00' } = {}) {
  return `<?xml version="1.0" encoding="utf-8"?>
<cfdi:Comprobante Version="4.0" Fecha="2026-10-31T13:49:46" SubTotal="${subTotal}" Moneda="MXN" Total="${total}" TipoDeComprobante="I" xmlns:cfdi="http://www.sat.gob.mx/cfd/4" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <cfdi:Emisor Rfc="AAA010101AAA" Nombre="EMISOR DE PRUEBA" RegimenFiscal="612" />
  <cfdi:Receptor Rfc="XAXX010101000" Nombre="PERSONA DE PRUEBA" UsoCFDI="G03" />
  <cfdi:Conceptos>
    <cfdi:Concepto ClaveProdServ="43232402" Cantidad="1" ClaveUnidad="E48" Descripcion="Servicio de prueba" ValorUnitario="4310.344" Importe="${importe}" ObjetoImp="02">
      <cfdi:Impuestos>
        <cfdi:Traslados>
          <cfdi:Traslado Base="4310.344000" Impuesto="002" TipoFactor="Tasa" TasaOCuota="0.160000" Importe="${traslado}" />
        </cfdi:Traslados>
      </cfdi:Impuestos>
    </cfdi:Concepto>
  </cfdi:Conceptos>
  <cfdi:Impuestos TotalImpuestosTrasladados="689.66">
    <cfdi:Traslados>
      <cfdi:Traslado Base="4310.34" Impuesto="002" TipoFactor="Tasa" TasaOCuota="0.160000" Importe="689.66" />
    </cfdi:Traslados>
  </cfdi:Impuestos>
  <cfdi:Complemento>
    <tfd:TimbreFiscalDigital xmlns:tfd="http://www.sat.gob.mx/TimbreFiscalDigital" Version="1.1" UUID="0C5F590D-200B-43B6-906F-972403B4A78D" FechaTimbrado="2026-10-31T13:50:00" />
  </cfdi:Complemento>
</cfdi:Comprobante>`;
}

test('accepts concept amounts with 6 decimals when the comprobante totals reconcile to the cent', () => {
  const res = parseCfdi(cfdi());
  assert.equal(res.ok, true, res.message);
  const d = res.data;
  assert.equal(d.subtotalCents, 431034);
  assert.equal(d.totalCents, 500000);
  assert.deepEqual(d.traslados, [
    { impuesto: '002', tipoFactor: 'Tasa', tasaOCuota: '0.160000', baseCents: 431034, importeCents: 68966 },
  ]);
  assert.equal(d.conceptos[0].importeCents, 431034);
});

test('rounds concept amounts half-up to cents', () => {
  assert.equal(parseCfdi(cfdi({ importe: '1.005' })).data.conceptos[0].importeCents, 101);
  assert.equal(parseCfdi(cfdi({ importe: '1.004999' })).data.conceptos[0].importeCents, 100);
  assert.equal(parseCfdi(cfdi({ importe: '12' })).data.conceptos[0].importeCents, 1200);
});

test('rejects concept amounts with more than 6 decimals or malformed', () => {
  for (const importe of ['4310.3440001', 'abc', '-1.00', '1e3', '']) {
    const res = parseCfdi(cfdi({ importe }));
    assert.equal(res.ok, false, `expected rejection for "${importe}"`);
    assert.equal(res.code, 'INVALID_AMOUNT');
  }
});

test('comprobante-level amounts stay strict: 2 decimals and exact to the cent', () => {
  assert.equal(parseCfdi(cfdi({ subTotal: '4310.340' })).code, 'INVALID_AMOUNT');
  assert.equal(parseCfdi(cfdi({ subTotal: '4310.344' })).code, 'INVALID_AMOUNT');
  const off = parseCfdi(cfdi({ total: '5000.01' }));
  assert.equal(off.ok, false);
  assert.equal(off.code, 'AMOUNTS_MISMATCH');
});
