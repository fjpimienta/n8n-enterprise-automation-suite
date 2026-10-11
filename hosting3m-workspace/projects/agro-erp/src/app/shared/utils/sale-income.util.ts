import type {
  PaymentMethod,
  SaleData,
  SaleIncome,
  SaleMode,
  SaleReferencePrice,
  SaleReferencePriceInput
} from '@core/models/sale.model';
import { AUTHORIZATION_TIMEZONE, parseGatewayTimestamp } from './authorization-deadline.util';

const SALE_MODE_SET = new Set<string>(['POR_PIEZA', 'POR_KG', 'POR_GENETICA']);
const PAYMENT_METHOD_SET = new Set<string>(['EFECTIVO', 'TRANSFERENCIA']);
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const MONEY_FORMAT = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });

/** "$15,000.00" (MXN, es-MX). The app registers no LOCALE_ID, so the currency pipe would print "MX$". */
export function formatMoney(value: number | null | undefined): string {
  return typeof value === 'number' && Number.isFinite(value) ? MONEY_FORMAT.format(value) : '—';
}

/** Rounds to cents. The server rejects money/weight values with more than 2 decimals. */
export function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

/** Gateway numerics arrive as strings; blank/invalid becomes null (never compared as text). */
export function parseOptionalNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Same shape the server accepts for money/weight: `^\d+(\.\d{1,2})?$` and greater than zero. */
export function isPositiveTwoDecimals(value: unknown): value is number {
  return typeof value === 'number'
    && Number.isFinite(value)
    && value > 0
    && Math.abs(value * 100 - Math.round(value * 100)) < 1e-6;
}

/** $/kg preview, rounded like the server (`round(precio_venta / peso_kg, 2)`). */
export function computePricePerKg(amount: number | null | undefined, weightKg: number | null | undefined): number | null {
  if (typeof amount !== 'number' || typeof weightKg !== 'number') return null;
  if (!Number.isFinite(amount) || !Number.isFinite(weightKg) || amount <= 0 || weightKg <= 0) return null;
  return roundMoney(amount / weightKg);
}

/**
 * Reference price to pre-fill the approval form: same category (case-insensitive) and mode,
 * active, and valid on `saleDate` (`valid_from <= date <= valid_to`, open-ended when `valid_to`
 * is null). When several match, the one with the latest `valid_from` wins (then the most
 * recently created). The caller passes only the active tenant's prices.
 */
export function pickReferencePrice(
  prices: readonly SaleReferencePrice[],
  category: string | null | undefined,
  mode: SaleMode,
  saleDate: string
): SaleReferencePrice | null {
  const cat = (category ?? '').trim().toUpperCase();
  if (!cat || !ISO_DATE.test(saleDate)) return null;

  const candidates = prices.filter(p =>
    p.isActive
    && p.category.trim().toUpperCase() === cat
    && p.saleMode === mode
    && p.validFrom.slice(0, 10) <= saleDate
    && (!p.validTo || p.validTo.slice(0, 10) >= saleDate)
  );

  candidates.sort((a, b) =>
    b.validFrom.localeCompare(a.validFrom) || (b.createdAt ?? '').localeCompare(a.createdAt ?? '')
  );
  return candidates[0] ?? null;
}

/**
 * Amount suggested by a reference price. POR_KG uses `reference_price_per_kg × weight` when both
 * are known; otherwise (and for the other modes) the reference amount per head.
 */
export function suggestAmount(
  reference: SaleReferencePrice | null,
  mode: SaleMode,
  weightKg: number | null | undefined
): number | null {
  if (!reference) return null;
  if (mode === 'POR_KG' && reference.referencePricePerKg !== null
      && typeof weightKg === 'number' && Number.isFinite(weightKg) && weightKg > 0) {
    return roundMoney(reference.referencePricePerKg * weightKg);
  }
  return reference.referenceAmount;
}

/** Raw values of the sale form (single row, or shared fields + one batch row). */
export interface SaleFormValue {
  mode: SaleMode;
  amount: number | null;
  weightKg: number | null;
  buyer: string;
  paymentMethod: PaymentMethod;
  invoiced: boolean;
  invoiceFolio: string;
}

/**
 * Builds `datos_venta`. Money/weight are rounded to cents; the weight is sent only for POR_KG
 * (the server also logs it as the animal's last weighing) and the folio only when invoiced.
 */
export function buildSaleData(form: SaleFormValue): SaleData {
  const data: SaleData = {
    modo_venta: form.mode,
    precio_venta: typeof form.amount === 'number' ? roundMoney(form.amount) : NaN,
    comprador: (form.buyer ?? '').trim(),
    forma_pago: form.paymentMethod,
    facturado: !!form.invoiced
  };
  if (form.mode === 'POR_KG' && typeof form.weightKg === 'number') data.peso_kg = roundMoney(form.weightKg);
  const folio = (form.invoiceFolio ?? '').trim();
  if (form.invoiced && folio) data.folio_factura = folio;
  return data;
}

/** Mirrors `fn_normalize_sale_data` (migration 071). Empty array = valid. Messages in Spanish. */
export function validateSaleData(data: Partial<SaleData> | null | undefined): string[] {
  if (!data || typeof data !== 'object') {
    return ['La aprobación de una venta requiere los datos de venta (modo, importe, comprador y forma de pago).'];
  }
  const errors: string[] = [];

  if (!SALE_MODE_SET.has(String(data.modo_venta ?? ''))) {
    errors.push('Selecciona el modo de venta.');
  }
  if (!isPositiveTwoDecimals(data.precio_venta)) {
    errors.push('El importe debe ser mayor a cero, con máximo 2 decimales.');
  }
  if (data.peso_kg !== undefined && data.peso_kg !== null && !isPositiveTwoDecimals(data.peso_kg)) {
    errors.push('El peso debe ser mayor a cero, con máximo 2 decimales.');
  }
  if (data.modo_venta === 'POR_KG' && (data.peso_kg === undefined || data.peso_kg === null)) {
    errors.push('La venta por kilo requiere el peso del animal.');
  }
  if (!(data.comprador ?? '').trim()) {
    errors.push('Indica el nombre del comprador.');
  }
  if (!PAYMENT_METHOD_SET.has(String(data.forma_pago ?? ''))) {
    errors.push('Selecciona la forma de pago.');
  }
  if (data.facturado !== undefined && typeof data.facturado !== 'boolean') {
    errors.push('Indica si la venta fue facturada.');
  }
  return errors;
}

/** Sum of the valid amounts of a batch, in cents precision. */
export function batchTotal(rows: readonly { amount: number | null | undefined }[]): number {
  let cents = 0;
  for (const row of rows) {
    if (typeof row.amount === 'number' && Number.isFinite(row.amount) && row.amount > 0) {
      cents += Math.round(row.amount * 100);
    }
  }
  return cents / 100;
}

const CDMX_DATE = new Intl.DateTimeFormat('en-CA', {
  timeZone: AUTHORIZATION_TIMEZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit'
});

/**
 * Sale date the server will record: `payload.fecha_evento` when it is a YYYY-MM-DD date,
 * otherwise the America/Mexico_City date of `fecha_solicitud` (stored as UTC).
 */
export function saleDateFor(fechaEvento: unknown, fechaSolicitud: string): string {
  if (typeof fechaEvento === 'string' && ISO_DATE.test(fechaEvento)) return fechaEvento;
  return CDMX_DATE.format(parseGatewayTimestamp(fechaSolicitud));
}

export interface SaleIncomeSummary {
  totalAmount: number;
  heads: number;
  invoiced: number;
  notInvoiced: number;
  banked: number;
  notBanked: number;
}

/** Totals of the "Ingresos por Venta" tab. One income row = one head. */
export function summarizeIncome(rows: readonly SaleIncome[]): SaleIncomeSummary {
  let total = 0, invoiced = 0, banked = 0;
  for (const r of rows) {
    const cents = Math.round(r.amount * 100);
    total += cents;
    if (r.invoiced) invoiced += cents;
    if (r.banked) banked += cents;
  }
  return {
    totalAmount: total / 100,
    heads: rows.length,
    invoiced: invoiced / 100,
    notInvoiced: (total - invoiced) / 100,
    banked: banked / 100,
    notBanked: (total - banked) / 100
  };
}

/**
 * Mirrors the `cattle_sale_reference_prices` constraints: category and mode required, at least
 * one of amount or $/kg (each > 0, 2 decimals), `valid_from` required and `valid_to >= valid_from`.
 */
export function validateReferencePriceInput(input: Partial<SaleReferencePriceInput>): string[] {
  const errors: string[] = [];
  if (!(input.category ?? '').trim()) errors.push('Selecciona la categoría.');
  if (!SALE_MODE_SET.has(String(input.saleMode ?? ''))) errors.push('Selecciona el modo de venta.');

  const hasAmount = input.referenceAmount !== null && input.referenceAmount !== undefined;
  const hasPerKg = input.referencePricePerKg !== null && input.referencePricePerKg !== undefined;
  if (!hasAmount && !hasPerKg) errors.push('Indica un importe por animal o un precio por kilo.');
  if (hasAmount && !isPositiveTwoDecimals(input.referenceAmount)) {
    errors.push('El importe debe ser mayor a cero, con máximo 2 decimales.');
  }
  if (hasPerKg && !isPositiveTwoDecimals(input.referencePricePerKg)) {
    errors.push('El precio por kilo debe ser mayor a cero, con máximo 2 decimales.');
  }

  if (!ISO_DATE.test(input.validFrom ?? '')) errors.push('Indica la fecha de inicio de vigencia.');
  if (input.validTo && (!ISO_DATE.test(input.validTo) || input.validTo < (input.validFrom ?? ''))) {
    errors.push('La fecha de fin de vigencia debe ser igual o posterior a la de inicio.');
  }
  return errors;
}
