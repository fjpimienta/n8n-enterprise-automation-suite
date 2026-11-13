import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { AgriSale, SaleListQuery } from '@core/models/agri-sale.model';
import { AgriApiService, ListResult } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import { SaleListComponent } from './sale-list.component';

const sale = (o: Partial<AgriSale> = {}): AgriSale => ({
  id: 's1', idCompany: 10, folio: 'S1', saleDate: '2026-11-12', buyerName: 'COMPRADOR SINTETICO', quantityKg: 1250.5, unitCode: 'KGM',
  unitPrice: 8.1, totalAmount: 10000, paymentMethod: 'PUE', ticketRef: 'T1', ticketWarning: false, plantationId: 'p1', plantationCode: 'P1',
  plantationName: 'Norte', lotId: null, lotCode: null, lotName: null, status: 'ACTIVE', voidReason: null, voidedAt: null, isTest: false,
  createdAt: '2026-11-12T18:30:00.000Z', ...o,
});

interface Deferred<T> { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void; }
const defer = <T,>(): Deferred<T> => {
  let resolve!: (v: T) => void; let reject!: (e: unknown) => void;
  const promise = new Promise<T>((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
};

const result = (items: AgriSale[], possiblyTruncated = false): ListResult<AgriSale> => ({ items, possiblyTruncated });

function setupList(opts: { role?: string; getSales?: (q: SaleListQuery) => Promise<ListResult<AgriSale>>; voidSale?: (id: string, reason: string) => Promise<{ alreadyVoid: boolean }> } = {}) {
  const role = signal(opts.role ?? 'ADMIN');
  const tenantId = signal<string | null>('10');
  const calls: SaleListQuery[] = [];
  const voids: Array<{ id: string; reason: string }> = [];
  const api = {
    getSales: (q: SaleListQuery) => { calls.push(q); return (opts.getSales ?? (async () => result([sale()])))(q); },
    voidSale: (id: string, reason: string) => { voids.push({ id, reason }); return (opts.voidSale ?? (async () => ({ alreadyVoid: false })))(id, reason); },
    getLots: async () => ({ items: [] }),
  };
  TestBed.configureTestingModule({
    providers: [
      { provide: TenantService, useValue: { activeTenantId: tenantId, activeTenant: () => ({ role: role() }) } },
      { provide: PlantationContextService, useValue: { allPlantations: signal([{ id: 'p1', code: 'P1', name: 'Norte', isActive: true }]), activePlantationId: signal('p1') } },
      { provide: AgriApiService, useValue: api },
    ],
  });
  const fixture = TestBed.createComponent(SaleListComponent);
  const el = fixture.nativeElement as HTMLElement;
  const settle = async () => { for (let i = 0; i < 4; i++) { fixture.detectChanges(); await fixture.whenStable(); } fixture.detectChanges(); };
  const text = () => (el.textContent ?? '').replace(/\s+/g, ' ');
  return { fixture, el, calls, voids, role, tenantId, settle, text };
}

describe('sale list', () => {
  it('ADMIN: loads the current month with every status and renders the rows', async () => {
    const t = setupList();
    await t.settle();
    const today = todayCdmx();
    expect(t.calls).toHaveLength(1);
    expect(t.calls[0]).toEqual({ dateFrom: `${today.slice(0, 8)}01`, dateTo: today, status: 'ALL', plantationId: null, lotId: null });
    expect(t.text()).toContain('S1');
    expect(t.text()).toContain('COMPRADOR SINTETICO');
    expect(t.text()).toContain('12/11/2026');
    expect(t.text()).toContain('$10,000.00');
    expect(t.text()).toContain('1,250.5 kg');
    expect(t.text()).toContain('P1');
  });

  it('shows the loading state while the first answer is pending', async () => {
    const d = defer<ListResult<AgriSale>>();
    const t = setupList({ getSales: () => d.promise });
    await t.settle();
    expect(t.text()).toContain('Cargando ventas…');
    expect(t.el.querySelector('[role="status"]')).not.toBeNull();
    d.resolve(result([sale()]));
    await t.settle();
    expect(t.text()).not.toContain('Cargando ventas…');
  });

  it('shows an explicit empty state', async () => {
    const t = setupList({ getSales: async () => result([]) });
    await t.settle();
    expect(t.text()).toContain('No hay ventas en el rango de fechas elegido.');
    expect(t.el.querySelector('table')).toBeNull();
  });

  it('an error is shown as an error, never as an empty list', async () => {
    const t = setupList({ getSales: async () => { throw new Error('Sin permiso para esta operación.'); } });
    await t.settle();
    expect(t.el.querySelector('.exp-alert.err')?.textContent).toContain('Sin permiso para esta operación.');
    expect(t.text()).toContain('No se pudo mostrar la lista.');
    expect(t.text()).not.toContain('No hay ventas');
  });

  it('warns when the list may have been cut by the server', async () => {
    const t = setupList({ getSales: async () => result([sale()], true) });
    await t.settle();
    expect(t.text()).toContain('La lista llegó con el máximo de registros');
    const quiet = setupList2();
    await quiet.settle();
    expect(quiet.text()).not.toContain('La lista llegó con el máximo');
  });

  it('a test sale carries the "Prueba" badge and a normal one does not', async () => {
    const t = setupList({ getSales: async () => result([sale({ id: 'a', isTest: true }), sale({ id: 'b', folio: 'S2', isTest: false })]) });
    await t.settle();
    const rows = Array.from(t.el.querySelectorAll('table tbody tr'));
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Prueba');
    expect(rows[1].textContent).not.toContain('Prueba');
  });

  it('a voided sale is flagged "Anulada" with its reason; an active one is not', async () => {
    const t = setupList({ getSales: async () => result([
      sale({ id: 'v', folio: 'S9', status: 'VOID', voidReason: 'Capturada dos veces' }), sale({ id: 'a', folio: 'S8' })]) });
    await t.settle();
    const rows = Array.from(t.el.querySelectorAll('table tbody tr'));
    expect(rows[0].textContent).toContain('Anulada');
    expect(rows[0].textContent).toContain('Motivo: Capturada dos veces');
    expect(rows[1].textContent).not.toContain('Anulada');
  });

  it('the detail panel opens on selection and shows the sale with its real instants in Mexico City time', async () => {
    const t = setupList({ getSales: async () => result([sale({ ticketWarning: true, ticketRef: null })]) });
    await t.settle();
    expect(t.el.querySelector('exp-detail-panel')).toBeNull();
    (t.el.querySelector('table tbody .exp-row-btn') as HTMLButtonElement).click();
    await t.settle();
    const panel = (t.el.querySelector('exp-detail-panel')?.textContent ?? '').replace(/\s+/g, ' ');
    expect(panel).toContain('Pago en una sola exhibición');
    expect(panel).toContain('Sin ticket');
    expect(panel).toContain('$8.10');
    expect(panel).toContain('12/11/26, 12:30'); // 18:30Z is 12:30 in Mexico City (UTC-6), not shifted again
  });

  it('changing the status filter reloads with that status', async () => {
    const t = setupList();
    await t.settle();
    const select = t.el.querySelector('#sale-list-status') as HTMLSelectElement;
    select.value = 'VOID';
    select.dispatchEvent(new Event('change'));
    await t.settle();
    expect(t.calls.at(-1)?.status).toBe('VOID');
    expect(t.calls).toHaveLength(2);
  });

  it('an invalid date range shows a message and requests nothing', async () => {
    const t = setupList();
    await t.settle();
    (t.fixture.componentInstance as any).dateFrom.set('2026-12-01');
    (t.fixture.componentInstance as any).dateTo.set('2026-11-01');
    await t.fixture.componentInstance.load();
    await t.settle();
    expect(t.calls).toHaveLength(1);
    expect(t.el.querySelector('.exp-alert.warn')?.textContent).toContain('La fecha inicial no puede ser posterior');
  });

  it('OWNER, EDITOR, CUSTOMER and no role: nothing is requested and no sale is shown', async () => {
    for (const role of ['OWNER', 'EDITOR', 'CUSTOMER', '']) {
      TestBed.resetTestingModule();
      const t = setupList({ role });
      await t.settle();
      expect(t.calls, role).toHaveLength(0);
      expect(t.el.querySelector('table'), role).toBeNull();
    }
  });

  it('no active company: nothing is requested', async () => {
    const t = setupList();
    await t.settle();
    t.tenantId.set(null);
    await t.settle();
    expect(t.calls).toHaveLength(1);
    expect(t.el.querySelector('table')).toBeNull();
  });

  it('a company change clears the rows at once and reloads; a late answer of the previous company is dropped', async () => {
    const first = defer<ListResult<AgriSale>>();
    let n = 0;
    const t = setupList({ getSales: () => (n++ === 0 ? first.promise : Promise.resolve(result([sale({ id: 'new', folio: 'N1', idCompany: 11 })]))) });
    await t.settle();
    t.tenantId.set('11');
    await t.settle();
    first.resolve(result([sale({ id: 'old', folio: 'OLD1' })]));
    await t.settle();
    expect(t.text()).toContain('N1');
    expect(t.text()).not.toContain('OLD1');
  });

  it('a role change to non-ADMIN clears the list', async () => {
    const t = setupList();
    await t.settle();
    expect(t.el.querySelector('table')).not.toBeNull();
    t.role.set('EDITOR');
    await t.settle();
    expect(t.el.querySelector('table')).toBeNull();
  });
});

function setupList2() { TestBed.resetTestingModule(); return setupList(); }
