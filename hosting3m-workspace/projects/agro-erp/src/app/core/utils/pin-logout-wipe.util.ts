import { DestroyRef, inject } from '@angular/core';
import { AuthService } from 'core-auth';
import { PinLockService } from '@core/services/pin-lock.service';

/**
 * Deletes every PIN record on the session `'logout'` event. Fire-and-forget and never throwing. The
 * event carries no scope, so this clears all records on the device (fail-safe: other users simply
 * need an online login before their next grace window).
 */
export function wirePinLogoutWipe(): void {
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
