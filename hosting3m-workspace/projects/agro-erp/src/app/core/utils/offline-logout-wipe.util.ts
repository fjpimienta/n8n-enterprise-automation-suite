import { DestroyRef, inject } from '@angular/core';
import { AuthService } from 'core-auth';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { OfflineWipeEventsService } from '@core/services/offline-wipe-events.service';
import { isWipePending } from '@core/utils/offline-wipe-pending.util';

/**
 * Wires the read cache wipe to the session `'logout'` event. Call once from an app initializer.
 * Fire-and-forget and never throwing: `wipeAll()` already resolves to a boolean, and any failure
 * is swallowed here. Only the offline read cache is wiped (there is no outbox yet).
 */
export function wireOfflineLogoutWipe(): void {
  const auth = inject(AuthService);
  const store = inject(OfflineStoreService);
  const events = inject(OfflineWipeEventsService);
  const subscription = auth.sessionEvents$.subscribe(event => {
    if (event.type === 'login') {
      // A valid session again: a copy wiped for an earlier ended session no longer applies.
      events.setExpiredWipeHeld(false);
      return;
    }
    if (event.type !== 'logout') return;
    // The expiry check already wiped the copy for this ended session and nothing can be written since, so a
    // second wipe would be redundant (T6). A pending wipe is never skipped.
    if (events.isExpiredWipeHeld() && !isWipePending()) return;
    try {
      void store.wipeAll().catch(() => undefined);
    } catch {
      // swallowed on purpose
    }
  });
  inject(DestroyRef).onDestroy(() => subscription.unsubscribe());
}
