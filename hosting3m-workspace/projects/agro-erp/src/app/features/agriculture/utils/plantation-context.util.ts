/**
 * Pure rules of the active-plantation context. The plantation is only a UI scope filter: the security
 * boundary stays id_company (the server list is always the source of truth; a stored id that is not in
 * it is ignored — fail-closed).
 */

export const PLANTATION_STORAGE_PREFIX = 'agri_active_plantation:';

/** Minimal Storage surface (window.localStorage in the app, a fake in tests). */
export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
  readonly length?: number;
  key?(index: number): string | null;
}

export interface PlantationOption {
  id: string;
  name: string;
  isActive: boolean;
  isDefault: boolean;
}

export function plantationStorageKey(idCompany: number): string {
  return `${PLANTATION_STORAGE_PREFIX}${idCompany}`;
}

/** Never throws (private windows, blocked storage, quota): returns null instead. */
export function readStoredPlantation(storage: StorageLike | null, idCompany: number): string | null {
  if (!storage) return null;
  try {
    const value = storage.getItem(plantationStorageKey(idCompany));
    return value && value.trim() ? value.trim() : null;
  } catch {
    return null;
  }
}

/** Never throws. `null` removes the stored choice. */
export function writeStoredPlantation(storage: StorageLike | null, idCompany: number, plantationId: string | null): void {
  if (!storage) return;
  try {
    if (plantationId) storage.setItem(plantationStorageKey(idCompany), plantationId);
    else storage.removeItem(plantationStorageKey(idCompany));
  } catch {
    // Storage unavailable: the context still works for the current page.
  }
}

/** Removes every stored choice (logout), so nothing is inherited by the next session in this browser. */
export function clearStoredPlantations(storage: StorageLike | null): void {
  if (!storage) return;
  try {
    // Inside the try: on a blocked storage even reading `length` throws.
    if (typeof storage.key !== 'function' || typeof storage.length !== 'number') return;
    const keys: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key && key.startsWith(PLANTATION_STORAGE_PREFIX)) keys.push(key);
    }
    keys.forEach(k => storage.removeItem(k));
  } catch {
    // ignore
  }
}

/**
 * Which plantation is active for a company:
 *   1. the last one the user chose for that company, if it is still active in the server list;
 *   2. otherwise the company's default (if active);
 *   3. otherwise any other active plantation (first by name);
 *   4. otherwise null (no active plantation: empty state).
 */
export function resolveActivePlantation(list: readonly PlantationOption[], storedId: string | null): string | null {
  const active = list.filter(p => p.isActive);
  if (storedId && active.some(p => p.id === storedId)) return storedId;
  const byDefault = active.find(p => p.isDefault);
  if (byDefault) return byDefault.id;
  const first = [...active].sort((a, b) => a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }))[0];
  return first ? first.id : null;
}
