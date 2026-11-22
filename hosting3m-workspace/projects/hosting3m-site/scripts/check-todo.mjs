#!/usr/bin/env node
// TODO guard: scans the build output for pending-content tokens (TODO_ followed by an uppercase name).
// mode "fail": exit 1 with a clear message (production). mode "warn": print and exit 0 (development, beta, CI).
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative, resolve } from 'node:path';

export const TOKEN = /TODO_[A-Z][A-Z0-9_]*/g;
const TEXT_EXT = new Set(['.html', '.js', '.mjs', '.css', '.json', '.xml', '.txt', '.webmanifest', '.svg']);

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) yield* walk(full);
    else if (TEXT_EXT.has(extname(name))) yield full;
  }
}

export function scan(dir) {
  const found = new Map(); // token -> Set(files)
  for (const file of walk(dir)) {
    for (const token of new Set(readFileSync(file, 'utf8').match(TOKEN) ?? [])) {
      if (!found.has(token)) found.set(token, new Set());
      found.get(token).add(relative(dir, file));
    }
  }
  return found;
}

export function report(dir, mode) {
  const found = scan(dir);
  if (found.size === 0) {
    console.log('TODO guard: no pending TODO_ tokens in the build output.');
    return 0;
  }
  const lines = [...found].sort().map(([t, files]) => `  - ${t}  (${[...files].slice(0, 3).join(', ')}${files.size > 3 ? ', ...' : ''})`);
  const head = mode === 'fail' ? 'TODO guard: BUILD FAILED' : 'TODO guard: warning';
  console.error(`${head}: ${found.size} pending TODO_ token(s) found in ${dir}\n${lines.join('\n')}`);
  if (mode === 'fail') {
    console.error('A production build cannot ship pending content. Resolve each token (see docs/phase-*/TODO.md) or use --configuration beta for beta hosts.');
    return 1;
  }
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = resolve(process.argv[2] ?? 'dist/hosting3m-site/browser');
  const mode = process.argv[3] === 'fail' ? 'fail' : 'warn';
  process.exit(report(dir, mode));
}
