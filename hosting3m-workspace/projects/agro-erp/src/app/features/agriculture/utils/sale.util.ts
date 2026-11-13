/**
 * Pure rules of the palm sales screens (migrations 104, 105 and 107). They mirror the procedures so the user gets
 * feedback before the round-trip; the database enforces every one of them regardless. Totals are never added up
 * here: they come from sp_agri_sales_balance. Only ratios of values the database already returned are derived.
 */
import type { AgriSale, SaleBalance } from '@core/models/agri-sale.model';
import { toInt, toNumber } from './agri.util';

// ---------------------------------------------------------------------------------------------------
// Roles (always the role of the ACTIVE company: tenantService.activeTenant()?.role, never the JWT role)
// ---------------------------------------------------------------------------------------------------

/**
 * Reading, summarizing and voiding sales is ADMIN only: the models agri_sales / agri_sale_balance / agri_sale_void and the
 * procedures accept no other role. OWNER is deliberately NOT included (unlike the expense screens).
 */
export function canManageSales(role: string | null | undefined): boolean {
  return (role ?? '').toUpperCase() === 'ADMIN';
}

export type SaleTab = 'RESUMEN' | 'VENTAS';

/** Tabs of the "Ventas" screen; nobody but ADMIN gets any. */
export function saleTabsFor(role: string | null | undefined): SaleTab[] {
  return canManageSales(role) ? ['RESUMEN', 'VENTAS'] : [];
}

// ---------------------------------------------------------------------------------------------------
// Void reason (same limits as sp_agri_void_sale: 5..300 characters after normalizing)
// ---------------------------------------------------------------------------------------------------

export const MIN_VOID_REASON = 5;
export const MAX_VOID_REASON = 300;

/** Control characters (line breaks included) become a space and the ends are trimmed, as the procedure does. */
export function normalizeVoidReason(text: string | null | undefined): string {
  return (text ?? '').replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').trim();
}

export function validateSaleVoidReason(text: string | null | undefined): string | null {
  const reason = normalizeVoidReason(text);
  if (!reason) return 'El motivo de la anulación es obligatorio.';
  if (reason.length < MIN_VOID_REASON) return `El motivo debe tener al menos ${MIN_VOID_REASON} caracteres.`;
  if (reason.length > MAX_VOID_REASON) return `El motivo no puede exceder ${MAX_VOID_REASON} caracteres.`;
  return null;
}

// ---------------------------------------------------------------------------------------------------
// Formatting (es-MX; the app registers no LOCALE_ID, so no Angular number pipes)
// ---------------------------------------------------------------------------------------------------

const KG = new Intl.NumberFormat('es-MX', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
const PRICE = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', minimumFractionDigits: 2, maximumFractionDigits: 4 });

/** 1234.5 -> "1,234.5 kg"; "—" when there is no finite value. */
export function formatKg(value: number | null | undefined): string {
  return value === null || value === undefined || !Number.isFinite(value) ? '—' : `${KG.format(value)} kg`;
}

/** 8.1 -> "$8.10" and 8.123456 -> "$8.1235" (MXN, up to 4 decimals); "—" when there is no finite value. */
export function formatPricePerKg(value: number | null | undefined): string {
  return value === null || value === undefined || !Number.isFinite(value) ? '—' : PRICE.format(value);
}

/** Average price per kilogram = total / kilograms, a ratio of two values the database returned; null without kilograms. */
export function averagePricePerKg(totalAmount: number, totalKg: number): number | null {
  return Number.isFinite(totalAmount) && Number.isFinite(totalKg) && totalKg > 0 ? totalAmount / totalKg : null;
}

const PAYMENT_METHODS: Record<string, string> = {
  PUE: 'Pago en una sola exhibición',
  PPD: 'Pago en parcialidades o diferido',
};

/** CFDI payment method code -> label; an unknown code is shown as it came. */
export function paymentMethodLabel(code: string | null | undefined): string {
  const text = (code ?? '').trim();
  return text ? PAYMENT_METHODS[text.toUpperCase()] ?? text : '—';
}

/** "P1 · L2", "P1" or "Sin plantación". */
export function salePlace(sale: Pick<AgriSale, 'plantationId' | 'plantationCode' | 'lotCode'>): string {
  if (!sale.plantationId) return 'Sin plantación';
  return `${sale.plantationCode ?? ''}${sale.lotCode ? ' · ' + sale.lotCode : ''}`;
}

/** Empty-list explanation; flags that a truncated page may hide matches. */
export function emptySalesMessage(o: { hasStatus: boolean; hasPlace: boolean; truncated: boolean }): string {
  const incomplete = o.truncated ? ' La lista llegó cortada: el resultado puede estar incompleto.' : '';
  if (o.hasStatus || o.hasPlace) return `Ninguna venta coincide con los filtros.${incomplete}`;
  return `No hay ventas en el rango de fechas elegido.${incomplete}`;
}

// ---------------------------------------------------------------------------------------------------
// Balance (answer of sp_agri_sales_balance; numerics may arrive as numbers or strings)
// ---------------------------------------------------------------------------------------------------

type Rec = Record<string, unknown>;
const list = (value: unknown): Rec[] => (Array.isArray(value) ? value.filter((x): x is Rec => !!x && typeof x === 'object') : []);
const text = (value: unknown): string | null => (value === null || value === undefined ? null : String(value));
const money = (value: unknown): number => toNumber(value) ?? 0;

export function parseSalesBalance(data: Rec): SaleBalance {
  return {
    grain: (text(data['grain']) ?? 'MONTH') as SaleBalance['grain'],
    dateFrom: text(data['date_from']) ?? '',
    dateTo: text(data['date_to']) ?? '',
    totalAmount: money(data['total_amount']),
    saleCount: toInt(data['sale_count']),
    totalQuantityKg: money(data['total_quantity_kg']),
    generalAmount: money(data['general_amount']),
    byPeriod: list(data['by_period']).map(p => ({
      periodStart: text(p['period_start']) ?? '', periodEnd: text(p['period_end']) ?? '',
      saleCount: toInt(p['sale_count']), quantityKg: money(p['quantity_kg']), totalAmount: money(p['total_amount']),
    })),
    byPlantation: list(data['by_plantation']).map(p => ({
      plantationId: text(p['plantation_id']), plantationCode: text(p['plantation_code']),
      plantationName: text(p['plantation_name']), totalAmount: money(p['total_amount']), saleCount: toInt(p['sale_count']),
    })),
  };
}
