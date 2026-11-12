#!/usr/bin/env node
// Lists EXACTLY what changed between two n8n workflow exports (old vs new), by node name:
//   nodes added / removed, nodes whose JSON changed (and which keys), connection changes, top-level keys that changed.
// Also exported as a module (diffExports) so the route test can assert the expected, minimal change.
// No dependencies, no network, no n8n.
// Usage: node diff_workflow_exports.mjs <old.json | git:<ref>:<repo path>> <new.json>
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const canon = (v) => JSON.stringify(v, (_, x) => (x && typeof x === 'object' && !Array.isArray(x)
  ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, x[k]])) : x));

export function loadExport(spec, cwd = process.cwd()) {
  if (spec.startsWith('git:')) {
    const [, ref, ...rest] = spec.split(':');
    return JSON.parse(execFileSync('git', ['show', `${ref}:${rest.join(':')}`], { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
  }
  return JSON.parse(fs.readFileSync(spec, 'utf8'));
}

export function diffExports(oldWf, newWf) {
  const byName = (wf) => new Map(wf.nodes.map((n) => [n.name, n]));
  const a = byName(oldWf);
  const b = byName(newWf);
  const added = [...b.keys()].filter((k) => !a.has(k));
  const removed = [...a.keys()].filter((k) => !b.has(k));
  const changedNodes = [];
  for (const [name, n] of a) {
    const m = b.get(name);
    if (!m) continue;
    if (canon(n) !== canon(m)) {
      const keys = [...new Set([...Object.keys(n), ...Object.keys(m)])].filter((k) => canon(n[k]) !== canon(m[k]));
      changedNodes.push({ name, keys });
    }
  }
  const conn = (wf) => wf.connections || {};
  const changedConnections = [];
  for (const k of new Set([...Object.keys(conn(oldWf)), ...Object.keys(conn(newWf))])) {
    if (canon(conn(oldWf)[k]) !== canon(conn(newWf)[k])) {
      changedConnections.push({ from: k, before: conn(oldWf)[k] ?? null, after: conn(newWf)[k] ?? null });
    }
  }
  const top = (wf) => Object.fromEntries(Object.entries(wf).filter(([k]) => k !== 'nodes' && k !== 'connections'));
  const changedTop = [...new Set([...Object.keys(top(oldWf)), ...Object.keys(top(newWf))])].filter((k) => canon(top(oldWf)[k]) !== canon(top(newWf)[k]));
  return { added, removed, changedNodes, changedConnections, changedTop, unchangedNodes: [...a.keys()].filter((k) => b.has(k)).length - changedNodes.length };
}

export function printDiff(d, out = console.log) {
  out(`nodes added (${d.added.length}): ${d.added.join(' | ') || '-'}`);
  out(`nodes removed (${d.removed.length}): ${d.removed.join(' | ') || '-'}`);
  out(`nodes changed (${d.changedNodes.length}): ${d.changedNodes.map((c) => `${c.name} [${c.keys.join(',')}]`).join(' | ') || '-'}`);
  out(`nodes byte-identical: ${d.unchangedNodes}`);
  out(`connections changed (${d.changedConnections.length}):`);
  for (const c of d.changedConnections) out(`  ${c.from}\n    before: ${canon(c.before)}\n    after:  ${canon(c.after)}`);
  out(`top-level keys changed: ${d.changedTop.join(', ') || '-'}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [oldSpec, newSpec] = process.argv.slice(2);
  if (!oldSpec || !newSpec) { console.error('usage: diff_workflow_exports.mjs <old.json|git:ref:path> <new.json>'); process.exit(2); }
  printDiff(diffExports(loadExport(oldSpec), loadExport(newSpec)));
}
