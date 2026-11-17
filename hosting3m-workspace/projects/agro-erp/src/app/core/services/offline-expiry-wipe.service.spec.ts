import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { AUTH_ENV_CONFIG } from 'core-auth';
import { vi } from 'vitest';
import { isWipePending, setWipePending } from '@core/utils/offline-wipe-pending.util';
import { OfflineStoreService, OFFLINE_DB_NAME } from './offline-store.service';
import { PinLockService, PIN_DB_NAME } from './pin-lock.service';
import { OfflineExpiryWipeService } from './offline-expiry-wipe.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';
import { LoggerService } from './logger.service';

const NOW_MS = Date.parse('2026-11-17T12:00:00.000Z');
const NOW_S = Math.floor(NOW_MS / 1000);

/** Unsigned JWT-shaped token: the client only reads the payload. */
function tokenWith(payload: Record<string, unknown>): string {
  const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${enc({ alg: 'HS256', typ: 'JWT' })}.${enc(payload)}.sig`;
}
const EXPIRED = () => tokenWith({ user: 'ana', id_company: 1, exp: NOW_S - 60 });
const VALID = () => tokenWith({ user: 'ana', id_company: 1, exp: NOW_S + 3600 });

describe('OfflineExpiryWipeService', () => {
  let store: { wipeAll: ReturnType<typeof vi.fn> };
  let pin: { clearAll: ReturnType<typeof vi.fn> };
  let config: { offlineGraceMs?: number } | null;
  let events: OfflineWipeEventsService;
  let warn: ReturnType<typeof vi.fn>;
  /** Databases that exist in the browser (fake-indexeddb). `indexedDB.databases()` is the real presence check. */
  let dbs: string[];

  function create(): OfflineExpiryWipeService {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        { provide: OfflineStoreService, useValue: store },
        { provide: PinLockService, useValue: pin },
        { provide: AUTH_ENV_CONFIG, useValue: config },
        { provide: LoggerService, useValue: { warn } }
      ]
    });
    events = TestBed.inject(OfflineWipeEventsService);
    return TestBed.inject(OfflineExpiryWipeService);
  }

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] });
    localStorage.clear();
    store = { wipeAll: vi.fn().mockResolvedValue(true) };
    pin = { clearAll: vi.fn().mockResolvedValue(true) };
    config = null; // production: no offlineGraceMs
    warn = vi.fn();
    dbs = [OFFLINE_DB_NAME, PIN_DB_NAME];
    vi.spyOn(indexedDB, 'databases').mockImplementation(async () => dbs.map(name => ({ name, version: 1 })));
    vi.spyOn(indexedDB, 'open');
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
    localStorage.clear();
  });

  it('wipes the cache when the stored token has expired without grace (T3, production)', async () => {
    const service = create();
    localStorage.setItem('authToken', EXPIRED());
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(isWipePending()).toBe(false);
  });

  it('does not wipe a valid token, even when the session state would look ambiguous (T2, T5)', async () => {
    // No AuthService is provided: the decision reads only the stored token's exp (D2).
    const service = create();
    localStorage.setItem('authToken', VALID());
    await service.check();
    expect(store.wipeAll).not.toHaveBeenCalled();
    expect(pin.clearAll).not.toHaveBeenCalled();
  });

  it('keeps the cache while the token is inside the configured grace window (T5)', async () => {
    config = { offlineGraceMs: 3_600_000 };
    const service = create();
    localStorage.setItem('authToken', tokenWith({ user: 'ana', id_company: 1, exp: NOW_S - 60 }));
    await service.check();
    expect(store.wipeAll).not.toHaveBeenCalled();
  });

  it('wipes the cache and the PIN records once grace has ended (T4, grace on)', async () => {
    config = { offlineGraceMs: 3_600_000 };
    const service = create();
    localStorage.setItem('authToken', tokenWith({ user: 'ana', id_company: 1, exp: NOW_S - 3700 }));
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pin.clearAll).toHaveBeenCalledTimes(1);
  });

  it('applies the same rule to the same user as to another one (D3)', async () => {
    const service = create();
    localStorage.setItem('authToken', EXPIRED());
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
  });

  it('never opens or touches the PIN database without grace (T11)', async () => {
    const service = create();
    localStorage.setItem('authToken', EXPIRED());
    await service.check();
    expect(pin.clearAll).not.toHaveBeenCalled();
    expect(indexedDB.open).not.toHaveBeenCalledWith(PIN_DB_NAME, expect.anything());
  });

  it('treats a token that cannot be read or has no exp as expired (D5)', async () => {
    const service = create();
    localStorage.setItem('authToken', 'garbage');
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    localStorage.setItem('authToken', tokenWith({ user: 'ana' }));
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(2);
  });

  describe('without any token (D5)', () => {
    it('does not create the cache database just to wipe it', async () => {
      dbs = [];
      const service = create();
      await service.check();
      expect(indexedDB.databases).toHaveBeenCalled();
      expect(store.wipeAll).not.toHaveBeenCalled();
      expect(indexedDB.open).not.toHaveBeenCalled();
      expect(pin.clearAll).not.toHaveBeenCalled();
    });

    it('wipes an existing cache database when there is no token', async () => {
      const service = create();
      await service.check();
      expect(store.wipeAll).toHaveBeenCalledTimes(1);
    });

    it('does not wipe when the database presence cannot be determined (never creates one)', async () => {
      vi.spyOn(indexedDB, 'databases').mockRejectedValue(new Error('unavailable'));
      const service = create();
      await service.check();
      expect(store.wipeAll).not.toHaveBeenCalled();
    });
  });

  it('keeps the pending flag and retries on the next check when a wipe is not confirmed (T8, D6)', async () => {
    store.wipeAll.mockResolvedValueOnce(false);
    const service = create();
    localStorage.setItem('authToken', EXPIRED());
    await service.check();
    expect(isWipePending()).toBe(true);
    await service.check();
    expect(store.wipeAll).toHaveBeenCalledTimes(2);
    expect(isWipePending()).toBe(false);
  });

  it('notifies the in-memory listeners once after a confirmed wipe', async () => {
    const onWiped = vi.fn();
    const service = create();
    events.wiped$.subscribe(onWiped);
    localStorage.setItem('authToken', EXPIRED());
    await service.check();
    expect(onWiped).toHaveBeenCalledTimes(1);
  });

  it('coalesces overlapping checks into one wipe', async () => {
    const service = create();
    localStorage.setItem('authToken', EXPIRED());
    await Promise.all([service.check(), service.check(), service.check()]);
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
  });

  it('operation-count regression: repeated ticks after expiry wipe exactly once', async () => {
    config = { offlineGraceMs: 3_600_000 };
    const service = create();
    localStorage.setItem('authToken', tokenWith({ user: 'ana', id_company: 1, exp: NOW_S - 7200 }));
    for (let i = 0; i < 10; i++) {
      await service.check();
      vi.advanceTimersByTime(60_000);
    }
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pin.clearAll).toHaveBeenCalledTimes(1);
  });

  it('wipes again when a token retried under a valid session later expires', async () => {
    const service = create();
    localStorage.setItem('authToken', tokenWith({ user: 'ana', id_company: 1, exp: NOW_S + 60 }));
    setWipePending(true);
    await service.check(); // valid session, pending retry: wipes, nothing is held for an ended session
    expect(store.wipeAll).toHaveBeenCalledTimes(1);

    vi.setSystemTime(NOW_MS + 120_000); // the same token is now past its exp
    await service.check();

    expect(store.wipeAll).toHaveBeenCalledTimes(2);
  });

  it('does not wipe when the wipe pending flag is clear and the token is valid (no extra work per tick)', async () => {
    const service = create();
    localStorage.setItem('authToken', VALID());
    for (let i = 0; i < 5; i++) {
      await service.check();
      vi.advanceTimersByTime(60_000);
    }
    expect(store.wipeAll).not.toHaveBeenCalled();
    expect(indexedDB.databases).not.toHaveBeenCalled();
  });
});
