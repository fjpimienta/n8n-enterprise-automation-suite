import { DestroyRef, inject } from '@angular/core';
import { AUTH_ENV_CONFIG, AuthService } from 'core-auth';
import { PinLockService } from '@core/services/pin-lock.service';
import { isOfflineGraceEnabled } from '@core/utils/offline-grace-config.util';

/**
 * Deletes every PIN record on the session `'logout'` event. Fire-and-forget and never throwing. The
 * event carries no scope, so this clears all records on the device (fail-safe: other users simply
 * need an online login before their next grace window).
 */
export function wirePinLogoutWipe(): void {
  // Without offlineGraceMs no PIN record can exist: do not open (or create) the PIN database on logout.
  if (!isOfflineGraceEnabled(inject(AUTH_ENV_CONFIG, { optional: true }))) return;
  const auth = inject(AuthService);
  const pinLock = inject(PinLockService);
  const subscription = auth.sessionEvents$.subscribe(event => {
    if (event.type !== 'logout') return;
    try {
      void pinLock.clearAll().catch(() => undefined);
    } catch {
      // swallowed on purpose
    }
  });
  inject(DestroyRef).onDestroy(() => subscription.unsubscribe());
}
