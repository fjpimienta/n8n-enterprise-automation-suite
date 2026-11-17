import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { openDB } from 'idb';
import { AuthService, SessionScope } from 'core-auth';
import { setWipePending } from '@core/utils/offline-wipe-pending.util';
import {
  OFFLINE_DB_NAME,
  OFFLINE_DB_VERSION,
  OFFLINE_STORE_NAME,
  OfflineStoreService
} from './offline-store.service';

/** Wipe fencing and the pending flag of the offline read cache (#1087, phase 1b-iii-c). */
describe('OfflineStoreService wipe fencing', () => {
  let scope: SessionScope | null;
  let state: 'valid' | 'grace' | 'expired';
  let service: OfflineStoreService;

  const A1: SessionScope = { user: 'ana', id_company: 1 };
  const A2: SessionScope = { user: 'ana', id_company: 2 };

  function create(): OfflineStoreService {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [{ provide: AuthService, useValue: { getSessionScope: () => scope, getSessionState: () => state } }]
    });
    return TestBed.inject(OfflineStoreService);
  }

  async function rawCount(): Promise<number> {
    const db = await openDB(OFFLINE_DB_NAME, OFFLINE_DB_VERSION, {
      upgrade: d => { d.createObjectStore(OFFLINE_STORE_NAME); }
    });
    const n = await db.count(OFFLINE_STORE_NAME);
    db.close();
    return n;
  }

  beforeEach(() => {
    scope = A1;
    state = 'valid';
    localStorage.clear();
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    service = create();
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    localStorage.clear();
    TestBed.resetTestingModule();
    await new Promise<void>(resolve => {
      const req = indexedDB.deleteDatabase(OFFLINE_DB_NAME);
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    });
  });

  it('fences a put that races with wipeAll: nothing is stored (epoch counter)', async () => {
    const [stored] = await Promise.all([
      service.put('livestock', [{ id: 1 }], A1),
      service.wipeAll()
    ]);
    expect(stored).toBe(false);
    expect(await rawCount()).toBe(0);
  });

  it('still stores normally after a wipe completes (the fence is not permanent)', async () => {
    await service.wipeAll();
    expect(await service.put('livestock', [{ id: 2 }], A1)).toBe(true);
    expect((await service.get('livestock'))?.data).toEqual([{ id: 2 }]);
  });

  it('wipeAll removes every company partition of the same user (T10)', async () => {
    expect(await service.put('livestock', [{ id: 1 }], A1)).toBe(true);
    scope = A2;
    expect(await service.put('livestock', [{ id: 2 }], A2)).toBe(true);
    expect(await rawCount()).toBe(2);
    expect(await service.wipeAll()).toBe(true);
    expect(await rawCount()).toBe(0);
  });

  it('fails closed while the wipe pending flag is set: get returns null and put stores nothing (D6)', async () => {
    expect(await service.put('livestock', [{ id: 1 }], A1)).toBe(true);
    setWipePending(true);
    expect(await service.get('livestock')).toBeNull();
    expect(await service.put('livestock', [{ id: 3 }], A1)).toBe(false);
    setWipePending(false);
    expect(await service.get('livestock')).not.toBeNull();
  });
});
