import { inject } from '@angular/core';
import { HttpErrorResponse, HttpHandlerFn, HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { Observable, catchError, throwError } from 'rxjs';
import { AUTH_ENV_CONFIG, AuthService, authInterceptor, isAllowedOrigin, isExemptRoute } from 'core-auth';
import { LoginHandoffService } from '@core/services/login-handoff.service';
import { isLoginRequest, userFromStoredToken } from '@core/utils/session-user.util';

/**
 * Grace-aware wrapper around core-auth's `authInterceptor` (#1087, phase 1b-iii-b). Register it AFTER
 * `offlineGraceGuard` and BEFORE `tenantInterceptor`.
 *
 * Why a wrapper and not a core-auth change: `authInterceptor` calls `getStoredToken()` on every request
 * (before the exempt check) and `logout()` on an expired token. In grace that would destroy the offline
 * session, its cache and its PIN record. core-auth's documented contract keeps those semantics, so the
 * app-level wrapper owns the grace cases and delegates everything else.
 *
 * - `'valid'` / `'expired'` at request time: delegate to `authInterceptor`, with a response converter
 *   (see below). Behavior is unchanged.
 * - `'grace'` at request time:
 *   - no request carries the Authorization header (the expired token never leaves the device);
 *   - non-API origins and exempt routes (login, public `companys getall`) go through without
 *     `authInterceptor`, so they never call `logout()`;
 *   - any other API request fails with status 0 (defense in depth; `offlineGraceGuard` blocks it first).
 * - In-flight race: a request sent while `'valid'` whose 401 arrives during grace is converted to status 0
 *   BEFORE `authInterceptor`'s `catchError` runs, so it cannot log out.
 */
export const graceAuthInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const config = inject(AUTH_ENV_CONFIG);

  // The login replaces the stored token: record who is signed in BEFORE the request leaves the device.
  if (isLoginRequest(req, config)) {
    inject(LoginHandoffService).begin(userFromStoredToken());
  }

  if (!isInGrace(auth)) {
    return authInterceptor(req, graceAwareNext(auth, next));
  }

  const clean = withoutAuthorization(req);
  if (!isAllowedOrigin(req.url, config) || isExemptRoute(req, config)) {
    return next(clean);
  }
  return offlineGrace(req);
};

/** Fail-closed read: a throwing check is treated as "not grace", the same as `offlineGraceGuard`. */
function isInGrace(auth: AuthService): boolean {
  try {
    return auth.getSessionState() === 'grace';
  } catch {
    return false;
  }
}

function graceAwareNext(auth: AuthService, next: HttpHandlerFn): HttpHandlerFn {
  return (req: HttpRequest<unknown>) => next(req).pipe(
    catchError((err: unknown) => {
      if (err instanceof HttpErrorResponse && err.status === 401 && isInGrace(auth)) {
        return offlineGrace(req);
      }
      return throwError(() => err);
    })
  );
}

function withoutAuthorization(req: HttpRequest<unknown>): HttpRequest<unknown> {
  return req.headers.has('Authorization') ? req.clone({ headers: req.headers.delete('Authorization') }) : req;
}

function offlineGrace(req: HttpRequest<unknown>): Observable<never> {
  return throwError(() => new HttpErrorResponse({ status: 0, statusText: 'OfflineGrace', url: req.url }));
}
