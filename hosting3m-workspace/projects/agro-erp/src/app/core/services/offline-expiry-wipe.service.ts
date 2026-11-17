import { Injectable, inject } from '@angular/core';
import { AUTH_ENV_CONFIG } from 'core-auth';
import { databaseExists } from '@core/utils/indexeddb-presence.util';
import { isWipePending, setWipePending } from '@core/utils/offline-wipe-pending.util';
import { graceMsOf, isPastGraceWindow, readStoredTokenExpiry } from '@core/utils/stored-token-expiry.util';
import { isOfflineGraceEnabled } from '@core/utils/offline-grace-config.util';
import { OfflineStoreService, OFFLINE_DB_NAME } from './offline-store.service';
import { PinLockService, PIN_DB_NAME } from './pin-lock.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';
import { LoggerService } from './logger.service';

/**
 * Wipes the offline copies once the stored session can no longer be used offline (#1087, phase 1b-iii-c).
 *
 * Decision rule (D1, D2, D5): the stored token's `exp` plus the grace window (0 without grace) has passed,
 * or the token is unreadable, or there is no token at all. The session state is NOT used, so a missing
 * tenant context never triggers a wipe by mistake. A valid or in-grace token never triggers it (#1096).
 *
 * - Cache (`agroerp-offline`): wiped for every user on the device (`wipeAll`). PIN records (`agroerp-pin`)
 *   are wiped only when grace is configured, and only if their database exists.
 * - Never creates a database just to wipe it. With no token, the wipe runs only when the cache database
 *   already exists; if its presence cannot be determined, nothing is created and the wipe is not confirmed.
 * - Fail-closed: a wipe that is not confirmed sets the pending flag (the cache is not served or written)
 *   and is retried on every later check. A confirmed wipe runs once per token in this page session.
 * - Makes no HTTP request and never calls `getStoredToken()` (which logs out). Overlapping calls share one run.
 */
@Injectable({ providedIn: 'root' })
export class OfflineExpiryWipeService {
  private readonly store = inject(OfflineStoreService);
  private readonly pin = inject(PinLockService);
  private readonly events = inject(OfflineWipeEventsService);
  private readonly logger = inject(LoggerService);
  private readonly config = inject(AUTH_ENV_CONFIG, { optional: true });

  /** Key of the stored value already confirmed wiped in this page session (kept in memory only). */
  private confirmedFor: string | null = null;
  private running: Promise<void> | null = null;

  /** Runs one check. Never rejects; safe to call from timers, listeners and the app initializer. */
  check(): Promise<void> {
    if (!this.running) {
      this.running = this.run()
        .catch(() => this.markPending())
        .finally(() => { this.running = null; });
    }
    return this.running;
  }

  private async run(): Promise<void> {
    const expiry = readStoredTokenExpiry();
    const pending = isWipePending();
    // One confirmed wipe per stored value: the token itself, or the unreadable raw value, or 'none'.
    const key = expiry.kind === 'none' ? 'none' : `${expiry.kind}:${expiry.kind === 'expiry' ? expiry.token : expiry.raw ?? ''}`;
    const due = pending
      || expiry.kind !== 'expiry'
      || isPastGraceWindow(expiry.exp, Date.now(), graceMsOf(this.config));
    if (!due) return;
    if (!pending && key === this.confirmedFor) return;

    const noToken = expiry.kind === 'none';
    const confirmed = await this.wipeStores(noToken);
    if (confirmed) {
      setWipePending(false);
      this.confirmedFor = key;
      this.events.notifyWiped();
    } else {
      this.markPending();
    }
  }

  private async wipeStores(noToken: boolean): Promise<boolean> {
    let confirmed = true;

    const cache = await databaseExists(OFFLINE_DB_NAME);
    if (cache === null && noToken) {
      confirmed = false; // cannot tell whether a cache exists, and must not create one to find out
    } else if (cache !== false) {
      if (!(await this.store.wipeAll())) confirmed = false;
    }

    if (isOfflineGraceEnabled(this.config)) {
      const pinDb = await databaseExists(PIN_DB_NAME);
      if (pinDb === null && noToken) {
        confirmed = false;
      } else if (pinDb !== false) {
        if (!(await this.pin.clearAll())) confirmed = false;
      }
    }
    return confirmed;
  }

  private markPending(): void {
    setWipePending(true);
    this.logger.warn('OfflineExpiryWipe: wipe not confirmed; the offline copy stays closed until a retry succeeds');
  }
}
