import { inject } from '@angular/core';
import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { throwError } from 'rxjs';
import { AUTH_ENV_CONFIG, AuthService, isAllowedOrigin, isExemptRoute } from 'core-auth';

/**
 * Global offline-grace guard (#1087, phase 1b-iii-a). Register it BEFORE `authInterceptor`.
 *
 * `authInterceptor` calls `AuthService.getStoredToken()` on every request, and that method calls
 * `logout()` when the token is expired. During the offline grace window (`getSessionState() ===
 * 'grace'`) ANY request would therefore destroy the session. This guard short-circuits API requests
 * in `'grace'` with a status-0 `HttpErrorResponse` (the same shape as a network failure) without
 * calling `next`, so the auth interceptor never runs.
 *
 * Only API-origin, non-exempt requests are blocked. Valid and expired sessions, non-API origins,
 * exempt routes (login) and any failure of the state check pass through untouched.
 */
export const offlineGraceGuard: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const config = inject(AUTH_ENV_CONFIG);

  let inGrace = false;
  try {
    inGrace = auth.getSessionState() === 'grace';
  } catch {
    return next(req);
  }
  if (!inGrace) return next(req);
  if (!isAllowedOrigin(req.url, config) || isExemptRoute(req, config)) return next(req);

  return throwError(() => new HttpErrorResponse({ status: 0, statusText: 'OfflineGrace', url: req.url }));
};
