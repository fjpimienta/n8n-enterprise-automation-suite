import { describe, expect, it } from 'vitest';
import {
  PLANTATION_STORAGE_PREFIX,
  StorageLike,
  clearStoredPlantations,
  plantationStorageKey,
  readStoredPlantation,
  resolveActivePlantation,
  writeStoredPlantation,
} from './plantation-context.util';

class MemoryStorage implements StorageLike {
  private map = new Map<string, string>();
  get length() { return this.map.size; }
  key(i: number) { return [...this.map.keys()][i] ?? null; }
  getItem(k: string) { return this.map.has(k) ? this.map.get(k)! : null; }
  setItem(k: string, v: string) { this.map.set(k, v); }
  removeItem(k: string) { this.map.delete(k); }
}

const throwing: StorageLike = {
  getItem() { throw new Error('SecurityError'); },
  setItem() { throw new Error('QuotaExceeded'); },
  removeItem() { throw new Error('SecurityError'); },
  get length() { throw new Error('SecurityError'); },
  key() { throw new Error('SecurityError'); },
};

const P = (id: string, name: string, isActive = true, isDefault = false) => ({ id, name, isActive, isDefault });

describe('resolveActivePlantation', () => {
  const list = [P('a', 'Zapote'), P('b', 'Bambú', true, true), P('c', 'Ceiba', false)];

  it('keeps the last choice when it is still active in the server list', () => {
    expect(resolveActivePlantation(list, 'a')).toBe('a');
  });
  it('falls back to the default when the stored choice is inactive (fail-closed)', () => {
    expect(resolveActivePlantation(list, 'c')).toBe('b');
  });
  it('ignores a stored id that is not in the server list (e.g. another company)', () => {
    expect(resolveActivePlantation(list, 'foreign-id')).toBe('b');
  });
  it('without a default, uses any other active plantation (first by name)', () => {
    expect(resolveActivePlantation([P('a', 'Zapote'), P('d', 'Acacia')], null)).toBe('d');
  });
  it('an inactive default is not used', () => {
    expect(resolveActivePlantation([P('a', 'Zapote'), P('x', 'Default inactiva', false, true)], null)).toBe('a');
  });
  it('no active plantation -> null (empty state)', () => {
    expect(resolveActivePlantation([P('c', 'Ceiba', false)], 'c')).toBeNull();
    expect(resolveActivePlantation([], null)).toBeNull();
  });
});

describe('stored choice per company', () => {
  it('uses one key per company', () => {
    expect(plantationStorageKey(10)).toBe(`${PLANTATION_STORAGE_PREFIX}10`);
    const s = new MemoryStorage();
    writeStoredPlantation(s, 10, 'p10');
    writeStoredPlantation(s, 3, 'p3');
    expect(readStoredPlantation(s, 10)).toBe('p10');
    expect(readStoredPlantation(s, 3)).toBe('p3');
    writeStoredPlantation(s, 10, null);
    expect(readStoredPlantation(s, 10)).toBeNull();
  });
  it('never throws when storage is blocked or missing', () => {
    expect(readStoredPlantation(throwing, 10)).toBeNull();
    expect(() => writeStoredPlantation(throwing, 10, 'x')).not.toThrow();
    expect(() => clearStoredPlantations(throwing)).not.toThrow();
    expect(readStoredPlantation(null, 10)).toBeNull();
  });
  it('logout clears every stored plantation and nothing else', () => {
    const s = new MemoryStorage();
    writeStoredPlantation(s, 10, 'p10');
    writeStoredPlantation(s, 3, 'p3');
    s.setItem('authToken', 'keep-me');
    clearStoredPlantations(s);
    expect(readStoredPlantation(s, 10)).toBeNull();
    expect(readStoredPlantation(s, 3)).toBeNull();
    expect(s.getItem('authToken')).toBe('keep-me');
  });
});
