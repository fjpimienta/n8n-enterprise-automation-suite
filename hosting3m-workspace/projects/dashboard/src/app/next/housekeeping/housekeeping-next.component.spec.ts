import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { AdminService } from '@features/admin/services/admin.service';
import { BookingService } from '@features/booking/services/booking.service';
import { HousekeepingNextComponent } from './housekeeping-next.component';

type Row = Record<string, unknown>;
let seq = 0;
const room = (o: Row = {}): Row => ({
  id: ++seq, room_number: String(100 + seq), type: 'DOBLE', status: 'available', cleaning_status: 'clean',
  hasPendingTicket: false, isCheckoutDate: false, hasIncomingToday: false, ...o
});
const reservation = { id: 1, room_id: 1, status: 'confirmed', check_in: '2026-11-27', check_out: '2026-11-28' };

function setup(rooms: Row[], opts: { loading?: boolean; reservations?: unknown[]; update?: () => Promise<void> } = {}) {
  const roomsSig = signal<Row[]>(rooms);
  const loadingSig = signal(opts.loading ?? false);
  const booking = {
    roomsWithStatus: roomsSig, loadingRooms: loadingSig, loadRooms: vi.fn(),
    updateCleaningStatus: vi.fn(opts.update ?? (async () => undefined))
  };
  const admin = { reservations: signal<unknown[]>(opts.reservations ?? [reservation]), loadReservations: vi.fn() };
  TestBed.configureTestingModule({
    imports: [HousekeepingNextComponent],
    providers: [{ provide: BookingService, useValue: booking }, { provide: AdminService, useValue: admin }]
  });
  const fixture = TestBed.createComponent(HousekeepingNextComponent);
  fixture.detectChanges();
  const el: HTMLElement = fixture.nativeElement;
  const buttons = () => Array.from(el.querySelectorAll<HTMLButtonElement>('.h-hk__action'));
  return { fixture, el, booking, admin, roomsSig, loadingSig, buttons };
}

describe('HousekeepingNextComponent', () => {
  it('loads rooms and reservations on init', () => {
    const { booking, admin } = setup([room()]);
    expect(booking.loadRooms).toHaveBeenCalledTimes(1);
    expect(admin.loadReservations).toHaveBeenCalledTimes(1);
  });

  it('lists sections in priority order with Spanish labels, and counts stay-overs without listing them', () => {
    const { el } = setup([
      room({ room_number: '305' }),
      room({ room_number: '304', status: 'occupied', isCheckoutDate: true }),
      room({ room_number: '303', cleaning_status: 'dirty' }),
      room({ room_number: '302', cleaning_status: 'dirty', hasIncomingToday: true }),
      room({ room_number: '301', status: 'occupied', isCheckoutDate: true, hasIncomingToday: true }),
      room({ room_number: '400', status: 'occupied' })
    ]);
    const titles = Array.from(el.querySelectorAll('h2')).map(h => h.textContent!.replace(/\s+/g, ' ').trim());
    expect(titles).toEqual(['Salida y llegada hoy 1', 'Sucias con llegada hoy 1', 'Por limpiar 1', 'Salidas de hoy 1', 'Listas 1']);
    expect(el.textContent).not.toContain('400');
    const kpis = Array.from(el.querySelectorAll('.h-kpi__value')).map(v => v.textContent!.trim());
    expect(kpis).toEqual(['1', '2', '2', '1', '1']); // urgent, to clean, departures, ready, stay-overs
    expect(el.textContent).not.toMatch(/AVAILABLE|OCCUPIED|DIRTY|clean\b/);
  });

  it('offers "Finalizar limpieza" only on free dirty rooms, with an accessible name', () => {
    const { buttons } = setup([
      room({ room_number: '101', cleaning_status: 'dirty' }),
      room({ room_number: '102', cleaning_status: 'dirty', hasIncomingToday: true }),
      room({ room_number: '103', status: 'occupied', cleaning_status: 'dirty' }),
      room({ room_number: '104', status: 'maintenance', cleaning_status: 'dirty' }),
      room({ room_number: '105', status: 'occupied', isCheckoutDate: true }),
      room({ room_number: '106' })
    ]);
    expect(buttons().map(b => b.getAttribute('aria-label'))).toEqual([
      'Finalizar limpieza de la habitación 102', 'Finalizar limpieza de la habitación 101']);
  });

  it('marks an occupied dirty room with "Revisar datos" and no action', () => {
    const { el, buttons } = setup([room({ room_number: '200', status: 'occupied', cleaning_status: 'dirty' })]);
    expect(el.textContent).toContain('Revisar datos');
    expect(buttons().length).toBe(0);
  });

  it('writes exactly "clean" once, shows success, and does NOT change the list by itself (no optimistic update)', async () => {
    const { fixture, el, booking, buttons } = setup([room({ id: 77, room_number: '110', cleaning_status: 'dirty' })]);
    buttons()[0].click();
    await fixture.whenStable(); fixture.detectChanges();
    expect(booking.updateCleaningStatus).toHaveBeenCalledTimes(1);
    expect(booking.updateCleaningStatus).toHaveBeenCalledWith(77, 'clean');
    expect(el.querySelector('.h-banner--ok')?.textContent).toContain('Habitación 110 marcada como limpia.');
    // the (fake) service never reloaded the rooms, so the row is still listed under "Por limpiar"
    expect(el.textContent).toContain('Por limpiar');
    expect(buttons().length).toBe(1);
  });

  it('a failed write shows an error and leaves the UI unchanged', async () => {
    const { fixture, el, buttons } = setup([room({ room_number: '111', cleaning_status: 'dirty' })], {
      update: async () => { throw new Error('Fallo DB: Update Limpieza'); }
    });
    buttons()[0].click();
    await fixture.whenStable(); fixture.detectChanges();
    expect(el.querySelector('.h-banner--error')?.textContent).toContain('No se pudo actualizar la habitación 111');
    expect(el.querySelector('.h-banner--ok')).toBeNull();
    expect(el.textContent).not.toContain('Fallo DB'); // raw gateway text is not shown
    expect(buttons().length).toBe(1);
    expect(buttons()[0].disabled).toBe(false);
  });

  it('ignores a second request for the same room while one is pending', async () => {
    let release!: () => void;
    const { fixture, booking, buttons } = setup([room({ id: 5, cleaning_status: 'dirty' })], {
      update: () => new Promise<void>(res => { release = res; })
    });
    const first = fixture.componentInstance.finish(5);
    fixture.componentInstance.finish(5);
    fixture.detectChanges();
    expect(buttons()[0].disabled).toBe(true);
    expect(buttons()[0].textContent).toContain('Guardando');
    release(); await first; fixture.detectChanges();
    expect(booking.updateCleaningStatus).toHaveBeenCalledTimes(1);
    expect(buttons()[0].disabled).toBe(false);
  });

  it('refuses, without calling the service, a room that is not free and dirty', async () => {
    const { fixture, el, booking } = setup([
      room({ id: 8, status: 'occupied', cleaning_status: 'dirty' }), room({ id: 9, status: 'maintenance', cleaning_status: 'dirty' }),
      room({ id: 10 })
    ]);
    for (const id of [8, 9, 10, 999]) await fixture.componentInstance.finish(id);
    fixture.detectChanges();
    expect(booking.updateCleaningStatus).not.toHaveBeenCalled();
    expect(el.querySelector('.h-banner--error')).not.toBeNull();
  });

  it('shows skeletons while loading, with no data yet', () => {
    const { el } = setup([], { loading: true });
    expect(el.querySelector('[aria-busy="true"]')).not.toBeNull();
    expect(el.querySelectorAll('.h-skeleton').length).toBeGreaterThan(0);
  });

  it('shows an empty state and "—" (never 0) when there are no rooms', () => {
    const { el } = setup([]);
    expect(el.textContent).toContain('Sin datos de habitaciones');
    const kpis = Array.from(el.querySelectorAll('.h-kpi__value')).map(v => v.textContent!.trim());
    expect(kpis).toEqual(['—', '—', '—', '—', '—']);
  });

  it('warns and shows "—" for reservation-derived counts when reservations are unknown', () => {
    const { el } = setup([room({ cleaning_status: 'dirty' })], { reservations: [{}] });
    expect(el.textContent).toContain('Sin datos de reservas');
    const kpis = Array.from(el.querySelectorAll('.h-kpi__value')).map(v => v.textContent!.trim());
    expect(kpis).toEqual(['—', '1', '—', '0', '—']);
  });

  it('keeps the list visible while the service reloads rooms after a write', () => {
    const { el, loadingSig, fixture } = setup([room({ cleaning_status: 'dirty' })]);
    loadingSig.set(true); fixture.detectChanges();
    expect(el.querySelector('.h-skeleton')).toBeNull();
    expect(el.textContent).toContain('Por limpiar');
  });
});
