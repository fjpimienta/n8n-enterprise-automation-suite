/**
 * Calendar-date helpers for the palpation report. Dates are `YYYY-MM-DD` strings and all arithmetic is done in UTC on the
 * calendar fields, so neither the browser zone nor the UTC serialisation of a Date can move a date by a day (CLAUDE.md, timezone guardrail).
 */

const CALENDAR_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * The gateway sends a `date` as the local midnight of the server zone (UTC-6). A value whose UTC time is later than 12:00 is not that
 * shape: it may belong to another calendar day, so it is rejected (fail-closed) instead of being cut to its first ten characters.
 */
export const LATEST_UTC_SECONDS_FOR_CALENDAR_DAY = 12 * 3600;

const ISO_DATE_OR_DATETIME = /^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/;

/** `YYYY-MM-DD` if the value is a valid calendar date, otherwise null. */
export function isCalendarDate(value: string): boolean {
  const m = CALENDAR_DATE.exec(value);
  if (!m) return false;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const probe = new Date(Date.UTC(y, mo - 1, d));
  return probe.getUTCFullYear() === y && probe.getUTCMonth() === mo - 1 && probe.getUTCDate() === d;
}

/**
 * Calendar day of a gateway date (America/Mexico_City, UTC-6: `2026-11-12T06:00:00.000Z`). Accepted shapes:
 *  - `YYYY-MM-DD`, or a timestamp whose UTC time is at most 12:00 (the day is the date written in the value);
 *  - anything else, including a timestamp after 12:00 UTC or one that crosses midnight in UTC, is null.
 */
export function calendarDateOf(value: string | null | undefined): string | null {
  if (typeof value !== 'string') return null;
  const m = ISO_DATE_OR_DATETIME.exec(value);
  if (!m) return null;
  const day = m[1] ?? '';
  if (!isCalendarDate(day)) return null;
  if (m[2] === undefined) return day; // date only
  const hour = Number(m[2]);
  const minute = Number(m[3]);
  const second = m[4] === undefined ? 0 : Number(m[4]);
  const fraction = m[5] === undefined ? 0 : Number(m[5]);
  if (hour > 23 || minute > 59 || second > 59) return null;
  const zone = m[6];
  let utcSeconds = hour * 3600 + minute * 60 + second + fraction;
  if (zone !== undefined && zone !== 'Z') {
    const sign = zone.startsWith('-') ? -1 : 1;
    const digits = zone.slice(1).replace(':', '');
    const offset = sign * (Number(digits.slice(0, 2)) * 3600 + Number(digits.slice(2, 4)) * 60);
    utcSeconds -= offset;
    if (utcSeconds < 0 || utcSeconds >= 24 * 3600) return null; // the UTC day would differ: not the expected shape
  }
  return utcSeconds > LATEST_UTC_SECONDS_FOR_CALENDAR_DAY ? null : day;
}

/** Today's calendar date in the browser's zone, from local fields (never from a UTC serialisation). */
export function todayLocal(now: Date = new Date()): string {
  const y = String(now.getFullYear()).padStart(4, '0');
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** `date` plus `days` calendar days, as `YYYY-MM-DD`. */
export function addCalendarDays(date: string, days: number): string {
  const m = CALENDAR_DATE.exec(date);
  if (!m) throw new Error('addCalendarDays: not a calendar date');
  const t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + days);
  const d = new Date(t);
  const y = String(d.getUTCFullYear()).padStart(4, '0');
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${dd}`;
}

/** Compares two calendar dates as strings (valid `YYYY-MM-DD` sorts lexicographically). */
export function compareCalendarDates(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
