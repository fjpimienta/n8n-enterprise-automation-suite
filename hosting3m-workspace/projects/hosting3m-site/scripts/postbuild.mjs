#!/usr/bin/env node
// Copies the SPA shell into one folder per public route (+ 404.html).
// Why: the server still holds legacy Sitejet folders such as /portfolio/index.html, and the deploy uses
// rsync WITHOUT --delete, so nginx would keep serving the old pages. Writing the new shell at the same
// paths overwrites them without deleting anything. Keep ROUTES in sync with src/app/app.routes.ts.
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const ROUTES = [
  'portfolio',
  'fjpimienta',
  'politica-de-privacidad',
  'condiciones-de-servicio',
  'eliminardatosusuarios',
];

const outDir = resolve(process.argv[2] ?? 'dist/hosting3m-site/browser');
const shell = join(outDir, 'index.html');
if (!existsSync(shell)) {
  console.error(`index.html not found in ${outDir}. Run "ng build hosting3m-site" first.`);
  process.exit(1);
}

for (const route of ROUTES) {
  const target = join(outDir, route, 'index.html');
  mkdirSync(dirname(target), { recursive: true });
  copyFileSync(shell, target);
}
copyFileSync(shell, join(outDir, '404.html'));
console.log(`Shell copied to ${ROUTES.length} route folders and 404.html in ${outDir}`);
