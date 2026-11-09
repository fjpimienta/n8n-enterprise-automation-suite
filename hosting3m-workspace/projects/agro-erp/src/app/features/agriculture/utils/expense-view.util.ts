/**
 * Pure helpers of the redesigned expense screens: period presets, previous-period range, trivial derivations
 * (average per day, share, delta), list filtering and capture readiness. Totals are never computed here:
 * they come from the balance endpoint; only ratios of values the database already returned are derived.
 */
import type { AgriExpense, BalancePeriod, ExpenseGrain, ExpenseInput } from '@core/models/agri-expense.model';
import { normalizeForSearch } from '@shared/utils/text-normalize.util';
import type { TrendBar } from '@shared/expenses-ui/expenses-ui.util';
import { MAX_AMOUNT, isValidIsoDate, parseAmountText } from './expense.util';

export { deltaPercent, formatDelta, formatPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
export type { TrendBar } from '@shared/expenses-ui/expenses-ui.util';

export type PeriodPreset = 'MONTH' | 'QUARTER' | 'YEAR' | 'CUSTOM';

export const PERIOD_PRESETS: ReadonlyArray<{ value: PeriodPreset; label: string }> = [
  { value: 'MONTH', label: 'Este mes' },
  { value: 'QUARTER', label: 'Trimestre' },
  { value: 'YEAR', label: 'Año' },
  { value: 'CUSTOM', label: 'Personalizado' },
];

export interface DateRange { from: string; to: string; }
export interface PresetRange extends DateRange { grain: ExpenseGrain; }

const DAY_MS = 86400000;
const utc = (iso: string) => new Date(`${iso}T00:00:00Z`);
const fmt = (d: Date) => d.toISOString().slice(0, 10);
const lastDayOfMonth = (y: number, m0: number) => new Date(Date.UTC(y, m0 + 1, 0));

export function addDays(date: string, days: number): string {
  return fmt(new Date(utc(date).getTime() + days * DAY_MS));
}

/** Inclusive number of days between two ISO dates (0 when invalid or reversed). */
export function daysInRange(from: string, to: string): number {
  if (!isValidIsoDate(from) || !isValidIsoDate(to)) return 0;
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

/** Grain for a free range: day up to ~2 months, month up to ~5 years, year beyond. */
export function grainForSpan(from: string, to: string): ExpenseGrain {
  const days = daysInRange(from, to);
  return days <= 62 ? 'DAY' : days <= 1830 ? 'MONTH' : 'YEAR';
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

// Trend bars --------------------------------------------------------------------------------------------

const MONTHS_SHORT = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export function shortPeriodLabel(grain: ExpenseGrain, start: string): string {
  if (!isValidIsoDate(start)) return start;
  switch (grain) {
    case 'DAY': return String(Number(start.slice(8, 10)));
    case 'WEEK': return start.slice(8, 10) + '/' + start.slice(5, 7);
    case 'MONTH': return MONTHS_SHORT[Number(start.slice(5, 7)) - 1];
    case 'YEAR': return start.slice(0, 4);
  }
}

/** Bars scaled to the largest period; a period is in progress when `today` falls inside it. */
export function buildTrendBars(periods: BalancePeriod[], grain: ExpenseGrain, today: string, format: (v: number) => string): TrendBar[] {
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

// Movements list ----------------------------------------------------------------------------------------

export interface ListFilter { search: string; categoryId: string; showVoided: boolean; }

/** Client-side filter over the loaded page only: concept, supplier, invoice folio and category name. */
export function filterExpenses(expenses: AgriExpense[], f: ListFilter): AgriExpense[] {
  const needle = normalizeForSearch(f.search.trim());
  return expenses.filter(e => {
    if (!f.showVoided && e.isVoid) return false;
    if (f.categoryId && e.categoryId !== f.categoryId) return false;
    if (!needle) return true;
    return normalizeForSearch([e.description, e.supplierName, e.invoiceFolio, e.categoryName].filter(Boolean).join(' ')).includes(needle);
  });
}

// Capture -----------------------------------------------------------------------------------------------

export type DateShortcut = 'TODAY' | 'YESTERDAY' | 'OTHER';

export function dateShortcutOf(expenseDate: string, today: string): DateShortcut {
  if (expenseDate === today) return 'TODAY';
  return expenseDate === addDays(today, -1) ? 'YESTERDAY' : 'OTHER';
}

/** Amount > 0 within limits and a category chosen: the minimum for enabling the primary button. */
export function isCaptureReady(input: ExpenseInput): boolean {
  const amount = parseAmountText(input.amount, 2);
  return !!input.categoryId && amount !== null && !Number.isNaN(amount) && amount > 0 && amount <= MAX_AMOUNT;
}
