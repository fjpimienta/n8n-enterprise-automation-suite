import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { AgriSale, SaleBalance, SaleListQuery } from '@core/models/agri-sale.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { SalePageComponent } from './sale-page.component';

const balance: SaleBalance = {
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: 1500, saleCount: 2, totalQuantityKg: 150, generalAmount: 0, byPeriod: [], byPlantation: [],
};
const sale: AgriSale = {
  id: 's1', idCompany: 10, folio: 'S1', saleDate: '2026-11-12', buyerName: 'COMPRADOR SINTETICO', quantityKg: 150, unitCode: 'KGM', unitPrice: 10, totalAmount: 1500,
  paymentMethod: 'PUE', ticketRef: 'T1', ticketWarning: false, plantationId: null, plantationCode: null, plantationName: null, lotId: null, lotCode: null,
  lotName: null, status: 'ACTIVE', voidReason: null, voidedAt: null, isTest: false, createdAt: '2026-11-12T18:30:00.000Z',
};

function setup(role = 'ADMIN') {
  const roleSignal = signal(role);
  const calls = { sales: [] as SaleListQuery[], balance: 0, voids: 0 };
  const api = {
    getSales: async (q: SaleListQuery) => { calls.sales.push(q); return { items: [sale], possiblyTruncated: false }; },
    getSalesBalance: async () => { calls.balance++; return balance; },
    voidSale: async () => { calls.voids++; return { alreadyVoid: false }; },
    getLots: async () => ({ items: [] }),
  };
  TestBed.configureTestingModule({
    providers: [
      { provide: TenantService, useValue: { activeTenantId: signal('10'), activeTenant: () => ({ role: roleSignal() }) } },
      { provide: PlantationContextService, useValue: { allPlantations: signal([]), activePlantationId: signal(null) } },
      { provide: AgriApiService, useValue: api },
    ],
  });
  const fixture = TestBed.createComponent(SalePageComponent);
  const el = fixture.nativeElement as HTMLElement;
  const settle = async () => { for (let i = 0; i < 4; i++) { fixture.detectChanges(); await fixture.whenStable(); } fixture.detectChanges(); };
  const tab = (label: string) => Array.from(el.querySelectorAll('.nav-tabs button')).find(b => b.textContent?.trim() === label) as HTMLButtonElement;
  return { fixture, el, calls, roleSignal, settle, tab, text: () => (el.textContent ?? '').replace(/\s+/g, ' ') };
}

describe('Ventas page', () => {
  it('ADMIN: two tabs, the summary first', async () => {
    const t = setup();
    await t.settle();
    expect(Array.from(t.el.querySelectorAll('.nav-tabs button')).map(b => b.textContent?.trim())).toEqual(['Resumen', 'Ventas registradas']);
    expect(t.tab('Resumen').classList.contains('active')).toBe(true);
    expect(t.el.querySelector('app-sale-balance')).not.toBeNull();
    expect(t.el.querySelector('app-sale-list')).toBeNull();
    expect(t.text()).toContain('Total vendido');
  });

  it('switches to the registered sales and back', async () => {
    const t = setup();
    await t.settle();
    t.tab('Ventas registradas').click();
    await t.settle();
    expect(t.el.querySelector('app-sale-list')).not.toBeNull();
    expect(t.text()).toContain('COMPRADOR SINTETICO');
    expect(t.el.querySelector('app-sale-balance')).toBeNull();
  });

  it('the summary offers a link to the registered sales', async () => {
    const t = setup();
    await t.settle();
    (Array.from(t.el.querySelectorAll('button')).find(b => b.textContent?.includes('Ver ventas registradas')) as HTMLButtonElement).click();
    await t.settle();
    expect(t.el.querySelector('app-sale-list')).not.toBeNull();
  });

  it('after a void the list reloads and the summary shows fresh figures when it is opened again', async () => {
    const t = setup();
    await t.settle();
    t.tab('Ventas registradas').click();
    await t.settle();
    const loads = t.calls.sales.length;
    const balanceCalls = t.calls.balance;
    (t.el.querySelector('table tbody .exp-row-btn') as HTMLButtonElement).click();
    await t.settle();
    (Array.from(t.el.querySelectorAll('exp-detail-panel button')).find(b => b.textContent?.includes('Anular venta')) as HTMLButtonElement).click();
    await t.settle();
    const area = t.el.querySelector('#sale-void-reason') as HTMLTextAreaElement;
    area.value = 'Comprador equivocado';
    area.dispatchEvent(new Event('input'));
    await t.settle();
    (Array.from(t.el.querySelectorAll('.modal-footer button')).find(b => b.textContent?.includes('Anular venta')) as HTMLButtonElement).click();
    await t.settle();
    expect(t.calls.voids).toBe(1);
    expect(t.calls.sales.length).toBe(loads + 1); // the list reloaded through the page refresh token
    t.tab('Resumen').click();
    await t.settle();
    expect(t.calls.balance).toBeGreaterThan(balanceCalls); // the summary loads again when shown
  });

  it('OWNER, EDITOR, CUSTOMER and no role: a lock message, no tabs and no request at all', async () => {
    for (const role of ['OWNER', 'EDITOR', 'CUSTOMER', '']) {
      TestBed.resetTestingModule();
      const t = setup(role);
      await t.settle();
      expect(t.text(), role).toContain('Solo para administradores');
      expect(t.el.querySelector('.nav-tabs'), role).toBeNull();
      expect(t.calls.sales.length + t.calls.balance, role).toBe(0);
    }
  });

  it('a role change to non-ADMIN removes the screen at once', async () => {
    const t = setup();
    await t.settle();
    t.roleSignal.set('EDITOR');
    await t.settle();
    expect(t.text()).toContain('Solo para administradores');
    expect(t.el.querySelector('app-sale-balance')).toBeNull();
  });
});
