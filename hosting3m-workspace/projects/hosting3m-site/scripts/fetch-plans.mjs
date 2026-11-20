#!/usr/bin/env node
// Build-time catalog snapshot: POST {apiBase}/v6/plans -> src/app/data/plans-snapshot.json (prerendered into the HTML).
// NEVER fails a build: on any network error, timeout, non-200, malformed body or empty list, the committed snapshot stays.
// An empty array is a valid snapshot. Public endpoint, no credentials. Skip with PLANS_SKIP_FETCH=1.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const snapshotPath = join(here, '../src/app/data/plans-snapshot.json');
const URL_PLANS = process.env.PLANS_API_URL ?? 'https://n8n.hosting3m.com/webhook/v6/plans';
const MAX_PLANS = 50;

/** Returns a short status line; never throws. */
export async function fetchPlansSnapshot(fetchImpl = fetch) {
  if (process.env.PLANS_SKIP_FETCH === '1') return 'plans snapshot: fetch skipped (PLANS_SKIP_FETCH=1), keeping the committed snapshot';
  try {
    const res = await fetchImpl(URL_PLANS, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return `plans snapshot: HTTP ${res.status}, keeping the committed snapshot`;
    const data = await res.json();
    if (!Array.isArray(data)) return 'plans snapshot: unexpected answer, keeping the committed snapshot';
    const plans = data.filter((p) => p && typeof p === 'object' && typeof p.plan_key === 'string').slice(0, MAX_PLANS);
    if (plans.length === 0) return 'plans snapshot: catalog is empty, keeping the committed snapshot';
    const next = JSON.stringify(plans, null, 2) + '\n';
    let current = '';
    try { current = readFileSync(snapshotPath, 'utf8'); } catch { /* first run */ }
    if (next === current) return `plans snapshot: ${plans.length} plan(s), unchanged`;
    writeFileSync(snapshotPath, next);
    return `plans snapshot: ${plans.length} plan(s) written to src/app/data/plans-snapshot.json (commit it to make it the fallback)`;
  } catch (err) {
    return `plans snapshot: ${err instanceof Error ? err.name : 'error'}, keeping the committed snapshot`;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log(await fetchPlansSnapshot());
  process.exit(0);
}
