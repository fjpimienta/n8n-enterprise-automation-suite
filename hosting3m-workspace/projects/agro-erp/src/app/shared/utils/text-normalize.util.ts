/**
 * Lowercase + strip diacritics, so "Peña" matches "pena" and "PEÑA" alike. Used by
 * `PagedTable`'s built-in search — standalone here so any other free-text search in the app
 * can reuse the exact same normalization instead of each one hand-rolling its own.
 */
export function normalizeForSearch(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();
}
