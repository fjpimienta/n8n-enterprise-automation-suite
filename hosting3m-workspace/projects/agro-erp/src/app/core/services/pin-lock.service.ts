import { Injectable, OnDestroy, inject } from '@angular/core';
import { IDBPDatabase, openDB } from 'idb';
import { AUTH_ENV_CONFIG, AuthService, SessionScope, SessionState } from 'core-auth';
import { LoggerService } from './logger.service';
import { isPinFormat, isTrivialPin } from '@core/utils/pin-policy.util';
import { isOfflineGraceEnabled } from '@core/utils/offline-grace-config.util';

/**
 * Separate database on purpose: `agroerp-offline` keeps its version (OFFLINE_DB_VERSION), and a cache
 * wipe never touches the PIN records (and vice versa).
 */
export const PIN_DB_NAME = 'agroerp-pin';
export const PIN_DB_VERSION = 1;
export const PIN_STORE_NAME = 'pin_records';
/**
 * PBKDF2-SHA256 iterations. Records with any other value are rejected as malformed (no silent
 * downgrade); raising it needs a migration. Measured: ~0.28 s per derivation on a desktop Node 22
 * (unthrottled), see CLAUDE.md for the throttled measurement.
 */
export const PIN_ITERATIONS = 600_000;
export const PIN_ALGORITHM = 'PBKDF2-SHA256';
export const PIN_SALT_BYTES = 16;
export const PIN_HASH_BYTES = 32;
export const PIN_MAX_ATTEMPTS = 5;

/** Persisted shape. Never contains the PIN itself. */
export interface PinRecord {
  user: string;
  salt: Uint8Array;
  hash: Uint8Array;
  iterations: number;
  algorithm: string;
  failedAttempts: number;
  createdAt: string;
}

export type PinCreateResult =
  | 'created'
  | 'disabled'
  | 'invalid-format'
  | 'trivial'
  | 'not-valid-session'
  | 'offline'
  | 'no-scope'
  | 'error';

export type PinVerifyResult =
  | { status: 'ok' }
  | { status: 'wrong'; remainingAttempts: number }
  | { status: 'locked' }
  | { status: 'no-record' }
  | { status: 'invalid-format' }
  | { status: 'not-grace' }
  | { status: 'no-scope' }
  | { status: 'error' };

/**
 * PIN record for the offline grace window (#1087, phase 1b-iii-b). Gates the UI only: the cache is
 * not encrypted, and the API stays blocked by `offlineGraceGuard` while in grace.
 *
 * - Created only in `'valid'` sessions while online. Keyed by the session `user` (scope).
 * - Fail-closed: no scope, no record, a malformed record, or any WebCrypto/IndexedDB failure is
 *   "not unlocked". The failure is never converted into a success.
 * - The attempt counter is persisted BEFORE the PIN is verified, so killing the app mid-verify cannot
 *   reset it. After `PIN_MAX_ATTEMPTS` failures the record is deleted; recovery is an online login.
 * - Logs carry error names only, never the PIN, hash, salt, scope values or tokens.
 */
@Injectable({ providedIn: 'root' })
export class PinLockService implements OnDestroy {
  private readonly auth = inject(AuthService);
  private readonly logger = inject(LoggerService);
  private readonly config = inject(AUTH_ENV_CONFIG, { optional: true });

  private dbPromise: Promise<IDBPDatabase> | null = null;
  private queue: Promise<unknown> = Promise.resolve();

  /** Creates (or replaces) the PIN for the current session. The PIN is never stored. Serialized. */
  createPin(pin: string): Promise<PinCreateResult> {
    return this.serialize(() => this.createPinNow(pin));
  }

  private async createPinNow(pin: string): Promise<PinCreateResult> {
    // Dormant without offlineGraceMs: nothing is derived and nothing is written to IndexedDB.
    if (!isOfflineGraceEnabled(this.config)) return 'disabled';
    if (!isPinFormat(pin)) return 'invalid-format';
    if (isTrivialPin(pin)) return 'trivial';

    let state: SessionState;
    let scope: SessionScope | null;
    try {
      state = this.auth.getSessionState();
      scope = this.auth.getSessionScope();
    } catch (err) {
      this.logError('create', err);
      return 'error';
    }
    if (!scope) return 'no-scope';
    if (state !== 'valid') return 'not-valid-session';
    if (!this.isOnline()) return 'offline';

    try {
      const salt = randomBytes(PIN_SALT_BYTES);
      const hash = await this.derive(pin, salt, PIN_ITERATIONS);
      const record: PinRecord = {
        user: scope.user,
        salt,
        hash,
        iterations: PIN_ITERATIONS,
        algorithm: PIN_ALGORITHM,
        failedAttempts: 0,
        createdAt: new Date().toISOString(),
      };
      await this.put(record);
      return 'created';
    } catch (err) {
      this.logError('create', err);
      return 'error';
    }
  }

  /**
   * Verifies the PIN against the record of the current grace session. Calls are serialized in this page
   * (queue) and the attempt is counted in one IndexedDB readwrite transaction, so two calls, or two
   * windows of the app, can never count one attempt for two guesses.
   */
  verify(pin: string): Promise<PinVerifyResult> {
    return this.serialize(() => this.verifyNow(pin));
  }

  private async verifyNow(pin: string): Promise<PinVerifyResult> {
    let state: SessionState;
    let scope: SessionScope | null;
    try {
      state = this.auth.getSessionState();
      scope = this.auth.getSessionScope();
    } catch (err) {
      this.logError('verify', err);
      return { status: 'error' };
    }
    if (!scope) return { status: 'no-scope' };
    if (state !== 'grace') return { status: 'not-grace' };
    if (!isPinFormat(pin)) return { status: 'invalid-format' };

    try {
      // Read, check and increment happen in ONE readwrite transaction, committed before any derivation.
      // The increment therefore survives a crash, and concurrent writers cannot lose it.
      const reservation = await this.reserveAttempt(scope.user);
      if (reservation.kind === 'missing') return { status: 'no-record' };
      if (reservation.kind === 'locked' || reservation.kind === 'malformed') return { status: 'locked' };

      const { record, attempts } = reservation;
      const candidate = await this.derive(pin, record.salt, record.iterations);
      if (!constantTimeEqual(candidate, record.hash)) {
        if (attempts >= PIN_MAX_ATTEMPTS) {
          await this.remove(scope.user);
          return { status: 'locked' };
        }
        return { status: 'wrong', remainingAttempts: PIN_MAX_ATTEMPTS - attempts };
      }

      // The session may have changed while deriving (tenant switch, logout): never unlock another scope.
      const after = this.currentScope();
      if (!after || after.user !== scope.user || after.id_company !== scope.id_company) {
        return { status: 'no-scope' };
      }
      await this.resetAttemptsIfUnchanged(scope.user, attempts);
      return { status: 'ok' };
    } catch (err) {
      this.logError('verify', err);
      return { status: 'error' };
    }
  }

  /**
   * Atomic read-check-increment of the attempt counter (single readwrite transaction). Returns the
   * attempts count including this one, or why no attempt can be made.
   */
  private async reserveAttempt(user: string): Promise<
    | { kind: 'missing' }
    | { kind: 'malformed' }
    | { kind: 'locked' }
    | { kind: 'reserved'; record: PinRecord; attempts: number }
  > {
    const db = await this.open();
    const tx = db.transaction(PIN_STORE_NAME, 'readwrite');
    const record = await tx.store.get(user) as PinRecord | undefined;
    if (!record) {
      await tx.done;
      return { kind: 'missing' };
    }
    if (!isWellFormed(record, user)) {
      await tx.store.delete(user);
      await tx.done;
      return { kind: 'malformed' };
    }
    if (record.failedAttempts >= PIN_MAX_ATTEMPTS) {
      await tx.store.delete(user);
      await tx.done;
      return { kind: 'locked' };
    }
    const attempts = record.failedAttempts + 1;
    await tx.store.put({ ...record, failedAttempts: attempts });
    await tx.done;
    return { kind: 'reserved', record, attempts };
  }

  /** Resets the counter after a correct PIN, only if nobody else counted an attempt meanwhile. */
  private async resetAttemptsIfUnchanged(user: string, expectedAttempts: number): Promise<void> {
    const db = await this.open();
    const tx = db.transaction(PIN_STORE_NAME, 'readwrite');
    const current = await tx.store.get(user) as PinRecord | undefined;
    if (current && current.failedAttempts === expectedAttempts) {
      await tx.store.put({ ...current, failedAttempts: 0 });
    }
    await tx.done;
  }

  /**
   * Deletes the PIN records of every user except `keepUser` (`null` deletes all). Used after a login with
   * a different (or unknown previous) user. Resolves `false` on failure.
   */
  async deleteOthers(keepUser: string | null): Promise<boolean> {
    try {
      const db = await this.open();
      const tx = db.transaction(PIN_STORE_NAME, 'readwrite');
      const keys = await tx.store.getAllKeys();
      for (const key of keys) {
        if (key !== keepUser) await tx.store.delete(key);
      }
      await tx.done;
      return true;
    } catch (err) {
      this.logError('deleteOthers', err);
      return false;
    }
  }

  /** True when a valid record exists for the current session user. Fail-closed: `false` on any error. */
  async hasRecord(): Promise<boolean> {
    const scope = this.currentScope();
    if (!scope) return false;
    try {
      const record = await this.get(scope.user);
      return !!record && isWellFormed(record, scope.user);
    } catch (err) {
      this.logError('hasRecord', err);
      return false;
    }
  }

  /** Attempts left for the current session user, or `null` when there is no usable record. */
  async remainingAttempts(): Promise<number | null> {
    const scope = this.currentScope();
    if (!scope) return null;
    try {
      const record = await this.get(scope.user);
      if (!record || !isWellFormed(record, scope.user)) return null;
      return Math.max(0, PIN_MAX_ATTEMPTS - record.failedAttempts);
    } catch (err) {
      this.logError('remainingAttempts', err);
      return null;
    }
  }

  /** Deletes every PIN record on this device. Called on the session `'logout'` event (no scope there). */
  async clearAll(): Promise<boolean> {
    try {
      const db = await this.open();
      await db.clear(PIN_STORE_NAME);
      return true;
    } catch (err) {
      this.logError('clearAll', err);
      return false;
    }
  }

  /** Closes the connection so the database can be deleted or upgraded. The next call reopens it. */
  closeConnection(): void {
    const pending = this.dbPromise;
    this.dbPromise = null;
    pending?.then(db => db.close()).catch(() => undefined);
  }

  ngOnDestroy(): void {
    this.closeConnection();
  }

  /** Runs `task` after every previously queued task of this service instance (one at a time). */
  private serialize<T>(task: () => Promise<T>): Promise<T> {
    const run = this.queue.then(task, task);
    this.queue = run.catch(() => undefined);
    return run;
  }

  private currentScope(): SessionScope | null {
    try {
      return this.auth.getSessionScope();
    } catch {
      return null;
    }
  }

  private isOnline(): boolean {
    return typeof navigator === 'undefined' || navigator.onLine !== false;
  }

  /** PBKDF2-SHA256 through WebCrypto. Throws when WebCrypto is unavailable (caller fails closed). */
  private async derive(pin: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
    const subtle = globalThis.crypto?.subtle;
    if (!subtle) throw new Error('WebCryptoUnavailable');
    const key = await subtle.importKey('raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits']);
    const bits = await subtle.deriveBits(
      { name: 'PBKDF2', salt: salt as BufferSource, iterations, hash: 'SHA-256' },
      key,
      PIN_HASH_BYTES * 8,
    );
    return new Uint8Array(bits);
  }

  private open(): Promise<IDBPDatabase> {
    if (!this.dbPromise) {
      if (typeof indexedDB === 'undefined' || !indexedDB) {
        return Promise.reject(new Error('IndexedDBUnavailable'));
      }
      this.dbPromise = openDB(PIN_DB_NAME, PIN_DB_VERSION, {
        upgrade: db => {
          if (!db.objectStoreNames.contains(PIN_STORE_NAME)) {
            db.createObjectStore(PIN_STORE_NAME, { keyPath: 'user' });
          }
        },
        blocking: () => this.closeConnection(),
      }).catch(err => {
        this.dbPromise = null;
        throw err;
      });
    }
    return this.dbPromise;
  }

  private async get(user: string): Promise<PinRecord | undefined> {
    const db = await this.open();
    return db.get(PIN_STORE_NAME, user);
  }

  private async put(record: PinRecord): Promise<void> {
    const db = await this.open();
    await db.put(PIN_STORE_NAME, record);
  }

  private async remove(user: string): Promise<void> {
    const db = await this.open();
    await db.delete(PIN_STORE_NAME, user);
  }

  /** Error name only: never the error message, which may echo inputs. */
  private logError(op: string, err: unknown): void {
    this.logger.warn(`PinLock: ${op} failed`, (err as Error)?.name);
  }
}

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  globalThis.crypto.getRandomValues(bytes);
  return bytes;
}

/** Constant-time comparison of two equal-length byte arrays (no early exit on the first mismatch). */
export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/**
 * Structural check of a stored record. Uses `ArrayBuffer.isView` instead of `instanceof`, because
 * structured clones may come back from another realm.
 */
export function isWellFormed(record: PinRecord, user: string): boolean {
  return !!record
    && record.user === user
    && ArrayBuffer.isView(record.salt) && record.salt.byteLength === PIN_SALT_BYTES
    && ArrayBuffer.isView(record.hash) && record.hash.byteLength === PIN_HASH_BYTES
    && record.iterations === PIN_ITERATIONS
    && record.algorithm === PIN_ALGORITHM
    && Number.isInteger(record.failedAttempts) && record.failedAttempts >= 0
    && typeof record.createdAt === 'string';
}
