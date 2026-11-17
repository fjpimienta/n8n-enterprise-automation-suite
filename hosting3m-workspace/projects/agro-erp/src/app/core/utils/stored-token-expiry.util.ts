import { jwtDecode } from 'jwt-decode';
import { isOfflineGraceEnabled } from '@core/utils/offline-grace-config.util';

/** localStorage key used by core-auth for the session token (read only, never written here). */
export const STORED_TOKEN_KEY = 'authToken';

export type StoredTokenExpiry =
  | { kind: 'none' }
  | { kind: 'unreadable'; raw: string | null }
  | { kind: 'expiry'; token: string; exp: number };

/**
 * Reads the stored token's `exp` without side effects: no logout, no HTTP, no tenant lookup. Anything that
 * cannot be read (storage error, malformed JWT, missing or non-numeric exp) is `unreadable`, which the caller
 * treats as expired (fail-closed). The token itself is returned only for in-memory identity comparison.
 */
export function readStoredTokenExpiry(): StoredTokenExpiry {
  let token: string | null;
  try {
    token = localStorage.getItem(STORED_TOKEN_KEY);
  } catch {
    return { kind: 'unreadable', raw: null };
  }
  if (token === null || token === '') return { kind: 'none' };
  try {
    const exp: unknown = jwtDecode<{ exp?: unknown }>(token)?.exp;
    if (typeof exp !== 'number' || !Number.isFinite(exp)) return { kind: 'unreadable', raw: token };
    return { kind: 'expiry', token, exp };
  } catch {
    return { kind: 'unreadable', raw: token };
  }
}

/** Grace window in ms: the configured `offlineGraceMs` when grace is enabled, otherwise 0. */
export function graceMsOf(config: { offlineGraceMs?: unknown } | null | undefined): number {
  if (!isOfflineGraceEnabled(config)) return 0;
  return (config as { offlineGraceMs: number }).offlineGraceMs;
}

/**
 * True once the grace window after `exp` has ended. Same second-granularity boundary as
 * `AuthService.getSessionState()`: a token still valid or inside grace is never past it.
 */
export function isPastGraceWindow(exp: number, nowMs: number, graceMs: number): boolean {
  return Math.floor(nowMs / 1000) * 1000 > exp * 1000 + graceMs;
}
