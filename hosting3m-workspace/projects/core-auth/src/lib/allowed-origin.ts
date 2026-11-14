import { isDevMode } from '@angular/core';
import { HttpRequest } from '@angular/common/http';
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

/**
 * True when the request is one of the public routes that intentionally carry no JWT and no tenant:
 *
 * - `POST` to the exact `apiUrl_token` endpoint (origin and path), i.e. the login call.
 * - `POST` to `<apiUrl_crud>/companys` whose body is exactly the `companys getall` read:
 *   `operation === 'getall'`, with `entity` and/or `table_name` present and equal to `'companys'`.
 *
 * Matching is by method, origin, exact path and body fields, never by origin alone or by path
 * substring. Any other request, including other `companys` operations, is not exempt and must
 * carry a JWT and an active tenant. The gateway remains responsible for authorization.
 */
export function isExemptRoute(req: HttpRequest<unknown>, config: AuthEnvironmentConfig): boolean {
  if (req.method !== 'POST') return false;

  const url = parseUrl(req.url);
  if (!url) return false;

  const tokenUrl = parseUrl(config.apiUrl_token);
  if (tokenUrl && url.origin === tokenUrl.origin && trimmedPath(url) === trimmedPath(tokenUrl)) {
    return true;
  }

  const crudUrl = parseUrl(config.apiUrl_crud);
  if (crudUrl && url.origin === crudUrl.origin && trimmedPath(url) === `${trimmedPath(crudUrl)}/companys`) {
    return isCompanysGetallBody(req.body);
  }

  return false;
}

function parseUrl(value: string | undefined): URL | null {
  if (!value) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

/** Pathname without trailing slashes, so `/x/` and `/x` compare equal. */
function trimmedPath(url: URL): string {
  return url.pathname.replace(/\/+$/, '');
}

/**
 * Identifies the public `companys getall` read sent by the dashboard and agro-erp services:
 * `{ entity: 'companys', table_name: 'companys', operation: 'getall', ... }`.
 * Every identifying field that is present must be `'companys'`, and at least one must be present.
 */
function isCompanysGetallBody(body: unknown): boolean {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return false;
  const { entity, table_name, operation } = body as Record<string, unknown>;
  if (operation !== 'getall') return false;
  const identifiers = [entity, table_name].filter((value) => value !== undefined);
  return identifiers.length > 0 && identifiers.every((value) => value === 'companys');
}
