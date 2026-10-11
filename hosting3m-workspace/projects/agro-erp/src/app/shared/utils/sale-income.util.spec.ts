import { describe, it, expect } from 'vitest';
import type { SaleIncome, SaleReferencePrice } from '@core/models/sale.model';
import {
  batchTotal,
  buildSaleData,
  computePricePerKg,
  formatMoney,
  pickReferencePrice,
  saleDateFor,
  suggestAmount,
  summarizeIncome,
  validateReferencePriceInput,
  validateSaleData
} from './sale-income.util';
import { formatCalendarDate } from './authorization-deadline.util';

const ref = (over: Partial<SaleReferencePrice>): SaleReferencePrice => ({
  id: 'r1', tenantId: 3, category: 'NOVILLO', saleMode: 'POR_PIEZA',
  referenceAmount: 15000, referencePricePerKg: null,
  validFrom: '2026-01-01', validTo: null, isActive: true, notes: null, createdAt: '2026-01-01T00:00:00Z',
  ...over
});

describe('pickReferencePrice', () => {
  it('matches category (case-insensitive), mode and a date inside the range', () => {
    const p = ref({});
    expect(pickReferencePrice([p], 'novillo', 'POR_PIEZA', '2026-10-03')).toBe(p);
  });

  it('ignores inactive, other category, other mode and out-of-range prices', () => {
    const prices = [
      ref({ id: 'inactive', isActive: false }),
      ref({ id: 'cat', category: 'VACA' }),
      ref({ id: 'mode', saleMode: 'POR_KG' }),
      ref({ id: 'future', validFrom: '2026-11-01' }),
      ref({ id: 'past', validFrom: '2025-01-01', validTo: '2025-12-31' })
    ];
    expect(pickReferencePrice(prices, 'NOVILLO', 'POR_PIEZA', '2026-10-03')).toBeNull();
  });

  it('treats valid_from and valid_to as inclusive', () => {
    const p = ref({ validFrom: '2026-10-03', validTo: '2026-10-03' });
    expect(pickReferencePrice([p], 'NOVILLO', 'POR_PIEZA', '2026-10-03')).toBe(p);
  });

  it('prefers the latest valid_from, then the most recently created', () => {
    const older = ref({ id: 'older', validFrom: '2026-01-01' });
    const newer = ref({ id: 'newer', validFrom: '2026-06-01' });
    const newerLater = ref({ id: 'newer-later', validFrom: '2026-06-01', createdAt: '2026-06-02T00:00:00Z' });
    expect(pickReferencePrice([older, newer, newerLater], 'NOVILLO', 'POR_PIEZA', '2026-10-03')?.id).toBe('newer-later');
  });

  it('returns null without category or with an invalid date', () => {
    expect(pickReferencePrice([ref({})], null, 'POR_PIEZA', '2026-10-03')).toBeNull();
    expect(pickReferencePrice([ref({})], 'NOVILLO', 'POR_PIEZA', '03/10/2026')).toBeNull();
  });
});

describe('suggestAmount', () => {
  it('uses $/kg × weight for POR_KG when both are known', () => {
    const p = ref({ saleMode: 'POR_KG', referenceAmount: null, referencePricePerKg: 52.5 });
    expect(suggestAmount(p, 'POR_KG', 420)).toBe(22050);
  });

  it('falls back to the reference amount', () => {
    expect(suggestAmount(ref({ saleMode: 'POR_KG', referencePricePerKg: 50 }), 'POR_KG', null)).toBe(15000);
    expect(suggestAmount(ref({}), 'POR_PIEZA', 420)).toBe(15000);
    expect(suggestAmount(null, 'POR_PIEZA', null)).toBeNull();
  });
});

describe('computePricePerKg', () => {
  it('derives and rounds to cents', () => {
    expect(computePricePerKg(22050, 420)).toBe(52.5);
    expect(computePricePerKg(10000, 3)).toBe(3333.33);
  });

  it('returns null for missing or non-positive values', () => {
    expect(computePricePerKg(10000, null)).toBeNull();
    expect(computePricePerKg(10000, 0)).toBeNull();
    expect(computePricePerKg(0, 400)).toBeNull();
  });
});

describe('validateSaleData (mirrors fn_normalize_sale_data)', () => {
  const valid = {
    modo_venta: 'POR_PIEZA' as const, precio_venta: 15000, comprador: 'Juan Pérez',
    forma_pago: 'TRANSFERENCIA' as const, facturado: false
  };

  it('accepts valid data', () => {
    expect(validateSaleData(valid)).toEqual([]);
    expect(validateSaleData({ ...valid, modo_venta: 'POR_KG', peso_kg: 420.5 })).toEqual([]);
  });

  it('requires the sale data (P0021)', () => {
    expect(validateSaleData(null)).toHaveLength(1);
  });

  it('rejects an invalid mode (P0022)', () => {
    expect(validateSaleData({ ...valid, modo_venta: 'AL_BULTO' as any })).toHaveLength(1);
  });

  it('rejects zero, negative or 3-decimal amounts (P0023)', () => {
    expect(validateSaleData({ ...valid, precio_venta: 0 })).toHaveLength(1);
    expect(validateSaleData({ ...valid, precio_venta: -5 })).toHaveLength(1);
    expect(validateSaleData({ ...valid, precio_venta: 10.555 })).toHaveLength(1);
    expect(validateSaleData({ ...valid, precio_venta: NaN })).toHaveLength(1);
  });

  it('requires a buyer (P0024)', () => {
    expect(validateSaleData({ ...valid, comprador: '   ' })).toHaveLength(1);
  });

  it('rejects an invalid payment method (P0025)', () => {
    expect(validateSaleData({ ...valid, forma_pago: 'CHEQUE' as any })).toHaveLength(1);
  });

  it('requires a positive weight for POR_KG (P0026)', () => {
    expect(validateSaleData({ ...valid, modo_venta: 'POR_KG' })).toHaveLength(1);
    expect(validateSaleData({ ...valid, modo_venta: 'POR_KG', peso_kg: 0 })).toHaveLength(1);
  });
});

describe('buildSaleData', () => {
  const form = {
    mode: 'POR_PIEZA' as const, amount: 15000.004, weightKg: 400, buyer: '  Juan  ',
    paymentMethod: 'EFECTIVO' as const, invoiced: false, invoiceFolio: 'A-1'
  };

  it('rounds the amount, trims the buyer and omits weight/folio when they do not apply', () => {
    expect(buildSaleData(form)).toEqual({
      modo_venta: 'POR_PIEZA', precio_venta: 15000, comprador: 'Juan', forma_pago: 'EFECTIVO', facturado: false
    });
  });

  it('sends the weight for POR_KG and the folio when invoiced', () => {
    const data = buildSaleData({ ...form, mode: 'POR_KG', invoiced: true, invoiceFolio: ' F-77 ' });
    expect(data.peso_kg).toBe(400);
    expect(data.folio_factura).toBe('F-77');
  });
});

describe('batchTotal', () => {
  it('adds valid amounts without float drift and ignores empty ones', () => {
    expect(batchTotal([{ amount: 0.1 }, { amount: 0.2 }, { amount: null }, { amount: 15000 }])).toBe(15000.3);
    expect(batchTotal([])).toBe(0);
  });
});

describe('saleDateFor', () => {
  it('uses payload.fecha_evento when it is a date', () => {
    expect(saleDateFor('2026-10-03', '2026-10-09T19:52:00')).toBe('2026-10-03');
  });

  it('falls back to the CDMX date of fecha_solicitud (UTC)', () => {
    // 2026-10-10 01:00 UTC = 2026-10-09 19:00 CDMX
    expect(saleDateFor(undefined, '2026-10-10T01:00:00')).toBe('2026-10-09');
  });
});

describe('summarizeIncome', () => {
  const row = (amount: number, invoiced: boolean, banked: boolean) => ({ amount, invoiced, banked }) as SaleIncome;

  it('splits totals by invoiced and banked', () => {
    expect(summarizeIncome([row(1000, true, true), row(500.5, false, true), row(200, false, false)])).toEqual({
      totalAmount: 1700.5, heads: 3, invoiced: 1000, notInvoiced: 700.5, banked: 1500.5, notBanked: 200
    });
  });
});

describe('formatCalendarDate', () => {
  it('never shifts a date to the previous day', () => {
    expect(formatCalendarDate('2026-10-03')).toBe('03/10/2026');
    expect(formatCalendarDate('2026-10-03T00:00:00.000Z')).toBe('03/10/2026');
    expect(formatCalendarDate(null)).toBe('—');
  });
});

describe('formatMoney', () => {
  it('formats MXN without the "MX" prefix', () => {
    expect(formatMoney(15000)).toBe('$15,000.00');
    expect(formatMoney(null)).toBe('—');
  });
});

describe('validateReferencePriceInput', () => {
  const valid = {
    category: 'NOVILLO', saleMode: 'POR_KG' as const, referenceAmount: null, referencePricePerKg: 52.5,
    validFrom: '2026-10-01', validTo: null, notes: null
  };

  it('accepts amount or $/kg alone', () => {
    expect(validateReferencePriceInput(valid)).toEqual([]);
    expect(validateReferencePriceInput({ ...valid, referenceAmount: 15000, referencePricePerKg: null })).toEqual([]);
  });

  it('requires at least one value (sale_reference_value_check)', () => {
    expect(validateReferencePriceInput({ ...valid, referencePricePerKg: null })).toHaveLength(1);
  });

  it('rejects valid_to before valid_from (sale_reference_range_check)', () => {
    expect(validateReferencePriceInput({ ...valid, validTo: '2026-09-30' })).toHaveLength(1);
    expect(validateReferencePriceInput({ ...valid, validTo: '2026-10-01' })).toEqual([]);
  });

  it('requires category and valid_from', () => {
    expect(validateReferencePriceInput({ ...valid, category: '', validFrom: '' })).toHaveLength(2);
  });
});
