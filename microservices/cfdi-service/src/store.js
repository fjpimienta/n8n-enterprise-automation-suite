import { createHash, randomBytes } from 'node:crypto';
import { link, mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const TENANT_ID_RE = /^[1-9][0-9]{0,9}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const YEAR_MONTH_RE = /^(\d{4})-(\d{2})-\d{2}T/;

export class StoreConflict extends Error {}

/**
 * Builds <tenantId>/<yyyy>/<mm>/<sha256>.xml only from validated parts.
 * Year and month come from the (already parsed) fechaEmision, so a re-store lands on the same path.
 */
export function relativePath(tenantId, fechaEmision, sha256) {
  const ym = YEAR_MONTH_RE.exec(fechaEmision);
  if (!TENANT_ID_RE.test(tenantId) || !ym || !SHA256_RE.test(sha256)) throw new Error('invalid path parts');
  return `${tenantId}/${ym[1]}/${ym[2]}/${sha256}.xml`;
}

/** Idempotent: same content is a no-op, different content at the same path throws StoreConflict. */
export async function storeXml(storageRoot, relPath, bytes) {
  const root = path.resolve(storageRoot);
  const target = path.resolve(root, relPath);
  if (!target.startsWith(root + path.sep)) throw new Error('path escapes storage root');

  await mkdir(path.dirname(target), { recursive: true, mode: 0o750 });
  // Write to a temp file then link(): link fails with EEXIST instead of overwriting, and a crash never
  // leaves a partial file at the final path.
  const tmp = `${target}.${randomBytes(6).toString('hex')}.tmp`;
  await writeFile(tmp, bytes, { mode: 0o640, flag: 'wx' });
  try {
    await link(tmp, target);
  } catch (err) {
    if (err.code !== 'EEXIST') throw err;
    const existing = await readFile(target);
    if (!createHash('sha256').update(existing).digest().equals(createHash('sha256').update(bytes).digest())) {
      throw new StoreConflict('a different file already exists at this path');
    }
  } finally {
    await unlink(tmp).catch(() => {});
  }
}
