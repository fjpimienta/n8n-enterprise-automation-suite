import { describe, expect, it } from 'vitest';
import type { ExpenseBalance } from '@core/models/agri-expense.model';
import type { SaleBalance } from '@core/models/agri-sale.model';
import {
  BalanceAvailabilityInput,
  balanceAvailability,
  buildIncomeExpense,
  formatSignedMoney,
  fromCents,
  netBalance,
  toCents,
} from './income-expense.util';

const RANGE = { dateFrom: '2026-11-01', dateTo: '2026-11-30' };
const sales = (total: number, o: Partial<SaleBalance> = {}): SaleBalance => ({
  grain: 'DAY', ...RANGE, totalAmount: total, saleCount: total ? 2 : 0, totalQuantityKg: 0, generalAmount: 0, byPeriod: [], byPlantation: [], ...o,
});
const expenses = (total: number, o: Partial<ExpenseBalance> = {}): ExpenseBalance => ({
  grain: 'DAY', ...RANGE, totalAmount: total, expenseCount: total ? 3 : 0, generalAmount: 0, byPeriod: [], byCategory: [], byPlantation: [], byLot: [], ...o,
});

describe('toCents / fromCents', () => {
  it('rounds money to integer cents', () => {
    expect(toCents(1234.56)).toBe(123456);
    expect(toCents(0)).toBe(0);
    expect(toCents(0.1 + 0.2)).toBe(30);
    expect(toCents(1.005)).toBe(101); // 1.005 * 100 is 100.49999999999999 in binary floating point
    expect(toCents(9999999999.99)).toBe(999999999999);
    expect(toCents(-250.05)).toBe(-25005);
  });
  it('is NaN for anything that is not a finite number', () => {
    for (const v of [Number.NaN, Infinity, -Infinity, undefined as unknown as number, '1' as unknown as number, null as unknown as number]) {
      expect(Number.isNaN(toCents(v))).toBe(true);
    }
    expect(Number.isNaN(fromCents(Number.NaN))).toBe(true);
    expect(fromCents(12345)).toBe(123.45);
  });
});

describe('netBalance (integer cents)', () => {
  it('positive, negative and zero', () => {
    expect(netBalance(1500, 1000)).toBe(500);
    expect(netBalance(1000, 1500)).toBe(-500);
    expect(netBalance(1000, 1000)).toBe(0);
  });
  it('decimal traps stay exact', () => {
    expect(netBalance(0.1 + 0.2, 0.1)).toBe(0.2);
    expect(netBalance(0.3, 0.1)).toBe(0.2); // 0.30 - 0.10 is 0.19999999999999998 in floating point
    expect(netBalance(1000.1, 250.05)).toBe(750.05);
    expect(netBalance(0.1, 0.3)).toBe(-0.2);
    expect(netBalance(0.1 + 0.2, 0.3)).toBe(0);
    expect(netBalance(19999999999.99, 9999999999.99)).toBe(10000000000);
  });
  it('NaN when either side is not finite', () => {
    expect(Number.isNaN(netBalance(Number.NaN, 1))).toBe(true);
    expect(Number.isNaN(netBalance(1, Infinity))).toBe(true);
  });
});

describe('buildIncomeExpense', () => {
  it('builds income, expense, net, counts and direction for the requested range', () => {
    expect(buildIncomeExpense(sales(1500.5), expenses(1000.25), RANGE)).toEqual({
      income: 1500.5, expense: 1000.25, net: 500.25, saleCount: 2, expenseCount: 3, direction: 'up' });
    expect(buildIncomeExpense(sales(100), expenses(250.1), RANGE)).toMatchObject({ net: -150.1, direction: 'down' });
    expect(buildIncomeExpense(sales(100), expenses(100), RANGE)).toMatchObject({ net: 0, direction: 'flat' });
  });
  it('one side missing -> null (never a balance from half the data)', () => {
    expect(buildIncomeExpense(null, expenses(100), RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(100), null, RANGE)).toBeNull();
    expect(buildIncomeExpense(undefined, undefined, RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(100), expenses(100), null)).toBeNull();
  });
  it('an answer of another range -> null, whichever side it is', () => {
    expect(buildIncomeExpense(sales(100, { dateFrom: '2026-10-01', dateTo: '2026-10-31' }), expenses(50), RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(100), expenses(50, { dateTo: '2026-11-29' }), RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(100, { dateFrom: '' }), expenses(50), RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(100), expenses(50), { dateFrom: '2026-11-01', dateTo: '2026-12-31' })).toBeNull();
  });
  it('a figure that is not finite -> null', () => {
    expect(buildIncomeExpense(sales(Number.NaN), expenses(50), RANGE)).toBeNull();
    expect(buildIncomeExpense(sales(10), expenses(Infinity), RANGE)).toBeNull();
  });
  it('does not mutate its inputs', () => {
    const s = sales(10); const e = expenses(5);
    const before = JSON.stringify([s, e]);
    buildIncomeExpense(s, e, RANGE);
    expect(JSON.stringify([s, e])).toBe(before);
  });
});

describe('formatSignedMoney', () => {
  it('shows the sign with the existing money format', () => {
    expect(formatSignedMoney(1000)).toBe('+$1,000.00');
    expect(formatSignedMoney(-250)).toBe('−$250.00');
    expect(formatSignedMoney(0)).toBe('$0.00');
    expect(formatSignedMoney(-0.004)).toBe('$0.00');
    expect(formatSignedMoney(0.2)).toBe('+$0.20');
    expect(formatSignedMoney(-1234567.89)).toBe('−$1,234,567.89');
  });
  it('"—" without a finite value', () => {
    for (const v of [null, undefined, Number.NaN, Infinity]) expect(formatSignedMoney(v)).toBe('—');
  });
});

describe('balanceAvailability', () => {
  const base = (o: Partial<BalanceAvailabilityInput> = {}): BalanceAvailabilityInput => ({
    scopeReady: true, salesLoading: false, expenseLoading: false, salesError: null, expenseError: null,
    sales: sales(1500), expense: expenses(1000), requested: RANGE, ...o });

  it('ready when both figures are present and match the requested range', () => {
    expect(balanceAvailability(base())).toEqual({ status: 'ready', reason: null });
  });
  it('empty when both periods have no sales and no expenses', () => {
    expect(balanceAvailability(base({ sales: sales(0), expense: expenses(0) }))).toEqual({ status: 'empty', reason: 'Sin ventas ni gastos en el periodo.' });
    expect(balanceAvailability(base({ sales: sales(0), expense: expenses(10) })).status).toBe('ready');
  });
  it('no plantation for the plantation scope: nothing was requested', () => {
    expect(balanceAvailability(base({ scopeReady: false, sales: null, expense: null })).status).toBe('no-scope');
  });
  it('loading while either call is pending, even if the other has failed', () => {
    expect(balanceAvailability(base({ salesLoading: true })).status).toBe('loading');
    expect(balanceAvailability(base({ expenseLoading: true, salesError: 'x', sales: null })).status).toBe('loading');
  });
  it('one side missing or failed: unavailable with the reason, never a balance', () => {
    expect(balanceAvailability(base({ sales: null, salesError: 'boom' }))).toEqual({ status: 'unavailable', reason: 'No se pudieron cargar las ventas.' });
    expect(balanceAvailability(base({ expense: null }))).toEqual({ status: 'unavailable', reason: 'No se pudieron cargar los gastos.' });
    expect(balanceAvailability(base({ expenseError: 'boom' })).reason).toBe('No se pudieron cargar los gastos.');
    expect(balanceAvailability(base({ salesError: 'boom' }))).toEqual({ status: 'unavailable', reason: 'No se pudieron cargar las ventas.' }); // a stale figure with an error is not used
    expect(balanceAvailability(base({ sales: null, expense: null, salesError: 'a', expenseError: 'b' })).reason).toBe('No se pudieron cargar las ventas ni los gastos.');
  });
  it('answers of another range: unavailable', () => {
    expect(balanceAvailability(base({ sales: sales(100, { dateFrom: '2026-10-01', dateTo: '2026-10-31' }) }))).toEqual({
      status: 'unavailable', reason: 'Las cifras no corresponden al mismo periodo.' });
    expect(balanceAvailability(base({ requested: null })).status).toBe('unavailable');
  });
});
