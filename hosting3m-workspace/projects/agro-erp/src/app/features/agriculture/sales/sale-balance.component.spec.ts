import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { SaleBalance, SaleBalanceQuery } from '@core/models/agri-sale.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import { rangeForPreset } from '../utils/expense-view.util';
import { SaleBalanceComponent } from './sale-balance.component';

const balance = (total: number, o: Partial<SaleBalance> = {}): SaleBalance => ({
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: total, saleCount: total ? 2 : 0, totalQuantityKg: total ? total / 8 : 0, generalAmount: 0,
  byPeriod: [{ periodStart: '2026-11-01', periodEnd: '2026-11-01', saleCount: total ? 2 : 0, quantityKg: total ? total / 8 : 0, totalAmount: total }],
  byPlantation: total ? [
    { plantationId: 'p1', plantationCode: 'P1', plantationName: 'Norte', totalAmount: total * 0.75, saleCount: 1 },
    { plantationId: null, plantationCode: null, plantationName: null, totalAmount: total * 0.25, saleCount: 1 },
  ] : [], ...o });

interface Deferred<T> { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void; }
const defer = <T,>(): Deferred<T> => {
  let resolve!: (v: T) => void; let reject!: (e: unknown) => void;
  const promise = new Promise<T>((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
};

function setup(opts: { role?: string; balance?: (q: SaleBalanceQuery) => Promise<SaleBalance> } = {}) {
  const role = signal(opts.role ?? 'ADMIN');
  const tenantId = signal<string | null>('10');
  const calls: SaleBalanceQuery[] = [];
  const api = {
    getSalesBalance: (q: SaleBalanceQuery) => { calls.push(q); return (opts.balance ?? (async () => balance(1500)))(q); },
    getLots: async () => ({ items: [] }),
  };
  TestBed.configureTestingModule({
    providers: [
      { provide: TenantService, useValue: { activeTenantId: tenantId, activeTenant: () => ({ role: role() }) } },
      { provide: PlantationContextService, useValue: { allPlantations: signal([{ id: 'p1', code: 'P1', name: 'Norte', isActive: true }]), activePlantationId: signal('p1') } },
      { provide: AgriApiService, useValue: api },
    ],
  });
  const fixture = TestBed.createComponent(SaleBalanceComponent);
  const el = fixture.nativeElement as HTMLElement;
  const settle = async () => { for (let i = 0; i < 4; i++) { fixture.detectChanges(); await fixture.whenStable(); } fixture.detectChanges(); };
  const text = () => (el.textContent ?? '').replace(/\s+/g, ' ');
  return { fixture, el, calls, role, tenantId, settle, text };
}

const month = () => rangeForPreset('MONTH', todayCdmx());

describe('sale summary', () => {
  it('ADMIN: requests the current month by day and the comparable previous range, and renders the four KPIs', async () => {
    const t = setup();
    await t.settle();
    const m = month();
    expect(t.calls[0]).toEqual({ dateFrom: m.from, dateTo: m.to, grain: 'DAY', plantationId: null, lotId: null });
    expect(t.calls).toHaveLength(2); // current + previous
    expect(t.text()).toContain('Total vendido');
    expect(t.text()).toContain('$1,500.00');
    expect(t.text()).toContain('Número de ventas');
    expect(t.text()).toContain('Kilos vendidos');
    expect(t.text()).toContain('187.5 kg'); // 1500 / 8
    expect(t.text()).toContain('Precio promedio por kg');
    expect(t.text()).toContain('$8.00'); // total / kilograms
    expect(t.text()).toContain('Ventas por día');
    expect(t.el.querySelector('exp-trend-bars')).not.toBeNull();
  });

  it('shows the variation against the previous period (computed from the second call)', async () => {
    const m = month();
    const t = setup({ balance: async q => balance(q.dateFrom === m.from ? 1500 : 1000) });
    await t.settle();
    expect(t.text()).toContain('+50%');
  });

  it('the previous-period call failing does not block the figures and shows no variation', async () => {
    const m = month();
    const t = setup({ balance: async q => { if (q.dateFrom !== m.from) throw new Error('boom'); return balance(1500); } });
    await t.settle();
    expect(t.text()).toContain('$1,500.00');
    expect(t.el.querySelector('.exp-alert.err')).toBeNull();
    expect(t.text()).not.toMatch(/[+−]\d+(\.\d)?%/);
  });

  it('no variation when the previous period had no sales', async () => {
    const m = month();
    const t = setup({ balance: async q => balance(q.dateFrom === m.from ? 1500 : 0) });
    await t.settle();
    expect(t.text()).toContain('Sin ventas en el periodo anterior');
  });

  it('the quarter in progress has no like-for-like comparison: one request only', async () => {
    const t = setup();
    await t.settle();
    t.calls.length = 0;
    t.fixture.componentInstance.setPreset('QUARTER');
    await t.settle();
    expect(t.calls).toHaveLength(1);
    expect(t.calls[0].grain).toBe('MONTH');
    expect(t.text()).toContain('Periodo en curso');
  });

  it('shows the loading state while the first answer is pending', async () => {
    const d = defer<SaleBalance>();
    const t = setup({ balance: () => d.promise });
    await t.settle();
    expect(t.text()).toContain('Calculando resumen…');
    expect(t.el.querySelector('[role="status"]')).not.toBeNull();
    d.resolve(balance(800));
    await t.settle();
    expect(t.text()).not.toContain('Calculando resumen…');
    expect(t.text()).toContain('$800.00');
  });

  it('an error is shown as an error, never as $0', async () => {
    const t = setup({ balance: async () => { throw new Error('Solo un administrador de la empresa puede consultar el balance de ventas.'); } });
    await t.settle();
    expect(t.el.querySelector('.exp-alert.err')?.textContent).toContain('Solo un administrador');
    expect(t.text()).not.toContain('Total vendido');
    expect(t.text()).not.toContain('$0.00');
  });

  it('a period without sales shows explicit empty states and "—" for the average price', async () => {
    const t = setup({ balance: async () => balance(0) });
    await t.settle();
    expect(t.text()).toContain('$0.00');
    expect(t.text()).toContain('Sin ventas en el periodo');
    expect(t.text()).toContain('Sin kilos vendidos');
    expect(t.text()).toContain('—');
  });

  it('the share by plantation has a "Sin plantación" bucket', async () => {
    const t = setup();
    await t.settle();
    expect(t.text()).toContain('P1 · Norte');
    expect(t.text()).toContain('Sin plantación');
    expect(t.text()).toContain('$1,125.00');
    expect(t.text()).toContain('$375.00');
  });

  it('a plantation filter sends the plantation (and never "")', async () => {
    const t = setup();
    await t.settle();
    t.calls.length = 0;
    await t.fixture.componentInstance.setPlantation('p1');
    await t.settle();
    expect(t.calls[0].plantationId).toBe('p1');
    expect(t.calls[0].lotId).toBeNull();
    t.calls.length = 0;
    await t.fixture.componentInstance.setPlantation('');
    await t.settle();
    expect(t.calls[0].plantationId).toBeNull();
  });

  it('a custom range is validated before any request', async () => {
    const t = setup();
    await t.settle();
    t.calls.length = 0;
    const c = t.fixture.componentInstance;
    c.preset.set('CUSTOM');
    c.customFrom.set('2026-12-01');
    c.customTo.set('2026-11-01');
    c.apply();
    await t.settle();
    expect(t.calls).toHaveLength(0);
    expect(t.el.querySelector('.exp-alert.warn')?.textContent).toContain('La fecha inicial no puede ser posterior');
  });

  it('a reload request of the page reloads the applied query', async () => {
    const t = setup();
    await t.settle();
    const before = t.calls.length;
    t.fixture.componentRef.setInput('refreshToken', 1);
    await t.settle();
    expect(t.calls.length).toBeGreaterThan(before);
  });

  it('OWNER, EDITOR, CUSTOMER and no role: nothing is requested and nothing is shown', async () => {
    for (const role of ['OWNER', 'EDITOR', 'CUSTOMER', '']) {
      TestBed.resetTestingModule();
      const t = setup({ role });
      await t.settle();
      expect(t.calls, role).toHaveLength(0);
      expect(t.text(), role).not.toContain('Total vendido');
    }
  });

  it('a company change clears the figures; a late answer of the previous company is dropped', async () => {
    const first = defer<SaleBalance>();
    let n = 0;
    const t = setup({ balance: () => (n++ === 0 ? first.promise : Promise.resolve(balance(222))) });
    await t.settle();
    t.tenantId.set('11');
    await t.settle();
    first.resolve(balance(999));
    await t.settle();
    expect(t.text()).toContain('$222.00');
    expect(t.text()).not.toContain('$999.00');
  });
});
