import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TenantService, authGuard } from 'core-auth';
import { OfflineSessionService, UNLOCK_ROUTE } from '@core/services/offline-session.service';
import { dashboardRouteFor } from '@shared/utils/business-domain.util';

/**
 * Replaces core-auth's `authGuard` on the private layout. Only `'grace'` changes:
 * - grace, unlocked for this scope: allowed (offline reads only; the API stays blocked by offlineGraceGuard).
 * - grace, not unlocked: redirect to the PIN screen.
 * - `'valid'` / `'expired'`: exactly core-auth's `authGuard`, unchanged.
 */
export const offlineSessionGuard: CanActivateFn = (route, state) => {
  const session = inject(OfflineSessionService);
  const router = inject(Router);
  if (session.readState() !== 'grace') return authGuard(route, state);
  return session.isUnlockedForCurrentScope() ? true : router.parseUrl(UNLOCK_ROUTE);
};

/** The unlock screen is only for grace sessions that are still locked; anything else goes home. */
export const unlockRouteGuard: CanActivateFn = () => {
  const session = inject(OfflineSessionService);
  const router = inject(Router);
  return session.readState() === 'grace' && !session.isUnlockedForCurrentScope() ? true : router.parseUrl('/');
};

/** PIN setup requires a valid (online-login) session. */
export const pinSetupRouteGuard: CanActivateFn = () => {
  const session = inject(OfflineSessionService);
  const router = inject(Router);
  return session.readState() === 'valid' ? true : router.parseUrl('/');
};

/**
 * Admin screens need the API, which is blocked in grace, and have no offline copy. Denied in grace
 * (fail-closed) and sent to the active company's dashboard.
 */
export const notInGraceGuard: CanActivateFn = () => {
  const session = inject(OfflineSessionService);
  if (session.readState() !== 'grace') return true;
  return inject(Router).parseUrl(dashboardRouteFor(inject(TenantService).activeTenant()));
};
