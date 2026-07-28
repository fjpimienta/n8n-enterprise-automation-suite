/**
 * WORKAROUND for a confirmed n8n Meta-CRUD gateway bug: when a table has zero rows,
 * `getall` returns `data: [{}]` (a single phantom object) instead of `data: []`.
 * Verified against cattle_breed_catalog (0 rows in DB, UI rendered "1/1" with a blank card).
 * Affects every model, including the compliance registry views.
 *
 * A row only counts as real if it carries the primary key the caller expects.
 * `Object.keys(row).length === 0` is not a sufficient check on its own: a phantom row can
 * also come back with real keys all set to null, still missing the identifier.
 *
 * Remove every call site once the gateway is fixed to return a true empty array.
 */
function hasIdentifier<T>(row: T | null | undefined, idKey: keyof T): boolean {
  if (row == null) return false;
  const id = row[idKey];
  return id !== null && id !== undefined && String(id).trim() !== '';
}

export function isPhantomRow<T>(row: T | null | undefined, idKey: keyof T): boolean {
  return !hasIdentifier(row, idKey);
}

export function stripPhantomRows<T>(rows: T[], idKey: keyof T): T[] {
  return rows.filter(row => hasIdentifier(row, idKey));
}
