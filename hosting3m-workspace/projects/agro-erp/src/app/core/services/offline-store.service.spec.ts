import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { openDB } from 'idb';
import { AuthService, SessionScope } from 'core-auth';
import {
  OFFLINE_DB_NAME,
  OFFLINE_DB_VERSION,
  OFFLINE_SCHEMA_VERSION,
  OFFLINE_STORE_NAME,
  OfflineDataset,
  OfflineStoreService
} from './offline-store.service';

const SECRET_TOKEN = 'eyJ.SECRET-TOKEN.sig';
const PII = 'Rancho PII Sentinel 4421';

describe('OfflineStoreService', () => {
  let scope: SessionScope | null;
  let service: OfflineStoreService;
  let logs: string[];

  const A1: SessionScope = { user: 'ana', id_company: 1 };
  const A2: SessionScope = { user: 'ana', id_company: 2 };
  const B1: SessionScope = { user: 'beto', id_company: 1 };

  function create(): OfflineStoreService {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [{ provide: AuthService, useValue: { getSessionScope: () => scope } }]
    });
    return TestBed.inject(OfflineStoreService);
  }

  async function rawStore() {
    return openDB(OFFLINE_DB_NAME, OFFLINE_DB_VERSION, {
      upgrade: db => { db.createObjectStore(OFFLINE_STORE_NAME); }
    });
  }

  beforeEach(() => {
    scope = A1;
    logs = [];
    for (const m of ['log', 'warn', 'error', 'info', 'debug'] as const) {
      vi.spyOn(console, m).mockImplementation((...args: unknown[]) => {
        logs.push(args.map(a => (a instanceof Error ? `${a.name}:${a.message}` : String(a))).join(' '));
      });
    }
    service = create();
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    TestBed.resetTestingModule(); // runs ngOnDestroy and closes the connection
    await new Promise<void>(resolve => {
      const req = indexedDB.deleteDatabase(OFFLINE_DB_NAME);
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    });
  });

  it('round-trips a snapshot with an ISO UTC savedAt', async () => {
    expect(await service.put('livestock', [{ id: 1 }])).toBe(true);
    const snap = await service.get<{ id: number }[]>('livestock');
    expect(snap?.data).toEqual([{ id: 1 }]);
    expect(snap?.savedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  });

  it('returns null when nothing was stored', async () => {
    expect(await service.get('catalogs')).toBeNull();
  });

  it('stores each entry under `${user}|${id_company}|${dataset}` carrying its scope', async () => {
    await service.put('catalogs', { breeds: [] });
    const db = await rawStore();
    const keys = await db.getAllKeys(OFFLINE_STORE_NAME);
    expect(keys).toEqual(['ana|1|catalogs']);
    const entry = await db.get(OFFLINE_STORE_NAME, 'ana|1|catalogs');
    expect(entry).toMatchObject({
      user: 'ana', id_company: 1, dataset: 'catalogs', schemaVersion: OFFLINE_SCHEMA_VERSION
    });
    expect(typeof entry.savedAt).toBe('string');
    db.close();
  });

  describe('partition isolation', () => {
    it('keeps user A/company 1, user A/company 2 and user B/company 1 apart', async () => {
      scope = A1; await service.put('livestock', 'a1');
      scope = A2; await service.put('livestock', 'a2');
      scope = B1; await service.put('livestock', 'b1');

      scope = A1; expect((await service.get('livestock'))?.data).toBe('a1');
      scope = A2; expect((await service.get('livestock'))?.data).toBe('a2');
      scope = B1; expect((await service.get('livestock'))?.data).toBe('b1');
    });

    it('returns only the active partition after a scope switch, and null for an empty one', async () => {
      scope = A1; await service.put('livestock', 'a1');
      scope = A2;
      expect(await service.get('livestock')).toBeNull();
      scope = A1;
      expect((await service.get('livestock'))?.data).toBe('a1');
    });

    it('does not let a "|" inside the user alias another partition', async () => {
      scope = { user: 'a|1', id_company: 2 }; await service.put('livestock', 'tricky');
      scope = { user: 'a', id_company: 1 };
      expect(await service.get('livestock')).toBeNull();
      await service.wipeScope({ user: 'a', id_company: 1 });
      scope = { user: 'a|1', id_company: 2 };
      expect((await service.get('livestock'))?.data).toBe('tricky');
    });

    it('returns null if the scope changes while the read is in flight', async () => {
      await service.put('livestock', 'a1');
      const original = (service as any).open.bind(service);
      vi.spyOn(service as any, 'open').mockImplementation(async () => {
        const db = await original();
        scope = A2; // switch tenant mid-read
        return db;
      });
      expect(await service.get('livestock')).toBeNull();
    });
  });

  describe('fail-closed on missing or ambiguous scope', () => {
    it.each([
      ['null', null],
      ['empty user', { user: '  ', id_company: 1 }],
      ['zero company', { user: 'ana', id_company: 0 }],
      ['string company', { user: 'ana', id_company: '1' }],
      ['fractional company', { user: 'ana', id_company: 1.5 }]
    ])('put resolves false and get returns null with %s scope, touching no database', async (_n, bad) => {
      scope = bad as SessionScope | null;
      const open = vi.spyOn(indexedDB, 'open');
      expect(await service.put('livestock', 'x')).toBe(false);
      expect(await service.get('livestock')).toBeNull();
      expect(open).not.toHaveBeenCalled();
    });

    it('does not expose entries stored earlier when the scope becomes null', async () => {
      await service.put('livestock', 'a1');
      scope = null;
      expect(await service.get('livestock')).toBeNull();
    });
  });

  describe('dataset allowlist', () => {
    it.each(['expenses', 'sales', 'income', 'ventas', 'gastos', '', 'LIVESTOCK', '__proto__', 'constructor'])(
      'rejects money or unknown dataset %j at runtime and stores nothing',
      async name => {
        expect(await service.put(name as OfflineDataset, { amount: 100 })).toBe(false);
        expect(await service.get(name as OfflineDataset)).toBeNull();
        const db = await rawStore();
        expect(await db.count(OFFLINE_STORE_NAME)).toBe(0);
        db.close();
      }
    );

    it('rejects non-string datasets', async () => {
      expect(await service.put(undefined as never, 1)).toBe(false);
      expect(await service.put({ toString: () => 'livestock' } as never, 1)).toBe(false);
    });

    it('does not accept a money dataset at compile time', () => {
      // @ts-expect-error money datasets are not part of OfflineDataset
      const bad: OfflineDataset = 'expenses';
      expect(bad).toBe('expenses'); // the type error above is the assertion; runtime rejects it (test above)
    });
  });

  describe('entry verification', () => {
    async function writeRaw(key: string, value: unknown) {
      const db = await rawStore();
      await db.put(OFFLINE_STORE_NAME, value, key);
      db.close();
    }
    const good = (over: Record<string, unknown> = {}) => ({
      user: 'ana', id_company: 1, dataset: 'livestock', savedAt: new Date().toISOString(),
      schemaVersion: OFFLINE_SCHEMA_VERSION, data: 'ok', ...over
    });

    it('accepts a well-formed raw entry (control)', async () => {
      await writeRaw('ana|1|livestock', good());
      expect((await service.get('livestock'))?.data).toBe('ok');
    });

    it('returns null on a different schemaVersion', async () => {
      await writeRaw('ana|1|livestock', good({ schemaVersion: OFFLINE_SCHEMA_VERSION + 1 }));
      expect(await service.get('livestock')).toBeNull();
    });

    it('returns null when the stored scope differs from the current one (tampered/misplaced entry)', async () => {
      await writeRaw('ana|1|livestock', good({ id_company: 2 }));
      expect(await service.get('livestock')).toBeNull();
      await writeRaw('ana|1|livestock', good({ user: 'beto' }));
      expect(await service.get('livestock')).toBeNull();
    });

    it('returns null when the stored dataset differs from the requested one', async () => {
      await writeRaw('ana|1|livestock', good({ dataset: 'catalogs' }));
      expect(await service.get('livestock')).toBeNull();
    });

    it.each([
      ['a string', 'garbage'],
      ['a number', 42],
      ['null', null],
      ['an array', []],
      ['missing data', (() => { const e: Record<string, unknown> = good(); delete e['data']; return e; })()],
      ['a bad savedAt', good({ savedAt: 'not-a-date' })],
      ['a non-string savedAt', good({ savedAt: 123 })]
    ])('returns null for a corrupt entry (%s) without throwing', async (_n, value) => {
      await writeRaw('ana|1|livestock', value);
      await expect(service.get('livestock')).resolves.toBeNull();
    });
  });

  describe('wipes', () => {
    it('wipeScope removes only that scope, both datasets, and leaves the others', async () => {
      scope = A1; await service.put('livestock', 'a1l'); await service.put('catalogs', 'a1c');
      scope = A2; await service.put('livestock', 'a2l');
      scope = B1; await service.put('livestock', 'b1l');

      expect(await service.wipeScope(A1)).toBe(true);

      scope = A1;
      expect(await service.get('livestock')).toBeNull();
      expect(await service.get('catalogs')).toBeNull();
      scope = A2; expect((await service.get('livestock'))?.data).toBe('a2l');
      scope = B1; expect((await service.get('livestock'))?.data).toBe('b1l');
    });

    it('wipeScope works for an explicit scope that is not the active one', async () => {
      scope = A2; await service.put('livestock', 'a2l');
      scope = A1;
      expect(await service.wipeScope(A2)).toBe(true);
      scope = A2;
      expect(await service.get('livestock')).toBeNull();
    });

    it('wipeScope rejects an invalid scope without touching data', async () => {
      await service.put('livestock', 'a1l');
      expect(await service.wipeScope({ user: '', id_company: 1 })).toBe(false);
      expect(await service.wipeScope(null as never)).toBe(false);
      expect((await service.get('livestock'))?.data).toBe('a1l');
    });

    it('wipeAll removes every partition', async () => {
      scope = A1; await service.put('livestock', 'a1');
      scope = A2; await service.put('catalogs', 'a2');
      scope = B1; await service.put('livestock', 'b1');
      expect(await service.wipeAll()).toBe(true);
      const db = await rawStore();
      expect(await db.count(OFFLINE_STORE_NAME)).toBe(0);
      db.close();
    });

    it('wipeAll works even with no session scope', async () => {
      await service.put('livestock', 'a1');
      scope = null;
      expect(await service.wipeAll()).toBe(true);
      scope = A1;
      expect(await service.get('livestock')).toBeNull();
    });
  });

  describe('IndexedDB failure paths (never throw to callers)', () => {
    it('is a no-throw when IndexedDB is unavailable', async () => {
      vi.stubGlobal('indexedDB', undefined);
      expect(await service.put('livestock', 'x')).toBe(false);
      expect(await service.get('livestock')).toBeNull();
      expect(await service.wipeAll()).toBe(false);
      expect(await service.wipeScope(A1)).toBe(false);
    });

    it('is a no-throw when indexedDB.open throws synchronously', async () => {
      vi.spyOn(indexedDB, 'open').mockImplementation(() => { throw new DOMException('denied', 'SecurityError'); });
      expect(await service.put('livestock', 'x')).toBe(false);
      expect(await service.get('livestock')).toBeNull();
    });

    it('resolves put to false on a quota error and keeps working afterwards', async () => {
      const put = vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementationOnce(() => {
        throw new DOMException('quota', 'QuotaExceededError');
      });
      expect(await service.put('livestock', 'big')).toBe(false);
      put.mockRestore();
      expect(await service.put('livestock', 'small')).toBe(true);
      expect((await service.get('livestock'))?.data).toBe('small');
    });

    it('resolves put to false when the data cannot be cloned', async () => {
      expect(await service.put('livestock', { fn: () => 1 })).toBe(false);
    });

    it('returns null when the read itself fails', async () => {
      vi.spyOn(IDBObjectStore.prototype, 'get').mockImplementation(() => {
        throw new DOMException('broken', 'UnknownError');
      });
      expect(await service.get('livestock')).toBeNull();
    });

    it('does not hang when the open is blocked, and recovers on the next call', async () => {
      // Hold a connection that ignores versionchange, then make the service request a higher version.
      const holder = await openDB(OFFLINE_DB_NAME, OFFLINE_DB_VERSION, {
        upgrade: db => { db.createObjectStore(OFFLINE_STORE_NAME); }
      });
      const realOpen = indexedDB.open.bind(indexedDB);
      const spy = vi.spyOn(indexedDB, 'open').mockImplementationOnce((name: string) =>
        realOpen(name, OFFLINE_DB_VERSION + 1));
      expect(await service.get('livestock')).toBeNull();
      spy.mockRestore();
      holder.close();
    });

    it('does not cache a failed open: the next call retries', async () => {
      const open = vi.spyOn(indexedDB, 'open').mockImplementationOnce(() => {
        throw new DOMException('denied', 'SecurityError');
      });
      expect(await service.put('livestock', 'x')).toBe(false);
      open.mockRestore();
      expect(await service.put('livestock', 'x')).toBe(true);
    });
  });

  describe('logging', () => {
    it('never logs data contents, scope values or tokens on failures', async () => {
      localStorage.setItem('authToken', SECRET_TOKEN);
      scope = { user: 'ana@example.test', id_company: 1 };
      vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementation(() => {
        throw new DOMException(`quota while storing ${PII}`, 'QuotaExceededError');
      });
      await service.put('livestock', [{ owner: PII, token: SECRET_TOKEN }]);
      await service.put('expenses' as OfflineDataset, { owner: PII });
      scope = null;
      await service.put('livestock', PII);
      vi.stubGlobal('indexedDB', undefined);
      await service.get('livestock');
      await service.wipeAll();

      const all = logs.join('\n');
      expect(logs.length).toBeGreaterThan(0); // failures are reported...
      expect(all).not.toContain(PII); // ...without contents,
      expect(all).not.toContain(SECRET_TOKEN);
      expect(all).not.toContain('ana@example.test');
      expect(all).toContain('QuotaExceededError'); // only the error name
      localStorage.removeItem('authToken');
    });
  });
});
