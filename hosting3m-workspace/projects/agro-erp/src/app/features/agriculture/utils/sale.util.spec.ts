import { describe, expect, it } from 'vitest';
import {
  MAX_VOID_REASON,
  averagePricePerKg,
  canManageSales,
  emptySalesMessage,
  formatKg,
  formatPricePerKg,
  normalizeVoidReason,
  parseSalesBalance,
  paymentMethodLabel,
  saleTabsFor,
  salePlace,
  validateSaleVoidReason,
} from './sale.util';

describe('sales visibility (role of the active company)', () => {
  it('only ADMIN, case-insensitive; never OWNER, EDITOR, CUSTOMER, GUEST or no role', () => {
    expect(['ADMIN', 'admin', 'Admin'].every(canManageSales)).toBe(true);
    expect(['OWNER', 'EDITOR', 'CUSTOMER', 'GUEST', '', null, undefined].some(canManageSales)).toBe(false);
  });
  it('tabs: both for ADMIN, none for everybody else', () => {
    expect(saleTabsFor('ADMIN')).toEqual(['RESUMEN', 'VENTAS']);
    expect(['OWNER', 'EDITOR', 'CUSTOMER', null].map(saleTabsFor)).toEqual([[], [], [], []]);
  });
});

describe('void reason', () => {
  it('line breaks and other control characters become a space and the ends are trimmed', () => {
    expect(normalizeVoidReason('  uno\ndos\r\ntres\t ')).toBe('uno dos  tres');
    expect(normalizeVoidReason(null)).toBe('');
  });
  it('accepts 5 to 300 characters after normalizing', () => {
    expect(validateSaleVoidReason('abcde')).toBeNull();
    expect(validateSaleVoidReason('x'.repeat(MAX_VOID_REASON))).toBeNull();
  });
  it('rejects empty, short and long reasons (the expense limit of 500 does not apply)', () => {
    expect(validateSaleVoidReason('')).toContain('obligatorio');
    expect(validateSaleVoidReason('   \n\t ')).toContain('obligatorio');
    expect(validateSaleVoidReason('abcd')).toContain('al menos 5');
    expect(validateSaleVoidReason(' ab \n cd ')).toBeNull(); // "ab   cd" = 7 characters
    expect(validateSaleVoidReason('x'.repeat(MAX_VOID_REASON + 1))).toContain('300');
    expect(validateSaleVoidReason('x'.repeat(400))).toContain('300');
  });
  it('a reason that is only line breaks and spaces counts as empty even if long', () => {
    expect(validateSaleVoidReason('\n\n\n\n\n\n\n')).toContain('obligatorio');
  });
});

describe('formatting', () => {
  it('kilograms: es-MX grouping, up to 3 decimals', () => {
    expect(formatKg(1234.5)).toBe('1,234.5 kg');
    expect(formatKg(0)).toBe('0 kg');
    expect(formatKg(12.3456)).toBe('12.346 kg');
    expect(formatKg(null)).toBe('—');
    expect(formatKg(Number.NaN)).toBe('—');
  });
  it('price per kilogram: MXN with 2 to 4 decimals', () => {
    expect(formatPricePerKg(8.1)).toBe('$8.10');
    expect(formatPricePerKg(8.123456)).toBe('$8.1235');
    expect(formatPricePerKg(undefined)).toBe('—');
  });
  it('average price per kilogram = total / kilograms; null without kilograms', () => {
    expect(averagePricePerKg(10000, 1250)).toBe(8);
    expect(averagePricePerKg(10000, 0)).toBeNull();
    expect(averagePricePerKg(Number.NaN, 5)).toBeNull();
  });
  it('payment method codes become labels and an unknown code stays as it came', () => {
    expect(paymentMethodLabel('PUE')).toBe('Pago en una sola exhibición');
    expect(paymentMethodLabel('ppd')).toBe('Pago en parcialidades o diferido');
    expect(paymentMethodLabel('XYZ')).toBe('XYZ');
    expect(paymentMethodLabel(null)).toBe('—');
  });
  it('place: plantation and lot, or "Sin plantación"', () => {
    expect(salePlace({ plantationId: null, plantationCode: null, lotCode: null })).toBe('Sin plantación');
    expect(salePlace({ plantationId: 'p', plantationCode: 'P1', lotCode: null })).toBe('P1');
    expect(salePlace({ plantationId: 'p', plantationCode: 'P1', lotCode: 'L2' })).toBe('P1 · L2');
  });
  it('empty-list message flags a truncated page', () => {
    expect(emptySalesMessage({ hasStatus: false, hasPlace: false, truncated: false })).toBe('No hay ventas en el rango de fechas elegido.');
    expect(emptySalesMessage({ hasStatus: true, hasPlace: false, truncated: false })).toBe('Ninguna venta coincide con los filtros.');
    expect(emptySalesMessage({ hasStatus: false, hasPlace: true, truncated: true })).toContain('cortada');
  });
});

describe('parseSalesBalance', () => {
  it('parses the answer of sp_agri_sales_balance (numerics as strings), ignoring the keys it does not use', () => {
    const b = parseSalesBalance({
      success: true, grain: 'DAY', date_from: '2026-11-01', date_to: '2026-11-30', total_amount: '30000.50', sale_count: '2',
      total_quantity_kg: '3000.250', general_amount: '10000', delta_pct: null, previous: { sale_count: 1 },
      by_period: [{ period_start: '2026-11-01', period_end: '2026-11-01', sale_count: '2', quantity_kg: '3000.25', total_amount: '30000.50' }],
      by_plantation: [
        { plantation_id: 'p1', plantation_code: 'P1', plantation_name: 'Norte', total_amount: '20000.50', sale_count: 1 },
        { plantation_id: null, plantation_code: null, plantation_name: null, total_amount: '10000', sale_count: 1 },
      ],
    });
    expect(b).toEqual({
      grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: 30000.5, saleCount: 2, totalQuantityKg: 3000.25, generalAmount: 10000,
      byPeriod: [{ periodStart: '2026-11-01', periodEnd: '2026-11-01', saleCount: 2, quantityKg: 3000.25, totalAmount: 30000.5 }],
      byPlantation: [
        { plantationId: 'p1', plantationCode: 'P1', plantationName: 'Norte', totalAmount: 20000.5, saleCount: 1 },
        { plantationId: null, plantationCode: null, plantationName: null, totalAmount: 10000, saleCount: 1 },
      ],
    });
  });
  it('missing or malformed lists become empty and missing numbers become 0', () => {
    const b = parseSalesBalance({ by_period: 'x', by_plantation: [null, 3] });
    expect(b).toMatchObject({ grain: 'MONTH', totalAmount: 0, saleCount: 0, totalQuantityKg: 0, byPeriod: [], byPlantation: [] });
  });
});
