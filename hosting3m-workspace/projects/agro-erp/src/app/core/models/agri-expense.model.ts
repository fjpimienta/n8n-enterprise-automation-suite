/**
 * Palm agricultural expenses (migration 081).
 *
 * Writes go only through procedures: `agri_record_expense` (ADMIN / OWNER / EDITOR), `agri_void_expense`
 * (ADMIN / OWNER). Amounts are read by ADMIN / OWNER only (`agri_expenses`, `agri_expense_summary`,
 * `agri_expense_balance`); the EDITOR only gets "Gasto registrado". Every total comes from the database.
 */

export type ExpenseGrain = 'DAY' | 'WEEK' | 'MONTH' | 'YEAR';

export const GRAIN_OPTIONS: ReadonlyArray<{ value: ExpenseGrain; label: string }> = [
  { value: 'DAY', label: 'Día' },
  { value: 'WEEK', label: 'Semana' },
  { value: 'MONTH', label: 'Mes' },
  { value: 'YEAR', label: 'Año' },
];

export interface ExpenseCategory {
  id: string;
  idCompany: number;
  code: string;
  name: string;
  sortOrder: number;
  isActive: boolean;
}

/** Global, read-only unit catalog. */
export interface ExpenseUnit {
  code: string;
  name: string;
  sortOrder: number;
}

/** Capture form (text fields as typed; parsed and validated before sending). */
export interface ExpenseInput {
  /** '' = general expense of the company (no plantation). */
  plantationId: string;
  /** '' = the whole plantation. */
  lotId: string;
  categoryId: string;
  expenseDate: string;
  amount: string;
  quantity: string;
  unitCode: string;
  supplierName: string;
  description: string;
  isInvoiced: boolean;
  invoiceFolio: string;
}

export interface AgriExpense {
  id: string;
  idCompany: number;
  plantationId: string | null;
  plantationCode: string | null;
  plantationName: string | null;
  lotId: string | null;
  lotCode: string | null;
  lotName: string | null;
  categoryId: string;
  categoryCode: string;
  categoryName: string;
  expenseDate: string;
  amount: number;
  quantity: number | null;
  unitCode: string | null;
  unitName: string | null;
  supplierName: string | null;
  description: string | null;
  isInvoiced: boolean;
  invoiceFolio: string | null;
  reportedByEmail: string;
  isVoid: boolean;
  voidReason: string | null;
  voidedByEmail: string | null;
  voidedAt: string | null;
  createdAt: string;
}

/** One row of vw_agri_expense_summary: period x plantation x lot x category (voided excluded). */
export interface ExpenseSummaryRow {
  id: string;
  idCompany: number;
  grain: ExpenseGrain;
  periodStart: string;
  periodEnd: string;
  plantationId: string | null;
  plantationCode: string | null;
  plantationName: string | null;
  lotId: string | null;
  lotCode: string | null;
  lotName: string | null;
  categoryId: string;
  categoryCode: string;
  categoryName: string;
  totalAmount: number;
  expenseCount: number;
}

export interface ExpenseBalanceQuery {
  dateFrom: string;
  dateTo: string;
  grain: ExpenseGrain;
  plantationId: string | null;
  lotId: string | null;
  categoryId: string | null;
}

export interface BalancePeriod {
  periodStart: string;
  periodEnd: string;
  totalAmount: number;
  expenseCount: number;
}

export interface BalanceByCategory {
  categoryId: string;
  categoryCode: string;
  categoryName: string;
  totalAmount: number;
  expenseCount: number;
}

export interface BalanceByPlantation {
  /** null = general expenses of the company. */
  plantationId: string | null;
  plantationCode: string | null;
  plantationName: string | null;
  totalAmount: number;
  expenseCount: number;
}

export interface BalanceByLot {
  lotId: string;
  lotCode: string;
  lotName: string | null;
  plantationId: string | null;
  totalAmount: number;
  expenseCount: number;
}

/** Answer of sp_agri_expense_balance. */
export interface ExpenseBalance {
  grain: ExpenseGrain;
  dateFrom: string;
  dateTo: string;
  totalAmount: number;
  expenseCount: number;
  generalAmount: number;
  byPeriod: BalancePeriod[];
  byCategory: BalanceByCategory[];
  byPlantation: BalanceByPlantation[];
  byLot: BalanceByLot[];
}

export interface CategoryInput {
  code: string;
  name: string;
  sortOrder: string;
}
