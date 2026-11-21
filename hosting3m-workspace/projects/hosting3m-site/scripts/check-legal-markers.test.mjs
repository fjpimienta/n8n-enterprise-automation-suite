// Run with: node --test projects/hosting3m-site/scripts/check-legal-markers.test.mjs
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { report, scan } from './check-legal-markers.mjs';

const outDir = (files) => {
  const dir = mkdtempSync(join(tmpdir(), 'legal-guard-'));
  for (const [name, content] of Object.entries(files)) {
    mkdirSync(join(dir, name, '..'), { recursive: true });
    writeFileSync(join(dir, name), content);
  }
  return dir;
};

test('reviewed legal text passes the production guard', () => {
  const dir = outDir({ 'politica-de-privacidad/index.html': '<p>Última actualización: 01/12/2026. Contacto [aviso] normal.</p>' });
  assert.equal(scan(dir).size, 0);
  assert.equal(report(dir, 'fail'), 0);
});

test('each editorial marker is detected (case-insensitive, with optional detail) and fails production only', () => {
  for (const marker of ['[VERIFICAR]', '[DECIDIR]', '[REVISAR]', '[FECHA DE PUBLICACIÓN]', '[verificar: domicilio]', '[FECHA DE PUBLICACI\\xD3N]']) {
    const dir = outDir({ 'condiciones-de-servicio/index.html': `<p>Texto ${marker} resto</p>` });
    assert.equal(scan(dir).size, 1, marker);
    assert.equal(report(dir, 'fail'), 1, marker);
    assert.equal(report(dir, 'warn'), 0, marker);
  }
});

test('markers in JavaScript chunks are found too', () => {
  const dir = outDir({ 'chunk-ABC.js': 'var t="Responsable: [DECIDIR] razón social";' });
  assert.deepEqual([...scan(dir).keys()], ['[DECIDIR]']);
  assert.equal(report(dir, 'fail'), 1);
});
