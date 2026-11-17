import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { openDB } from 'idb';
import { Subject } from 'rxjs';
import { vi } from 'vitest';
import { AuthService, SessionEvent, SessionScope, SessionState } from 'core-auth';
import { wireOfflineLogoutWipe } from '@core/utils/offline-logout-wipe.util';
import { isWipePending } from '@core/utils/offline-wipe-pending.util';
import { OfflineStoreService, OFFLINE_DB_NAME, OFFLINE_DB_VERSION, OFFLINE_STORE_NAME } from './offline-store.service';
import { PinLockService } from './pin-lock.service';
import { OfflineExpiryWipeService } from './offline-expiry-wipe.service';
import { LoggerService } from './logger.service';

/**
 * Final state of the offline copy around an expired session (T6, #1087 1b-iii-c). Real OfflineStoreService and
 * real IndexedDB (fake-indexeddb): the assertions read what is really left in the cache, not call counts.
 */

const T0 = Date.parse('2026-11-17T12:00:00.000Z');
const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenExp = (exp: number) => `${enc({ alg: 'HS256' })}.${enc({ user: 'ana', id_company: 1, exp })}.sig`;
const expOf = (token: string): number => JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp;
const SCOPE: SessionScope = { user: 'ana', id_company: 1 };

/** Lets the fire-and-forget IndexedDB work of a logout finish. */
async function flushIdb(): Promise<void> {
  for (let i = 0; i < 20; i++) await new Promise(resolve => setTimeout(resolve, 5));
}

describe('expired session: final state of the offline copy (T6)', () => {
  let events: Subject<SessionEvent>;
  let store: OfflineStoreService;
  let expiry: OfflineExpiryWipeService;

  /** Session state derived from the stored token, the way AuthService reads it. */
  function state(): SessionState {
    const token = localStorage.getItem('authToken');
    if (!token) return 'expired';
    return Math.floor(Date.now() / 1000) <= expOf(token) ? 'valid' : 'expired';
  }

  async function rawCount(): Promise<number> {
    const db = await openDB(OFFLINE_DB_NAME, OFFLINE_DB_VERSION, {
      upgrade: d => { if (!d.objectStoreNames.contains(OFFLINE_STORE_NAME)) d.createObjectStore(OFFLINE_STORE_NAME); }
    });
    const n = await db.count(OFFLINE_STORE_NAME);
    db.close();
    return n;
  }

  beforeEach(() => {
    vi.useFakeTimers({ now: T0, toFake: ['Date'] });
    localStorage.clear();
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    events = new Subject<SessionEvent>();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        {
          provide: AuthService,
          useValue: {
            sessionEvents$: events.asObservable(),
            getSessionState: () => state(),
            getSessionScope: () => (localStorage.getItem('authToken') ? SCOPE : null)
          }
        },
        { provide: PinLockService, useValue: { clearAll: vi.fn().mockResolvedValue(true) } },
        { provide: LoggerService, useValue: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }
      ]
    });
    TestBed.runInInjectionContext(() => wireOfflineLogoutWipe());
    store = TestBed.inject(OfflineStoreService);
    expiry = TestBed.inject(OfflineExpiryWipeService);
  });

  afterEach(async () => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
    localStorage.clear();
    await new Promise<void>(resolve => {
      const req = indexedDB.deleteDatabase(OFFLINE_DB_NAME);
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    });
  });

  /** AuthService.logout(): the token goes first, then the event. */
  function logout(): void {
    localStorage.removeItem('authToken');
    events.next({ type: 'logout' });
  }

  function login(exp: number): void {
    localStorage.setItem('authToken', tokenExp(exp));
    events.next({ type: 'login', scope: SCOPE });
  }

  it('ends with an empty offline cache and a clean state when the same user logs in with an expired token', async () => {
    login(T0 / 1000 + 3600);
    expect(await store.put('livestock', [{ id: 1 }], SCOPE)).toBe(true);

    vi.setSystemTime(T0 + 2 * 3600_000); // the token is now past its exp and its (zero) grace
    await expiry.check(); // start-up or a tick: the expired copy is wiped
    logout(); // the login POST sees the expired token and logs out (AuthService.getStoredToken)
    await flushIdb();
    await expiry.check(); // the next tick finds no token
    login(T0 / 1000 + 2 * 3600 + 3600); // the same user signs in again: a valid token
    await expiry.check();

    expect(await rawCount()).toBe(0);
    expect(isWipePending()).toBe(false);
  });

  it('a voluntary logout with a valid session always empties the cache', async () => {
    login(T0 / 1000 + 3600);
    expect(await store.put('livestock', [{ id: 1 }], SCOPE)).toBe(true);

    logout();
    await flushIdb();

    expect(await rawCount()).toBe(0);
  });

  it('a voluntary logout with a valid session empties the cache right after an expired-session wipe', async () => {
    login(T0 / 1000 + 3600);
    vi.setSystemTime(T0 + 2 * 3600_000);
    await expiry.check(); // expired: the copy is wiped in this page session

    login(T0 / 1000 + 2 * 3600 + 3600); // a new valid session starts, no tick runs in between
    expect(await store.put('livestock', [{ id: 2 }], SCOPE)).toBe(true);
    logout();
    await flushIdb();

    expect(await rawCount()).toBe(0);
  });
});
