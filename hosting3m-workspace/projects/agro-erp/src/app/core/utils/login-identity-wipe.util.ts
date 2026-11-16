import { DestroyRef, inject } from '@angular/core';
import { AuthService } from 'core-auth';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { PinLockService } from '@core/services/pin-lock.service';
import { LoginHandoffService } from '@core/services/login-handoff.service';
import { userFromStoredToken } from '@core/utils/session-user.util';

/**
 * On a successful login, keeps the offline data only when the new user is the SAME user whose data is
 * on the device. Otherwise (a different user, or the previous user could not be determined) the offline
 * cache is wiped and the PIN records of every other user are deleted. Fail-closed.
 *
 * A failed login emits no `'login'` event, so the cache and the PIN stay intact.
 * Fire-and-forget and never throwing. Call once from an app initializer.
 */
export function wireLoginIdentityWipe(): void {
  const auth = inject(AuthService);
  const handoff = inject(LoginHandoffService);
  const store = inject(OfflineStoreService);
  const pinLock = inject(PinLockService);

  const subscription = auth.sessionEvents$.subscribe(event => {
    if (event.type !== 'login') return;
    // Read the identity from the stored token: the event's `scope` depends on the tenant list, which the
    // login screen stores only after this event.
    const previousUser = handoff.consume()?.previousUser ?? null;
    const currentUser = userFromStoredToken();
    if (previousUser !== null && previousUser === currentUser) return;
    try {
      void store.wipeAll().catch(() => undefined);
      void pinLock.deleteOthers(currentUser).catch(() => undefined);
    } catch {
      // swallowed on purpose
    }
  });
  inject(DestroyRef).onDestroy(() => subscription.unsubscribe());
}
