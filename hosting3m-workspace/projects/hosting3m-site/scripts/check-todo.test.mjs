// Run with: node --test projects/hosting3m-site/scripts
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { report, scan } from './check-todo.mjs';

const outDir = (files) => {
  const dir = mkdtempSync(join(tmpdir(), 'todo-guard-'));
  for (const [name, content] of Object.entries(files)) writeFileSync(join(dir, name), content);
  return dir;
};

test('a build without pending tokens passes the production guard', () => {
  const dir = outDir({ 'index.html': '<h1>Hosting3M</h1>', 'main.js': 'var a="ok";' });
  assert.equal(scan(dir).size, 0);
  assert.equal(report(dir, 'fail'), 0);
});

test('unresolved CFDI tokens in the output (flag on) fail the production guard but only warn on beta', () => {
  const dir = outDir({ 'chunk.js': 'var c={title:"TODO_CFDI_CLAIM_TITLE",text:"TODO_CFDI_CLAIM_TEXT"};' });
  assert.deepEqual([...scan(dir).keys()].sort(), ['TODO_CFDI_CLAIM_TEXT', 'TODO_CFDI_CLAIM_TITLE']);
  assert.equal(report(dir, 'fail'), 1);
  assert.equal(report(dir, 'warn'), 0);
});
