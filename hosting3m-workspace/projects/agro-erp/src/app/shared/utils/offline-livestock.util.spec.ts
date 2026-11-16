import { findFinancialLookingColumns, sanitizeLivestockForOffline, snapshotMatchesTenant } from './offline-livestock.util';

describe('offline livestock util', () => {
  it('sets metadata to null on every row and keeps other columns', () => {
    const out = sanitizeLivestockForOffline([
      { id: '1', tenant_id: 1, rfid_siniiga: 'A', metadata: { purchase_price: 9, notes: 'x', anything: 1 } },
      { id: '2', tenant_id: 1, metadata: '{"seller_name":"Z"}' },
      { id: '3', tenant_id: 1 }
    ]);
    expect(out.map(r => r['metadata'])).toEqual([null, null, null]);
    expect(out[0]).toEqual({ id: '1', tenant_id: 1, rfid_siniiga: 'A', metadata: null });
    expect(JSON.stringify(out)).not.toMatch(/purchase_price|seller_name|notes|anything/);
  });

  it('does not mutate the input', () => {
    const input = [{ id: '1', metadata: { a: 1 } }];
    sanitizeLivestockForOffline(input);
    expect(input[0].metadata).toEqual({ a: 1 });
  });

  it('drops non-object rows and non-arrays', () => {
    expect(sanitizeLivestockForOffline([null, 'x', [], { id: 1 }])).toEqual([{ id: 1, metadata: null }]);
    expect(sanitizeLivestockForOffline(undefined)).toEqual([]);
  });

  it('flags financial-looking top-level columns', () => {
    expect(findFinancialLookingColumns([{ id: 1, purchase_price: 1, costo_total: 2, metadata: {} }, { valor_estimado: 1, amount: 1 }]))
      .toEqual(['amount', 'costo_total', 'purchase_price', 'valor_estimado']);
    expect(findFinancialLookingColumns([{ id: 1, lot_name: 'a' }])).toEqual([]);
  });

  it('snapshotMatchesTenant requires every row tenant_id to match (numeric strings ok)', () => {
    expect(snapshotMatchesTenant([{ tenant_id: 1 }, { tenant_id: '1' }], 1)).toBe(true);
    expect(snapshotMatchesTenant([{ tenant_id: 1 }, { tenant_id: 2 }], 1)).toBe(false);
    expect(snapshotMatchesTenant([{ id: 1 }], 1)).toBe(false);
    expect(snapshotMatchesTenant('x', 1)).toBe(false);
  });
});
