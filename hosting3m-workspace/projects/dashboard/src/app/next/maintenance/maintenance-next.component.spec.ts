import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { BookingService } from '@features/booking/services/booking.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { MaintenanceNextComponent } from './maintenance-next.component';

type Row = Record<string, unknown>;
const days = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();
const rooms = (): Row[] => [
  { id: 1, room_number: '101', type: 'DOBLE', status: 'maintenance', cleaning_status: 'clean', hasPendingTicket: true },
  { id: 2, room_number: '102', type: 'DOBLE', status: 'available', cleaning_status: 'clean', hasPendingTicket: true },
  { id: 3, room_number: '103', type: 'DOBLE', status: 'available', cleaning_status: 'clean', hasPendingTicket: false }
];
let seq = 0;
const ticket = (o: Row = {}): Row => ({
  id: ++seq, room_id: 1, status: 'PENDING', priority: 'NORMAL', issue_type: 'PLOMERIA', description: 'Fuga', created_at: days(1), cost: '1234.00', ...o
});

async function setup(tickets: Row[] | (() => Promise<Row[]>), roomRows: Row[] = rooms()) {
  const load = vi.fn(typeof tickets === 'function' ? tickets : async () => tickets);
  const booking = { roomsWithStatus: signal<Row[]>(roomRows), loadingRooms: signal(false), loadRooms: vi.fn() };
  TestBed.configureTestingModule({
    imports: [MaintenanceNextComponent],
    providers: [{ provide: MaintenanceService, useValue: { loadTickets: load } }, { provide: BookingService, useValue: booking }]
  });
  const fixture = TestBed.createComponent(MaintenanceNextComponent);
  fixture.detectChanges();
  await fixture.whenStable();
  fixture.detectChanges();
  const el: HTMLElement = fixture.nativeElement;
  const kpis = () => Array.from(el.querySelectorAll('.h-kpi__value')).map(v => v.textContent!.trim());
  const titles = () => Array.from(el.querySelectorAll('h2')).map(h => h.textContent!.replace(/\s+/g, ' ').trim());
  return { fixture, el, load, booking, kpis, titles };
}

describe('MaintenanceNextComponent', () => {
  it('loads tickets (forced refresh) and rooms on init, and never writes', async () => {
    const { load, booking } = await setup([ticket()]);
    expect(load).toHaveBeenCalledWith(true);
    expect(booking.loadRooms).toHaveBeenCalledTimes(1);
  });

  it('shows sections in priority order with Spanish labels and the right KPIs', async () => {
    const { titles, kpis } = await setup([
      ticket({ priority: 'LOW', room_id: 2 }),
      ticket({ priority: 'CRITICAL', room_id: 1, created_at: days(4) }),
      ticket({ priority: 'NORMAL', room_id: 2 }),
      ticket({ priority: 'URGENTE', room_id: 2 })
    ]);
    expect(titles()).toEqual(['Crítica 1', 'Normal 1', 'Baja 1', 'Revisar datos 1']);
    expect(kpis()).toEqual(['3', '1', '1', '1', '1']); // open, critical, old, blocked rooms, rooms with a pending ticket
  });

  it('labels the room state and the age, and marks old tickets', async () => {
    const { el } = await setup([ticket({ room_id: 1, created_at: days(5) }), ticket({ room_id: 2, created_at: days(0) })]);
    const text = el.textContent!.replace(/\s+/g, ' ');
    expect(text).toContain('Bloqueada');
    expect(text).toContain('Con falla pendiente');
    expect(text).toContain('Antiguo');
    expect(text).toContain('Reportada: Hace 5 días');
    expect(text).toContain('Reportada: Hoy');
    expect(el.querySelectorAll('.h-chip--maintenance').length).toBeGreaterThan(0);
  });

  it('is read-only: no buttons besides "Actualizar", no inputs, and no cost', async () => {
    const { el } = await setup([ticket(), ticket({ priority: 'CRITICAL' })]);
    const buttons = Array.from(el.querySelectorAll('button')).map(b => b.textContent!.trim());
    expect(buttons).toEqual(['Actualizar']);
    expect(el.querySelectorAll('input, textarea, select').length).toBe(0);
    expect(el.textContent).not.toMatch(/1234|\$|Costo/i);
  });

  it('maps issue types to Spanish and shows "Otro" for unknown or missing', async () => {
    const { el } = await setup([
      ticket({ issue_type: 'AIRE_ACONDICIONADO' }), ticket({ issue_type: 'JARDINERIA' }), ticket({ issue_type: undefined, description: 'x' })
    ]);
    const chips = Array.from(el.querySelectorAll('.h-chip')).map(c => c.textContent!.trim());
    expect(chips).toContain('Aire acondicionado');
    expect(chips.filter(c => c === 'Otro').length).toBe(2);
    expect(el.textContent).not.toMatch(/AIRE_ACONDICIONADO|JARDINERIA/);
  });

  it('keeps a ticket without id, and one with neither description nor type, under "Revisar datos" with a count', async () => {
    const { el, titles } = await setup([ticket({ id: undefined }), ticket({ description: '', issue_type: '' }), ticket()]);
    expect(titles()).toEqual(['Normal 1', 'Revisar datos 2']);
    const text = el.textContent!.replace(/\s+/g, ' ');
    expect(text).toContain('2 fallas tienen datos por revisar');
    expect(text).toContain('Sin identificador');
    expect(text).toContain('Sin descripción ni tipo');
    expect(text).toContain('Sin descripción');
  });

  it('does not list resolved tickets, and shows a real zero when only resolved ones exist', async () => {
    const { el, kpis } = await setup([ticket({ status: 'RESOLVED' })]);
    expect(el.textContent).toContain('No hay fallas abiertas.');
    expect(kpis().slice(0, 3)).toEqual(['0', '0', '0']);
  });

  it('data:[{}] (empty collection) is unknown, not zero', async () => {
    const { el, kpis } = await setup([{}]);
    expect(el.textContent).toContain('Sin datos de fallas');
    expect(kpis().slice(0, 3)).toEqual(['—', '—', '—']);
    expect(kpis()[4]).toBe('—');
  });

  it('a failed load shows an alert and unknown counters', async () => {
    const { el, kpis } = await setup(async () => { throw new Error('boom'); });
    expect(el.querySelector('[role="alert"]')!.textContent).toContain('No se pudieron cargar las fallas');
    expect(kpis().slice(0, 3)).toEqual(['—', '—', '—']);
  });

  it('shows "—" for room-derived counters when there are no rooms (never 0)', async () => {
    const { kpis } = await setup([ticket()], []);
    expect(kpis()).toEqual(['1', '0', '0', '—', '—']);
  });

  it('"Actualizar" reloads tickets and rooms', async () => {
    const { fixture, el, load, booking } = await setup([ticket()]);
    el.querySelector<HTMLButtonElement>('button')!.click();
    await fixture.whenStable();
    expect(load).toHaveBeenCalledTimes(2);
    expect(booking.loadRooms).toHaveBeenCalledTimes(2);
  });

  it('never calls alert() or confirm()', async () => {
    const a = vi.spyOn(window, 'alert').mockImplementation(() => undefined);
    const c = vi.spyOn(window, 'confirm').mockImplementation(() => true);
    const { el } = await setup([ticket()]);
    el.querySelector<HTMLButtonElement>('button')!.click();
    expect(a).not.toHaveBeenCalled();
    expect(c).not.toHaveBeenCalled();
  });
});
