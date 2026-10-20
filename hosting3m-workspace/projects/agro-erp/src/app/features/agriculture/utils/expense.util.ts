/**
 * Pure rules of the palm expense screens (migration 081). They mirror the procedures so the user gets
 * feedback before the round-trip; the database enforces every one of them regardless. Totals are never
 * computed here: they come from sp_agri_expense_balance and vw_agri_expense_summary.
 */
import type {
  AgriExpense,
  CategoryInput,
  ExpenseBalance,
  ExpenseCategory,
  ExpenseGrain,
  ExpenseInput,
  ExpenseSummaryRow,
} from '@core/models/agri-expense.model';
import type { CsvColumn } from '@shared/utils/csv-export.util';
import { blankToNull, toInt, toNumber } from './agri.util';

// ---------------------------------------------------------------------------------------------------
// Roles (always the role of the ACTIVE company: tenantService.activeTenant()?.role, never the JWT role)
// ---------------------------------------------------------------------------------------------------

const CAPTURE_ROLES = new Set(['ADMIN', 'OWNER', 'EDITOR']);
const READ_ROLES = new Set(['ADMIN', 'OWNER']);

/** Capturing an expense is a field operation: ADMIN, OWNER and EDITOR (CUSTOMER is read-only). */
export function canCaptureExpense(role: string | null | undefined): boolean {
  return CAPTURE_ROLES.has((role ?? '').toUpperCase());
}

/** Amounts (list, balance, summary), voiding and the category catalog: ADMIN / OWNER only. */
export function canReadExpenses(role: string | null | undefined): boolean {
  return READ_ROLES.has((role ?? '').toUpperCase());
}

export type ExpenseTab = 'BALANCE' | 'GASTOS' | 'CATEGORIAS';

/** Tabs of the "Gastos" screen. The EDITOR gets none: only the capture. */
export function expenseTabsFor(role: string | null | undefined): ExpenseTab[] {
  return canReadExpenses(role) ? ['BALANCE', 'GASTOS', 'CATEGORIAS'] : [];
}

// ---------------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------------

export const MAX_AMOUNT = 9999999999.99;
export const MAX_QUANTITY = 999999999.999;

const GROUPED = /^\d{1,3}(,\d{3})+(\.\d+)?$/;
const PLAIN = /^\d+(\.\d+)?$/;

/**
 * Typed amount -> number. Accepts "$10,000.50", "10,000", "10000.5" and "10 000" (Mexican format: comma for
 * thousands, dot for decimals). '' -> null. Anything else (a decimal comma such as "10,5", negatives, more
 * decimals than allowed, letters) -> NaN, so the value never reaches the gateway with a comma (C5).
 */
export function parseAmountText(text: string | null | undefined, maxDecimals: number): number | null {
  let value = (text ?? '').trim().replace(/^\$/, '').replace(/\s*mxn$/i, '').replace(/\s+/g, '');
  if (value === '') return null;
  if (GROUPED.test(value)) value = value.replace(/,/g, '');
  else if (!PLAIN.test(value)) return NaN;
  const decimals = value.split('.')[1] ?? '';
  return decimals.length > maxDecimals ? NaN : Number(value);
}

const MONEY = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const AMOUNT = new Intl.NumberFormat('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** 10000.5 -> "$10,000.50" (display). */
export function formatMoney(value: number | null | undefined): string {
  return value === null || value === undefined || !Number.isFinite(value) ? '—' : MONEY.format(value);
}

/** 10000.5 -> "10,000.50" (what the amount input shows after leaving it). */
export function formatAmountInput(value: number): string {
  return AMOUNT.format(value);
}

// ---------------------------------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------------------------------

export function emptyExpenseInput(plantationId: string, today: string): ExpenseInput {
  return {
    plantationId, lotId: '', categoryId: '', expenseDate: today, amount: '', quantity: '', unitCode: '',
    supplierName: '', description: '', isInvoiced: false, invoiceFolio: '',
  };
}

/** Same rules as sp_agri_record_expense; `today` is America/Mexico_City (todayCdmx). */
export function validateExpenseInput(input: ExpenseInput, today: string): string | null {
  if (input.lotId && !input.plantationId) return 'Elige la plantación del lote.';
  if (!input.categoryId) return 'Elige la categoría del gasto.';
  if (!isValidIsoDate(input.expenseDate)) return 'Captura la fecha del gasto.';
  if (input.expenseDate > today) return 'La fecha del gasto no puede ser futura.';

  const amount = parseAmountText(input.amount, 2);
  if (amount === null) return 'Captura el monto del gasto.';
  if (Number.isNaN(amount)) return 'El monto debe ser un número con máximo 2 decimales (ej. 10,000.50).';
  if (amount <= 0) return 'El monto debe ser mayor que 0.';
  if (amount > MAX_AMOUNT) return 'El monto excede el máximo permitido.';

  const quantity = parseAmountText(input.quantity, 3);
  const unit = input.unitCode.trim();
  if ((quantity === null) !== (unit === '')) return 'La cantidad y la unidad de medida van juntas: captura ambas o ninguna.';
  if (quantity !== null && (Number.isNaN(quantity) || quantity <= 0 || quantity > MAX_QUANTITY)) {
    return 'La cantidad debe ser un número mayor que 0, con máximo 3 decimales.';
  }
  if (input.supplierName.trim().length > 150) return 'El proveedor no puede exceder 150 caracteres.';
  if (input.isInvoiced && input.invoiceFolio.trim().length > 60) return 'El folio de factura no puede exceder 60 caracteres.';
  return null;
}

/**
 * Capture form -> procedure fields. Optional uuids go as null (never '': C4), the amount as a plain decimal
 * string without commas (C5), and the folio only when the expense is invoiced. The actor email is never sent:
 * the gateway takes it from the verified JWT. Call only after validateExpenseInput returned null.
 */
export function buildExpenseFields(input: ExpenseInput): Record<string, unknown> {
  const plantationId = blankToNull(input.plantationId);
  const amount = parseAmountText(input.amount, 2) as number;
  const quantity = parseAmountText(input.quantity, 3);
  return {
    plantation_id: plantationId,
    lot_id: plantationId ? blankToNull(input.lotId) : null,
    category_id: input.categoryId,
    expense_date: input.expenseDate,
    amount: amount.toFixed(2),
    quantity: quantity === null ? null : String(quantity),
    unit_code: quantity === null ? null : blankToNull(input.unitCode),
    supplier_name: blankToNull(input.supplierName),
    description: blankToNull(input.description),
    is_invoiced: input.isInvoiced,
    invoice_folio: input.isInvoiced ? blankToNull(input.invoiceFolio) : null,
  };
}

export function validateVoidReason(reason: string): string | null {
  const text = reason.trim();
  if (!text) return 'El motivo de la anulación es obligatorio.';
  if (text.length > 500) return 'El motivo no puede exceder 500 caracteres.';
  return null;
}

// ---------------------------------------------------------------------------------------------------
// Dates and periods (pure YYYY-MM-DD arithmetic in UTC: no time zone drift)
// ---------------------------------------------------------------------------------------------------

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

function parseIsoDate(text: string): Date | null {
  const m = ISO_DATE.exec(text ?? '');
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = new Date(Date.UTC(y, mo - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === mo - 1 && date.getUTCDate() === d ? date : null;
}

const iso = (date: Date): string => date.toISOString().slice(0, 10);

export function isValidIsoDate(text: string): boolean {
  return parseIsoDate(text) !== null;
}

/** First day of the period that contains `date` (WEEK = ISO week, Monday). Same as date_trunc in SQL. */
export function truncToPeriod(date: string, grain: ExpenseGrain): string {
  const d = parseIsoDate(date);
  if (!d) return date;
  if (grain === 'WEEK') d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  if (grain === 'MONTH') d.setUTCDate(1);
  if (grain === 'YEAR') { d.setUTCMonth(0); d.setUTCDate(1); }
  return iso(d);
}

/** Last day of the period that starts at `start`. */
export function periodEndOf(start: string, grain: ExpenseGrain): string {
  const d = parseIsoDate(start);
  if (!d) return start;
  if (grain === 'WEEK') d.setUTCDate(d.getUTCDate() + 6);
  if (grain === 'MONTH') return iso(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)));
  if (grain === 'YEAR') return `${d.getUTCFullYear()}-12-31`;
  return iso(d);
}

/**
 * The balance always covers whole periods: the range is widened to the start of the first period and the
 * end of the last one, so the totals (sp_agri_expense_balance) and the detail (vw_agri_expense_summary, one
 * row per whole period) always agree. Future days add nothing: an expense is never in the future.
 */
export function snapRangeToGrain(from: string, to: string, grain: ExpenseGrain): { from: string; to: string } {
  return { from: truncToPeriod(from, grain), to: periodEndOf(truncToPeriod(to, grain), grain) };
}

function addYearsClamped(date: Date, years: number): Date {
  const y = date.getUTCFullYear() + years;
  const lastDay = new Date(Date.UTC(y, date.getUTCMonth() + 1, 0)).getUTCDate();
  return new Date(Date.UTC(y, date.getUTCMonth(), Math.min(date.getUTCDate(), lastDay)));
}

export const MAX_BALANCE_YEARS = 10;
export const MAX_DAY_SPAN = 366;

/** Same limits as sp_agri_expense_balance (checked on the snapped range). */
export function validateBalanceRange(from: string, to: string, grain: ExpenseGrain): string | null {
  const a = parseIsoDate(from);
  const b = parseIsoDate(to);
  if (!a || !b) return 'Captura fechas válidas para el periodo.';
  if (a > b) return 'La fecha inicial no puede ser posterior a la final.';
  if (b >= addYearsClamped(a, MAX_BALANCE_YEARS)) return `El rango máximo es de ${MAX_BALANCE_YEARS} años.`;
  const days = Math.round((b.getTime() - a.getTime()) / 86400000) + 1;
  if (grain === 'DAY' && days > MAX_DAY_SPAN) return `Por día, el rango máximo es de ${MAX_DAY_SPAN} días.`;
  return null;
}

const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/** ISO week number of a date (week 1 contains the first Thursday of the year). */
export function isoWeekNumber(date: string): number {
  const d = parseIsoDate(date);
  if (!d) return 0;
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = Date.UTC(d.getUTCFullYear(), 0, 1);
  return Math.ceil(((d.getTime() - yearStart) / 86400000 + 1) / 7);
}

const dmy = (date: string): string => `${date.slice(8, 10)}/${date.slice(5, 7)}/${date.slice(0, 4)}`;

/** Display label of a period: "20/10/2026", "Sem. 43 · 19/10–25/10/2026", "Octubre 2026", "2026". */
export function periodLabel(grain: ExpenseGrain, start: string, end: string): string {
  if (!isValidIsoDate(start)) return start;
  switch (grain) {
    case 'DAY': return dmy(start);
    case 'WEEK': return `Sem. ${isoWeekNumber(start)} · ${dmy(start).slice(0, 5)}–${dmy(end)}`;
    case 'MONTH': {
      const month = MONTHS[Number(start.slice(5, 7)) - 1];
      return `${month.charAt(0).toUpperCase()}${month.slice(1)} ${start.slice(0, 4)}`;
    }
    case 'YEAR': return start.slice(0, 4);
  }
}

// ---------------------------------------------------------------------------------------------------
// Balance (answer of sp_agri_expense_balance; numerics may arrive as numbers or strings)
// ---------------------------------------------------------------------------------------------------

type Rec = Record<string, unknown>;
const list = (value: unknown): Rec[] => (Array.isArray(value) ? value.filter((x): x is Rec => !!x && typeof x === 'object') : []);
const text = (value: unknown): string | null => (value === null || value === undefined ? null : String(value));
const money = (value: unknown): number => toNumber(value) ?? 0;

export function parseExpenseBalance(data: Rec): ExpenseBalance {
  return {
    grain: (text(data['grain']) ?? 'MONTH') as ExpenseGrain,
    dateFrom: text(data['date_from']) ?? '',
    dateTo: text(data['date_to']) ?? '',
    totalAmount: money(data['total_amount']),
    expenseCount: toInt(data['expense_count']),
    generalAmount: money(data['general_amount']),
    byPeriod: list(data['by_period']).map(p => ({
      periodStart: text(p['period_start']) ?? '', periodEnd: text(p['period_end']) ?? '',
      totalAmount: money(p['total_amount']), expenseCount: toInt(p['expense_count']),
    })),
    byCategory: list(data['by_category']).map(c => ({
      categoryId: text(c['category_id']) ?? '', categoryCode: text(c['category_code']) ?? '',
      categoryName: text(c['category_name']) ?? '', totalAmount: money(c['total_amount']), expenseCount: toInt(c['expense_count']),
    })),
    byPlantation: list(data['by_plantation']).map(p => ({
      plantationId: text(p['plantation_id']), plantationCode: text(p['plantation_code']),
      plantationName: text(p['plantation_name']), totalAmount: money(p['total_amount']), expenseCount: toInt(p['expense_count']),
    })),
    byLot: list(data['by_lot']).map(l => ({
      lotId: text(l['lot_id']) ?? '', lotCode: text(l['lot_code']) ?? '', lotName: text(l['lot_name']),
      plantationId: text(l['plantation_id']), totalAmount: money(l['total_amount']), expenseCount: toInt(l['expense_count']),
    })),
  };
}

// ---------------------------------------------------------------------------------------------------
// Category catalog
// ---------------------------------------------------------------------------------------------------

const CATEGORY_CODE = /^[A-Z0-9_]+$/;
const sameText = (a: string, b: string) => a.trim().toUpperCase() === b.trim().toUpperCase();

/** "Servicios (dron/aspersión)" -> "SERVICIOS_DRON_ASPERSION" (suggestion; the user may change it on creation). */
export function categoryCodeFromName(name: string): string {
  return (name ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
}

/** Validates against the ACTIVE categories of the company (unique code and name among active rows). */
export function validateCategoryInput(input: CategoryInput, existing: ExpenseCategory[], editingId: string | null): string | null {
  const name = input.name.trim();
  if (!name) return 'El nombre de la categoría es obligatorio.';
  if (name.length > 120) return 'El nombre no puede exceder 120 caracteres.';
  if (!editingId) {
    const code = input.code.trim().toUpperCase();
    if (!code) return 'La clave de la categoría es obligatoria.';
    if (code.length > 40) return 'La clave no puede exceder 40 caracteres.';
    if (!CATEGORY_CODE.test(code)) return 'La clave solo admite letras sin acento, números y guion bajo (ej. FERTILIZANTES).';
    if (existing.some(c => c.isActive && c.code === code)) return `Ya existe una categoría activa con la clave "${code}".`;
  }
  if (input.sortOrder.trim() !== '' && !/^\d{1,6}$/.test(input.sortOrder.trim())) return 'El orden debe ser un número entero de 0 a 999999.';
  const editing = existing.find(c => c.id === editingId);
  if (editing && !editing.isActive) return null;
  if (existing.some(c => c.isActive && c.id !== editingId && sameText(c.name, name))) return `Ya existe una categoría activa llamada "${name}".`;
  return null;
}

/** A category can be reactivated only if no other active category uses its code or name. */
export function reactivationConflict(category: ExpenseCategory, existing: ExpenseCategory[]): string | null {
  const other = existing.find(c => c.isActive && c.id !== category.id && (c.code === category.code || sameText(c.name, category.name)));
  return other ? `No se puede reactivar: la categoría activa "${other.name}" ya usa esa clave o ese nombre.` : null;
}

/** Create: code, name and order. Edit: name and order only (the code is immutable, P0082). */
export function buildCategoryFields(input: CategoryInput, isCreate: boolean): Record<string, unknown> {
  const fields: Record<string, unknown> = {
    category_name: input.name.trim(),
    sort_order: input.sortOrder.trim() === '' ? 100 : Number(input.sortOrder.trim()),
  };
  if (isCreate) {
    fields['category_code'] = input.code.trim().toUpperCase();
    fields['is_active'] = true;
  }
  return fields;
}

// ---------------------------------------------------------------------------------------------------
// CSV (amounts as plain decimals so spreadsheets read them as numbers)
// ---------------------------------------------------------------------------------------------------

const plainAmount = (value: number | null) => (value === null ? '' : value.toFixed(2));

export function expenseCsvColumns(): CsvColumn<AgriExpense>[] {
  return [
    { header: 'Fecha', value: e => e.expenseDate },
    { header: 'Plantación', value: e => e.plantationName ?? 'General (sin plantación)' },
    { header: 'Lote', value: e => e.lotCode ?? '' },
    { header: 'Categoría', value: e => e.categoryName },
    { header: 'Monto', value: e => plainAmount(e.amount) },
    { header: 'Cantidad', value: e => (e.quantity === null ? '' : String(e.quantity)) },
    { header: 'Unidad', value: e => e.unitCode ?? '' },
    { header: 'Proveedor', value: e => e.supplierName ?? '' },
    { header: 'Descripción', value: e => e.description ?? '' },
    { header: 'Facturado', value: e => (e.isInvoiced ? 'Sí' : 'No') },
    { header: 'Folio', value: e => e.invoiceFolio ?? '' },
    { header: 'Capturó', value: e => e.reportedByEmail },
    { header: 'Estado', value: e => (e.isVoid ? 'Anulado' : 'Vigente') },
    { header: 'Motivo de anulación', value: e => e.voidReason ?? '' },
  ];
}

export function summaryCsvColumns(): CsvColumn<ExpenseSummaryRow>[] {
  return [
    { header: 'Periodo', value: r => periodLabel(r.grain, r.periodStart, r.periodEnd) },
    { header: 'Inicio', value: r => r.periodStart },
    { header: 'Fin', value: r => r.periodEnd },
    { header: 'Plantación', value: r => r.plantationName ?? 'General (sin plantación)' },
    { header: 'Lote', value: r => r.lotCode ?? '' },
    { header: 'Categoría', value: r => r.categoryName },
    { header: 'Total', value: r => plainAmount(r.totalAmount) },
    { header: 'Gastos', value: r => String(r.expenseCount) },
  ];
}
