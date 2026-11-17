/**
 * Whether an IndexedDB database exists, WITHOUT creating it (`indexedDB.open` would create it). Resolves
 * `null` when the browser cannot tell (no `databases()` support or an error): the caller decides, and this
 * helper never throws.
 */
export async function databaseExists(name: string): Promise<boolean | null> {
  try {
    if (typeof indexedDB === 'undefined' || typeof indexedDB.databases !== 'function') return null;
    const list = await indexedDB.databases();
    return list.some(entry => entry.name === name);
  } catch {
    return null;
  }
}
