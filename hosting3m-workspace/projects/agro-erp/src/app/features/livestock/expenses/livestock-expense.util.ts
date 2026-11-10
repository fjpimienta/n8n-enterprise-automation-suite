/**
 * Pure math of the Livestock expense screens. Components only wire signals to these functions.
 * The dashboard owns the data (already filtered by business model, species and lot); nothing is fetched here.
 * Amounts reach the browser as numbers or strings: they are parsed explicitly and never compared as text.
 */
import type { Expense } from '../models/expense.model';
import type { Livestock } from '../models/livestock.model';
import { DateRange, PeriodGrain, PeriodPreset, PeriodTotal, addDays, elapsedDays, previousRange, rangeForPreset } from '@shared/expenses-ui/expenses-period.util';
import { deltaPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
import { isValuedHead } from '@shared/utils/herd-status.util';
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
export const NO_CATEGORY_KEY = 'SIN_CATEGORIA';
export const NO_CATEGORY_LABEL = 'Sin categoría';
/** Groups shown in "Gasto por tipo" before the rest is summed into "Otros". */
export const MAX_TYPE_GROUPS = 6;
/** Category chips of the history before the rest is reachable through "Otros". */
export const MAX_CATEGORY_CHIPS = 8;

/** Obvious spellings only. Anything else stays as its own category. */
const CATEGORY_ALIASES: Readonly<Record<string, string>> = { ALIMENTO: 'ALIMENTACION', ALIMENTOS: 'ALIMENTACION' };

/** Trim, uppercase, strip accents and collapse inner spaces; '' for a missing value. */
export function normalizeCategory(raw: string | null | undefined): string {
  return String(raw ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().trim().replace(/\s+/g, ' ');
}

/** Group key: the normalized value (aliases applied) or SIN_CATEGORIA when there is none. */
export function categoryKey(raw: string | null | undefined): string {
  const n = normalizeCategory(raw);
  return n ? (CATEGORY_ALIASES[n] ?? n) : NO_CATEGORY_KEY;
}

const sentenceCase = (text: string) => {
  const t = text.trim().replace(/\s+/g, ' ').toLowerCase();
  return t.charAt(0).toUpperCase() + t.slice(1);
};

/** Label of a group: known label, "Sin categoría", or the received text in sentence case. */
export function groupLabel(key: string, sampleRaw?: string | null): string {
  if (key in EXPENSE_CATEGORY_LABELS) return EXPENSE_CATEGORY_LABELS[key];
  if (key === NO_CATEGORY_KEY) return NO_CATEGORY_LABEL;
  if (key === OTHER_CATEGORY_KEY) return OTHER_CATEGORY_LABEL;
  return sentenceCase(sampleRaw || key);
}

/** Label of one expense as it must be read: the known label, or the text exactly as received. */
export function categoryLabel(raw: string | null | undefined): string {
  const key = categoryKey(raw);
  if (key in EXPENSE_CATEGORY_LABELS) return EXPENSE_CATEGORY_LABELS[key];
  return String(raw ?? '').trim().replace(/\s+/g, ' ') || NO_CATEGORY_LABEL;
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

/**
 * Spend by normalized category, largest first. At most MAX_TYPE_GROUPS groups are listed; the rest is summed
 * into a final "Otros" row (with its count), so the rows always add up to the sum of all the expenses.
 */
export function spendByType(expenses: readonly Expense[]): TypeRow[] {
  const groups = new Map<string, TypeRow>();
  for (const e of expenses) {
    const key = categoryKey(e.category);
    const row = groups.get(key) ?? { key, label: groupLabel(key, e.category), amount: 0, count: 0 };
    row.amount += amountOf(e);
    row.count += 1;
    groups.set(key, row);
  }
  const sorted = [...groups.values()].sort((a, b) => b.amount - a.amount);
  const named = sorted.filter(r => r.key !== OTHER_CATEGORY_KEY);
  const head = named.slice(0, MAX_TYPE_GROUPS);
  const rest = [...named.slice(MAX_TYPE_GROUPS), ...sorted.filter(r => r.key === OTHER_CATEGORY_KEY)];
  if (!rest.length) return head;
  return [...head, { key: OTHER_CATEGORY_KEY, label: OTHER_CATEGORY_LABEL, amount: rest.reduce((t, r) => t + r.amount, 0), count: rest.reduce((t, r) => t + r.count, 0) }];
}

const weightOf = (a: Pick<Livestock, 'current_weight_kg'> | null | undefined) => {
  const n = Number(a?.current_weight_kg ?? 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
};

/** Estimated value of the herd: weight x price. Deceased animals (BAJA_MORTANDAD) do not add to it. */
export function herdValue(cattle: readonly Livestock[], pricePerKg: number): number {
  return cattle.reduce((sum, a) => (isValuedHead(a) ? sum + weightOf(a) * pricePerKg : sum), 0);
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
    if (isValuedHead(a)) g.value += weightOf(a) * pricePerKg; // heads still count; deceased animals add no value
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

/** Chips of the history: the categories that exist in the list (largest first, max 8) plus "Otros" for the rest. */
export function categoryChipOptions(expenses: readonly Expense[]): Array<{ value: string; label: string }> {
  const rows = new Map<string, { label: string; amount: number }>();
  for (const e of expenses) {
    const key = categoryKey(e.category);
    const r = rows.get(key) ?? { label: groupLabel(key, e.category), amount: 0 };
    r.amount += amountOf(e);
    rows.set(key, r);
  }
  const sorted = [...rows.entries()].filter(([k]) => k !== OTHER_CATEGORY_KEY).sort((a, b) => b[1].amount - a[1].amount);
  const options = sorted.slice(0, MAX_CATEGORY_CHIPS).map(([value, r]) => ({ value, label: r.label }));
  if (sorted.length > MAX_CATEGORY_CHIPS || rows.has(OTHER_CATEGORY_KEY)) options.push({ value: OTHER_CATEGORY_KEY, label: OTHER_CATEGORY_LABEL });
  return options;
}

/** Search matches concept, category (label or value as received), arete and fuego. Newest first. */
export function filterHistory(expenses: readonly Expense[], f: HistoryFilter, lookup: readonly Livestock[], scope: readonly Livestock[]): Expense[] {
  const needle = normalizeForSearch(f.search.trim());
  const byId = new Map(lookup.map(a => [a.id, a] as const));
  const chipKeys = new Set(categoryChipOptions(expenses).map(o => o.value).filter(v => v !== OTHER_CATEGORY_KEY));
  return filterByRange(expenses, f.from, f.to)
    .filter(e => {
      if (f.categoryKey) {
        const key = categoryKey(e.category);
        if (f.categoryKey === OTHER_CATEGORY_KEY ? chipKeys.has(key) : key !== f.categoryKey) return false;
      }
      if (f.onlyGeneral && !isGeneralExpense(e, scope)) return false;
      if (!needle) return true;
      const animal = e.livestock_id ? byId.get(e.livestock_id) : undefined;
      const haystack = [e.description, e.category, categoryLabel(e.category), e.rfid_siniiga, animal?.rfid_siniiga, animal?.numero_fuego].filter(Boolean).join(' ');
      return normalizeForSearch(haystack).includes(needle);
    })
    .sort((a, b) => (expenseDay(b) < expenseDay(a) ? -1 : expenseDay(b) > expenseDay(a) ? 1 : 0));
}
