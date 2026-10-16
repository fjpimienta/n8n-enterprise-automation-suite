import { describe, it, expect } from 'vitest';
import type { PendingAuthorization } from '@core/models/pending-authorization.model';
import {
  NO_GUIDE_LABEL,
  distinctGuides,
  distinctOrderCodes,
  formatCategoryCounts,
  groupSaleAuthorizations,
  isOwnCompanyRow,
  matchesSaleFilters
} from './sale-order-grouping.util';

let seq = 0;
const req = (overrides: Partial<PendingAuthorization> & { orden?: string | null; guia?: string | null; category?: string } = {}): PendingAuthorization => {
  const { orden, guia, category, ...rest } = overrides;
  seq++;
  return {
    id: `r${seq}`,
    id_company: 5,
    livestock_id: `l${seq}`,
    sale_order_id: orden ? `so-${orden}` : null,
    tipo_evento: 'VENTA',
    payload: { orden_venta: orden ?? undefined, guia_transito: guia ?? undefined, rfid_siniiga: `99990000${seq}` },
    solicitado_por_email: 'capataz@rancho.mx',
    fecha_solicitud: '2026-10-16T15:00:00',
    estado: 'PENDIENTE',
    cattle_livestock_data: { id: `l${seq}`, category: category ?? 'VACA', species: 'BOVINO' },
    ...rest
  };
};

describe('groupSaleAuthorizations', () => {
  it('groups one order with two guides, counting categories per guide', () => {
    const rows = [
      req({ orden: 'OV-000003', guia: '14288', category: 'VACA' }),
      req({ orden: 'OV-000003', guia: '14287', category: 'NOVILLO' }),
      req({ orden: 'OV-000003', guia: '14287', category: 'NOVILLO' }),
      req({ orden: 'OV-000003', guia: '14287', category: 'VACA' })
    ];
    const { orders, ungrouped, foreignExcluded } = groupSaleAuthorizations(rows, 5);

    expect(foreignExcluded).toBe(0);
    expect(ungrouped).toEqual([]);
    expect(orders).toHaveLength(1);
    const [order] = orders;
    expect(order.orderCode).toBe('OV-000003');
    expect(order.saleOrderId).toBe('so-OV-000003');
    expect(order.total).toBe(4);
    expect(order.requestedBy).toBe('capataz@rancho.mx');
    expect(order.hasForeignRows).toBe(false);
    expect(order.guides.map(g => g.guiaTransito)).toEqual(['14287', '14288']);
    expect(order.guides[0].requests).toHaveLength(3);
    expect(order.guides[0].categoryCounts).toEqual({ NOVILLO: 2, VACA: 1 });
    expect(formatCategoryCounts(order.guides[0].categoryCounts)).toBe('2 NOVILLO · 1 VACA');
    expect(order.guides[1].categoryCounts).toEqual({ VACA: 1 });
  });

  it('keeps requests without an order (old sales, mortality) ungrouped, exactly as before', () => {
    const legacySale = req({ guia: '13001' });
    const mortality = req({ tipo_evento: 'BAJA_MORTANDAD', payload: { causa_mortandad: 'Golpe' } });
    const mortalityWithStrayCode = req({ tipo_evento: 'BAJA_MORTANDAD', orden: 'OV-000009' });
    const ordered = req({ orden: 'OV-000010', guia: '14290' });
    const { orders, ungrouped } = groupSaleAuthorizations([legacySale, ordered, mortality, mortalityWithStrayCode], 5);

    expect(orders.map(o => o.orderCode)).toEqual(['OV-000010']);
    expect(ungrouped.map(r => r.id)).toEqual([legacySale.id, mortality.id, mortalityWithStrayCode.id]);
  });

  it('sorts orders numerically and puts guide-less requests under "Sin guía"', () => {
    const rows = [req({ orden: 'OV-000010' }), req({ orden: 'OV-000002', guia: '5' }), req({ orden: 'OV-000002' })];
    const { orders } = groupSaleAuthorizations(rows, 5);
    expect(orders.map(o => o.orderCode)).toEqual(['OV-000002', 'OV-000010']);
    expect(orders[0].guides.map(g => g.guiaTransito)).toEqual(['5', NO_GUIDE_LABEL]);
  });

  it('excludes rows of other companies and flags their order (never returned for resolution)', () => {
    const own = req({ orden: 'OV-000004', guia: '1' });
    const foreignSameOrder = req({ orden: 'OV-000004', guia: '1', id_company: 6 });
    const foreignOtherOrder = req({ orden: 'OV-000005', guia: '2', id_company: 6 });
    const foreignNoOrder = req({ id_company: 7 });
    const { orders, ungrouped, foreignExcluded } = groupSaleAuthorizations([own, foreignSameOrder, foreignOtherOrder, foreignNoOrder], 5);

    expect(foreignExcluded).toBe(3);
    expect(orders).toHaveLength(1);
    expect(orders[0].orderCode).toBe('OV-000004');
    expect(orders[0].total).toBe(1);
    expect(orders[0].hasForeignRows).toBe(true);
    expect(orders[0].guides[0].requests.map(r => r.id)).toEqual([own.id]);
    expect(ungrouped).toEqual([]);
  });

  it('is fail-closed without an active company: nothing is returned', () => {
    const rows = [req({ orden: 'OV-000001' }), req()];
    for (const active of [null, undefined, 0, NaN]) {
      const grouping = groupSaleAuthorizations(rows, active as any);
      expect(grouping.orders).toEqual([]);
      expect(grouping.ungrouped).toEqual([]);
      expect(grouping.foreignExcluded).toBe(2);
    }
  });

  it('accepts id_company as a gateway string', () => {
    expect(isOwnCompanyRow({ id_company: '5' as any }, 5)).toBe(true);
    expect(isOwnCompanyRow({ id_company: 5 }, 6)).toBe(false);
  });
});

describe('quick filters', () => {
  const rows = [
    req({ orden: 'OV-000003', guia: '14287' }),
    req({ orden: 'OV-000003', guia: '14288' }),
    req({ orden: 'OV-000001', guia: '14287' }),
    req({ guia: '13001' })
  ];

  it('lists distinct orders and guides present in the list', () => {
    expect(distinctOrderCodes(rows)).toEqual(['OV-000001', 'OV-000003']);
    expect(distinctGuides(rows)).toEqual(['13001', '14287', '14288']);
  });

  it('filters by order and/or guide ("" = any)', () => {
    expect(rows.filter(r => matchesSaleFilters(r, 'OV-000003', '')).length).toBe(2);
    expect(rows.filter(r => matchesSaleFilters(r, '', '14287')).length).toBe(2);
    expect(rows.filter(r => matchesSaleFilters(r, 'OV-000003', '14287')).length).toBe(1);
    expect(rows.filter(r => matchesSaleFilters(r, '', '')).length).toBe(4);
  });
});
