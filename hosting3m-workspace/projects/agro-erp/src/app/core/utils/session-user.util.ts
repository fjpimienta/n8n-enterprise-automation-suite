import { HttpRequest } from '@angular/common/http';
import { jwtDecode } from 'jwt-decode';

const TOKEN_KEY = 'authToken';

/**
 * Identity key of the session user (`user`, else `email`), read from the stored JWT claims. Independent
 * of the tenant list and of expiry, so it works in grace and before a fresh login updates the tenants.
 * Returns `null` when there is no token or it cannot be decoded. Never logs the token or its claims.
 */
export function userFromStoredToken(storage: Storage = localStorage): string | null {
  try {
    const token = storage.getItem(TOKEN_KEY);
    if (!token) return null;
    const claims = jwtDecode<{ user?: unknown; email?: unknown }>(token);
    const user = [claims?.user, claims?.email]
      .find((v): v is string => typeof v === 'string' && v.trim().length > 0);
    return user ? user.trim() : null;
  } catch {
    return null;
  }
}

/** True for the login POST: same origin and path as `apiUrl_token`, method POST. */
export function isLoginRequest(req: HttpRequest<unknown>, config: { apiUrl_token?: string }): boolean {
  if (req.method !== 'POST' || !config.apiUrl_token) return false;
  try {
    const target = new URL(req.url);
    const login = new URL(config.apiUrl_token);
    return target.origin === login.origin
      && target.pathname.replace(/\/+$/, '') === login.pathname.replace(/\/+$/, '');
  } catch {
    return false;
  }
}

