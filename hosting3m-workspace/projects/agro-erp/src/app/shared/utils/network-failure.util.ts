import { HttpErrorResponse } from '@angular/common/http';

/**
 * True only for a genuine network failure: an `HttpErrorResponse` with status 0, or the browser
 * reporting `navigator.onLine === false`.
 *
 * `navigator.onLine === false` counts as a network failure for ANY error, whatever its type or
 * status: while the browser is offline no response can have arrived, so whatever was thrown cannot
 * be a genuine server answer. Everything else (HTTP >= 400, gateway `error:true`
 * surfaced as an `Error`, parsing errors) is NOT a network failure and must never trigger a
 * cache fallback.
 */
export function isNetworkFailure(error: unknown): boolean {
  if (error instanceof HttpErrorResponse && error.status === 0) return true;
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}
