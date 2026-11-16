import { Injectable, OnDestroy, inject } from '@angular/core';
import { IDBPDatabase, openDB } from 'idb';
import { AuthService, SessionScope } from 'core-auth';
import { LoggerService } from './logger.service';

/**
 * Closed allowlist of datasets that may be cached offline (#1087, phase 1b).
 * Money datasets (expenses, sales, income) are deliberately NOT part of this union and are
 * also rejected at runtime: they must never be written to the device.
 */
export type OfflineDataset = 'livestock' | 'catalogs';

export const OFFLINE_DATASETS: readonly OfflineDataset[] = Object.freeze(['livestock', 'catalogs']);

export const OFFLINE_DB_NAME = 'agroerp-offline';
/** IndexedDB structural version (bump only when the object stores change). */
export const OFFLINE_DB_VERSION = 1;
/** Version of the stored entry shape. A mismatch makes `get()` return `null`. */
export const OFFLINE_SCHEMA_VERSION = 1;
export const OFFLINE_STORE_NAME = 'entries';

/** Value returned by `get()`. */
export interface OfflineSnapshot<T = unknown> {
  data: T;
  /** ISO-8601 UTC timestamp of when the snapshot was stored. */
  savedAt: string;
}

/** Shape persisted in IndexedDB. Carries its own scope for defense in depth. */
interface OfflineEntry {
  user: string;
  id_company: number;
  dataset: OfflineDataset;
  savedAt: string;
  schemaVersion: number;
  data: unknown;
}

/**
 * Partitioned offline read-cache (#1087, phase 1b-ii). Not wired into any feature yet.
 *
 * - One object store keyed by `${user}|${id_company}|${dataset}`; `get()` reads the scope from
 *   `AuthService.getSessionScope()` at call time; `put()` takes the scope the data was fetched for and
 *   requires it to equal the current one (fail-closed: no scope, no read and no write).
 * - `'expired'` sessions (`AuthService.getSessionState()`) can neither read nor write; `'grace'` can.
 * - Every entry stores its scope and schema version, and `get()` re-verifies both.
 * - Plaintext IndexedDB (owner decision); only `livestock` and `catalogs` can be stored.
 * - Never throws to callers: failures resolve `get` to `null` and `put` to `false`. Logs carry the
 *   error name only, never data, scope values or tokens.
 */
@Injectable({ providedIn: 'root' })
export class OfflineStoreService implements OnDestroy {
  private readonly auth = inject(AuthService);
  private readonly logger = inject(LoggerService);

  private dbPromise: Promise<IDBPDatabase> | null = null;

  /**
   * Stores `data` under the partition of `expectedScope`. Resolves `true` only when it was persisted.
   *
   * **Callers must capture the scope (`AuthService.getSessionScope()`) when the fetch STARTS** and
   * pass that value here, not a scope read after the response arrives: otherwise a tenant switch
   * between the fetch and the write could store company A's data under company B's partition.
   *
   * Fail-closed: resolves `false` and stores nothing, in any partition, unless `expectedScope` is
   * valid AND equals the current session scope at call time AND still equals it after the
   * IndexedDB connection is open (immediately before the write), and the session state is not
   * `'expired'` (`'valid'` and `'grace'` are allowed).
   */
  async put(dataset: OfflineDataset, data: unknown, expectedScope: SessionScope): Promise<boolean> {
    try {
      if (!this.isAllowedDataset(dataset)) {
        this.logger.warn('OfflineStore: dataset rejected (not in allowlist)');
        return false;
      }
      if (!this.isValidScope(expectedScope)) return false;
      // Snapshot: later mutation of the caller's object must not change the partition written.
      const scope: SessionScope = { user: expectedScope.user, id_company: expectedScope.id_company };
      const current = this.currentScope();
      if (!current || !this.sameScope(scope, current)) return false;
      if (this.isExpired()) return false;
      const entry: OfflineEntry = {
        user: scope.user,
        id_company: scope.id_company,
        dataset,
        savedAt: new Date().toISOString(),
        schemaVersion: OFFLINE_SCHEMA_VERSION,
        data
      };
      const db = await this.open();
      // The scope or session may have changed while the connection was opening: re-verify.
      const after = this.currentScope();
      if (!after || !this.sameScope(scope, after) || this.isExpired()) return false;
      await db.put(OFFLINE_STORE_NAME, entry, this.key(scope, dataset));
      return true;
    } catch (err) {
      this.logFailure('put', err);
      return false;
    }
  }

  /** Reads the snapshot of the active session scope, or `null` (missing, mismatched, corrupt, failure). */
  async get<T = unknown>(dataset: OfflineDataset): Promise<OfflineSnapshot<T> | null> {
    try {
      if (!this.isAllowedDataset(dataset)) {
        this.logger.warn('OfflineStore: dataset rejected (not in allowlist)');
        return null;
      }
      const scope = this.currentScope();
      if (!scope || this.isExpired()) return null;
      const db = await this.open();
      const raw: unknown = await db.get(OFFLINE_STORE_NAME, this.key(scope, dataset));
      if (raw === undefined) return null;

      // The scope may have changed while awaiting IndexedDB: re-read it and require a match.
      const after = this.currentScope();
      if (!after || !this.sameScope(scope, after) || this.isExpired()) return null;
      if (!this.isValidEntry(raw, after, dataset)) return null;
      return { data: raw.data as T, savedAt: raw.savedAt };
    } catch (err) {
      this.logFailure('get', err);
      return null;
    }
  }

  /** Deletes every dataset of one explicit scope (e.g. a user/company being signed out or removed). */
  async wipeScope(scope: SessionScope): Promise<boolean> {
    try {
      if (!this.isValidScope(scope)) return false;
      const db = await this.open();
      const tx = db.transaction(OFFLINE_STORE_NAME, 'readwrite');
      // Await every delete together with `tx.done` so an aborted transaction rejects into the
      // catch below instead of leaving unhandled rejections.
      // A synchronous throw (e.g. the transaction already aborted) is turned into a rejected
      // promise so the ones already created are still attached to the same Promise.all.
      const pending: Promise<unknown>[] = [tx.done];
      for (const dataset of OFFLINE_DATASETS) {
        try {
          pending.push(tx.store.delete(this.key(scope, dataset)));
        } catch (err) {
          pending.push(Promise.reject(err));
        }
      }
      await Promise.all(pending);
      return true;
    } catch (err) {
      this.logFailure('wipeScope', err);
      return false;
    }
  }

  /** Deletes everything this store holds, for all users and companies. */
  async wipeAll(): Promise<boolean> {
    try {
      const db = await this.open();
      await db.clear(OFFLINE_STORE_NAME);
      return true;
    } catch (err) {
      this.logFailure('wipeAll', err);
      return false;
    }
  }

  ngOnDestroy(): void {
    const pending = this.dbPromise;
    this.dbPromise = null;
    pending?.then(db => db.close()).catch(() => undefined);
  }

  // ---- internals ----

  private open(): Promise<IDBPDatabase> {
    if (!this.dbPromise) {
      const attempt = this.openConnection();
      this.dbPromise = attempt;
      // A failed open must not be cached: the next call retries.
      attempt.catch(() => {
        if (this.dbPromise === attempt) this.dbPromise = null;
      });
    }
    return this.dbPromise;
  }

  private openConnection(): Promise<IDBPDatabase> {
    return new Promise<IDBPDatabase>((resolve, reject) => {
      if (typeof indexedDB === 'undefined' || !indexedDB) {
        reject(new Error('IndexedDBUnavailable'));
        return;
      }
      let abandoned = false;
      openDB(OFFLINE_DB_NAME, OFFLINE_DB_VERSION, {
        upgrade: db => {
          if (!db.objectStoreNames.contains(OFFLINE_STORE_NAME)) {
            db.createObjectStore(OFFLINE_STORE_NAME);
          }
        },
        blocked: () => {
          abandoned = true;
          reject(new Error('IndexedDBBlocked'));
        },
        blocking: () => this.dropConnection(),
        terminated: () => this.dropConnection()
      }).then(
        db => {
          // A blocked open that finally succeeds after we gave up must not leak its connection.
          if (abandoned) db.close();
          else resolve(db);
        },
        reject
      );
    });
  }

  /** Closes and forgets the connection so another tab/version can proceed; the next call reopens. */
  private dropConnection(): void {
    const pending = this.dbPromise;
    this.dbPromise = null;
    pending?.then(db => db.close()).catch(() => undefined);
  }

  private currentScope(): SessionScope | null {
    const scope = this.auth.getSessionScope();
    return this.isValidScope(scope) ? { user: scope.user, id_company: scope.id_company } : null;
  }

  /** Fail-closed: anything but `'valid'` or `'grace'` (including a throwing check) counts as expired. */
  private isExpired(): boolean {
    try {
      const state = this.auth.getSessionState();
      return state !== 'valid' && state !== 'grace';
    } catch {
      return true;
    }
  }

  private isValidScope(scope: unknown): scope is SessionScope {
    if (!scope || typeof scope !== 'object') return false;
    const s = scope as Partial<SessionScope>;
    return typeof s.user === 'string' && s.user.trim().length > 0
      && typeof s.id_company === 'number' && Number.isInteger(s.id_company) && s.id_company > 0;
  }

  private sameScope(a: SessionScope, b: SessionScope): boolean {
    return a.user === b.user && a.id_company === b.id_company;
  }

  private isAllowedDataset(dataset: unknown): dataset is OfflineDataset {
    return typeof dataset === 'string' && (OFFLINE_DATASETS as readonly string[]).includes(dataset);
  }

  /** `user` is URI-encoded so a `|` inside it can never alias another (user, company) key. */
  private key(scope: SessionScope, dataset: OfflineDataset): string {
    return `${encodeURIComponent(scope.user)}|${scope.id_company}|${dataset}`;
  }

  private isValidEntry(raw: unknown, scope: SessionScope, dataset: OfflineDataset): raw is OfflineEntry {
    if (!raw || typeof raw !== 'object') return false;
    const e = raw as Partial<OfflineEntry>;
    return e.schemaVersion === OFFLINE_SCHEMA_VERSION
      && e.dataset === dataset
      && e.user === scope.user
      && e.id_company === scope.id_company
      && typeof e.savedAt === 'string'
      && !Number.isNaN(Date.parse(e.savedAt))
      && 'data' in e;
  }

  /** Logs the operation and the error name only: never data, scope values or tokens. */
  private logFailure(op: string, err: unknown): void {
    const name = err instanceof Error || (err && typeof err === 'object' && 'name' in err)
      ? String((err as { name: unknown }).name)
      : 'UnknownError';
    this.logger.warn(`OfflineStore: ${op} failed`, name);
  }
}
