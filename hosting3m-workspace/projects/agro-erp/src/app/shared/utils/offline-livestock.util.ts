/**
 * Offline sanitization and validation of the livestock read-cache (#1087, phase 1b-iii-a).
 * Fail-closed: `metadata` (free-form JSONB that can carry purchase prices, sellers, notes) is NEVER
 * cached, so every row is stored with `metadata: null`.
 */

const FINANCIAL_COLUMN_PATTERN = /(price|cost|precio|costo|monto|amount|valor)/i;

/** Top-level column names that look financial. Reported, never silently dropped or guessed. */
export function findFinancialLookingColumns(rows: readonly unknown[]): string[] {
  const found = new Set<string>();
  for (const row of rows) {
    if (!row || typeof row !== 'object') continue;
    for (const key of Object.keys(row)) {
      if (key !== 'metadata' && FINANCIAL_COLUMN_PATTERN.test(key)) found.add(key);
    }
  }
  return [...found].sort();
}

/** Copy of `rows` with `metadata` set to `null` on every row; non-object rows are dropped. */
export function sanitizeLivestockForOffline(rows: unknown): Record<string, unknown>[] {
  if (!Array.isArray(rows)) return [];
  return rows
    .filter((row): row is Record<string, unknown> => !!row && typeof row === 'object' && !Array.isArray(row))
    .map(row => ({ ...row, metadata: null }));
}

/**
 * True only when `data` is an array and EVERY row has `tenant_id` equal to `idCompany`
 * (compared numerically: the gateway returns numerics as strings).
 */
export function snapshotMatchesTenant(data: unknown, idCompany: number): data is Record<string, unknown>[] {
  if (!Array.isArray(data)) return false;
  return data.every(row => {
    if (!row || typeof row !== 'object') return false;
    const tenant = (row as Record<string, unknown>)['tenant_id'];
    if (tenant === null || tenant === undefined || tenant === '') return false;
    return Number(tenant) === idCompany;
  });
}
