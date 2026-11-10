/**
 * Domain-agnostic period helpers of the expense screens: presets, whole-period ranges, the previous period,
 * elapsed days, averages and trend bars. Pure YYYY-MM-DD arithmetic in UTC (no time zone drift).
 */
import type { TrendBar } from './expenses-ui.util';

export type PeriodGrain = 'DAY' | 'WEEK' | 'MONTH' | 'YEAR';
export type PeriodPreset = 'MONTH' | 'QUARTER' | 'YEAR' | 'CUSTOM';

export const PERIOD_PRESETS: ReadonlyArray<{ value: PeriodPreset; label: string }> = [
  { value: 'MONTH', label: 'Este mes' },
  { value: 'QUARTER', label: 'Trimestre' },
  { value: 'YEAR', label: 'Año' },
  { value: 'CUSTOM', label: 'Personalizado' },
];

export interface DateRange { from: string; to: string; }
export interface PresetRange extends DateRange { grain: PeriodGrain; }
/** One bucket of a trend: what buildTrendBars needs. */
export interface PeriodTotal { periodStart: string; periodEnd: string; totalAmount: number; }

const DAY_MS = 86400000;
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const utc = (iso: string) => new Date(`${iso}T00:00:00Z`);
const fmt = (d: Date) => d.toISOString().slice(0, 10);
const lastDayOfMonth = (y: number, m0: number) => new Date(Date.UTC(y, m0 + 1, 0));

function isIsoDate(text: string): boolean {
  const m = ISO_DATE.exec(text ?? '');
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.getUTCFullYear() === Number(m[1]) && d.getUTCMonth() === Number(m[2]) - 1 && d.getUTCDate() === Number(m[3]);
}

export function addDays(date: string, days: number): string {
  return fmt(new Date(utc(date).getTime() + days * DAY_MS));
}

/** Inclusive number of days between two ISO dates (0 when invalid or reversed). */
export function daysInRange(from: string, to: string): number {
  if (!isIsoDate(from) || !isIsoDate(to)) return 0;
  const n = Math.round((utc(to).getTime() - utc(from).getTime()) / DAY_MS) + 1;
  return n > 0 ? n : 0;
}

/** Month view groups by day; quarter and year group by month. */
export function rangeForPreset(preset: Exclude<PeriodPreset, 'CUSTOM'>, today: string): PresetRange {
  const d = utc(today);
  const y = d.getUTCFullYear();
  const m = d.getUTCMonth();
  if (preset === 'MONTH') return { from: fmt(new Date(Date.UTC(y, m, 1))), to: fmt(lastDayOfMonth(y, m)), grain: 'DAY' };
  if (preset === 'QUARTER') {
    const q = Math.floor(m / 3) * 3;
    return { from: fmt(new Date(Date.UTC(y, q, 1))), to: fmt(lastDayOfMonth(y, q + 2)), grain: 'MONTH' };
  }
  return { from: `${y}-01-01`, to: `${y}-12-31`, grain: 'MONTH' };
}

/** The equivalent period right before `range` (previous month / quarter / year; same length for a custom range). */
export function previousRange(preset: PeriodPreset, range: DateRange): DateRange {
  const a = utc(range.from);
  const y = a.getUTCFullYear();
  const m = a.getUTCMonth();
  if (preset === 'MONTH') return { from: fmt(new Date(Date.UTC(y, m - 1, 1))), to: fmt(lastDayOfMonth(y, m - 1)) };
  if (preset === 'QUARTER') return { from: fmt(new Date(Date.UTC(y, m - 3, 1))), to: fmt(lastDayOfMonth(y, m - 1)) };
  if (preset === 'YEAR') return { from: `${y - 1}-01-01`, to: `${y - 1}-12-31` };
  const n = daysInRange(range.from, range.to);
  return { from: addDays(range.from, -n), to: addDays(range.from, -1) };
}

/** Days that can already hold expenses: the range cut at `today` (an expense is never in the future). */
export function elapsedDays(range: DateRange, today: string): number {
  return daysInRange(range.from, range.to < today ? range.to : today);
}

/** Average per elapsed day; null when there is nothing to divide by. */
export function averagePerDay(total: number, days: number): number | null {
  return days > 0 && Number.isFinite(total) ? total / days : null;
}

const MONTHS_SHORT = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export function shortPeriodLabel(grain: PeriodGrain, start: string): string {
  if (!isIsoDate(start)) return start;
  switch (grain) {
    case 'DAY': return String(Number(start.slice(8, 10)));
    case 'WEEK': return start.slice(8, 10) + '/' + start.slice(5, 7);
    case 'MONTH': return MONTHS_SHORT[Number(start.slice(5, 7)) - 1];
    case 'YEAR': return start.slice(0, 4);
  }
}

/** Bars scaled to the largest period; a period is in progress when `today` falls inside it. */
export function buildTrendBars(periods: ReadonlyArray<PeriodTotal>, grain: PeriodGrain, today: string, format: (v: number) => string): TrendBar[] {
  const max = Math.max(0, ...periods.map(p => p.totalAmount));
  return periods.map(p => ({
    key: p.periodStart,
    label: shortPeriodLabel(grain, p.periodStart),
    value: p.totalAmount,
    valueText: format(p.totalAmount),
    heightPct: max > 0 ? Math.max(p.totalAmount > 0 ? 2 : 0, (p.totalAmount / max) * 100) : 0,
    inProgress: p.periodStart <= today && today <= p.periodEnd,
  }));
}
