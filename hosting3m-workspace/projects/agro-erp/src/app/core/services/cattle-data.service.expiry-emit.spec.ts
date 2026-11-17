import 'fake-indexeddb/auto';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { vi } from 'vitest';
import { AuthService, TenantService } from 'core-auth';
import { setWipePending, isWipePending } from '@core/utils/offline-wipe-pending.util';
import { CattleApiService } from './cattle-api.service';
import { CattleDataService } from './cattle-data.service';
import { OfflineStoreService, OFFLINE_DB_NAME } from './offline-store.service';
import { PinLockService } from './pin-lock.service';
import { OfflineExpiryWipeService } from './offline-expiry-wipe.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';
import { LoggerService } from './logger.service';

/**
 * The in-memory herd and the wipe event (#1087, 1b-iii-c audit). Real CattleDataService, real
 * OfflineWipeEventsService and real OfflineExpiryWipeService. Only the stores and the network are mocked.
 */

const NOW_MS = Date.parse('2026-11-17T12:00:00.000Z');
const NOW_S = Math.floor(NOW_MS / 1000);
const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenExp = (exp: number) => `${enc({ alg: 'HS256' })}.${enc({ user: 'ana', id_company: 3, exp })}.sig`;
const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

describe('wipe event and the in-memory herd (audit fix)', () => {
  let store: { get: ReturnType<typeof vi.fn>; put: ReturnType<typeof vi.fn>; wipeAll: ReturnType<typeof vi.fn> };
  let svc: CattleDataService;
  let expiry: OfflineExpiryWipeService;
  let events: OfflineWipeEventsService;

  async function loadHerd(): Promise<void> {
    TestBed.flushEffects();
    await settle();
    expect(svc.cattleList().length).toBe(1);
  }

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] });
    localStorage.clear();
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    vi.spyOn(indexedDB, 'databases').mockResolvedValue([{ name: OFFLINE_DB_NAME, version: 1 }]);
    store = {
      get: vi.fn().mockResolvedValue(null),
      put: vi.fn().mockResolvedValue(true),
      wipeAll: vi.fn().mockResolvedValue(true)
    };
    TestBed.configureTestingModule({
      providers: [
        { provide: CattleApiService, useValue: { getAllLivestock: vi.fn().mockResolvedValue([{ id: 'a', tenant_id: 3 }]) } },
        { provide: TenantService, useValue: { activeTenantId: signal<number | null>(3).asReadonly(), activeTenantChanges$: new Subject<number | null>(), availableTenants: () => [{ id_company: 3 }] } },
        { provide: AuthService, useValue: { sessionEvents$: new Subject<{ type: string }>(), getSessionScope: () => ({ user: 'ana', id_company: 3 }), getSessionState: () => 'valid' } },
        { provide: OfflineStoreService, useValue: store },
        { provide: PinLockService, useValue: { clearAll: vi.fn().mockResolvedValue(true) } },
        { provide: LoggerService, useValue: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }
      ]
    });
    svc = TestBed.inject(CattleDataService);
    expiry = TestBed.inject(OfflineExpiryWipeService);
    events = TestBed.inject(OfflineWipeEventsService);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('keeps a loaded herd when a valid session retries a pending wipe', async () => {
    localStorage.setItem('authToken', tokenExp(NOW_S + 3600));
    await loadHerd();
    setWipePending(true);
    const emitted = vi.spyOn(events, 'notifyWiped');

    await expiry.check();

    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(isWipePending()).toBe(false);
    expect(emitted).not.toHaveBeenCalled();
    expect(svc.cattleList().length).toBe(1);
    expect(svc.hasLoadedOnce()).toBe(true);
  });

  it('clears the herd once when the stored token has expired', async () => {
    localStorage.setItem('authToken', tokenExp(NOW_S + 3600));
    await loadHerd();
    localStorage.setItem('authToken', tokenExp(NOW_S - 60));
    const emitted = vi.spyOn(events, 'notifyWiped');

    await expiry.check();
    await expiry.check();

    expect(emitted).toHaveBeenCalledTimes(1);
    expect(svc.cattleList()).toEqual([]);
    expect(svc.hasLoadedOnce()).toBe(false);
  });

  it('notifies at most once for the no-token state, also when a pending retry runs', async () => {
    const emitted = vi.spyOn(events, 'notifyWiped');

    await expiry.check();
    setWipePending(true);
    await expiry.check();
    await expiry.check();

    expect(emitted).toHaveBeenCalledTimes(1);
  });
});
