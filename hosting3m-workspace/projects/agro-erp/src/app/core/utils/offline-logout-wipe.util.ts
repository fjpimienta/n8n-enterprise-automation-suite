import { DestroyRef, inject } from '@angular/core';
import { AuthService } from 'core-auth';
import { OfflineStoreService } from '@core/services/offline-store.service';

/**
 * Wires the read cache wipe to the session `'logout'` event. Call once from an app initializer.
 * Fire-and-forget and never throwing: `wipeAll()` already resolves to a boolean, and any failure
 * is swallowed here. Only the offline read cache is wiped (there is no outbox yet).
 */
export function wireOfflineLogoutWipe(): void {
  const auth = inject(AuthService);
  const store = inject(OfflineStoreService);
  const subscription = auth.sessionEvents$.subscribe(event => {
    if (event.type !== 'logout') return;
    try {
      void store.wipeAll().catch(() => undefined);
    } catch {
      // swallowed on purpose
    }
  });
  inject(DestroyRef).onDestroy(() => subscription.unsubscribe());
}
