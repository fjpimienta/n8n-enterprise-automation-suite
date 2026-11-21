#!/usr/bin/env node
// Legal-review guard: the legal pages must carry the lawyer-reviewed text. While an editorial marker such as
// [VERIFICAR], [DECIDIR], [REVISAR] or [FECHA DE PUBLICACIÓN] is left in the build output, a production build fails.
// Same style as check-todo.mjs. mode "fail": exit 1 (production). mode "warn": print and exit 0 (beta, development, CI).
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative, resolve } from 'node:path';

// "Ó" also appears escaped in minified JavaScript (\xD3 / Ó), hence the alternatives.
export const MARKER = /\[(?:VERIFICAR|DECIDIR|REVISAR|FECHA DE PUBLICACI(?:Ó|O|\\xD3|\\u00D3)N)[^\]\n]{0,80}\]/gi;
const TEXT_EXT = new Set(['.html', '.js', '.mjs', '.json', '.xml', '.txt']);

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) yield* walk(full);
    else if (TEXT_EXT.has(extname(name))) yield full;
  }
}

/** Returns Map(marker text -> Set(files)). */
export function scan(dir) {
  const found = new Map();
  for (const file of walk(dir)) {
    for (const marker of new Set(readFileSync(file, 'utf8').match(MARKER) ?? [])) {
      if (!found.has(marker)) found.set(marker, new Set());
      found.get(marker).add(relative(dir, file));
    }
  }
  return found;
}

export function report(dir, mode) {
  const found = scan(dir);
  if (found.size === 0) {
    console.log('Legal guard: no editorial markers in the build output.');
    return 0;
  }
  const lines = [...found].sort().map(([m, files]) => `  - ${m}  (${[...files].slice(0, 3).join(', ')}${files.size > 3 ? ', ...' : ''})`);
  const head = mode === 'fail' ? 'Legal guard: BUILD FAILED' : 'Legal guard: warning';
  console.error(`${head}: ${found.size} editorial marker(s) found in ${dir}\n${lines.join('\n')}`);
  if (mode === 'fail') {
    console.error('A production build cannot ship unreviewed legal text. Replace each marker with the lawyer-reviewed wording (see docs/phase-4/cutover-runbook.md, section 5).');
    return 1;
  }
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = resolve(process.argv[2] ?? 'dist/hosting3m-site/browser');
  process.exit(report(dir, process.argv[3] === 'fail' ? 'fail' : 'warn'));
}
