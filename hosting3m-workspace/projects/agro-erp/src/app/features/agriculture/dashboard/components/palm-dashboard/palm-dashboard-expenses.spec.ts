import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { ExpenseBalance, ExpenseBalanceQuery } from '@core/models/agri-expense.model';
import type { SaleBalance, SaleBalanceQuery } from '@core/models/agri-sale.model';
import { rangeForPreset } from '@shared/expenses-ui/expenses-period.util';
import { AgriApiService } from '../../../services/agri-api.service';
import { todayCdmx } from '../../../utils/agri.util';
import { PlantationContextService } from '../../../services/plantation-context.service';
import { PalmDashboardComponent } from './palm-dashboard.component';

const bal = (total: number, o: Partial<ExpenseBalance> = {}): ExpenseBalance => ({
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: total, expenseCount: total ? 2 : 0, generalAmount: total ? 100 : 0,
  byPeriod: [{ periodStart: '2026-11-01', periodEnd: '2026-11-01', totalAmount: total, expenseCount: total ? 2 : 0 }],
  byCategory: total ? [{ categoryId: 'c1', categoryCode: 'F', categoryName: 'Fertilizantes', totalAmount: total, expenseCount: 2 }] : [],
  byPlantation: total ? [{ plantationId: 'p1', plantationCode: 'P1', plantationName: 'Norte', totalAmount: total, expenseCount: 2 }] : [],
  byLot: [], ...o });

const salesBal = (total: number, o: Partial<SaleBalance> = {}): SaleBalance => ({
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: total, saleCount: total ? 2 : 0, totalQuantityKg: 0, generalAmount: 0,
  byPeriod: [], byPlantation: [], ...o });

interface Deferred<T> { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void; }
const defer = <T,>(): Deferred<T> => { let resolve!: (v: T) => void; let reject!: (e: unknown) => void; const promise = new Promise<T>((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };

function setup(opts: { role?: string; balance?: (q: ExpenseBalanceQuery) => Promise<ExpenseBalance>; sales?: (q: SaleBalanceQuery) => Promise<SaleBalance> } = {}) {
  const role = signal(opts.role ?? 'ADMIN');
  const tenantId = signal<string | null>('10');
  const plantationId = signal<string | null>('p1');
  const calls: ExpenseBalanceQuery[] = [];
  const salesCalls: SaleBalanceQuery[] = [];
  const api = {
    // The dates are echoed like the real procedures do (the dashboard checks them against the requested range).
    getSalesBalance: (q: SaleBalanceQuery) => { salesCalls.push(q); return (opts.sales ?? (async (x: SaleBalanceQuery) => salesBal(2468, { dateFrom: x.dateFrom, dateTo: x.dateTo })))(q); },
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
  return { fixture, el, calls, salesCalls, role, tenantId, plantationId, settle, press, text: () => (el.querySelector('.exp-screen')?.textContent ?? '').replace(/\s+/g, ' ') };
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
    // (the balance card of the income block has its own badge; only the expense total card is meant here)
    expect(Array.from(t.el.querySelectorAll('.exp-kpi-delta')).filter(d => !d.closest('[aria-labelledby="income-expense-title"]'))).toHaveLength(0);
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

describe('palm dashboard income vs. expense block', () => {
  // The real procedures echo the requested dates; the expense fake does the same here so both answers match the range.
  const echo = (total: number) => async (q: ExpenseBalanceQuery) => bal(total, { dateFrom: q.dateFrom, dateTo: q.dateTo });
  const echoSales = (total: number, o: Partial<SaleBalance> = {}) => async (q: SaleBalanceQuery) => salesBal(total, { dateFrom: q.dateFrom, dateTo: q.dateTo, ...o });
  const month = () => rangeForPreset('MONTH', todayCdmx());
  type T = ReturnType<typeof setup>;
  const block = (t: T) => (t.el.querySelector('#income-expense-title')?.parentElement?.textContent ?? '').replace(/\s+/g, ' ');
  const card = (t: T, label: string) => {
    const el = Array.from(t.el.querySelectorAll('#income-expense-title ~ * exp-kpi-card, #income-expense-title ~ exp-kpi-card'))
      .concat(Array.from(t.el.querySelectorAll('exp-kpi-card')).filter(c => c.closest('[aria-labelledby="income-expense-title"]')))
      .find(c => (c.textContent ?? '').includes(label));
    return (el?.textContent ?? '').replace(/\s+/g, ' ');
  };

  it('ADMIN: sales, expenses and a signed balance with the labels and the indicative note', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    const b = block(t);
    expect(b).toContain('Ingresos vs. gastos');
    expect(card(t, 'Ventas (total con impuestos)')).toContain('$2,468.00');
    expect(card(t, 'Gastos (monto capturado)')).toContain('$1,500.00');
    expect(card(t, 'Balance')).toContain('+$968.00');
    expect(card(t, 'Balance')).toContain('A favor');
    expect(card(t, 'Balance')).toContain('Ventas menos gastos');
    expect(b).toContain('Cifra orientativa, no es un resultado contable');
    expect(b).toContain('2 ventas vigentes');
    expect(b).toContain('2 gastos vigentes');
  });

  it('asks the sales procedure for the same range, grain and scope as the expenses, with the lot null', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    expect(t.salesCalls).toHaveLength(1);
    const m = month();
    expect(t.salesCalls[0]).toEqual({ dateFrom: m.from, dateTo: m.to, grain: 'DAY', plantationId: null, lotId: null });
    const { dateFrom, dateTo, grain, plantationId } = t.calls.find(c => c.dateFrom === m.from && c.dateTo === m.to)!;
    expect(t.salesCalls[0]).toEqual({ dateFrom, dateTo, grain, plantationId, lotId: null });
    await t.press('Año');
    const last = t.salesCalls[t.salesCalls.length - 1];
    expect(last.dateFrom.endsWith('-01-01')).toBe(true);
    expect(last.grain).toBe('MONTH');
    expect(last.lotId).toBeNull();
  });

  it('plantation scope: the active plantation goes to both calls', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    await t.press('Esta plantación');
    expect(t.salesCalls.some(c => c.plantationId === 'p1' && c.lotId === null)).toBe(true);
    expect(t.calls.some(c => c.plantationId === 'p1')).toBe(true);
  });

  it('plantation scope without an active plantation: nothing is requested and the block says what to do', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    t.plantationId.set(null);
    await t.press('Esta plantación');
    const before = t.salesCalls.length;
    expect(block(t)).toContain('Elige una plantación para ver el balance.');
    expect(card(t, 'Balance')).toBe('');
    t.plantationId.set(null);
    await t.settle();
    expect(t.salesCalls.length).toBe(before);
  });

  it('negative balance: minus sign and "En contra"', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(1000) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('−$500.00');
    expect(card(t, 'Balance')).toContain('En contra');
  });

  it('zero balance: $0.00 without a favorable or unfavorable badge', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(1500) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('$0.00');
    expect(card(t, 'Balance')).not.toContain('A favor');
    expect(card(t, 'Balance')).not.toContain('En contra');
  });

  it('decimal traps are exact: 0.30 - 0.10 = +$0.20 and (0.1 + 0.2) - 0.30 = $0.00', async () => {
    const a = setup({ balance: echo(0.1), sales: echoSales(0.3) });
    await a.settle();
    expect(card(a, 'Balance')).toContain('+$0.20');
    TestBed.resetTestingModule();
    const b = setup({ balance: echo(0.3), sales: echoSales(0.1 + 0.2) });
    await b.settle();
    expect(card(b, 'Balance')).toContain('$0.00');
    expect(card(b, 'Balance')).not.toContain('+$0.00');
  });

  it('nothing in the period: both at $0.00 with an explicit message', async () => {
    const t = setup({ balance: echo(0), sales: echoSales(0) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('$0.00');
    expect(block(t)).toContain('Sin ventas ni gastos en el periodo.');
  });

  it('shows a loading state while a figure is pending', async () => {
    const d = defer<SaleBalance>();
    const t = setup({ balance: echo(1500), sales: () => d.promise });
    await t.settle();
    expect(block(t)).toContain('Calculando ingresos y gastos…');
    expect(card(t, 'Balance')).toContain('Calculando…');
    d.resolve(salesBal(2000, { dateFrom: month().from, dateTo: month().to }));
    await t.settle();
    expect(card(t, 'Balance')).toContain('+$500.00');
  });

  it('sales failing: expenses stay, the sales card shows its error and there is NO balance', async () => {
    const t = setup({ balance: echo(1500), sales: () => Promise.reject(new Error('Sin conexión con ventas')) });
    await t.settle();
    expect(card(t, 'Ventas (total con impuestos)')).toContain('No disponible');
    expect(card(t, 'Ventas (total con impuestos)')).toContain('Sin conexión con ventas');
    expect(card(t, 'Gastos (monto capturado)')).toContain('$1,500.00');
    expect(card(t, 'Balance')).toContain('No disponible');
    expect(card(t, 'Balance')).toContain('No se pudieron cargar las ventas.');
    expect(card(t, 'Balance')).not.toMatch(/[+−]\$/);
    expect(t.text()).toContain('Total del periodo'); // the expense overview below is untouched
  });

  it('expenses failing: sales stay and there is NO balance', async () => {
    const t = setup({ balance: () => Promise.reject(new Error('Sin conexión')), sales: echoSales(2468) });
    await t.settle();
    expect(card(t, 'Ventas (total con impuestos)')).toContain('$2,468.00');
    expect(card(t, 'Gastos (monto capturado)')).toContain('No disponible');
    expect(card(t, 'Balance')).toContain('No disponible');
    expect(card(t, 'Balance')).toContain('No se pudieron cargar los gastos.');
    expect(card(t, 'Balance')).not.toMatch(/[+−]\$/);
  });

  it('both failing: both cards explain it and the balance is unavailable', async () => {
    const t = setup({ balance: () => Promise.reject(new Error('x')), sales: () => Promise.reject(new Error('y')) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('No se pudieron cargar las ventas ni los gastos.');
  });

  it('an answer whose dates do not match the requested range: no balance', async () => {
    const t = setup({ balance: echo(1500), sales: async () => salesBal(2468, { dateFrom: '2020-01-01', dateTo: '2020-01-31' }) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('No disponible');
    expect(card(t, 'Balance')).toContain('Las cifras no corresponden al mismo periodo.');
    expect(card(t, 'Balance')).not.toMatch(/[+−]\$/);
  });

  it('the same mismatch on the expense side: no balance', async () => {
    const t = setup({ balance: async () => bal(1500, { dateFrom: '2020-01-01', dateTo: '2020-01-31' }), sales: echoSales(2468) });
    await t.settle();
    expect(card(t, 'Balance')).toContain('Las cifras no corresponden al mismo periodo.');
  });

  it('role gating: OWNER keeps the expense block but makes no sales call and has no income block', async () => {
    const t = setup({ role: 'OWNER', balance: echo(1500) });
    await t.settle();
    expect(t.salesCalls).toHaveLength(0);
    expect(t.el.querySelector('#income-expense-title')).toBeNull();
    expect(t.text()).toContain('Total del periodo');
  });

  it('role gating: EDITOR and CUSTOMER see nothing financial and make no calls', async () => {
    for (const role of ['EDITOR', 'CUSTOMER', '']) {
      TestBed.resetTestingModule();
      const t = setup({ role });
      await t.settle();
      expect(t.salesCalls, role).toHaveLength(0);
      expect(t.calls, role).toHaveLength(0);
      expect(t.el.querySelector('#income-expense-title'), role).toBeNull();
      expect(t.el.textContent, role).not.toContain('Ventas (total con impuestos)');
    }
  });

  it('a role change to EDITOR clears the block at once; OWNER to ADMIN adds it with its own request', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    expect(block(t)).toContain('$2,468.00');
    t.role.set('EDITOR');
    await t.settle();
    expect(t.el.querySelector('#income-expense-title')).toBeNull();
    expect(t.el.textContent).not.toContain('2,468');
    TestBed.resetTestingModule();
    const o = setup({ role: 'OWNER', balance: echo(1500), sales: echoSales(2468) });
    await o.settle();
    expect(o.salesCalls).toHaveLength(0);
    o.role.set('ADMIN');
    await o.settle();
    expect(o.salesCalls).toHaveLength(1);
    expect(block(o)).toContain('+$968.00');
  });

  it('race on a selector change: the late sales answer of the previous selection is dropped', async () => {
    const slow = defer<SaleBalance>();
    let n = 0;
    const t = setup({ balance: echo(1500), sales: q => (n++ === 0 ? slow.promise : echoSales(3000)(q)) });
    await t.settle();
    await t.press('Año');
    slow.resolve(salesBal(777777, { dateFrom: t.salesCalls[0].dateFrom, dateTo: t.salesCalls[0].dateTo }));
    await t.settle();
    expect(block(t)).not.toContain('777,777');
    expect(card(t, 'Ventas (total con impuestos)')).toContain('$3,000.00');
    expect(card(t, 'Balance')).toContain('+$1,500.00');
  });

  it('race on a selector change: the late expense answer does not combine with the new sales answer', async () => {
    const slow = defer<ExpenseBalance>();
    let mains = 0; // the first request of the current month (not its previous period) is the slow one
    const t = setup({ balance: q => (q.dateFrom === month().from && mains++ === 0 ? slow.promise : echo(1000)(q)), sales: echoSales(3000) });
    await t.settle();
    await t.press('Año');
    slow.resolve(bal(555555, { dateFrom: month().from, dateTo: month().to }));
    await t.settle();
    expect(block(t)).not.toContain('555,555');
    expect(card(t, 'Balance')).toContain('+$2,000.00');
  });

  it('company switch: both figures are cleared, the late answers of the previous company are ignored', async () => {
    const lateSales = defer<SaleBalance>();
    const lateExpense = defer<ExpenseBalance>();
    let s = 0; let e = 0;
    const t = setup({ balance: q => (q.dateFrom === month().from && e++ === 0 ? lateExpense.promise : echo(1000)(q)), sales: q => (s++ === 0 ? lateSales.promise : echoSales(1600)(q)) });
    await t.settle();
    t.tenantId.set('11');
    await t.settle();
    expect(card(t, 'Balance')).toContain('+$600.00');
    lateSales.resolve(salesBal(999999, { dateFrom: month().from, dateTo: month().to }));
    lateExpense.resolve(bal(1, { dateFrom: month().from, dateTo: month().to }));
    await t.settle();
    expect(block(t)).not.toContain('999,999');
    expect(card(t, 'Balance')).toContain('+$600.00');
  });

  it('company switch: while the new company loads, no figure of the previous one stays on screen', async () => {
    const pendingSales = defer<SaleBalance>();
    const pendingExpense = defer<ExpenseBalance>();
    let s = 0; let e = 0;
    const t = setup({
      balance: q => (q.dateFrom === month().from && e++ > 0 ? pendingExpense.promise : echo(1500)(q)),
      sales: q => (s++ > 0 ? pendingSales.promise : echoSales(2468)(q)),
    });
    await t.settle();
    expect(block(t)).toContain('$2,468.00');
    t.tenantId.set('11');
    await t.settle();
    expect(block(t)).not.toContain('2,468');
    expect(block(t)).not.toContain('1,500');
    expect(card(t, 'Balance')).toContain('Calculando…');
    pendingSales.resolve(salesBal(100, { dateFrom: month().from, dateTo: month().to }));
    pendingExpense.resolve(bal(40, { dateFrom: month().from, dateTo: month().to }));
    await t.settle();
    expect(card(t, 'Balance')).toContain('+$60.00');
  });

  it('no active company: nothing is requested', async () => {
    const t = setup({ balance: echo(1500), sales: echoSales(2468) });
    await t.settle();
    t.tenantId.set(null);
    await t.settle();
    const n = t.salesCalls.length;
    await t.press('Año').catch(() => undefined);
    expect(t.salesCalls.length).toBe(n);
  });
});
