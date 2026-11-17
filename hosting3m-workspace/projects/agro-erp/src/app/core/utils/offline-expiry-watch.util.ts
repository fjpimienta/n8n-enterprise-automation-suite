import { DestroyRef, inject } from '@angular/core';
import { OfflineExpiryWipeService } from '@core/services/offline-expiry-wipe.service';
import { STORED_TOKEN_KEY } from '@core/utils/stored-token-expiry.util';

/** Period of the expiry check (no HTTP, one localStorage read and one JWT decode per tick). */
export const OFFLINE_EXPIRY_CHECK_MS = 60_000;

/**
 * Runs the expiry check at app start, on tab visibility changes, every 60 s, and when another tab changes the
 * stored token (#1087, phase 1b-iii-c). Synchronous and non-blocking: the check is started and not awaited, so
 * bootstrap never waits for IndexedDB. Call once from an app initializer.
 */
export function startOfflineExpiryWatch(): void {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  const expiry = inject(OfflineExpiryWipeService);
  const check = (): void => { void expiry.check(); };
  const onStorage = (event: StorageEvent): void => {
    // `key === null` means another tab cleared all storage.
    if (event.key === null || event.key === STORED_TOKEN_KEY) check();
  };

  document.addEventListener('visibilitychange', check);
  window.addEventListener('storage', onStorage);
  const timer = setInterval(check, OFFLINE_EXPIRY_CHECK_MS);

  inject(DestroyRef).onDestroy(() => {
    document.removeEventListener('visibilitychange', check);
    window.removeEventListener('storage', onStorage);
    clearInterval(timer);
  });
  check();
}
