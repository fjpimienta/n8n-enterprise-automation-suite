/**
 * Pure math of the Livestock expense screens. Components only wire signals to these functions.
 * The dashboard owns the data (already filtered by business model, species and lot); nothing is fetched here.
 * Amounts reach the browser as numbers or strings: they are parsed explicitly and never compared as text.
 */
import type { Expense } from '../models/expense.model';
import type { Livestock } from '../models/livestock.model';
import { DateRange, PeriodGrain, PeriodPreset, PeriodTotal, addDays, elapsedDays, previousRange, rangeForPreset } from '@shared/expenses-ui/expenses-period.util';
import { deltaPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
import { normalizeForSearch } from '@shared/utils/text-normalize.util';

/** Reference price used for the estimated value of the herd (MXN per kg). Not configurable yet. */
export const REFERENCE_PRICE_PER_KG = 65;
/** An animal is "at risk" when its balance is below this percentage of its estimated value (negative counts). */
export const RISK_MARGIN_PCT = 10;

export type LivestockPeriodPreset = Exclude<PeriodPreset, 'CUSTOM'>;

export const LIVESTOCK_PERIOD_PRESETS: ReadonlyArray<{ value: LivestockPeriodPreset; label: string }> = [
  { value: 'MONTH', label: 'Este mes' },
  { value: 'QUARTER', label: 'Trimestre' },
  { value: 'YEAR', label: 'Año' },
];

// Categories ----------------------------------------------------------------------------------------------

export const EXPENSE_CATEGORY_LABELS: Readonly<Record<string, string>> = {
  ALIMENTACION: 'Alimentación',
  MEDICINA: 'Medicina y sanidad',
  SUPLEMENTOS: 'Suplementos',
  MANEJO: 'Manejo y fletes',
};
export const OTHER_CATEGORY_KEY = 'OTROS';
export const OTHER_CATEGORY_LABEL = 'Otros';

const upperKey = (raw: string | null | undefined) => (raw ?? '').trim().toUpperCase();

/** Group key: one of the four known categories, or OTROS for any legacy / missing value. */
export function categoryKey(raw: string | null | undefined): string {
  const key = upperKey(raw);
  return key in EXPENSE_CATEGORY_LABELS ? key : OTHER_CATEGORY_KEY;
}

/** Label of the group ("Otros" for anything unknown) — used by aggregations. */
export function categoryGroupLabel(raw: string | null | undefined): string {
  const key = categoryKey(raw);
  return key === OTHER_CATEGORY_KEY ? OTHER_CATEGORY_LABEL : EXPENSE_CATEGORY_LABELS[key];
}

/** Label of one expense: the known label, or the value exactly as received for a legacy category. */
export function categoryLabel(raw: string | null | undefined): string {
  const key = categoryKey(raw);
  if (key !== OTHER_CATEGORY_KEY) return EXPENSE_CATEGORY_LABELS[key];
  return (raw ?? '').trim() || OTHER_CATEGORY_LABEL;
}

// Amounts and dates ---------------------------------------------------------------------------------------

export function amountOf(expense: Pick<Expense, 'amount'>): number {
  const n = Number(expense.amount);
  return Number.isFinite(n) ? n : 0;
}

/** YYYY-MM-DD part of an expense date (plain date or timestamp). */
export function expenseDay(expense: Pick<Expense, 'expense_date'>): string {
  return String(expense.expense_date ?? '').split(/[ T]/)[0];
}

export function sumAmount(expenses: readonly Expense[]): number {
  return expenses.reduce((sum, e) => sum + amountOf(e), 0);
}

/** Expenses whose day falls in [from, to]; a blank bound is open. */
export function filterByRange(expenses: readonly Expense[], from: string, to: string): Expense[] {
  return expenses.filter(e => {
    const day = expenseDay(e);
    return !!day && (!from || day >= from) && (!to || day <= to);
  });
}

// Period ---------------------------------------------------------------------------------------------------

export interface PeriodView { range: DateRange; grain: PeriodGrain; inProgress: boolean; }

export function periodView(preset: LivestockPeriodPreset, today: string): PeriodView {
  const r = rangeForPreset(preset, today);
  return { range: { from: r.from, to: r.to }, grain: r.grain, inProgress: r.from <= today && today <= r.to };
}

/**
 * The range the current one is compared with, always like for like. In progress: the same number of elapsed
 * days from the start of the previous period (capped at its last day). Closed: the whole previous period.
 */
export function previousCut(preset: LivestockPeriodPreset, range: DateRange, today: string): DateRange {
  const prev = previousRange(preset, range);
  if (!(range.from <= today && today <= range.to)) return prev;
  const end = addDays(prev.from, elapsedDays(range, today) - 1);
  return { from: prev.from, to: end < prev.to ? end : prev.to };
}

export function comparisonLabel(preset: LivestockPeriodPreset, inProgress: boolean): string {
  if (!inProgress) return 'vs. periodo anterior';
  return preset === 'MONTH' ? 'vs. mismos días del mes anterior' : 'vs. mismos días del periodo anterior';
}

/** Delta of the period spend vs. its like-for-like cut; null when the previous cut has nothing to compare with. */
export function spendDelta(expenses: readonly Expense[], preset: LivestockPeriodPreset, today: string): { current: number; previous: number; delta: number | null } {
  const view = periodView(preset, today);
  const cut = previousCut(preset, view.range, today);
  const current = sumAmount(filterByRange(expenses, view.range.from, view.range.to));
  const previous = sumAmount(filterByRange(expenses, cut.from, cut.to));
  return { current, previous, delta: deltaPercent(current, previous) };
}

const monthEnd = (month: string) => {
  const [y, m] = month.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};

/** Spend per day (DAY grain) or per month (MONTH grain) across the whole range, zero-filled. */
export function spendTrend(expenses: readonly Expense[], range: DateRange, grain: PeriodGrain): PeriodTotal[] {
  const byDay = new Map<string, number>();
  for (const e of filterByRange(expenses, range.from, range.to)) {
    const key = grain === 'DAY' ? expenseDay(e) : expenseDay(e).slice(0, 7);
    byDay.set(key, (byDay.get(key) ?? 0) + amountOf(e));
  }
  const out: PeriodTotal[] = [];
  if (grain === 'DAY') {
    for (let day = range.from; day <= range.to; day = addDays(day, 1)) out.push({ periodStart: day, periodEnd: day, totalAmount: byDay.get(day) ?? 0 });
    return out;
  }
  let month = range.from.slice(0, 7);
  const last = range.to.slice(0, 7);
  while (month <= last) {
    out.push({ periodStart: `${month}-01`, periodEnd: monthEnd(month), totalAmount: byDay.get(month) ?? 0 });
    const [y, m] = month.split('-').map(Number);
    month = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  }
  return out;
}

// Aggregations --------------------------------------------------------------------------------------------

export interface TypeRow { key: string; label: string; amount: number; count: number; }

/** Spend by category group; any unknown value is added to "Otros". Sorted by amount, descending. */
export function spendByType(expenses: readonly Expense[]): TypeRow[] {
  const groups = new Map<string, TypeRow>();
  for (const e of expenses) {
    const key = categoryKey(e.category);
    const row = groups.get(key) ?? { key, label: categoryGroupLabel(e.category), amount: 0, count: 0 };
    row.amount += amountOf(e);
    row.count += 1;
    groups.set(key, row);
  }
  return [...groups.values()].sort((a, b) => b.amount - a.amount);
}

const weightOf = (a: Pick<Livestock, 'current_weight_kg'> | null | undefined) => {
  const n = Number(a?.current_weight_kg ?? 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
};

export function herdValue(cattle: readonly Livestock[], pricePerKg: number): number {
  return cattle.reduce((sum, a) => sum + weightOf(a) * pricePerKg, 0);
}

/** Spend per head; null without heads. */
export function perHead(total: number, heads: number): number | null {
  return heads > 0 && Number.isFinite(total) ? total / heads : null;
}

const uppCodeOf = (a: Livestock | null | undefined): string => (a?.production_unit_id && String(a.upp_code ?? '').trim()) || '';

export type UppRowKind = 'upp' | 'none' | 'general';
export interface UppRow {
  key: string;
  label: string;
  kind: UppRowKind;
  heads: number;
  value: number;
  spend: number;
  balance: number;
  /** Spend as a percentage of the estimated value; null when there is no value to compare with. */
  spendOverValuePct: number | null;
}

export const NO_UPP_LABEL = 'Sin UPP asignada';
export const GENERAL_LABEL = 'Gastos generales';

/**
 * Accumulated balance by UPP (all dates). An expense counts for a UPP only when its animal is in `cattle` and has
 * one; otherwise (no animal, animal not in scope, animal without UPP) it is a general expense. The "none" row holds
 * the animals without UPP (value only); the "general" row is added when there is any general spend.
 */
export function uppBalance(cattle: readonly Livestock[], expenses: readonly Expense[], pricePerKg: number): UppRow[] {
  const byId = new Map(cattle.map(a => [a.id, a] as const));
  const groups = new Map<string, { heads: number; value: number; spend: number; kind: UppRowKind }>();
  for (const a of cattle) {
    const code = uppCodeOf(a);
    const key = code || NO_UPP_LABEL;
    const g = groups.get(key) ?? { heads: 0, value: 0, spend: 0, kind: code ? 'upp' : 'none' };
    g.heads += 1;
    g.value += weightOf(a) * pricePerKg;
    groups.set(key, g);
  }
  let general = 0;
  for (const e of expenses) {
    const code = e.livestock_id ? uppCodeOf(byId.get(e.livestock_id)) : '';
    if (code) {
      const g = groups.get(code) ?? { heads: 0, value: 0, spend: 0, kind: 'upp' as UppRowKind };
      g.spend += amountOf(e);
      groups.set(code, g);
    } else {
      general += amountOf(e);
    }
  }
  const rows: UppRow[] = [...groups.entries()].map(([key, g]) => toUppRow(key, key, g.kind, g.heads, g.value, g.spend))
    .sort((a, b) => b.value - a.value);
  if (general > 0) rows.push(toUppRow('__general', GENERAL_LABEL, 'general', 0, 0, general));
  return rows;
}

function toUppRow(key: string, label: string, kind: UppRowKind, heads: number, value: number, spend: number): UppRow {
  return { key, label, kind, heads, value, spend, balance: value - spend, spendOverValuePct: value > 0 ? sharePercent(spend, value) : null };
}

/** Net accumulated balance: estimated value of the herd minus all the spend (every row, "none" and "general" included). */
export function netBalance(rows: readonly UppRow[]): number {
  return rows.reduce((sum, r) => sum + r.balance, 0);
}

// Cost per animal -----------------------------------------------------------------------------------------

export interface AnimalCostRow {
  livestockId: string;
  arete: string;
  fuego: string;
  category: string;
  upp: string;
  weightKg: number;
  hasWeight: boolean;
  total: number;
  count: number;
  costPerKg: number | null;
  value: number | null;
  balance: number | null;
  atRisk: boolean;
}

/** At risk: has a value and its balance is under RISK_MARGIN_PCT of it (a negative balance always is). No weight: never. */
export function isAtRisk(value: number | null, balance: number | null): boolean {
  return value !== null && balance !== null && value > 0 && balance < (value * RISK_MARGIN_PCT) / 100;
}

/** One row per animal with linked expenses (accumulated, all dates). `lookup` resolves animals out of the current scope. */
export function animalCosts(expenses: readonly Expense[], lookup: readonly Livestock[], pricePerKg: number): AnimalCostRow[] {
  const byId = new Map(lookup.map(a => [a.id, a] as const));
  const grouped = new Map<string, { total: number; count: number }>();
  for (const e of expenses) {
    if (!e.livestock_id) continue;
    const g = grouped.get(e.livestock_id) ?? { total: 0, count: 0 };
    g.total += amountOf(e);
    g.count += 1;
    grouped.set(e.livestock_id, g);
  }
  return [...grouped.entries()].map(([id, g]) => {
    const animal = byId.get(id);
    const weightKg = weightOf(animal);
    const hasWeight = weightKg > 0;
    const value = hasWeight ? weightKg * pricePerKg : null;
    const balance = value === null ? null : value - g.total;
    return {
      livestockId: id,
      arete: animal?.rfid_siniiga || 'Desconocido',
      fuego: animal?.numero_fuego ?? '',
      category: animal?.category ?? '',
      upp: uppCodeOf(animal),
      weightKg, hasWeight, total: g.total, count: g.count,
      costPerKg: hasWeight ? g.total / weightKg : null,
      value, balance,
      atRisk: isAtRisk(value, balance),
    };
  });
}

export type AnimalSort = 'SPEND' | 'WORST_BALANCE';

/** "Mayor gasto": total descending. "Peor balance": lowest balance first; animals without weight go last. */
export function sortAnimalCosts(rows: readonly AnimalCostRow[], mode: AnimalSort): AnimalCostRow[] {
  const copy = [...rows];
  if (mode === 'SPEND') return copy.sort((a, b) => b.total - a.total);
  return copy.sort((a, b) => {
    if (a.balance === null && b.balance === null) return b.total - a.total;
    if (a.balance === null) return 1;
    if (b.balance === null) return -1;
    return a.balance - b.balance || b.total - a.total;
  });
}

// History ---------------------------------------------------------------------------------------------------

/** General = no animal, or an animal that is out of scope or has no UPP (same rule as the "Gastos generales" row). */
export function isGeneralExpense(expense: Expense, cattle: readonly Livestock[]): boolean {
  if (!expense.livestock_id) return true;
  return !uppCodeOf(cattle.find(a => a.id === expense.livestock_id));
}

export interface HistoryFilter { search: string; categoryKey: string; from: string; to: string; onlyGeneral: boolean; }

/** Search matches concept, category (label or value as received), arete and fuego. Newest first. */
export function filterHistory(expenses: readonly Expense[], f: HistoryFilter, lookup: readonly Livestock[], scope: readonly Livestock[]): Expense[] {
  const needle = normalizeForSearch(f.search.trim());
  const byId = new Map(lookup.map(a => [a.id, a] as const));
  return filterByRange(expenses, f.from, f.to)
    .filter(e => {
      if (f.categoryKey && categoryKey(e.category) !== f.categoryKey) return false;
      if (f.onlyGeneral && !isGeneralExpense(e, scope)) return false;
      if (!needle) return true;
      const animal = e.livestock_id ? byId.get(e.livestock_id) : undefined;
      const haystack = [e.description, e.category, categoryLabel(e.category), e.rfid_siniiga, animal?.rfid_siniiga, animal?.numero_fuego].filter(Boolean).join(' ');
      return normalizeForSearch(haystack).includes(needle);
    })
    .sort((a, b) => (expenseDay(b) < expenseDay(a) ? -1 : expenseDay(b) > expenseDay(a) ? 1 : 0));
}

/** Chips for the history: the four known categories plus "Otros" only when a legacy value exists. */
export function categoryChipOptions(expenses: readonly Expense[]): Array<{ value: string; label: string }> {
  const options = Object.entries(EXPENSE_CATEGORY_LABELS).map(([value, label]) => ({ value, label }));
  if (expenses.some(e => categoryKey(e.category) === OTHER_CATEGORY_KEY)) options.push({ value: OTHER_CATEGORY_KEY, label: OTHER_CATEGORY_LABEL });
  return options;
}
