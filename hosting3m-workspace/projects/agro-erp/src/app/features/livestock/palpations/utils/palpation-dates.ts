/**
 * Calendar-date helpers for the palpation report. Dates are `YYYY-MM-DD` strings and all arithmetic is done in UTC on the
 * calendar fields, so neither the browser zone nor the UTC serialisation of a Date can move a date by a day (CLAUDE.md, timezone guardrail).
 */

const CALENDAR_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

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
 * Calendar day of a gateway date. The gateway sends a `date` as the local midnight of the server zone
 * (America/Mexico_City, UTC-6: `2026-11-12T06:00:00.000Z`), so the calendar day is the first ten characters.
 * Returns null when the value does not start with a valid calendar date.
 */
export function calendarDateOf(value: string | null | undefined): string | null {
  if (typeof value !== 'string') return null;
  const head = value.slice(0, 10);
  return isCalendarDate(head) ? head : null;
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
