/**
 * Pure helpers of the redesigned expense screens: period presets, previous-period range, trivial derivations
 * (average per day, share, delta), list filtering and capture readiness. Totals are never computed here:
 * they come from the balance endpoint; only ratios of values the database already returned are derived.
 */
import type { AgriExpense, ExpenseGrain, ExpenseInput } from '@core/models/agri-expense.model';
import { normalizeForSearch } from '@shared/utils/text-normalize.util';
import { DateRange, PeriodPreset, addDays, daysInRange, elapsedDays, previousRange } from '@shared/expenses-ui/expenses-period.util';
import { MAX_AMOUNT, parseAmountText } from './expense.util';

export { deltaPercent, formatDelta, formatPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
export type { TrendBar } from '@shared/expenses-ui/expenses-ui.util';
// Generic period helpers live in the shared util (also used by Livestock); re-exported so existing imports keep working.
export {
  PERIOD_PRESETS, addDays, averagePerDay, buildTrendBars, daysInRange, elapsedDays, previousRange, rangeForPreset, shortPeriodLabel,
} from '@shared/expenses-ui/expenses-period.util';
export type { DateRange, PeriodPreset, PresetRange } from '@shared/expenses-ui/expenses-period.util';

/** Grain for a free range: day up to ~2 months, month up to ~5 years, year beyond. */
export function grainForSpan(from: string, to: string): ExpenseGrain {
  const days = daysInRange(from, to);
  return days <= 62 ? 'DAY' : days <= 1830 ? 'MONTH' : 'YEAR';
}

export type Comparison =
  | { kind: 'range'; range: DateRange; grain: ExpenseGrain | null; label: string }
  | { kind: 'in-progress' };

/**
 * What the current total may be compared with, never across different lengths:
 * - closed period: the equivalent previous period (same grain as the query);
 * - month in progress: the same number of elapsed days of the previous month (capped to its last day), by day;
 * - quarter / year / custom in progress: no like-for-like cut exists with whole-month grain, so no comparison.
 */
export function comparisonFor(preset: PeriodPreset, range: DateRange, today: string): Comparison {
  const inProgress = range.from <= today && today <= range.to;
  if (!inProgress) return { kind: 'range', range: previousRange(preset, range), grain: null, label: 'vs. periodo anterior' };
  if (preset !== 'MONTH') return { kind: 'in-progress' };
  const prev = previousRange('MONTH', range);
  const end = addDays(prev.from, elapsedDays(range, today) - 1);
  return { kind: 'range', range: { from: prev.from, to: end < prev.to ? end : prev.to }, grain: 'DAY', label: 'vs. mismos días del mes anterior' };
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

/** Empty-list explanation; flags that a truncated page may hide matches. */
export function emptyListMessage(o: { loaded: number; hasSearch: boolean; hasCategory: boolean; truncated: boolean }): string {
  const incomplete = o.truncated ? ' La lista llegó cortada: el resultado puede estar incompleto.' : '';
  if (o.loaded > 0 || o.hasSearch || o.hasCategory) return `Ningún gasto coincide con la búsqueda o los filtros.${incomplete}`;
  return `No hay gastos con esos filtros.${incomplete}`;
}
