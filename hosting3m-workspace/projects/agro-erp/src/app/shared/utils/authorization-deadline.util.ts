export const AUTHORIZATION_TIMEZONE = 'America/Mexico_City';

/**
 * Time zone of the n8n process that serves the Meta-CRUD gateway (`TZ` of the n8n container,
 * verified in LOCAL on 2026-10-10). Its Postgres driver reads a `timestamp without time zone`
 * as local time of that process, so the naive UTC value comes back shifted (see below).
 */
export const GATEWAY_PROCESS_TIMEZONE = 'America/Mexico_City';

/**
 * Parses a gateway value of a naive-UTC column (`pending_authorizations.fecha_solicitud` /
 * `fecha_resolucion`: `timestamp without time zone` filled with `now()` on a server running
 * `Etc/UTC`) into the real instant. The gateway delivers it in two shapes:
 *  - top-level columns as an ISO string ending in `Z`, produced by the n8n process reading the
 *    naive UTC wall clock as GATEWAY_PROCESS_TIMEZONE time — e.g. naive `2026-10-11 00:40:50`
 *    arrives as `2026-10-11T06:40:50.364Z`. The wall clock of that instant in
 *    GATEWAY_PROCESS_TIMEZONE is the original naive UTC value, so it is re-read as UTC;
 *  - JSON-embedded values (`row_to_json` joins) as naive text without offset: read as UTC.
 * A numeric offset (e.g. `-06:00`) is taken as a real instant. Also normalizes the Postgres text
 * form (space separator, microseconds).
 *
 * Workaround: correct only while the n8n process runs in GATEWAY_PROCESS_TIMEZONE in every
 * environment. The root fix is in the gateway (return naive timestamps unchanged).
 */
export function parseGatewayTimestamp(value: string): Date {
  let iso = value.trim().replace(' ', 'T').replace(/(\.\d{3})\d+/, '$1');
  if (!iso.includes('T')) iso += 'T00:00:00';
  // Offset check only on the time part, so a date like "2026-10-09" is not read as "-09".
  if (/T.*[Zz]$/.test(iso)) return undoGatewayShift(new Date(iso));
  if (!/T.*[+-]\d{2}(?::?\d{2})?$/.test(iso)) iso += 'Z';
  return new Date(iso);
}

/** Wall clock of `shifted` in GATEWAY_PROCESS_TIMEZONE, re-read as UTC (milliseconds kept). */
function undoGatewayShift(shifted: Date): Date {
  const ms = shifted.getTime();
  if (Number.isNaN(ms)) return shifted;
  const p = wallClock(GATEWAY_PARTS, ms);
  return new Date(Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second, ((ms % 1000) + 1000) % 1000));
}

interface WallClock { year: number; month: number; day: number; hour: number; minute: number; second: number }

const wallClockFormat = (timeZone: string) => new Intl.DateTimeFormat('en-US', {
  timeZone,
  hourCycle: 'h23',
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit'
});

const LOCAL_PARTS = wallClockFormat(AUTHORIZATION_TIMEZONE);
const GATEWAY_PARTS = wallClockFormat(GATEWAY_PROCESS_TIMEZONE);

function wallClock(format: Intl.DateTimeFormat, instantMs: number): WallClock {
  const parts: Record<string, number> = {};
  for (const p of format.formatToParts(new Date(instantMs))) {
    if (p.type !== 'literal') parts[p.type] = Number(p.value);
  }
  return { year: parts['year'], month: parts['month'], day: parts['day'], hour: parts['hour'], minute: parts['minute'], second: parts['second'] };
}

/** Wall-clock fields of `instantMs` in America/Mexico_City. */
function localParts(instantMs: number): WallClock {
  return wallClock(LOCAL_PARTS, instantMs);
}

/** Offset (ms) of America/Mexico_City at `instantMs`, measured, never hard-coded as -06:00. */
function zoneOffsetMs(instantMs: number): number {
  const p = localParts(instantMs);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(instantMs / 1000) * 1000;
}

/** UTC instant at which the given America/Mexico_City wall-clock midnight occurs. */
function localMidnightToUtc(year: number, month: number, day: number): number {
  const guess = Date.UTC(year, month - 1, day);
  const first = guess - zoneOffsetMs(guess);
  // Re-measure at the candidate instant in case the offset differs across the guess (DST rules).
  return guess - zoneOffsetMs(first);
}

/**
 * Calendar date (YYYY-MM-DD) of `fecha_solicitud` in America/Mexico_City. Mirrors
 * `fn_authorization_local_date` (migration 072): the value is naive UTC.
 */
export function authorizationLocalDate(fechaSolicitud: string): string {
  const p = localParts(parseGatewayTimestamp(fechaSolicitud).getTime());
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/**
 * Last valid instant of a request: 23:59:59.999 America/Mexico_City of the calendar day it was
 * requested (migration 072, `fn_authorization_expired`). Computed as the next CDMX midnight − 1 ms.
 */
export function getAuthorizationDeadline(fechaSolicitud: string): Date {
  const [year, month, day] = authorizationLocalDate(fechaSolicitud).split('-').map(Number);
  // Date.UTC normalizes day + 1 across month/year ends.
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  return new Date(localMidnightToUtc(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate()) - 1);
}

/**
 * True once the request can no longer be resolved or cancelled. Same rule as
 * `fn_authorization_expired` (migration 072): its CDMX request date is before today's CDMX date,
 * i.e. from 00:00 America/Mexico_City of the following day on.
 */
export function isAuthorizationExpired(fechaSolicitud: string, nowMs: number): boolean {
  return nowMs > getAuthorizationDeadline(fechaSolicitud).getTime();
}

const DISPLAY_FORMAT = new Intl.DateTimeFormat('es-MX', {
  timeZone: AUTHORIZATION_TIMEZONE,
  dateStyle: 'short',
  timeStyle: 'short',
  hourCycle: 'h23'
});

/** Gateway timestamp rendered in America/Mexico_City regardless of the browser's zone. */
/** A real instant (e.g. a computed deadline) rendered in America/Mexico_City. */
export function formatInstantInCdmx(instant: Date): string {
  return Number.isNaN(instant.getTime()) ? '—' : DISPLAY_FORMAT.format(instant);
}

export function formatAuthorizationTimestamp(value: string | null | undefined): string {
  if (!value) return '—';
  const date = parseGatewayTimestamp(value);
  return Number.isNaN(date.getTime()) ? '—' : DISPLAY_FORMAT.format(date);
}

/**
 * Calendar date (Postgres `date`, e.g. `sale_date`) as DD/MM/AAAA. A date has no instant, so it
 * is never shifted to America/Mexico_City — only the YYYY-MM-DD part is read.
 */
export function formatCalendarDate(value: string | null | undefined): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec((value ?? '').trim());
  return match ? `${match[3]}/${match[2]}/${match[1]}` : '—';
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
