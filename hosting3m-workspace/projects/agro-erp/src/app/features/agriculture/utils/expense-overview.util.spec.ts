import { describe, expect, it } from 'vitest';
import type { ExpenseBalance } from '@core/models/agri-expense.model';
import { groupTopN } from '@shared/expenses-ui/expenses-ui.util';
import { categoryGroups, plantationGroups, planOverview } from './expense-overview.util';

const TODAY = '2026-11-09';

describe('planOverview', () => {
  it('month in progress: day grain, compared with the same elapsed days of the previous month', () => {
    const p = planOverview('MONTH', 'COMPANY', null, TODAY)!;
    expect(p.query).toMatchObject({ dateFrom: '2026-11-01', dateTo: '2026-11-30', grain: 'DAY', plantationId: null });
    expect(p.previous).toMatchObject({ dateFrom: '2026-10-01', dateTo: '2026-10-09', grain: 'DAY' });
    expect(p.company).toBeNull();
  });
  it('quarter and year in progress have no like-for-like cut: no previous request', () => {
    expect(planOverview('QUARTER', 'COMPANY', null, TODAY)).toMatchObject({ query: { grain: 'MONTH', dateFrom: '2026-10-01', dateTo: '2026-12-31' }, previous: null });
    expect(planOverview('YEAR', 'COMPANY', null, TODAY)).toMatchObject({ query: { grain: 'MONTH', dateFrom: '2026-01-01' }, previous: null });
    expect(planOverview('YEAR', 'COMPANY', null, TODAY)!.comparison).toEqual({ kind: 'in-progress' });
  });
  it('plantation scope passes the active plantation and also plans the company-wide query', () => {
    const p = planOverview('MONTH', 'PLANTATION', 'p1', TODAY)!;
    expect(p.query.plantationId).toBe('p1');
    expect(p.previous!.plantationId).toBe('p1');
    expect(p.company).toMatchObject({ plantationId: null, dateFrom: '2026-11-01', dateTo: '2026-11-30' });
  });
  it('plantation scope without an active plantation plans nothing (fail closed)', () => {
    expect(planOverview('MONTH', 'PLANTATION', null, TODAY)).toBeNull();
    expect(planOverview('MONTH', 'PLANTATION', '', TODAY)).toBeNull();
  });
});

const balance = (o: Partial<ExpenseBalance> = {}): ExpenseBalance => ({
  grain: 'DAY', dateFrom: '', dateTo: '', totalAmount: 0, expenseCount: 0, generalAmount: 0, byPeriod: [], byCategory: [], byPlantation: [], byLot: [], ...o });

describe('groups', () => {
  it('top 6 categories plus Otros; the rows add up to the total', () => {
    const byCategory = Array.from({ length: 9 }, (_, i) => ({ categoryId: 'c' + i, categoryCode: 'C' + i, categoryName: 'Cat ' + i, totalAmount: 100 - i * 5, expenseCount: 1 }));
    const rows = categoryGroups(balance({ byCategory }));
    expect(rows.length).toBe(7);
    expect(rows[6]).toMatchObject({ label: 'Otros', count: 3, amount: 70 + 65 + 60 });
    expect(rows.reduce((t, r) => t + r.amount, 0)).toBe(byCategory.reduce((t, c) => t + c.totalAmount, 0));
  });
  it('drops zero rows and handles a missing balance', () => {
    expect(categoryGroups(null)).toEqual([]);
    expect(groupTopN([{ key: 'a', label: 'A', amount: 0, count: 0 }], 6)).toEqual([]);
  });
  it('plantation rows keep the general row and sort by amount', () => {
    const rows = plantationGroups(balance({ byPlantation: [
      { plantationId: null, plantationCode: null, plantationName: null, totalAmount: 50, expenseCount: 1 },
      { plantationId: 'p1', plantationCode: 'P1', plantationName: 'Norte', totalAmount: 80, expenseCount: 2 }] }));
    expect(rows.map(r => r.label)).toEqual(['P1 · Norte', 'General (sin plantación)']);
  });
});
