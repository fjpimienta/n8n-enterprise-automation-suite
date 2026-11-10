import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { ExpenseBalance, ExpenseBalanceQuery } from '@core/models/agri-expense.model';
import { AgriApiService } from '../../../services/agri-api.service';
import { PlantationContextService } from '../../../services/plantation-context.service';
import { PalmDashboardComponent } from './palm-dashboard.component';

const bal = (total: number, o: Partial<ExpenseBalance> = {}): ExpenseBalance => ({
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: total, expenseCount: total ? 2 : 0, generalAmount: total ? 100 : 0,
  byPeriod: [{ periodStart: '2026-11-01', periodEnd: '2026-11-01', totalAmount: total, expenseCount: total ? 2 : 0 }],
  byCategory: total ? [{ categoryId: 'c1', categoryCode: 'F', categoryName: 'Fertilizantes', totalAmount: total, expenseCount: 2 }] : [],
  byPlantation: total ? [{ plantationId: 'p1', plantationCode: 'P1', plantationName: 'Norte', totalAmount: total, expenseCount: 2 }] : [],
  byLot: [], ...o });

interface Deferred<T> { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void; }
const defer = <T,>(): Deferred<T> => { let resolve!: (v: T) => void; let reject!: (e: unknown) => void; const promise = new Promise<T>((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };

function setup(opts: { role?: string; balance?: (q: ExpenseBalanceQuery) => Promise<ExpenseBalance> } = {}) {
  const role = signal(opts.role ?? 'ADMIN');
  const tenantId = signal<string | null>('10');
  const plantationId = signal<string | null>('p1');
  const calls: ExpenseBalanceQuery[] = [];
  const api = {
    getExpenseBalance: (q: ExpenseBalanceQuery) => { calls.push(q); return (opts.balance ?? (async () => bal(1500)))(q); },
    getPlantationSummaries: async () => ({ items: [], possiblyTruncated: false }),
    getLotSummaries: async () => ({ items: [], possiblyTruncated: false }),
  };
  TestBed.configureTestingModule({
    providers: [
      provideRouter([]),
      { provide: TenantService, useValue: { activeTenantId: tenantId, activeTenant: () => ({ role: role() }) } },
      { provide: PlantationContextService, useValue: { activePlantationId: plantationId, activePlantation: signal({ id: 'p1', code: 'P1', name: 'Norte' }), allPlantations: signal([]), status: signal('ready'), error: signal(null) } },
      { provide: AgriApiService, useValue: api },
    ],
  });
  const fixture = TestBed.createComponent(PalmDashboardComponent);
  const el = fixture.nativeElement as HTMLElement;
  const settle = async () => { for (let i = 0; i < 4; i++) { fixture.detectChanges(); await fixture.whenStable(); } fixture.detectChanges(); };
  const press = async (label: string) => {
    (Array.from(el.querySelectorAll('.exp-screen button')).find(b => b.textContent?.trim().startsWith(label)) as HTMLButtonElement).click();
    await settle();
  };
  return { fixture, el, calls, role, tenantId, plantationId, settle, press, text: () => (el.querySelector('.exp-screen')?.textContent ?? '').replace(/\s+/g, ' ') };
}

describe('palm dashboard expense overview', () => {
  it('ADMIN: renders the KPIs, the trend and the share bars of the company scope', async () => {
    const t = setup();
    await t.settle();
    expect(t.text()).toContain('Total del periodo');
    expect(t.text()).toContain('$1,500.00');
    expect(t.text()).toContain('Generales (sin plantación)');
    expect(t.text()).toContain('En qué se gasta');
    expect(t.text()).toContain('Por plantación');
    expect(t.text()).toContain('Toda la empresa');
    expect(t.el.querySelector('exp-trend-bars')).not.toBeNull();
    expect(t.calls[0]).toMatchObject({ grain: 'DAY', plantationId: null });
  });

  it('EDITOR: no balance request and no amounts anywhere', async () => {
    const t = setup({ role: 'EDITOR' });
    await t.settle();
    expect(t.calls.length).toBe(0);
    expect(t.el.querySelector('.exp-screen')).toBeNull();
    expect(t.el.textContent).not.toContain('$');
  });

  it('a role change to EDITOR clears the amounts at once', async () => {
    const t = setup();
    await t.settle();
    expect(t.text()).toContain('$1,500.00');
    t.role.set('EDITOR');
    await t.settle();
    expect(t.el.querySelector('.exp-screen')).toBeNull();
    expect(t.el.textContent).not.toContain('$1,500.00');
  });

  it('company switch: nothing of the previous company stays and a late answer of it is ignored', async () => {
    const first = defer<ExpenseBalance>();
    let n = 0;
    const t = setup({ balance: () => (n++ === 0 ? first.promise : Promise.resolve(bal(777))) });
    await t.settle();
    t.tenantId.set('11');
    await t.settle();
    expect(t.text()).toContain('$777.00');
    first.resolve(bal(999999)); // the answer of the first company arrives late
    await t.settle();
    expect(t.text()).not.toContain('999,999');
    expect(t.text()).toContain('$777.00');
  });

  it('company switch goes back to the defaults (month, whole company)', async () => {
    const t = setup();
    await t.settle();
    await t.press('Año');
    await t.press('Esta plantación');
    t.tenantId.set('11');
    await t.settle();
    const pressed = Array.from(t.el.querySelectorAll('.exp-screen button[aria-pressed="true"]')).map(b => b.textContent?.trim().replace('✓', '').trim());
    expect(pressed).toEqual(['Este mes', 'Toda la empresa']);
  });

  it('shows an error as an error, never as $0, and keeps the rest of the dashboard', async () => {
    const t = setup({ balance: () => Promise.reject(new Error('Sin conexión')) });
    await t.settle();
    expect(t.text()).toContain('Sin conexión');
    expect(t.el.querySelector('.exp-screen [role="alert"]')).not.toBeNull();
    expect(t.text()).not.toContain('$0.00');
    expect(t.text()).not.toContain('Total del periodo');
    expect(t.el.textContent).toContain('Lotes por etapa productiva');
  });

  it('a failing previous period only hides the delta', async () => {
    const t = setup({ balance: q => (q.dateTo === '2026-11-30' || q.dateFrom.startsWith('2026-11') ? Promise.resolve(bal(1500)) : Promise.reject(new Error('x'))) });
    await t.settle();
    expect(t.text()).toContain('$1,500.00');
    expect(t.el.querySelector('.exp-kpi-delta')).toBeNull();
  });

  it('scope toggle passes the active plantation (and asks the company total for the share)', async () => {
    const t = setup({ balance: async q => (q.plantationId ? bal(300) : bal(1200)) });
    await t.settle();
    await t.press('Esta plantación');
    const sent = t.calls.filter(c => c.plantationId === 'p1');
    expect(sent.length).toBeGreaterThan(0);
    expect(t.text()).toContain('Plantación P1 · Norte');
    expect(t.text()).toContain('Parte de la empresa');
    expect(t.text()).toContain('25%'); // 300 / 1200
    expect(t.text()).not.toContain('Por plantación');
  });

  it('switching the active plantation reloads only in the plantation scope', async () => {
    const t = setup();
    await t.settle();
    const before = t.calls.length;
    t.plantationId.set('p2');
    await t.settle();
    expect(t.calls.length).toBe(before); // company scope: no reload
    await t.press('Esta plantación');
    const mid = t.calls.length;
    t.plantationId.set('p3');
    await t.settle();
    expect(t.calls.length).toBeGreaterThan(mid);
    expect(t.calls.some(c => c.plantationId === 'p3')).toBe(true);
  });

  it('period change reloads with the new range', async () => {
    const t = setup();
    await t.settle();
    const before = t.calls.length;
    await t.press('Año');
    expect(t.calls.length).toBeGreaterThan(before);
    const last = t.calls[t.calls.length - 1];
    expect(last.dateFrom.endsWith('-01-01')).toBe(true);
    expect(last.grain).toBe('MONTH');
  });

  it('a stale answer after a period change is ignored', async () => {
    const slow = defer<ExpenseBalance>();
    let n = 0;
    const t = setup({ balance: () => (n++ === 0 || n === 2 ? slow.promise : Promise.resolve(bal(42))) });
    await t.settle();
    await t.press('Trimestre');
    slow.resolve(bal(5555));
    await t.settle();
    expect(t.text()).not.toContain('5,555');
  });

  it('empty month: intentional empty state, KPIs at $0 and no blank chart', async () => {
    const t = setup({ balance: async () => bal(0) });
    await t.settle();
    expect(t.text()).toContain('$0.00');
    expect((t.text().match(/Sin gastos en el periodo/g) ?? []).length).toBeGreaterThanOrEqual(3);
    expect(t.el.querySelector('.exp-bars')).toBeNull();
  });
});
