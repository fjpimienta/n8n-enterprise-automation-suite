import { describe, expect, it } from 'vitest';
import type { SaleIncome } from '@core/models/sale.model';
import type { Expense } from '../models/expense.model';
import type { Livestock } from '../models/livestock.model';
import {
  accumulatedResult, incomesInRange, isMortality, mortalityLoss, periodResult, recentSales, resultTone, resultWord, scopeIncomes, signedMoney, sumIncome,
} from './livestock-result.util';
import { sumAmount } from './livestock-expense.util';

const inc = (o: Partial<SaleIncome> = {}): SaleIncome => ({
  id: 'i' + Math.random(), tenantId: 3, livestockId: 'a1', pendingAuthorizationId: null, saleDate: '2026-11-05', saleMode: 'PER_HEAD' as never,
  amount: 1000, weightKg: null, pricePerKg: null, buyerName: 'Comprador', paymentMethod: 'EFECTIVO' as never, invoiced: false, invoiceFolio: null, banked: false, guiaTransito: null, ...o });
const exp = (o: Partial<Expense> = {}): Expense => ({ id: 'e' + Math.random(), expense_date: '2026-11-05', category: 'MANEJO', amount: 100, ...o });
const cow = (o: Partial<Livestock> = {}): Livestock => ({ id: 'a1', business_model: 'CRIA', current_weight_kg: 100, rfid_siniiga: '07001', ...o });

describe('incomes in range', () => {
  const list = [inc({ saleDate: '2026-10-31' }), inc({ saleDate: '2026-11-01' }), inc({ saleDate: '2026-11-30T12:00:00Z' }), inc({ saleDate: '2026-12-01' })];
  it('includes both boundaries and excludes the rest', () => {
    expect(incomesInRange(list, '2026-11-01', '2026-11-30').length).toBe(2);
  });
  it('handles empty lists and open bounds', () => {
    expect(incomesInRange([], '2026-11-01', '2026-11-30')).toEqual([]);
    expect(incomesInRange(list, '', '').length).toBe(4);
    expect(sumIncome([inc({ amount: '250.5' as unknown as number }), inc({ amount: 'x' as unknown as number })])).toBe(250.5);
  });
});

describe('scope of incomes', () => {
  const a = inc({ livestockId: 'a1' }), b = inc({ livestockId: 'b1' }), ghost = inc({ livestockId: 'zz' }), other = inc({ livestockId: 'a1', tenantId: 9 });
  const scoped = new Set(['a1']); const known = new Set(['a1', 'b1']);
  it('keeps the active company and the animals in scope only', () => {
    expect(scopeIncomes([a, b, other], 3, scoped, known, true)).toEqual([a]);
  });
  it('keeps unknown animals only without species / lot filters', () => {
    expect(scopeIncomes([ghost], 3, scoped, known, true)).toEqual([ghost]);
    expect(scopeIncomes([ghost], 3, scoped, known, false)).toEqual([]);
  });
  it('fails closed without a company', () => {
    expect(scopeIncomes([a], null, scoped, known, true)).toEqual([]);
  });
});

describe('period result', () => {
  const today = '2026-11-09';
  const incomes = [inc({ saleDate: '2026-11-03', amount: 5000 }), inc({ saleDate: '2026-10-05', amount: 2000 }), inc({ saleDate: '2026-10-25', amount: 9999 })];
  const expenses = [exp({ expense_date: '2026-11-04', amount: 1500 }), exp({ expense_date: '2026-10-06', amount: 500 })];
  it('income minus spend, with the like-for-like previous cut (same elapsed days)', () => {
    const r = periodResult(incomes, expenses, 'MONTH', today);
    expect(r).toMatchObject({ income: 5000, spend: 1500, result: 3500, soldHeads: 1, previousIncome: 2000, previousSpend: 500 });
    expect(r.incomeDelta).toBeCloseTo(150);
    expect(r.resultDelta).toBeCloseTo(((3500 - 1500) / 1500) * 100);
  });
  it('hides the result delta when the sign changes between the previous and the current result', () => {
    // previous cut: +1500 income - 500 spend = +1000; current: 0 income - 1500 spend = -1500
    const r = periodResult([inc({ saleDate: '2026-10-05', amount: 1500 })], [exp({ expense_date: '2026-10-06', amount: 500 }), exp({ expense_date: '2026-11-04', amount: 1500 })], 'MONTH', '2026-11-09');
    expect(r.result).toBe(-1500);
    expect(r.resultDelta).toBeNull();
    // opposite change: negative before, positive now
    const r2 = periodResult([inc({ saleDate: '2026-11-03', amount: 3000 })], [exp({ expense_date: '2026-10-06', amount: 500 })], 'MONTH', '2026-11-09');
    expect(r2.result).toBe(3000);
    expect(r2.resultDelta).toBeNull();
  });
  it('short previous month is capped at its last day', () => {
    const r = periodResult([inc({ saleDate: '2026-02-28', amount: 100 })], [], 'MONTH', '2026-03-31');
    expect(r.previousIncome).toBe(100);
  });
  it('empty data gives zeros and no deltas', () => {
    expect(periodResult([], [], 'MONTH', today)).toMatchObject({ income: 0, spend: 0, result: 0, soldHeads: 0, incomeDelta: null, resultDelta: null });
  });
  it('is consistent: result = income - spend and the accumulated result adds everything', () => {
    const r = periodResult(incomes, expenses, 'YEAR', today);
    expect(r.result).toBe(r.income - r.spend);
    expect(accumulatedResult(incomes, expenses)).toBe(sumIncome(incomes) - sumAmount(expenses));
  });
});

describe('sign, tone and words', () => {
  it('conveys the sign in text', () => {
    expect(signedMoney(1250)).toBe('+$1,250.00');
    expect(signedMoney(-500)).toBe('−$500.00');
    expect(signedMoney(0)).toBe('$0.00');
    expect(resultTone(0.001)).toBe('flat');
    expect([resultWord(5), resultWord(-5), resultWord(0)]).toEqual(['Ganancia', 'Pérdida', 'Sin ganancia ni pérdida']);
  });
});

describe('mortality', () => {
  it('counts every dead animal; the loss is weight x price and animals without weight add 0 and are flagged', () => {
    const r = mortalityLoss([cow({ current_weight_kg: 200 }), cow({ id: 'a2', current_weight_kg: 0 }), cow({ id: 'a3', current_weight_kg: undefined })], 10);
    expect(r).toEqual({ count: 3, estimatedLoss: 2000, withoutWeight: 2 });
    expect(mortalityLoss([], 10)).toEqual({ count: 0, estimatedLoss: 0, withoutWeight: 0 });
  });
  it('recognizes the status ignoring case', () => {
    expect(isMortality({ current_status: ' baja_mortandad ' })).toBe(true);
    expect(isMortality({ current_status: 'VENDIDO' })).toBe(false);
  });
});

describe('recent sales', () => {
  it('lists the period sales newest first, max 5, with the animal tag', () => {
    const incomes = Array.from({ length: 7 }, (_, i) => inc({ id: 's' + i, saleDate: `2026-11-0${i + 1}`, amount: 100 + i }));
    incomes.push(inc({ id: 'old', saleDate: '2026-10-01' }));
    const rows = recentSales(incomes, { from: '2026-11-01', to: '2026-11-30' }, [cow()], 5);
    expect(rows.map(r => r.id)).toEqual(['s6', 's5', 's4', 's3', 's2']);
    expect(rows[0]).toMatchObject({ buyer: 'Comprador', tag: '07001', amount: 106 });
  });
});
