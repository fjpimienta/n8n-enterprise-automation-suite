/**
 * Palm sales (migrations 104, 105 and 107).
 *
 * Sales are registered from a CFDI voucher (chat route) and are never edited: the only change a registered sale accepts is
 * its void (`agri_sale_void`, ADMIN only). Reads: `agri_sales` (list) and `agri_sale_balance` (totals), both ADMIN only.
 * Every total comes from the database; the unit is always KGM (kilograms).
 */
import type { ExpenseGrain } from './agri-expense.model';

export type SaleStatus = 'ACTIVE' | 'VOID';
export type SaleStatusFilter = 'ALL' | SaleStatus;

export const SALE_STATUS_OPTIONS: ReadonlyArray<{ value: SaleStatusFilter; label: string }> = [
  { value: 'ALL', label: 'Todas' },
  { value: 'ACTIVE', label: 'Vigentes' },
  { value: 'VOID', label: 'Anuladas' },
];

/** One row of the browser view `vw_agri_sale_ui_list` (model `agri_sales`). */
export interface AgriSale {
  id: string;
  idCompany: number;
  /** Series + folio of the voucher ("" when it has none). */
  folio: string;
  /** Date only (YYYY-MM-DD), taken from the first 10 characters of the gateway value. */
  saleDate: string;
  buyerName: string;
  quantityKg: number;
  unitCode: string;
  unitPrice: number | null;
  totalAmount: number;
  paymentMethod: string | null;
  ticketRef: string | null;
  ticketWarning: boolean;
  plantationId: string | null;
  plantationCode: string | null;
  plantationName: string | null;
  lotId: string | null;
  lotCode: string | null;
  lotName: string | null;
  status: SaleStatus;
  voidReason: string | null;
  /** Real instant (ISO) of the void, or null. */
  voidedAt: string | null;
  isTest: boolean;
  /** Real instant (ISO) of the registration. */
  createdAt: string;
}

export interface SaleListQuery {
  dateFrom: string;
  dateTo: string;
  plantationId: string | null;
  lotId: string | null;
  status: SaleStatusFilter;
}

export interface SaleBalanceQuery {
  dateFrom: string;
  dateTo: string;
  grain: ExpenseGrain;
  plantationId: string | null;
  lotId: string | null;
}

export interface SaleBalancePeriod {
  periodStart: string;
  periodEnd: string;
  saleCount: number;
  quantityKg: number;
  totalAmount: number;
}

export interface SaleBalancePlantation {
  /** null = sales without a plantation. */
  plantationId: string | null;
  plantationCode: string | null;
  plantationName: string | null;
  totalAmount: number;
  saleCount: number;
}

/** Answer of `sp_agri_sales_balance` (voided sales are not counted). */
export interface SaleBalance {
  grain: ExpenseGrain;
  dateFrom: string;
  dateTo: string;
  totalAmount: number;
  saleCount: number;
  totalQuantityKg: number;
  generalAmount: number;
  byPeriod: SaleBalancePeriod[];
  byPlantation: SaleBalancePlantation[];
}
