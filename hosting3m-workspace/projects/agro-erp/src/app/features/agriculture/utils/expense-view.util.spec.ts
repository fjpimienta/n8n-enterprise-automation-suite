import { describe, expect, it } from 'vitest';
import type { AgriExpense, ExpenseInput } from '@core/models/agri-expense.model';
import { emptyExpenseInput } from './expense.util';
import {
  addDays, averagePerDay, buildTrendBars, dateShortcutOf, daysInRange, deltaPercent, elapsedDays, filterExpenses,
  formatDelta, formatPercent, grainForSpan, isCaptureReady, previousRange, rangeForPreset, sharePercent, shortPeriodLabel,
} from './expense-view.util';

const expense = (o: Partial<AgriExpense> = {}): AgriExpense => ({
  id: '1', idCompany: 10, plantationId: null, plantationCode: null, plantationName: null, lotId: null, lotCode: null, lotName: null,
  categoryId: 'c1', categoryCode: 'FERT', categoryName: 'Fertilizantes', expenseDate: '2026-10-05', amount: 100, quantity: null,
  unitCode: null, unitName: null, supplierName: null, description: null, isInvoiced: false, invoiceFolio: null,
  reportedByEmail: 'a@example.test', isVoid: false, voidReason: null, voidedByEmail: null, voidedAt: null, createdAt: '', ...o,
});
const input = (o: Partial<ExpenseInput> = {}): ExpenseInput => ({ ...emptyExpenseInput('', '2026-10-20'), ...o });

describe('period ranges', () => {
  it('month view is the whole calendar month by day', () => {
    expect(rangeForPreset('MONTH', '2026-02-10')).toEqual({ from: '2026-02-01', to: '2026-02-28', grain: 'DAY' });
    expect(rangeForPreset('MONTH', '2028-02-10').to).toBe('2028-02-29');
  });
  it('quarter and year are grouped by month', () => {
    expect(rangeForPreset('QUARTER', '2026-11-09')).toEqual({ from: '2026-10-01', to: '2026-12-31', grain: 'MONTH' });
    expect(rangeForPreset('QUARTER', '2026-03-31')).toEqual({ from: '2026-01-01', to: '2026-03-31', grain: 'MONTH' });
    expect(rangeForPreset('YEAR', '2026-11-09')).toEqual({ from: '2026-01-01', to: '2026-12-31', grain: 'MONTH' });
  });
  it('previous range is the equivalent period before', () => {
    expect(previousRange('MONTH', { from: '2026-03-01', to: '2026-03-31' })).toEqual({ from: '2026-02-01', to: '2026-02-28' });
    expect(previousRange('MONTH', { from: '2026-01-01', to: '2026-01-31' })).toEqual({ from: '2025-12-01', to: '2025-12-31' });
    expect(previousRange('QUARTER', { from: '2026-01-01', to: '2026-03-31' })).toEqual({ from: '2025-10-01', to: '2025-12-31' });
    expect(previousRange('QUARTER', { from: '2026-10-01', to: '2026-12-31' })).toEqual({ from: '2026-07-01', to: '2026-09-30' });
    expect(previousRange('YEAR', { from: '2026-01-01', to: '2026-12-31' })).toEqual({ from: '2025-01-01', to: '2025-12-31' });
  });
  it('custom previous range has the same length and ends the day before', () => {
    expect(previousRange('CUSTOM', { from: '2026-10-10', to: '2026-10-19' })).toEqual({ from: '2026-09-30', to: '2026-10-09' });
  });
  it('counts days, inclusive, and cuts at today', () => {
    expect(daysInRange('2026-10-01', '2026-10-31')).toBe(31);
    expect(daysInRange('2026-10-31', '2026-10-01')).toBe(0);
    expect(daysInRange('nope', '2026-10-01')).toBe(0);
    expect(elapsedDays({ from: '2026-10-01', to: '2026-10-31' }, '2026-10-20')).toBe(20);
    expect(elapsedDays({ from: '2026-09-01', to: '2026-09-30' }, '2026-10-20')).toBe(30);
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });
  it('picks a grain for a free range', () => {
    expect(grainForSpan('2026-10-01', '2026-10-31')).toBe('DAY');
    expect(grainForSpan('2026-01-01', '2026-12-31')).toBe('MONTH');
    expect(grainForSpan('2010-01-01', '2026-12-31')).toBe('YEAR');
  });
});

describe('derivations and formatting', () => {
  it('average per day', () => {
    expect(averagePerDay(3000, 30)).toBe(100);
    expect(averagePerDay(3000, 0)).toBeNull();
  });
  it('share', () => {
    expect(sharePercent(25, 100)).toBe(25);
    expect(sharePercent(5, 0)).toBe(0);
    expect(formatPercent(33.333)).toBe('33.3%');
    expect(formatPercent(null)).toBe('—');
  });
  it('delta vs. previous period', () => {
    expect(deltaPercent(120, 100)).toBe(20);
    expect(deltaPercent(80, 100)).toBe(-20);
    expect(deltaPercent(80, 0)).toBeNull();
    expect(deltaPercent(80, null)).toBeNull();
    expect(formatDelta(20)).toBe('+20%');
    expect(formatDelta(-8.26)).toBe('−8.3%');
    expect(formatDelta(0)).toBe('0%');
    expect(formatDelta(null)).toBe('');
  });
});

describe('trend bars', () => {
  const periods = [
    { periodStart: '2026-10-01', periodEnd: '2026-10-01', totalAmount: 50, expenseCount: 1 },
    { periodStart: '2026-10-02', periodEnd: '2026-10-02', totalAmount: 200, expenseCount: 2 },
    { periodStart: '2026-10-03', periodEnd: '2026-10-03', totalAmount: 0, expenseCount: 0 },
  ];
  it('scales to the largest value, flags the period in progress and carries a text value', () => {
    const bars = buildTrendBars(periods, 'DAY', '2026-10-02', v => `$${v}`);
    expect(bars.map(b => b.heightPct)).toEqual([25, 100, 0]);
    expect(bars.map(b => b.inProgress)).toEqual([false, true, false]);
    expect(bars[1].valueText).toBe('$200');
  });
  it('all zero gives empty bars', () => {
    expect(buildTrendBars([periods[2]], 'DAY', '2026-10-03', String)[0].heightPct).toBe(0);
  });
  it('short labels', () => {
    expect(shortPeriodLabel('DAY', '2026-10-05')).toBe('5');
    expect(shortPeriodLabel('MONTH', '2026-10-01')).toBe('oct');
    expect(shortPeriodLabel('YEAR', '2026-01-01')).toBe('2026');
  });
});

describe('list filter', () => {
  const rows = [
    expense({ id: '1', description: 'Urea 20 bultos', supplierName: 'Agro Peña' }),
    expense({ id: '2', categoryId: 'c2', categoryName: 'Combustible', description: 'Diésel', isVoid: true }),
    expense({ id: '3', categoryId: 'c2', categoryName: 'Combustible', invoiceFolio: 'F-123' }),
  ];
  const base = { search: '', categoryId: '', showVoided: true };
  it('filters by category chip', () => {
    expect(filterExpenses(rows, { ...base, categoryId: 'c2' }).map(e => e.id)).toEqual(['2', '3']);
  });
  it('hides voided unless asked', () => {
    expect(filterExpenses(rows, { ...base, showVoided: false }).map(e => e.id)).toEqual(['1', '3']);
  });
  it('searches concept, supplier and folio ignoring case and accents', () => {
    expect(filterExpenses(rows, { ...base, search: 'UREA' }).map(e => e.id)).toEqual(['1']);
    expect(filterExpenses(rows, { ...base, search: 'pena' }).map(e => e.id)).toEqual(['1']);
    expect(filterExpenses(rows, { ...base, search: 'f-123' }).map(e => e.id)).toEqual(['3']);
    expect(filterExpenses(rows, { ...base, search: 'zzz' })).toEqual([]);
  });
  it('combines filters', () => {
    expect(filterExpenses(rows, { search: 'diesel', categoryId: 'c2', showVoided: false })).toEqual([]);
  });
});

describe('capture', () => {
  it('is ready only with a valid amount and a category', () => {
    expect(isCaptureReady(input())).toBe(false);
    expect(isCaptureReady(input({ categoryId: 'c1' }))).toBe(false);
    expect(isCaptureReady(input({ amount: '100' }))).toBe(false);
    expect(isCaptureReady(input({ categoryId: 'c1', amount: '1,250.50' }))).toBe(true);
    expect(isCaptureReady(input({ categoryId: 'c1', amount: '0' }))).toBe(false);
    expect(isCaptureReady(input({ categoryId: 'c1', amount: '10,5' }))).toBe(false);
    expect(isCaptureReady(input({ categoryId: 'c1', amount: '99999999999' }))).toBe(false);
  });
  it('detects the date shortcut', () => {
    expect(dateShortcutOf('2026-10-20', '2026-10-20')).toBe('TODAY');
    expect(dateShortcutOf('2026-10-19', '2026-10-20')).toBe('YESTERDAY');
    expect(dateShortcutOf('2026-10-01', '2026-10-20')).toBe('OTHER');
  });
});
