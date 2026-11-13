import { isDevMode } from '@angular/core';
import { AuthEnvironmentConfig } from './auth.config';

/** Returns the origin (scheme + host + port) of an absolute URL, or null if it cannot be parsed. */
function originOf(url: string | undefined): string | null {
  if (!url) return null;
  try {
    const origin = new URL(url).origin;
    return origin === 'null' ? null : origin;
  } catch {
    return null;
  }
}

/**
 * True only when the request URL's origin exactly equals the origin of one of the
 * configured API base URLs. Relative or unparseable URLs are never allowed.
 * In dev mode, a warning is logged for requests that are not allowed.
 */
export function isAllowedOrigin(requestUrl: string, config: AuthEnvironmentConfig): boolean {
  const requestOrigin = originOf(requestUrl);
  const allowed = [config.apiUrl_crud, config.apiUrl_token, config.apiUrl_ai, config.apiUrl_upload]
    .map(originOf)
    .filter((o): o is string => o !== null);
  const isAllowed = requestOrigin !== null && allowed.includes(requestOrigin);
  if (!isAllowed && isDevMode()) {
    console.warn(`[core-auth] Origin not in AUTH_ENV_CONFIG allowlist; JWT and X-Tenant-ID not attached to: ${requestOrigin ?? '(unparseable URL)'}`);
  }
  return isAllowed;
}
