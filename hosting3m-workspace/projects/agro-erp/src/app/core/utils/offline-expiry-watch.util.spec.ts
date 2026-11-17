import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { AUTH_ENV_CONFIG } from 'core-auth';
import { vi } from 'vitest';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { PinLockService } from '@core/services/pin-lock.service';
import { LoggerService } from '@core/services/logger.service';
import { OFFLINE_DB_NAME } from '@core/services/offline-store.service';
import { PIN_DB_NAME } from '@core/services/pin-lock.service';
import { OFFLINE_EXPIRY_CHECK_MS, startOfflineExpiryWatch } from './offline-expiry-watch.util';

const NOW_MS = Date.parse('2026-11-17T12:00:00.000Z');
const NOW_S = Math.floor(NOW_MS / 1000);
const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const expiredToken = () => `${enc({ alg: 'HS256' })}.${enc({ user: 'ana', id_company: 1, exp: NOW_S - 60 })}.sig`;

describe('startOfflineExpiryWatch', () => {
  let store: { wipeAll: ReturnType<typeof vi.fn> };
  let pin: { clearAll: ReturnType<typeof vi.fn> };

  function start(): void {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        { provide: OfflineStoreService, useValue: store },
        { provide: PinLockService, useValue: pin },
        { provide: AUTH_ENV_CONFIG, useValue: {} },
        { provide: LoggerService, useValue: { warn: vi.fn() } }
      ]
    });
    TestBed.runInInjectionContext(() => startOfflineExpiryWatch());
  }

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date', 'setInterval', 'clearInterval', 'setTimeout', 'clearTimeout'] });
    localStorage.clear();
    store = { wipeAll: vi.fn().mockResolvedValue(true) };
    pin = { clearAll: vi.fn().mockResolvedValue(true) };
    vi.spyOn(indexedDB, 'databases').mockResolvedValue([{ name: OFFLINE_DB_NAME, version: 1 }, { name: PIN_DB_NAME, version: 1 }]);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it('does not block bootstrap: it returns synchronously', () => {
    localStorage.setItem('authToken', expiredToken());
    expect(() => start()).not.toThrow();
  });

  it('runs one check at start and one per 60 s tick', async () => {
    localStorage.setItem('authToken', expiredToken());
    start();
    await vi.advanceTimersByTimeAsync(0);
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(OFFLINE_EXPIRY_CHECK_MS).toBe(60_000);
  });

  it('operation-count regression: five ticks after expiry perform exactly one wipe', async () => {
    localStorage.setItem('authToken', expiredToken());
    start();
    await vi.advanceTimersByTimeAsync(5 * OFFLINE_EXPIRY_CHECK_MS);
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pin.clearAll).not.toHaveBeenCalled();
  });

  it('checks on visibilitychange', async () => {
    start();
    await vi.advanceTimersByTimeAsync(0);
    const before = store.wipeAll.mock.calls.length;
    localStorage.setItem('authToken', expiredToken());
    document.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(0);
    expect(store.wipeAll.mock.calls.length).toBe(before + 1);
  });

  it('checks when the authToken changes in another tab, and ignores other keys', async () => {
    start();
    await vi.advanceTimersByTimeAsync(0);
    const before = store.wipeAll.mock.calls.length;
    window.dispatchEvent(new StorageEvent('storage', { key: 'other' }));
    await vi.advanceTimersByTimeAsync(0);
    expect(store.wipeAll.mock.calls.length).toBe(before);
    localStorage.setItem('authToken', expiredToken());
    window.dispatchEvent(new StorageEvent('storage', { key: 'authToken' }));
    await vi.advanceTimersByTimeAsync(0);
    expect(store.wipeAll.mock.calls.length).toBe(before + 1);
  });

  it('stops every listener and the timer when the injector is destroyed', async () => {
    localStorage.setItem('authToken', expiredToken());
    start();
    await vi.advanceTimersByTimeAsync(0);
    TestBed.resetTestingModule();
    const before = store.wipeAll.mock.calls.length;
    localStorage.setItem('authToken', expiredToken());
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new StorageEvent('storage', { key: 'authToken' }));
    await vi.advanceTimersByTimeAsync(3 * OFFLINE_EXPIRY_CHECK_MS);
    expect(store.wipeAll.mock.calls.length).toBe(before);
  });
});
