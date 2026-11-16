import 'fake-indexeddb/auto';
import { TestBed } from '@angular/core/testing';
import { openDB } from 'idb';
import { Subject } from 'rxjs';
import { AuthService, SessionEvent, SessionScope, SessionState } from 'core-auth';
import { wirePinLogoutWipe } from '@core/utils/pin-logout-wipe.util';
import {
  PIN_DB_NAME,
  PIN_ITERATIONS,
  PIN_MAX_ATTEMPTS,
  PIN_STORE_NAME,
  PinLockService,
  PinRecord,
  isWellFormed,
  constantTimeEqual,
} from './pin-lock.service';

const PIN = '482915';
const SCOPE: SessionScope = { user: 'ana@example.com', id_company: 1 };
/** PBKDF2 at 600k iterations is ~0.3 s here; give every derivation-heavy test room. */
const SLOW = 60_000;

describe('PinLockService', () => {
  let state: SessionState;
  let scope: SessionScope | null;
  let events: Subject<SessionEvent>;
  let logs: unknown[][];
  let current: PinLockService | null;

  /** A fresh service instance over the same IndexedDB, as after an app restart. */
  function fresh(): PinLockService {
    current?.closeConnection();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [{
        provide: AuthService,
        useValue: {
          getSessionState: () => state,
          getSessionScope: () => scope,
          sessionEvents$: events.asObservable(),
        },
      }],
    });
    current = TestBed.inject(PinLockService);
    return current;
  }

  beforeEach(() => {
    state = 'valid';
    scope = { ...SCOPE };
    events = new Subject<SessionEvent>();
    logs = [];
    vi.spyOn(console, 'warn').mockImplementation((...args: unknown[]) => { logs.push(args); });
    current = null;
  });

  afterEach(async () => {
    current?.closeConnection();
    current = null;
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    await new Promise<void>(resolve => {
      const req = indexedDB.deleteDatabase(PIN_DB_NAME);
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    });
  });

  describe('create', () => {
    it('creates a PIN in a valid online session and stores no plaintext PIN', async () => {
      const svc = fresh();
      expect(await svc.createPin(PIN)).toBe('created');

      const db = await openDB(PIN_DB_NAME, 1);
      const record = await db.get(PIN_STORE_NAME, SCOPE.user) as PinRecord;
      db.close();
      expect(record.user).toBe(SCOPE.user);
      expect(record.iterations).toBe(PIN_ITERATIONS);
      expect(record.algorithm).toBe('PBKDF2-SHA256');
      expect(record.failedAttempts).toBe(0);
      expect(record.salt.byteLength).toBe(16);
      expect(record.hash.byteLength).toBe(32);
      expect(JSON.stringify(record, (_k, v) => (ArrayBuffer.isView(v) ? Array.from(v as Uint8Array) : v)))
        .not.toContain(PIN);
    }, SLOW);

    it('rejects malformed and trivial PINs without deriving', async () => {
      const svc = fresh();
      const derive = vi.spyOn(svc as any, 'derive');
      for (const bad of ['12345', '1234567', 'abcdef', '12 456']) {
        expect(await svc.createPin(bad)).toBe('invalid-format');
      }
      for (const trivial of ['000000', '111111', '123456', '654321', '012345', '987654']) {
        expect(await svc.createPin(trivial)).toBe('trivial');
      }
      expect(derive).not.toHaveBeenCalled();
    });

    it('requires a valid session with a scope, and online', async () => {
      const svc = fresh();
      state = 'grace';
      expect(await svc.createPin(PIN)).toBe('not-valid-session');
      state = 'valid';
      scope = null;
      expect(await svc.createPin(PIN)).toBe('no-scope');
      scope = { ...SCOPE };
      vi.spyOn(svc as any, 'isOnline').mockReturnValue(false);
      expect(await svc.createPin(PIN)).toBe('offline');
      expect(await svc.hasRecord()).toBe(false);
    });

    it('fails closed when WebCrypto is unavailable: no record is written', async () => {
      const svc = fresh();
      vi.stubGlobal('crypto', { getRandomValues: (a: Uint8Array) => a });
      expect(await svc.createPin(PIN)).toBe('error');
      vi.unstubAllGlobals();
      expect(await svc.hasRecord()).toBe(false);
    });
  });

  describe('verify', () => {
    it('accepts the right PIN in grace and rejects a wrong one with the remaining count', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      expect(await svc.verify('900001')).toEqual({ status: 'wrong', remainingAttempts: 4 });
      expect(await svc.verify(PIN)).toEqual({ status: 'ok' });
      expect(await svc.remainingAttempts()).toBe(PIN_MAX_ATTEMPTS);
    }, SLOW);

    it('only verifies in grace and with a scope', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      expect(await svc.verify(PIN)).toEqual({ status: 'not-grace' });
      state = 'grace';
      scope = null;
      expect(await svc.verify(PIN)).toEqual({ status: 'no-scope' });
    });

    it('returns no-record when nothing was set up', async () => {
      const svc = fresh();
      state = 'grace';
      expect(await svc.verify(PIN)).toEqual({ status: 'no-record' });
    });

    it('rejects a malformed PIN format without counting an attempt', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      expect(await svc.verify('12a')).toEqual({ status: 'invalid-format' });
      expect(await svc.remainingAttempts()).toBe(PIN_MAX_ATTEMPTS);
    }, SLOW);

    it('locks out after 5 failures, persisted across service re-instantiation', async () => {
      const first = fresh();
      await first.createPin(PIN);
      state = 'grace';
      for (let i = 0; i < 3; i++) await first.verify('193847');

      const second = fresh();
      expect(await second.remainingAttempts()).toBe(2);
      expect(await second.verify('193847')).toEqual({ status: 'wrong', remainingAttempts: 1 });
      expect(await second.verify('193847')).toEqual({ status: 'locked' });

      const third = fresh();
      expect(await third.hasRecord()).toBe(false);
      expect(await third.verify(PIN)).toEqual({ status: 'no-record' });
    }, SLOW);

    it('persists the attempt BEFORE verifying: a kill mid-derivation still counts it', async () => {
      const first = fresh();
      await first.createPin(PIN);
      state = 'grace';
      vi.spyOn(first as any, 'derive').mockRejectedValueOnce(Object.assign(new Error('killed'), { name: 'AbortError' }));
      expect(await first.verify(PIN)).toEqual({ status: 'error' });

      const restarted = fresh();
      expect(await restarted.remainingAttempts()).toBe(PIN_MAX_ATTEMPTS - 1);
    }, SLOW);

    it('resets the counter on success', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      await svc.verify('193847');
      await svc.verify('193847');
      expect(await svc.verify(PIN)).toEqual({ status: 'ok' });
      expect(await svc.remainingAttempts()).toBe(PIN_MAX_ATTEMPTS);
    }, SLOW);

    it('treats a malformed record as locked and deletes it', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      const db = await openDB(PIN_DB_NAME, 1);
      const record = await db.get(PIN_STORE_NAME, SCOPE.user) as PinRecord;
      await db.put(PIN_STORE_NAME, { ...record, iterations: 1 });
      db.close();
      state = 'grace';
      expect(await svc.verify(PIN)).toEqual({ status: 'locked' });
      expect(await svc.hasRecord()).toBe(false);
    }, SLOW);

    it('fails closed on a WebCrypto failure, never as a success', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      vi.spyOn(svc as any, 'derive').mockRejectedValue(Object.assign(new Error('x'), { name: 'OperationError' }));
      expect(await svc.verify(PIN)).toEqual({ status: 'error' });
    }, SLOW);
  });

  describe('logout', () => {
    it('deletes the PIN records on the logout event', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      expect(await svc.hasRecord()).toBe(true);

      TestBed.runInInjectionContext(() => wirePinLogoutWipe());
      events.next({ type: 'logout' });
      await vi.waitFor(async () => expect(await svc.hasRecord()).toBe(false));
    }, SLOW);
  });

  describe('logging', () => {
    it('never logs the PIN, and logs only error names', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      vi.spyOn(svc as any, 'derive').mockRejectedValueOnce(
        Object.assign(new Error(`failed for ${PIN}`), { name: 'OperationError' }));
      await svc.verify(PIN);
      await svc.verify('193847');
      const printed = JSON.stringify(logs);
      expect(printed).not.toContain(PIN);
      expect(printed).not.toContain(SCOPE.user);
      expect(printed).toContain('OperationError');
    }, SLOW);
  });

  describe('helpers', () => {
    it('constantTimeEqual compares every byte', () => {
      expect(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3]))).toBe(true);
      expect(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 4]))).toBe(false);
      expect(constantTimeEqual(new Uint8Array([1]), new Uint8Array([1, 2]))).toBe(false);
    });

    it('isWellFormed rejects a record for another user', () => {
      const record = {
        user: 'other', salt: new Uint8Array(16), hash: new Uint8Array(32), iterations: PIN_ITERATIONS,
        algorithm: 'PBKDF2-SHA256', failedAttempts: 0, createdAt: 'x',
      };
      expect(isWellFormed(record as PinRecord, 'ana')).toBe(false);
      expect(isWellFormed(record as PinRecord, 'other')).toBe(true);
    });
  });

  describe('concurrency', () => {
    it('two concurrent wrong verifies in one window count BOTH attempts', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      state = 'grace';
      const [a, b] = await Promise.all([svc.verify('193847'), svc.verify('193847')]);
      expect(a).toEqual({ status: 'wrong', remainingAttempts: 4 });
      expect(b).toEqual({ status: 'wrong', remainingAttempts: 3 });
      expect(await svc.remainingAttempts()).toBe(3);
    }, SLOW);

    it('two windows (two service instances on the same database) count both attempts', async () => {
      const windowA = fresh();
      await windowA.createPin(PIN);
      state = 'grace';
      const windowB = TestBed.runInInjectionContext(() => new PinLockService());
      try {
        const [a, b] = await Promise.all([windowA.verify('193847'), windowB.verify('193847')]);
        expect([a, b].map(r => (r as { remainingAttempts: number }).remainingAttempts).sort()).toEqual([3, 4]);
        expect(await windowA.remainingAttempts()).toBe(3);
      } finally {
        windowB.closeConnection();
      }
    }, SLOW);
  });

  describe('deleteOthers', () => {
    it('keeps the named user and deletes every other PIN record', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      scope = { user: 'beto@example.com', id_company: 1 };
      await svc.createPin('193847');
      scope = { ...SCOPE };

      expect(await svc.deleteOthers('ana@example.com')).toBe(true);
      expect(await svc.hasRecord()).toBe(true);
      scope = { user: 'beto@example.com', id_company: 1 };
      expect(await svc.hasRecord()).toBe(false);
    }, SLOW);

    it('deletes everything when no user is kept', async () => {
      const svc = fresh();
      await svc.createPin(PIN);
      expect(await svc.deleteOthers(null)).toBe(true);
      expect(await svc.hasRecord()).toBe(false);
    }, SLOW);
  });
});
