export const AUTHORIZATION_TIMEZONE = 'America/Mexico_City';

/**
 * Parses a gateway timestamp as a real UTC instant. `pending_authorizations.fecha_solicitud`
 * and `fecha_resolucion` are `timestamp without time zone` filled with `now()` on a server
 * running `Etc/UTC`, so a value without an offset is UTC, never browser-local time. Also
 * normalizes the Postgres text form (space separator, microseconds) for strict parsers.
 */
export function parseGatewayTimestamp(value: string): Date {
  let iso = value.trim().replace(' ', 'T').replace(/(\.\d{3})\d+/, '$1');
  if (!iso.includes('T')) iso += 'T00:00:00';
  // Offset check only on the time part, so a date like "2026-10-09" is not read as "-09".
  if (!/T.*(?:[Zz]|[+-]\d{2}(?::?\d{2})?)$/.test(iso)) iso += 'Z';
  return new Date(iso);
}

/**
 * Expiry instant of a request, mirroring the backend rule: it expires once CURRENT_DATE (UTC)
 * passes the UTC date of `fecha_solicitud`, i.e. at the start of that UTC day + 24h. In
 * America/Mexico_City (UTC-6) that is 18:00 of the same day when requested before 18:00,
 * otherwise 18:00 of the next day.
 */
export function getAuthorizationDeadline(fechaSolicitud: string): Date {
  const createdAt = parseGatewayTimestamp(fechaSolicitud);
  return new Date(Date.UTC(createdAt.getUTCFullYear(), createdAt.getUTCMonth(), createdAt.getUTCDate() + 1));
}

const DISPLAY_FORMAT = new Intl.DateTimeFormat('es-MX', {
  timeZone: AUTHORIZATION_TIMEZONE,
  dateStyle: 'short',
  timeStyle: 'short',
  hourCycle: 'h23'
});

/** Gateway timestamp rendered in America/Mexico_City regardless of the browser's zone. */
export function formatAuthorizationTimestamp(value: string | null | undefined): string {
  if (!value) return '—';
  const date = parseGatewayTimestamp(value);
  return Number.isNaN(date.getTime()) ? '—' : DISPLAY_FORMAT.format(date);
}

export type CountdownSeverity = 'ok' | 'warning' | 'danger';

/** Verde (>4h), amarillo (≤4h), rojo (<1h) — umbrales tal cual definidos en el alcance. */
export function getCountdownSeverity(msRemaining: number): CountdownSeverity {
  if (msRemaining < 60 * 60 * 1000) return 'danger';
  if (msRemaining <= 4 * 60 * 60 * 1000) return 'warning';
  return 'ok';
}

export function formatCountdown(msRemaining: number): string {
  if (msRemaining <= 0) return 'Vencida';
  const totalMinutes = Math.floor(msRemaining / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h ${minutes}m`;
}
