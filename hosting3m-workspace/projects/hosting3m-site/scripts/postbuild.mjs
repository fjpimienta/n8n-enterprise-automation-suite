#!/usr/bin/env node
// Writes 404.html from the client-rendered shell (index.csr.html): the router shows the "not found" page.
// Prerendering already creates one folder/index.html per route, which overwrites the legacy Sitejet pages
// at the same paths when deploying with rsync WITHOUT --delete (nothing is ever deleted on the server).
import { copyFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const outDir = resolve(process.argv[2] ?? 'dist/hosting3m-site/browser');
const shell = join(outDir, 'index.csr.html');
if (!existsSync(shell)) {
  console.error(`index.csr.html not found in ${outDir}. Run "ng build hosting3m-site" first.`);
  process.exit(1);
}
copyFileSync(shell, join(outDir, '404.html'));
console.log(`404.html written in ${outDir}`);
