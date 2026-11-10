/**
 * Pure rules of the expense overview of the palm dashboard: which balance queries a period and a scope need, and
 * what the previous period is compared with. The like-for-like cut is the one of the Balance screen (comparisonFor).
 */
import type { ExpenseBalance, ExpenseBalanceQuery } from '@core/models/agri-expense.model';
import { DateRange, PERIOD_PRESETS, PeriodPreset, rangeForPreset } from '@shared/expenses-ui/expenses-period.util';
import { GroupRow, groupTopN } from '@shared/expenses-ui/expenses-ui.util';
import { snapRangeToGrain } from './expense.util';
import { Comparison, comparisonFor } from './expense-view.util';

export type OverviewPreset = Exclude<PeriodPreset, 'CUSTOM'>;
export type OverviewScope = 'COMPANY' | 'PLANTATION';

export const OVERVIEW_PRESETS = PERIOD_PRESETS.filter(p => p.value !== 'CUSTOM') as ReadonlyArray<{ value: OverviewPreset; label: string }>;
export const OVERVIEW_SCOPES: ReadonlyArray<{ value: OverviewScope; label: string }> = [
  { value: 'COMPANY', label: 'Toda la empresa' },
  { value: 'PLANTATION', label: 'Esta plantación' },
];
/** Categories listed before the rest goes into "Otros". */
export const OVERVIEW_MAX_CATEGORIES = 6;

export interface OverviewPlan {
  range: DateRange;
  /** Current period. `plantationId` is set only for the plantation scope. */
  query: ExpenseBalanceQuery;
  comparison: Comparison;
  /** Previous like-for-like cut; null when there is none (period in progress without a like-for-like cut). */
  previous: ExpenseBalanceQuery | null;
  /** Company-wide query of the same period (the denominator of "Parte de la empresa"); null in company scope. */
  company: ExpenseBalanceQuery | null;
}

/** null when the plantation scope has no active plantation (nothing is requested). */
export function planOverview(preset: OverviewPreset, scope: OverviewScope, plantationId: string | null, today: string): OverviewPlan | null {
  if (scope === 'PLANTATION' && !plantationId) return null;
  const r = rangeForPreset(preset, today);
  const range = { from: r.from, to: r.to };
  const query: ExpenseBalanceQuery = {
    dateFrom: range.from, dateTo: range.to, grain: r.grain, plantationId: scope === 'PLANTATION' ? plantationId : null, lotId: null, categoryId: null,
  };
  const comparison = comparisonFor(preset, range, today);
  let previous: ExpenseBalanceQuery | null = null;
  if (comparison.kind === 'range') {
    const grain = comparison.grain ?? query.grain;
    const prev = comparison.grain ? comparison.range : snapRangeToGrain(comparison.range.from, comparison.range.to, grain);
    previous = { ...query, grain, dateFrom: prev.from, dateTo: prev.to };
  }
  return { range, query, comparison, previous, company: scope === 'PLANTATION' ? { ...query, plantationId: null } : null };
}

/** "En qué se gasta": top categories and "Otros", from the balance by category. */
export function categoryGroups(balance: ExpenseBalance | null): GroupRow[] {
  return groupTopN((balance?.byCategory ?? []).map(c => ({ key: c.categoryId, label: c.categoryName, amount: c.totalAmount, count: c.expenseCount })), OVERVIEW_MAX_CATEGORIES);
}

/** "Por plantación" rows (company scope), general expenses included. */
export function plantationGroups(balance: ExpenseBalance | null): GroupRow[] {
  return (balance?.byPlantation ?? [])
    .map(p => ({ key: p.plantationId ?? 'general', label: p.plantationId ? `${p.plantationCode} · ${p.plantationName}` : 'General (sin plantación)', amount: p.totalAmount, count: p.expenseCount }))
    .filter(r => r.amount > 0).sort((a, b) => b.amount - a.amount);
}
