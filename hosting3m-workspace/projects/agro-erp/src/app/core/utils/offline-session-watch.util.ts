import { DestroyRef, inject } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs';
import { AUTH_ENV_CONFIG, AuthService, TenantService } from 'core-auth';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { isOfflineGraceEnabled } from '@core/utils/offline-grace-config.util';

/** Low-frequency re-check so an open session re-locks when it enters grace. */
export const OFFLINE_SESSION_CHECK_MS = 60_000;

/**
 * Keeps `OfflineSessionService` current without any HTTP call: on tab visibility, on a timer, on every
 * navigation, on login/logout, on tenant switches and on online/offline events. Call once from an app
 * initializer.
 */
export function startOfflineSessionWatch(): void {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  // Production (no offlineGraceMs): no listener, no timer, no subscription. Nothing would ever change.
  if (!isOfflineGraceEnabled(inject(AUTH_ENV_CONFIG, { optional: true }))) return;
  const session = inject(OfflineSessionService);
  const auth = inject(AuthService);
  const tenants = inject(TenantService);
  const router = inject(Router);

  const refresh = () => session.refresh();
  const onVisibility = () => refresh();
  const onOnline = () => session.setOnline(true);
  const onOffline = () => session.setOnline(false);

  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('online', onOnline);
  window.addEventListener('offline', onOffline);
  const timer = setInterval(refresh, OFFLINE_SESSION_CHECK_MS);
  const subscriptions = [
    auth.sessionEvents$.subscribe(refresh),
    tenants.activeTenantChanges$.subscribe(refresh),
    router.events.pipe(filter(e => e instanceof NavigationEnd)).subscribe(refresh),
  ];

  inject(DestroyRef).onDestroy(() => {
    document.removeEventListener('visibilitychange', onVisibility);
    window.removeEventListener('online', onOnline);
    window.removeEventListener('offline', onOffline);
    clearInterval(timer);
    subscriptions.forEach(s => s.unsubscribe());
  });
}
