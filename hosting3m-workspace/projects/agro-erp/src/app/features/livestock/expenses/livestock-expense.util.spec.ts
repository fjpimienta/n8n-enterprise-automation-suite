import { describe, expect, it } from 'vitest';
import { isActiveHead, valuedBiomassKg } from '@shared/utils/herd-status.util';
import { mortalityLoss } from './livestock-result.util';
import type { Expense } from '../models/expense.model';
import type { Livestock } from '../models/livestock.model';
import {
  RISK_MARGIN_PCT, REFERENCE_PRICE_PER_KG, amountOf, animalCosts, categoryChipOptions, categoryKey, categoryLabel, groupLabel, normalizeCategory,
  comparisonLabel, expenseDay, filterByRange, filterHistory, herdValue, isAtRisk, isGeneralExpense, netBalance, perHead, periodView,
  previousCut, sortAnimalCosts, spendByType, spendDelta, spendTrend, sumAmount, uppBalance,
} from './livestock-expense.util';

const exp = (o: Partial<Expense> = {}): Expense => ({ id: 'e' + Math.random(), expense_date: '2026-11-05', category: 'ALIMENTACION', amount: 100, ...o });
const cow = (o: Partial<Livestock> = {}): Livestock => ({
  id: 'a1', business_model: 'CRIA', category: 'VACA', current_weight_kg: 400, rfid_siniiga: '0700000001', numero_fuego: 'F1',
  production_unit_id: 'u1', upp_code: 'UPP-1', ...o });
const P = 10; // price used by the tests

describe('categories', () => {
  it('normalizes accents, case and spaces', () => {
    expect(normalizeCategory('  Alimentación   Mixta ')).toBe('ALIMENTACION MIXTA');
    expect(normalizeCategory(undefined)).toBe('');
    expect(categoryKey(' medicina ')).toBe('MEDICINA');
  });
  it('maps only the obvious aliases to ALIMENTACION', () => {
    expect(categoryKey('ALIMENTO')).toBe('ALIMENTACION');
    expect(categoryKey('alimentos')).toBe('ALIMENTACION');
    expect(categoryKey('FORRAJE')).toBe('FORRAJE');
  });
  it('labels the four known keys and shows other values as received', () => {
    expect(categoryLabel('ALIMENTACION')).toBe('Alimentación');
    expect(categoryLabel(' medicina ')).toBe('Medicina y sanidad');
    expect(categoryLabel('SUPLEMENTOS')).toBe('Suplementos');
    expect(categoryLabel('MANEJO')).toBe('Manejo y fletes');
    expect(categoryLabel('Herrajes  nuevos')).toBe('Herrajes nuevos');
    expect(groupLabel('HERRAJES NUEVOS', 'HERRAJES NUEVOS')).toBe('Herrajes nuevos');
  });
  it('treats an empty or missing category as "Sin categoría", not "Otros"', () => {
    expect(categoryKey('')).toBe('SIN_CATEGORIA');
    expect(categoryKey(null)).toBe('SIN_CATEGORIA');
    expect(categoryLabel(undefined)).toBe('Sin categoría');
    expect(groupLabel('SIN_CATEGORIA')).toBe('Sin categoría');
  });
});

describe('amounts and dates', () => {
  it('parses string amounts and ignores garbage', () => {
    expect(amountOf(exp({ amount: '1250.5' as unknown as number }))).toBe(1250.5);
    expect(amountOf(exp({ amount: 'x' as unknown as number }))).toBe(0);
    expect(sumAmount([exp({ amount: '10' as unknown as number }), exp({ amount: 5 })])).toBe(15);
  });
  it('takes the date part of timestamps and filters by inclusive range with open bounds', () => {
    expect(expenseDay(exp({ expense_date: '2026-11-05T18:00:00.000Z' }))).toBe('2026-11-05');
    const list = [exp({ expense_date: '2026-10-31' }), exp({ expense_date: '2026-11-01T00:00:00Z' }), exp({ expense_date: '2026-11-30' }), exp({ expense_date: '2026-12-01' })];
    expect(filterByRange(list, '2026-11-01', '2026-11-30').length).toBe(2);
    expect(filterByRange(list, '', '2026-10-31').length).toBe(1);
    expect(filterByRange(list, '2026-12-01', '').length).toBe(1);
    expect(filterByRange(list, '', '').length).toBe(4);
  });
});

describe('period and like-for-like cut', () => {
  it('month in progress: same elapsed days of the previous month', () => {
    const v = periodView('MONTH', '2026-11-09');
    expect(v.inProgress).toBe(true);
    expect(previousCut('MONTH', v.range, '2026-11-09')).toEqual({ from: '2026-10-01', to: '2026-10-09' });
  });
  it('month in progress with a shorter previous month is capped at its last day', () => {
    const v = periodView('MONTH', '2026-03-31');
    expect(previousCut('MONTH', v.range, '2026-03-31')).toEqual({ from: '2026-02-01', to: '2026-02-28' });
  });
  it('quarter and year in progress are cut by elapsed days too', () => {
    // Q4 started 2026-10-01; on 2026-11-09 40 days elapsed -> Q3 from 2026-07-01 for 40 days
    const q = periodView('QUARTER', '2026-11-09');
    expect(previousCut('QUARTER', q.range, '2026-11-09')).toEqual({ from: '2026-07-01', to: '2026-08-09' });
    const y = periodView('YEAR', '2026-11-09');
    expect(previousCut('YEAR', y.range, '2026-11-09')).toEqual({ from: '2025-01-01', to: '2025-11-09' });
  });
  it('year cut on a leap day stays inside the previous year', () => {
    const y = periodView('YEAR', '2028-12-31'); // 366 elapsed days vs a 365-day previous year
    expect(previousCut('YEAR', y.range, '2028-12-31')).toEqual({ from: '2027-01-01', to: '2027-12-31' });
  });
  it('a closed period compares with the whole previous period', () => {
    const closed = { from: '2026-09-01', to: '2026-09-30' };
    expect(previousCut('MONTH', closed, '2026-11-09')).toEqual({ from: '2026-08-01', to: '2026-08-31' });
  });
  it('labels what is compared', () => {
    expect(comparisonLabel('MONTH', true)).toBe('vs. mismos días del mes anterior');
    expect(comparisonLabel('QUARTER', true)).toBe('vs. mismos días del periodo anterior');
    expect(comparisonLabel('YEAR', false)).toBe('vs. periodo anterior');
  });
  it('computes the delta only between equal cuts', () => {
    const list = [
      exp({ expense_date: '2026-11-03', amount: 300 }), exp({ expense_date: '2026-11-20', amount: 999 }), // future day: not counted as elapsed
      exp({ expense_date: '2026-10-05', amount: 200 }), exp({ expense_date: '2026-10-25', amount: 5000 }), // after day 9: outside the cut
    ];
    const r = spendDelta(list, 'MONTH', '2026-11-09');
    expect(r.previous).toBe(200);
    expect(r.current).toBe(300 + 999); // the whole current range is summed; only past rows exist in real data
    expect(r.delta).toBeCloseTo(((1299 - 200) / 200) * 100);
  });
  it('has no delta when the previous cut is empty', () => {
    expect(spendDelta([exp({ expense_date: '2026-11-03' })], 'MONTH', '2026-11-09').delta).toBeNull();
  });
});

describe('trend', () => {
  it('month view: one zero-filled bucket per day', () => {
    const t = spendTrend([exp({ expense_date: '2026-11-02', amount: 10 }), exp({ expense_date: '2026-11-02', amount: 5 })], { from: '2026-11-01', to: '2026-11-30' }, 'DAY');
    expect(t.length).toBe(30);
    expect(t[1]).toEqual({ periodStart: '2026-11-02', periodEnd: '2026-11-02', totalAmount: 15 });
    expect(t[0].totalAmount).toBe(0);
  });
  it('quarter / year view: one bucket per month with its last day', () => {
    const t = spendTrend([exp({ expense_date: '2026-02-10', amount: 7 })], { from: '2026-01-01', to: '2026-12-31' }, 'MONTH');
    expect(t.length).toBe(12);
    expect(t[1]).toEqual({ periodStart: '2026-02-01', periodEnd: '2026-02-28', totalAmount: 7 });
    expect(t[11].periodEnd).toBe('2026-12-31');
  });
});

describe('by type', () => {
  it('groups by normalized key, merges aliases and sorts by amount', () => {
    const rows = spendByType([exp({ category: 'MEDICINA', amount: 50 }), exp({ category: 'Herrajes', amount: 30 }), exp({ category: '', amount: 20 }), exp({ category: 'ALIMENTO', amount: 10 }), exp({ category: 'Alimentación', amount: 5 })]);
    expect(rows.map(r => [r.label, r.amount, r.count])).toEqual([['Medicina y sanidad', 50, 1], ['Herrajes', 30, 1], ['Sin categoría', 20, 1], ['Alimentación', 15, 2]]);
  });
  it('lists at most 6 groups and sums the rest into Otros with its count', () => {
    const list = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'].map((c, i) => exp({ category: c, amount: 100 - i * 10 }));
    list.push(exp({ category: 'H', amount: 5 }));
    const rows = spendByType(list);
    expect(rows.map(r => r.label)).toEqual(['A', 'B', 'C', 'D', 'E', 'F', 'Otros']);
    expect(rows[6]).toMatchObject({ amount: 40 + 30 + 5, count: 3 });
  });
  it('keeps the invariant: the groups add up to all the expenses', () => {
    const list = Array.from({ length: 12 }, (_, i) => exp({ category: i % 3 === 0 ? '' : `CAT${i}`, amount: 10 + i }));
    expect(spendByType(list).reduce((t, r) => t + r.amount, 0)).toBe(sumAmount(list));
    expect(spendByType(list).reduce((t, r) => t + r.count, 0)).toBe(list.length);
  });
});

describe('herd value and per head', () => {
  it('values weight x price and ignores animals without weight', () => {
    expect(herdValue([cow({ current_weight_kg: 100 }), cow({ id: 'a2', current_weight_kg: 0 }), cow({ id: 'a3', current_weight_kg: undefined })], P)).toBe(1000);
    expect(REFERENCE_PRICE_PER_KG).toBe(65);
  });
  it('per head needs heads', () => {
    expect(perHead(300, 3)).toBe(100);
    expect(perHead(300, 0)).toBeNull();
  });
});

describe('balance by UPP', () => {
  const cattle = [
    cow({ id: 'a1', current_weight_kg: 100 }),
    cow({ id: 'a2', current_weight_kg: 200 }),
    cow({ id: 'a3', current_weight_kg: 50, production_unit_id: null, upp_code: null }), // no UPP
    cow({ id: 'a4', current_weight_kg: 10, upp_code: 'UPP-2', production_unit_id: 'u2' }),
  ];
  const expenses = [
    exp({ livestock_id: 'a1', amount: 100 }),
    exp({ livestock_id: 'a3', amount: 40 }),   // animal without UPP -> general
    exp({ amount: 60 }),                        // no animal -> general
    exp({ livestock_id: 'ghost', amount: 5 }),  // animal out of scope -> general
  ];
  const rows = uppBalance(cattle, expenses, P);
  it('groups heads, value and spend per UPP, with "none" and "general" rows', () => {
    const upp1 = rows.find(r => r.label === 'UPP-1')!;
    expect(upp1).toMatchObject({ kind: 'upp', heads: 2, value: 3000, spend: 100, balance: 2900 });
    expect(upp1.spendOverValuePct).toBeCloseTo(100 / 3000 * 100);
    expect(rows.find(r => r.kind === 'none')).toMatchObject({ label: 'Sin UPP asignada', heads: 1, value: 500, spend: 0 });
    expect(rows.find(r => r.kind === 'general')).toMatchObject({ label: 'Gastos generales', spend: 105, value: 0, spendOverValuePct: null });
  });
  it('net balance is herd value minus all the spend', () => {
    expect(netBalance(rows)).toBe(herdValue(cattle, P) - sumAmount(expenses));
  });
  it('has no general row without general spend', () => {
    expect(uppBalance([cow()], [exp({ livestock_id: 'a1' })], P).some(r => r.kind === 'general')).toBe(false);
  });
});

describe('risk flag', () => {
  it(`flags a balance below ${RISK_MARGIN_PCT}% of the value, negatives included`, () => {
    expect(isAtRisk(1000, 99)).toBe(true);
    expect(isAtRisk(1000, 100)).toBe(false);
    expect(isAtRisk(1000, 500)).toBe(false);
    expect(isAtRisk(1000, -1)).toBe(true);
  });
  it('never flags an animal without weight', () => {
    expect(isAtRisk(null, null)).toBe(false);
    expect(isAtRisk(0, -50)).toBe(false);
  });
});

describe('cost per animal', () => {
  const lookup = [cow({ id: 'a1', current_weight_kg: 100 }), cow({ id: 'a2', current_weight_kg: 0, rfid_siniiga: '0700000002' }), cow({ id: 'a3', current_weight_kg: 10, production_unit_id: null, upp_code: null })];
  const expenses = [exp({ livestock_id: 'a1', amount: 950 }), exp({ livestock_id: 'a1', amount: 10 }), exp({ livestock_id: 'a2', amount: 500 }), exp({ livestock_id: 'a3', amount: 1 }), exp({ livestock_id: 'zz', amount: 7 }), exp({ amount: 99 })];
  const rows = animalCosts(expenses, lookup, P);
  it('groups only expenses linked to an animal', () => {
    expect(rows.length).toBe(4);
    expect(rows.find(r => r.livestockId === 'a1')).toMatchObject({ total: 960, count: 2, weightKg: 100, value: 1000, balance: 40, costPerKg: 9.6, atRisk: true, upp: 'UPP-1' });
  });
  it('without weight: no value, no cost per kg, not at risk', () => {
    expect(rows.find(r => r.livestockId === 'a2')).toMatchObject({ hasWeight: false, value: null, balance: null, costPerKg: null, atRisk: false });
  });
  it('animal without UPP and unknown animal do not break', () => {
    expect(rows.find(r => r.livestockId === 'a3')!.upp).toBe('');
    expect(rows.find(r => r.livestockId === 'zz')).toMatchObject({ arete: 'Desconocido', hasWeight: false });
  });
  it('sorts by spend or by worst balance (no weight last)', () => {
    expect(sortAnimalCosts(rows, 'SPEND').map(r => r.livestockId)).toEqual(['a1', 'a2', 'zz', 'a3']);
    expect(sortAnimalCosts(rows, 'WORST_BALANCE').map(r => r.livestockId)).toEqual(['a1', 'a3', 'a2', 'zz']); // balances: a1 40, a3 99
  });
});

describe('history', () => {
  const cattle = [cow({ id: 'a1' }), cow({ id: 'a3', rfid_siniiga: '0700000003', numero_fuego: 'F3', production_unit_id: null, upp_code: null })];
  const list = [
    exp({ id: '1', expense_date: '2026-11-01', description: 'Pastura', livestock_id: 'a1', category: 'ALIMENTACION' }),
    exp({ id: '2', expense_date: '2026-11-03', description: 'Vacuna', category: 'MEDICINA' }),
    exp({ id: '3', expense_date: '2026-11-02', description: 'Flete', category: 'HERRAJES', livestock_id: 'a3' }),
  ];
  const base = { search: '', categoryKey: '', from: '', to: '', onlyGeneral: false };
  it('sorts newest first', () => {
    expect(filterHistory(list, base, cattle, cattle).map(e => e.id)).toEqual(['2', '3', '1']);
  });
  it('searches concept, category as received, arete and fuego, ignoring accents', () => {
    expect(filterHistory(list, { ...base, search: 'VACUNA' }, cattle, cattle).map(e => e.id)).toEqual(['2']);
    expect(filterHistory(list, { ...base, search: 'herrajes' }, cattle, cattle).map(e => e.id)).toEqual(['3']);
    expect(filterHistory(list, { ...base, search: '0700000001' }, cattle, cattle).map(e => e.id)).toEqual(['1']);
    expect(filterHistory(list, { ...base, search: 'f1' }, cattle, cattle).map(e => e.id)).toEqual(['1']);
    expect(filterHistory(list, { ...base, search: 'f3' }, cattle, cattle).map(e => e.id)).toEqual(['3']);
    expect(filterHistory(list, { ...base, search: 'alimentacion' }, cattle, cattle).map(e => e.id)).toEqual(['1']);
  });
  it('filters by category chip (Otros for legacy values), range and general-only', () => {
    expect(filterHistory(list, { ...base, categoryKey: 'HERRAJES' }, cattle, cattle).map(e => e.id)).toEqual(['3']);
    expect(filterHistory(list, { ...base, from: '2026-11-02', to: '2026-11-02' }, cattle, cattle).map(e => e.id)).toEqual(['3']);
    expect(filterHistory(list, { ...base, onlyGeneral: true }, cattle, cattle).map(e => e.id)).toEqual(['2', '3']);
    expect(isGeneralExpense(list[0], cattle)).toBe(false);
  });
  it('builds the chips from the categories that exist and adds Otros only beyond 8', () => {
    expect(categoryChipOptions(list).map(o => o.value).sort()).toEqual(['ALIMENTACION', 'HERRAJES', 'MEDICINA']);
    const many = Array.from({ length: 10 }, (_, i) => exp({ id: 'm' + i, category: `C${i}`, amount: 100 - i }));
    const chips = categoryChipOptions(many);
    expect(chips.length).toBe(9);
    expect(chips[8]).toEqual({ value: 'OTROS', label: 'Otros' });
    // "Otros" reaches the categories without their own chip
    expect(filterHistory(many, { ...base, categoryKey: 'OTROS' }, [], []).map(e => e.id).sort()).toEqual(['m8', 'm9']);
  });
});

describe('deceased animals (BAJA_MORTANDAD) and the estimated herd value', () => {
  const alive = cow({ id: 'a1', current_weight_kg: 100 });
  const dead = cow({ id: 'a2', current_weight_kg: 300, current_status: 'BAJA_MORTANDAD' });
  const deadNoWeight = cow({ id: 'a3', current_weight_kg: 0, current_status: ' baja_mortandad ' });
  const deadList = [alive, dead, deadNoWeight];

  it('herdValue excludes them, with and without weight', () => {
    expect(herdValue(deadList, P)).toBe(1000);
    expect(herdValue([dead], P)).toBe(0);
    expect(herdValue([alive, dead], P)).toBe(herdValue([alive], P));
    expect(herdValue([alive, dead], P)).toBe(herdValue([alive, { ...dead, current_status: 'ACTIVO' }], P) - 300 * P);
  });
  it('uppBalance excludes their value but keeps the head counts', () => {
    const row = uppBalance(deadList, [], P).find(r => r.label === 'UPP-1')!;
    expect(row).toMatchObject({ heads: 3, value: 1000, spend: 0, balance: 1000 });
    expect(netBalance(uppBalance(deadList, [exp({ amount: 40 })], P))).toBe(herdValue(deadList, P) - 40);
  });
  it('the dashboard biomass x price equals the summary herd value for the same list', () => {
    expect(valuedBiomassKg(deadList)).toBe(100);
    expect(valuedBiomassKg(deadList) * P).toBe(herdValue(deadList, P));
    expect(valuedBiomassKg([{ current_status: 'ACTIVO', current_weight_kg: '250' }, { current_status: 'VENDIDO', current_weight_kg: 90 }, { current_weight_kg: 'x' }])).toBe(250);
    expect(valuedBiomassKg([dead])).toBe(0);
  });
  it('keeps counting them as heads and keeps the mortality loss', () => {
    expect(isActiveHead(dead)).toBe(true);
    expect(deadList.filter(isActiveHead).length).toBe(3);
    expect(mortalityLoss([dead, deadNoWeight], P)).toEqual({ count: 2, estimatedLoss: 3000, withoutWeight: 1 });
  });
});
