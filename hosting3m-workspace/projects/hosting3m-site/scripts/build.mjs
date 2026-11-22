#!/usr/bin/env node
// Official build for hosting3m-site: ng build + 404.html + TODO guard.
// Usage (from hosting3m-workspace/): node projects/hosting3m-site/scripts/build.mjs [--configuration production|beta|development]
// production -> a pending TODO_ token or an unreviewed legal marker ([VERIFICAR], [DECIDIR], ...) FAILS the build.
// beta/development -> warning only.
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { report } from './check-todo.mjs';
import { report as reportLegal } from './check-legal-markers.mjs';
import { fetchPlansSnapshot } from './fetch-plans.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const workspace = resolve(here, '../../..');
const idx = process.argv.indexOf('--configuration');
const configuration = idx > -1 ? process.argv[idx + 1] : 'production';
if (!['production', 'beta', 'development'].includes(configuration)) {
  console.error(`Unknown configuration "${configuration}". Use production, beta or development.`);
  process.exit(2);
}

// Catalog snapshot for the prerender. Never fails the build (falls back to the committed snapshot).
if (configuration !== 'development') console.log(await fetchPlansSnapshot());

const run = (cmd, args) => spawnSync(cmd, args, { cwd: workspace, stdio: 'inherit' });
if (run('npx', ['ng', 'build', 'hosting3m-site', '--configuration', configuration]).status !== 0) process.exit(1);
const out = join(workspace, 'dist/hosting3m-site/browser');
if (run('node', [join(here, 'postbuild.mjs'), out]).status !== 0) process.exit(1);
// Both guards fail a production build; on beta and development they only warn.
const mode = configuration === 'production' ? 'fail' : 'warn';
const todo = report(out, mode);
const legal = reportLegal(out, mode);
process.exit(todo || legal);
