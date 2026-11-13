/**
 * Pure rules of the income-vs-expense block of the palm dashboard. Both figures are totals that the database already
 * computed (sp_agri_sales_balance and sp_agri_expense_balance); the only arithmetic done here is ONE subtraction, in integer
 * cents. A balance exists only when both figures are present and both answers describe exactly the requested range, so it
 * is never built from half of the data or from answers of different selections.
 */
import type { ExpenseBalance } from '@core/models/agri-expense.model';
import type { SaleBalance } from '@core/models/agri-sale.model';
import { formatMoney } from '@shared/expenses-ui/expenses-ui.util';

export type BalanceDirection = 'up' | 'down' | 'flat';

/** The range the screen asked for (the same dates were sent to both procedures). */
export interface RequestedRange {
  dateFrom: string;
  dateTo: string;
}

export interface IncomeExpense {
  /** Sales total (CFDI total, taxes included). */
  income: number;
  /** Expense total (amount as captured). */
  expense: number;
  /** income - expense, with 2 decimals. */
  net: number;
  saleCount: number;
  expenseCount: number;
  direction: BalanceDirection;
}

/** Money with at most 2 decimals -> integer cents. NaN for a value that is not finite. */
export function toCents(value: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return Number.NaN;
  // toPrecision first: 1.005 * 100 is 100.49999999999999 in binary floating point.
  return Math.round(Number((value * 100).toPrecision(15)));
}

export function fromCents(cents: number): number {
  return Number.isFinite(cents) ? cents / 100 : Number.NaN;
}

/** income - expense computed in integer cents (0.30 - 0.10 is 0.2, not 0.19999999999999998). NaN if either is not finite. */
export function netBalance(income: number, expense: number): number {
  const cents = toCents(income) - toCents(expense);
  return Number.isNaN(cents) ? Number.NaN : fromCents(cents);
}

const directionOf = (net: number): BalanceDirection => (net > 0 ? 'up' : net < 0 ? 'down' : 'flat');

const sameRange = (answer: { dateFrom: string; dateTo: string }, requested: RequestedRange): boolean =>
  answer.dateFrom === requested.dateFrom && answer.dateTo === requested.dateTo;

/**
 * The balance of one selection, or null when it cannot be trusted: a figure missing, a figure that is not finite, no requested
 * range, or an answer whose date_from / date_to differ from the requested range (an answer of another selection).
 */
export function buildIncomeExpense(
  sales: SaleBalance | null | undefined,
  expense: ExpenseBalance | null | undefined,
  requested: RequestedRange | null | undefined,
): IncomeExpense | null {
  if (!sales || !expense || !requested) return null;
  if (!sameRange(sales, requested) || !sameRange(expense, requested)) return null;
  const net = netBalance(sales.totalAmount, expense.totalAmount);
  if (Number.isNaN(net)) return null;
  return {
    income: fromCents(toCents(sales.totalAmount)), expense: fromCents(toCents(expense.totalAmount)), net,
    saleCount: sales.saleCount, expenseCount: expense.expenseCount, direction: directionOf(net),
  };
}

/** "+$1,000.00", "−$250.00" (minus sign U+2212, as the variation badges) and "$0.00"; "—" when there is no finite value. */
export function formatSignedMoney(net: number | null | undefined): string {
  if (net === null || net === undefined) return '—';
  const cents = toCents(net);
  if (Number.isNaN(cents)) return '—';
  if (cents === 0) return formatMoney(0);
  return `${cents > 0 ? '+' : '−'}${formatMoney(Math.abs(cents) / 100)}`;
}

export type BalanceStatus = 'no-scope' | 'loading' | 'unavailable' | 'empty' | 'ready';

export interface BalanceAvailabilityInput {
  /** false when the scope needs a plantation and there is none: nothing was requested. */
  scopeReady: boolean;
  salesLoading: boolean;
  expenseLoading: boolean;
  salesError: string | null;
  expenseError: string | null;
  sales: SaleBalance | null;
  expense: ExpenseBalance | null;
  requested: RequestedRange | null;
}

export interface BalanceAvailability {
  status: BalanceStatus;
  /** Short Spanish reason shown with "No disponible" (null when the balance is available). */
  reason: string | null;
}

/** Whether the balance can be shown and, when it cannot, a short reason. */
export function balanceAvailability(input: BalanceAvailabilityInput): BalanceAvailability {
  if (!input.scopeReady) return { status: 'no-scope', reason: 'Elige una plantación para ver el balance.' };
  if (input.salesLoading || input.expenseLoading) return { status: 'loading', reason: null };
  const salesMissing = !input.sales || !!input.salesError;
  const expenseMissing = !input.expense || !!input.expenseError;
  if (salesMissing && expenseMissing) return { status: 'unavailable', reason: 'No se pudieron cargar las ventas ni los gastos.' };
  if (salesMissing) return { status: 'unavailable', reason: 'No se pudieron cargar las ventas.' };
  if (expenseMissing) return { status: 'unavailable', reason: 'No se pudieron cargar los gastos.' };
  const balance = buildIncomeExpense(input.sales, input.expense, input.requested);
  if (!balance) return { status: 'unavailable', reason: 'Las cifras no corresponden al mismo periodo.' };
  if (balance.saleCount === 0 && balance.expenseCount === 0) return { status: 'empty', reason: 'Sin ventas ni gastos en el periodo.' };
  return { status: 'ready', reason: null };
}
