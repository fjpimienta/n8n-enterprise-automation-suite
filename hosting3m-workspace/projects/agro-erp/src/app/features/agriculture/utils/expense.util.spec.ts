import { describe, expect, it } from 'vitest';
import type { AgriExpense, ExpenseCategory, ExpenseInput } from '@core/models/agri-expense.model';
import { friendlyGatewayError, todayCdmx } from './agri.util';
import {
  buildCategoryFields,
  buildExpenseFields,
  canCaptureExpense,
  canReadExpenses,
  categoryCodeFromName,
  emptyExpenseInput,
  expenseCsvColumns,
  expenseTabsFor,
  formatAmountInput,
  formatMoney,
  isoWeekNumber,
  parseAmountText,
  parseExpenseBalance,
  periodEndOf,
  periodLabel,
  reactivationConflict,
  snapRangeToGrain,
  truncToPeriod,
  validateBalanceRange,
  validateCategoryInput,
  validateExpenseInput,
  validateVoidReason,
} from './expense.util';

const TODAY = '2026-10-20';
const input = (o: Partial<ExpenseInput> = {}): ExpenseInput => ({
  ...emptyExpenseInput('plant-1', TODAY), categoryId: 'cat-1', amount: '1500', ...o,
});
const category = (o: Partial<ExpenseCategory>): ExpenseCategory => ({
  id: 'c', idCompany: 10, code: 'RIEGO', name: 'Riego', sortOrder: 100, isActive: true, ...o,
});

describe('visibility rules (role of the active company)', () => {
  it('capture: ADMIN, OWNER and EDITOR, case-insensitive; never CUSTOMER or no role', () => {
    expect(['ADMIN', 'OWNER', 'EDITOR', 'editor'].every(canCaptureExpense)).toBe(true);
    expect([null, undefined, '', 'CUSTOMER', 'GUEST'].some(canCaptureExpense)).toBe(false);
  });

  it('amounts, voiding and catalog: ADMIN and OWNER only', () => {
    expect(canReadExpenses('ADMIN')).toBe(true);
    expect(canReadExpenses('owner')).toBe(true);
    expect(canReadExpenses('EDITOR')).toBe(false);
    expect(canReadExpenses(null)).toBe(false);
  });

  it('tabs: the EDITOR gets none (capture only); ADMIN / OWNER get balance, list and catalog', () => {
    expect(expenseTabsFor('EDITOR')).toEqual([]);
    expect(expenseTabsFor('CUSTOMER')).toEqual([]);
    expect(expenseTabsFor('OWNER')).toEqual(['BALANCE', 'GASTOS', 'CATEGORIAS']);
  });
});

describe('parseAmountText', () => {
  it('accepts plain numbers, thousands commas, a leading $ and spaces', () => {
    expect(parseAmountText('10000', 2)).toBe(10000);
    expect(parseAmountText('10,000', 2)).toBe(10000);
    expect(parseAmountText(' $10,000.50 ', 2)).toBe(10000.5);
    expect(parseAmountText('1,234,567.89', 2)).toBe(1234567.89);
    expect(parseAmountText('10 000', 2)).toBe(10000);
    expect(parseAmountText('1500.5 MXN', 2)).toBe(1500.5);
  });

  it('empty -> null', () => {
    expect(parseAmountText('', 2)).toBeNull();
    expect(parseAmountText('   ', 2)).toBeNull();
    expect(parseAmountText(null, 2)).toBeNull();
    expect(parseAmountText(' $ ', 2)).toBeNull(); // only the sign: "Captura el monto
  });

  it('rejects a decimal comma, misplaced commas, negatives, letters and extra decimals (NaN)', () => {
    for (const bad of ['10,5', '1,50', '10,00,0', '-5', 'abc', '10.555', '1.2.3', ',']) {
      expect(parseAmountText(bad, 2), bad).toBeNaN();
    }
    expect(parseAmountText('1.234', 3)).toBe(1.234);
    expect(parseAmountText('1.2345', 3)).toBeNaN();
  });
});

describe('formatting', () => {
  it('money in pesos and the amount input with thousands separators', () => {
    expect(formatMoney(10000.5)).toBe('$10,000.50');
    expect(formatMoney(0)).toBe('$0.00');
    expect(formatMoney(null)).toBe('—');
    expect(formatAmountInput(1234567.8)).toBe('1,234,567.80');
  });
});

describe('todayCdmx (default expense date)', () => {
  it('uses America/Mexico_City, not UTC: 21 Oct 03:00 UTC is still 20 Oct in CDMX', () => {
    expect(todayCdmx(new Date('2026-10-21T03:00:00Z'))).toBe('2026-10-20');
    expect(todayCdmx(new Date('2026-10-21T06:00:00Z'))).toBe('2026-10-21');
    // What toISOString() would have proposed in the evening (the bug of the livestock modal).
    expect(new Date('2026-10-21T03:00:00Z').toISOString().slice(0, 10)).toBe('2026-10-21');
  });

  it('the new capture form starts on today and the active plantation', () => {
    expect(emptyExpenseInput('p-9', TODAY)).toMatchObject({ plantationId: 'p-9', lotId: '', expenseDate: TODAY, isInvoiced: false });
  });
});

describe('validateExpenseInput', () => {
  it('a complete expense passes', () => {
    expect(validateExpenseInput(input({ quantity: '1', unitCode: 'TON', isInvoiced: true, invoiceFolio: 'F-1' }), TODAY)).toBeNull();
  });

  it('category, date and amount are required; date never in the future (CDMX)', () => {
    expect(validateExpenseInput(input({ categoryId: '' }), TODAY)).toMatch(/categoría/);
    expect(validateExpenseInput(input({ expenseDate: '' }), TODAY)).toMatch(/fecha/);
    expect(validateExpenseInput(input({ expenseDate: '2026-10-21' }), TODAY)).toMatch(/futura/);
    expect(validateExpenseInput(input({ amount: '' }), TODAY)).toMatch(/Captura el monto/);
    expect(validateExpenseInput(input({ amount: '0' }), TODAY)).toMatch(/mayor que 0/);
    expect(validateExpenseInput(input({ amount: '10,5' }), TODAY)).toMatch(/2 decimales/);
    expect(validateExpenseInput(input({ amount: '10000000000' }), TODAY)).toMatch(/máximo/);
  });

  it('quantity and unit go together; quantity > 0 with up to 3 decimals', () => {
    expect(validateExpenseInput(input({ quantity: '2' }), TODAY)).toMatch(/van juntas/);
    expect(validateExpenseInput(input({ unitCode: 'KG' }), TODAY)).toMatch(/van juntas/);
    expect(validateExpenseInput(input({ quantity: '0', unitCode: 'KG' }), TODAY)).toMatch(/mayor que 0/);
    expect(validateExpenseInput(input({ quantity: '1.2345', unitCode: 'KG' }), TODAY)).toMatch(/3 decimales/);
  });

  it('a lot needs its plantation', () => {
    expect(validateExpenseInput(input({ plantationId: '', lotId: 'lot-1' }), TODAY)).toMatch(/plantación del lote/);
  });
});

describe('buildExpenseFields', () => {
  it('optional uuids go as null (never ""), the amount as a plain string without commas', () => {
    const f = buildExpenseFields(input({ plantationId: '', lotId: '', amount: '$10,000.5', supplierName: '  ', description: ' Papelería ' }));
    expect(f).toEqual({
      plantation_id: null, lot_id: null, category_id: 'cat-1', expense_date: TODAY, amount: '10000.50',
      quantity: null, unit_code: null, supplier_name: null, description: 'Papelería', is_invoiced: false, invoice_folio: null,
    });
    expect(Object.values(f)).not.toContain('');
  });

  it('lot and quantity / unit when given; folio only when invoiced; never an actor email', () => {
    const f = buildExpenseFields(input({ lotId: 'lot-1', quantity: '1,000', unitCode: 'KG', isInvoiced: true, invoiceFolio: ' A-77 ' }));
    expect(f).toMatchObject({ plantation_id: 'plant-1', lot_id: 'lot-1', quantity: '1000', unit_code: 'KG', invoice_folio: 'A-77' });
    expect(buildExpenseFields(input({ invoiceFolio: 'A-77' }))['invoice_folio']).toBeNull();
    expect(f).not.toHaveProperty('actor_email');
    expect(f).not.toHaveProperty('reported_by_email');
  });

  it('a general expense never sends a lot even if one was left selected', () => {
    expect(buildExpenseFields(input({ plantationId: '', lotId: 'lot-1' }))['lot_id']).toBeNull();
  });
});

describe('periods (same as date_trunc in SQL)', () => {
  it('truncates to day, ISO week (Monday), month and year', () => {
    expect(truncToPeriod('2026-10-22', 'DAY')).toBe('2026-10-22');
    expect(truncToPeriod('2026-10-25', 'WEEK')).toBe('2026-10-19'); // Sunday -> Monday before
    expect(truncToPeriod('2026-10-19', 'WEEK')).toBe('2026-10-19');
    expect(truncToPeriod('2026-10-22', 'MONTH')).toBe('2026-10-01');
    expect(truncToPeriod('2026-10-22', 'YEAR')).toBe('2026-01-01');
  });

  it('period ends, including February of a leap year', () => {
    expect(periodEndOf('2026-10-19', 'WEEK')).toBe('2026-10-25');
    expect(periodEndOf('2028-02-01', 'MONTH')).toBe('2028-02-29');
    expect(periodEndOf('2026-01-01', 'YEAR')).toBe('2026-12-31');
  });

  it('snaps a range to whole periods', () => {
    expect(snapRangeToGrain('2026-10-07', '2026-10-20', 'MONTH')).toEqual({ from: '2026-10-01', to: '2026-10-31' });
    expect(snapRangeToGrain('2026-10-21', '2026-10-21', 'WEEK')).toEqual({ from: '2026-10-19', to: '2026-10-25' });
    expect(snapRangeToGrain('2026-03-15', '2026-10-20', 'DAY')).toEqual({ from: '2026-03-15', to: '2026-10-20' });
  });

  it('validates like sp_agri_expense_balance', () => {
    expect(validateBalanceRange('2026-01-01', '2026-12-31', 'MONTH')).toBeNull();
    expect(validateBalanceRange('2026-02-01', '2026-01-01', 'DAY')).toMatch(/posterior/);
    expect(validateBalanceRange('2025-01-01', '2026-01-02', 'DAY')).toMatch(/366 días/);
    expect(validateBalanceRange('2025-01-01', '2025-12-31', 'DAY')).toBeNull();
    expect(validateBalanceRange('2016-01-01', '2026-01-01', 'YEAR')).toMatch(/10 años/);
    expect(validateBalanceRange('2016-01-01', '2025-12-31', 'YEAR')).toBeNull();
    expect(validateBalanceRange('2026-02-30', '2026-03-01', 'DAY')).toMatch(/fechas válidas/);
  });

  it('labels: ISO week number and Spanish month names', () => {
    expect(isoWeekNumber('2026-01-01')).toBe(1);
    expect(isoWeekNumber('2026-10-19')).toBe(43);
    expect(isoWeekNumber('2027-01-01')).toBe(53);
    expect(periodLabel('DAY', '2026-10-20', '2026-10-20')).toBe('20/10/2026');
    expect(periodLabel('WEEK', '2026-10-19', '2026-10-25')).toBe('Sem. 43 · 19/10–25/10/2026');
    expect(periodLabel('MONTH', '2026-10-01', '2026-10-31')).toBe('Octubre 2026');
    expect(periodLabel('YEAR', '2026-01-01', '2026-12-31')).toBe('2026');
  });
});

describe('parseExpenseBalance', () => {
  it('parses numbers that arrive as strings or numbers, and missing lists as empty', () => {
    const b = parseExpenseBalance({
      success: true, grain: 'MONTH', date_from: '2026-10-01', date_to: '2026-10-31',
      total_amount: '11500.50', expense_count: '3', general_amount: 1500.5,
      by_period: [{ period_start: '2026-10-01', period_end: '2026-10-31', total_amount: '11500.50', expense_count: 3 }],
      by_category: [{ category_id: 'c1', category_code: 'FERTILIZANTES', category_name: 'Fertilizantes', total_amount: 10000, expense_count: 1 }],
      by_plantation: [{ plantation_id: null, plantation_code: null, plantation_name: null, total_amount: '1500.50', expense_count: 1 }],
    });
    expect(b.totalAmount).toBe(11500.5);
    expect(b.expenseCount).toBe(3);
    expect(b.generalAmount).toBe(1500.5);
    expect(b.byPeriod[0]).toEqual({ periodStart: '2026-10-01', periodEnd: '2026-10-31', totalAmount: 11500.5, expenseCount: 3 });
    expect(b.byPlantation[0]).toMatchObject({ plantationId: null, totalAmount: 1500.5 });
    expect(b.byLot).toEqual([]);
  });
});

describe('category catalog', () => {
  const existing = [category({ id: 'a', code: 'RIEGO', name: 'Riego' }), category({ id: 'b', code: 'OTROS', name: 'Otros', isActive: false })];

  it('suggests a code from the name without accents', () => {
    expect(categoryCodeFromName('Servicios (dron/aspersión)')).toBe('SERVICIOS_DRON_ASPERSION');
    expect(categoryCodeFromName('  Mano de obra ')).toBe('MANO_DE_OBRA');
  });

  it('create: code format and uniqueness among active categories (code upper-cased)', () => {
    expect(validateCategoryInput({ code: 'riego', name: 'Riego 2', sortOrder: '' }, existing, null)).toMatch(/clave "RIEGO"/);
    expect(validateCategoryInput({ code: 'CON ESPACIO', name: 'X', sortOrder: '' }, existing, null)).toMatch(/guion bajo/);
    expect(validateCategoryInput({ code: 'OTROS', name: 'Otros', sortOrder: '10' }, existing, null)).toBeNull();
    expect(validateCategoryInput({ code: 'NUEVA', name: ' riego ', sortOrder: '' }, existing, null)).toMatch(/llamada/);
  });

  it('edit: the code is not validated (immutable) but the name stays unique', () => {
    expect(validateCategoryInput({ code: '', name: 'Riego tecnificado', sortOrder: '5' }, existing, 'a')).toBeNull();
    expect(validateCategoryInput({ code: '', name: 'Riego', sortOrder: 'x' }, existing, 'a')).toMatch(/orden/);
  });

  it('reactivation conflicts with an active category of the same code or name', () => {
    expect(reactivationConflict(category({ id: 'z', code: 'RIEGO', name: 'Viejo', isActive: false }), existing)).toMatch(/Riego/);
    expect(reactivationConflict(existing[1], existing)).toBeNull();
  });

  it('fields: create sends code, edit never does', () => {
    expect(buildCategoryFields({ code: 'qa_x', name: ' QA ', sortOrder: '' }, true))
      .toEqual({ category_name: 'QA', sort_order: 100, category_code: 'QA_X', is_active: true });
    expect(buildCategoryFields({ code: 'ignored', name: 'QA', sortOrder: '7' }, false)).toEqual({ category_name: 'QA', sort_order: 7 });
  });
});

describe('void and errors', () => {
  it('the void reason is mandatory', () => {
    expect(validateVoidReason('   ')).toMatch(/obligatorio/);
    expect(validateVoidReason('Duplicado')).toBeNull();
  });

  it('gateway errors seen in the LOCAL curl tests become Spanish; procedure messages pass through', () => {
    expect(friendlyGatewayError('invalid input syntax for type numeric: "10,000"')).toMatch(/formato numérico/);
    expect(friendlyGatewayError('invalid input syntax for type uuid: ""')).toMatch(/no es válido/);
    expect(friendlyGatewayError('duplicate key value violates unique constraint "uq_agri_expense_categories_code_active"')).toMatch(/clave/);
    expect(friendlyGatewayError('La fecha del gasto no puede ser futura.')).toBe('La fecha del gasto no puede ser futura.');
  });
});

describe('CSV', () => {
  it('expense rows: plain decimal amounts and Spanish labels', () => {
    const e = {
      expenseDate: '2026-10-20', plantationName: null, lotCode: null, categoryName: 'Riego', amount: 1500.5, quantity: null,
      unitCode: null, supplierName: null, description: 'x', isInvoiced: true, invoiceFolio: 'F-1', reportedByEmail: 'a@b.c',
      isVoid: true, voidReason: 'Duplicado',
    } as AgriExpense;
    const values = expenseCsvColumns().map(c => c.value(e));
    expect(values).toEqual(['2026-10-20', 'General (sin plantación)', '', 'Riego', '1500.50', '', '', '', 'x', 'Sí', 'F-1', 'a@b.c', 'Anulado', 'Duplicado']);
  });
});
