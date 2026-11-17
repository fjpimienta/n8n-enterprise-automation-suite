import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { vi } from 'vitest';
import { AuthService, SessionEvent } from 'core-auth';
import { wireOfflineLogoutWipe } from '@core/utils/offline-logout-wipe.util';
import { OfflineStoreService, OFFLINE_DB_NAME } from './offline-store.service';
import { PinLockService } from './pin-lock.service';
import { OfflineExpiryWipeService } from './offline-expiry-wipe.service';
import { LoggerService } from './logger.service';

/** Counts every wipe of the offline copy from the expiry check and from the session events (T6). */
const NOW_S = Math.floor(Date.parse('2026-11-17T12:00:00.000Z') / 1000);
const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenExp = (exp: number) => `${enc({ alg: 'HS256' })}.${enc({ user: 'ana', id_company: 1, exp })}.sig`;
const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

describe('expired session login: wipe count (T6)', () => {
  let events: Subject<SessionEvent>;
  let wipeAll: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers({ now: Date.parse('2026-11-17T12:00:00.000Z'), toFake: ['Date'] });
    localStorage.clear();
    events = new Subject<SessionEvent>();
    wipeAll = vi.fn().mockResolvedValue(true);
    vi.spyOn(indexedDB, 'databases').mockResolvedValue([{ name: OFFLINE_DB_NAME, version: 1 }]);
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { sessionEvents$: events.asObservable() } },
        { provide: OfflineStoreService, useValue: { wipeAll } },
        { provide: PinLockService, useValue: { clearAll: vi.fn().mockResolvedValue(true) } },
        { provide: LoggerService, useValue: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }
      ]
    });
    TestBed.runInInjectionContext(() => wireOfflineLogoutWipe());
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('wipes once overall when the same user logs in again with an expired token', async () => {
    const expiry = TestBed.inject(OfflineExpiryWipeService);
    localStorage.setItem('authToken', tokenExp(NOW_S - 60));

    await expiry.check(); // check at start or on a tick: the expired copy is wiped
    // The login POST sees the expired token: AuthService.logout() clears it and emits 'logout'.
    localStorage.removeItem('authToken');
    events.next({ type: 'logout' });
    await settle();
    await expiry.check(); // the next tick finds no token: nothing new to wipe
    // The same user logs in again: a valid token and a 'login' event.
    localStorage.setItem('authToken', tokenExp(NOW_S + 3600));
    events.next({ type: 'login', scope: { user: 'ana', id_company: 1 } });
    await expiry.check();

    expect(wipeAll).toHaveBeenCalledTimes(1);
  });

  it('still wipes on logout from a valid session, also after an earlier expired wipe', async () => {
    const expiry = TestBed.inject(OfflineExpiryWipeService);
    localStorage.setItem('authToken', tokenExp(NOW_S - 60));
    await expiry.check();

    localStorage.setItem('authToken', tokenExp(NOW_S + 3600));
    events.next({ type: 'login', scope: { user: 'ana', id_company: 1 } });
    localStorage.removeItem('authToken');
    events.next({ type: 'logout' });

    expect(wipeAll).toHaveBeenCalledTimes(2);
  });

  it('still wipes on logout from a valid session that never had an expiry wipe', async () => {
    localStorage.setItem('authToken', tokenExp(NOW_S + 3600));
    events.next({ type: 'login', scope: { user: 'ana', id_company: 1 } });
    localStorage.removeItem('authToken');
    events.next({ type: 'logout' });
    expect(wipeAll).toHaveBeenCalledTimes(1);
  });
});
