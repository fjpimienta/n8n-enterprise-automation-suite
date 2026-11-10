/**
 * Pure math of the "Resultado del periodo" block: sales income, result (income - spend) and mortality loss.
 * Same like-for-like rules as the spend KPIs (see livestock-expense.util.ts). Nothing here fetches anything.
 */
import type { SaleIncome } from '@core/models/sale.model';
import { deltaPercent, formatMoney } from '@shared/expenses-ui/expenses-ui.util';
import type { Expense } from '../models/expense.model';
import type { Livestock } from '../models/livestock.model';
import { LivestockPeriodPreset, filterByRange, periodView, previousCut, sumAmount } from './livestock-expense.util';

const num = (v: unknown) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const incomeDay = (i: Pick<SaleIncome, 'saleDate'>) => String(i.saleDate ?? '').split(/[ T]/)[0];

/** Incomes whose sale day falls in [from, to] (inclusive; a blank bound is open). */
export function incomesInRange(incomes: readonly SaleIncome[], from: string, to: string): SaleIncome[] {
  return incomes.filter(i => {
    const d = incomeDay(i);
    return !!d && (!from || d >= from) && (!to || d <= to);
  });
}

export function sumIncome(incomes: readonly SaleIncome[]): number {
  return incomes.reduce((t, i) => t + num(i.amount), 0);
}

/**
 * Incomes in scope: of the active company, and of an animal inside the module / species / lot filter. An income whose
 * animal is not in the herd list at all is kept only when no species / lot filter is active (so it never vanishes from totals).
 */
export function scopeIncomes(
  incomes: readonly SaleIncome[], tenantId: number | null, scopedIds: ReadonlySet<string>, knownIds: ReadonlySet<string>, keepUnknown: boolean,
): SaleIncome[] {
  if (tenantId === null || !Number.isFinite(tenantId)) return [];
  return incomes.filter(i => i.tenantId === tenantId && (scopedIds.has(i.livestockId) || (keepUnknown && !knownIds.has(i.livestockId))));
}

export interface PeriodResult {
  income: number;
  spend: number;
  result: number;
  soldHeads: number;
  incomeDelta: number | null;
  resultDelta: number | null;
  previousIncome: number;
  previousSpend: number;
}

/** Income, spend and result of the period, with the delta against the like-for-like previous cut. */
export function periodResult(incomes: readonly SaleIncome[], expenses: readonly Expense[], preset: LivestockPeriodPreset, today: string): PeriodResult {
  const { range } = periodView(preset, today);
  const cut = previousCut(preset, range, today);
  const inPeriod = incomesInRange(incomes, range.from, range.to);
  const income = sumIncome(inPeriod);
  const spend = sumAmount(filterByRange(expenses, range.from, range.to));
  const previousIncome = sumIncome(incomesInRange(incomes, cut.from, cut.to));
  const previousSpend = sumAmount(filterByRange(expenses, cut.from, cut.to));
  const result = income - spend;
  const previousResult = previousIncome - previousSpend;
  return {
    income, spend, result, soldHeads: inPeriod.length,
    incomeDelta: deltaPercent(income, previousIncome),
    // A percentage across a change of sign (e.g. +$100 vs −$300) misleads: only same-sign results are compared.
    resultDelta: result > 0 && previousResult > 0 ? deltaPercent(result, previousResult) : null,
    previousIncome, previousSpend,
  };
}

/** All sales income minus all expenses (every date). */
export function accumulatedResult(incomes: readonly SaleIncome[], expenses: readonly Expense[]): number {
  return sumIncome(incomes) - sumAmount(expenses);
}

export type ResultTone = 'up' | 'down' | 'flat';
export const resultTone = (value: number): ResultTone => (Math.round(value * 100) === 0 ? 'flat' : value > 0 ? 'up' : 'down');

/** "+$1,000.00", "−$500.00" or "$0.00": the sign is part of the text, never only a color. */
export function signedMoney(value: number): string {
  const tone = resultTone(value);
  if (tone === 'flat') return formatMoney(0);
  return `${tone === 'up' ? '+' : '−'}${formatMoney(Math.abs(value))}`;
}

export function resultWord(value: number): string {
  const tone = resultTone(value);
  return tone === 'flat' ? 'Sin ganancia ni pérdida' : tone === 'up' ? 'Ganancia' : 'Pérdida';
}

export interface MortalityLoss { count: number; estimatedLoss: number; withoutWeight: number; }

/** Animals dead (BAJA_MORTANDAD) and their estimated loss: last known weight x price. No weight: counted, adds 0, flagged. */
export function mortalityLoss(animals: readonly Livestock[], pricePerKg: number): MortalityLoss {
  let estimatedLoss = 0;
  let withoutWeight = 0;
  for (const a of animals) {
    const w = num(a.current_weight_kg);
    if (w > 0) estimatedLoss += w * pricePerKg; else withoutWeight += 1;
  }
  return { count: animals.length, estimatedLoss, withoutWeight };
}

export const isMortality = (a: Pick<Livestock, 'current_status'>) => (a.current_status ?? '').trim().toUpperCase() === 'BAJA_MORTANDAD';

export interface SaleRow { id: string; date: string; buyer: string; tag: string; amount: number; }

/** Latest sales of the period (newest first, max `limit`). */
export function recentSales(incomes: readonly SaleIncome[], range: { from: string; to: string }, lookup: readonly Livestock[], limit = 5): SaleRow[] {
  const byId = new Map(lookup.map(a => [a.id, a] as const));
  return incomesInRange(incomes, range.from, range.to)
    .sort((a, b) => (incomeDay(b) < incomeDay(a) ? -1 : incomeDay(b) > incomeDay(a) ? 1 : 0))
    .slice(0, limit)
    .map(i => {
      const a = byId.get(i.livestockId);
      return { id: i.id, date: incomeDay(i), buyer: i.buyerName || '—', tag: a?.rfid_siniiga || a?.numero_fuego || a?.electronic_rfid || '—', amount: num(i.amount) };
    });
}
