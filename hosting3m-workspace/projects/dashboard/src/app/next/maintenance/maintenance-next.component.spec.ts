import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { BookingService } from '@features/booking/services/booking.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { AuthService } from 'core-auth';
import { MaintenanceNextComponent } from './maintenance-next.component';
import { TicketResolutionService } from './ticket-resolution.service';

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

interface Opts {
  role?: string | null;
  /** Fresh tickets returned by the resolution service's read. Defaults to the board's own list. */
  fresh?: (roomId: number) => Promise<Row[]>;
  resolveTicket?: () => Promise<void>;
  updateRoom?: () => Promise<void>;
}

async function setup(tickets: Row[] | (() => Promise<Row[]>), roomRows: Row[] = rooms(), opts: Opts = {}) {
  const load = vi.fn(typeof tickets === 'function' ? tickets : async () => tickets);
  const booking = { roomsWithStatus: signal<Row[]>(roomRows), loadingRooms: signal(false), loadRooms: vi.fn() };
  const resolution = {
    loadRoomTickets: vi.fn(opts.fresh ?? (async (roomId: number) => (typeof tickets === 'function' ? await tickets() : tickets).filter(t => t['room_id'] === roomId))),
    resolveTicket: vi.fn(opts.resolveTicket ?? (async () => undefined)),
    updateRoom: vi.fn(opts.updateRoom ?? (async () => undefined))
  };
  const role = opts.role === undefined ? 'ADMIN' : opts.role;
  TestBed.configureTestingModule({
    imports: [MaintenanceNextComponent],
    providers: [
      { provide: MaintenanceService, useValue: { loadTickets: load } }, { provide: BookingService, useValue: booking },
      { provide: TicketResolutionService, useValue: resolution }, { provide: AuthService, useValue: { currentUser: signal(role === null ? null : { role }) } }
    ]
  });
  const fixture = TestBed.createComponent(MaintenanceNextComponent);
  fixture.detectChanges();
  await fixture.whenStable();
  fixture.detectChanges();
  const el: HTMLElement = fixture.nativeElement;
  const kpis = () => Array.from(el.querySelectorAll('.h-kpi__value')).map(v => v.textContent!.trim());
  const titles = () => Array.from(el.querySelectorAll('h2')).map(h => h.textContent!.replace(/\s+/g, ' ').trim());
  const buttons = () => Array.from(el.querySelectorAll<HTMLButtonElement>('button'));
  const click = async (label: RegExp) => {
    buttons().find(b => label.test(b.getAttribute('aria-label') ?? b.textContent ?? ''))!.click();
    fixture.detectChanges();
  };
  const settle = async () => { await fixture.whenStable(); fixture.detectChanges(); await fixture.whenStable(); fixture.detectChanges(); };
  return { fixture, el, load, booking, resolution, kpis, titles, buttons, click, settle };
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

  it('a role without permission sees no action: no buttons besides "Actualizar", no inputs, and no cost; an explanation is shown', async () => {
    const { el } = await setup([ticket(), ticket({ priority: 'CRITICAL' })], rooms(), { role: 'CUSTOMER' });
    expect(el.textContent).toContain('Solo un administrador puede resolver fallas');
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

  it('shows both "Antiguo" thresholds on the board', async () => {
    const { el } = await setup([ticket()]);
    expect(el.textContent!.replace(/\s+/g, ' ')).toContain('Críticas desde 1 día; las demás desde 3 días');
  });

  it('marks a CRITICAL ticket as old from 1 day and a NORMAL one only from 3 days', async () => {
    const { el } = await setup([
      ticket({ priority: 'CRITICAL', created_at: days(1), description: 'critica ayer' }),
      ticket({ priority: 'CRITICAL', created_at: days(0), description: 'critica hoy' }),
      ticket({ priority: 'NORMAL', created_at: days(2), description: 'normal 2 dias' }),
      ticket({ priority: 'NORMAL', created_at: days(3), description: 'normal 3 dias' })
    ]);
    const rowsText = Array.from(el.querySelectorAll('li.h-mt__row')).map(li => li.textContent!.replace(/\s+/g, ' '));
    const old = (needle: string) => rowsText.find(r => r.includes(needle))!.includes('Antiguo');
    expect([old('critica ayer'), old('critica hoy'), old('normal 2 dias'), old('normal 3 dias')]).toEqual([true, false, false, true]);
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

describe('MaintenanceNextComponent: resolving a fault (R1, R2, R3, R9)', () => {
  const resolveFlow = async (t: Awaited<ReturnType<typeof setup>>, label = /Resolver falla de la habitación 101/) => {
    await t.click(label);
    await t.click(/Confirmar resolución/);
    await t.settle();
  };
  const two = () => [ticket({ id: 101, room_id: 1 }), ticket({ id: 102, room_id: 1, priority: 'LOW' })];

  it('R3: an ADMIN sees "Resolver falla"; EDITOR, CUSTOMER, unknown and signed-out users see none', async () => {
    expect((await setup([ticket({ room_id: 1 })])).buttons().map(b => b.textContent!.trim())).toContain('Resolver falla');
    TestBed.resetTestingModule();
    for (const role of ['EDITOR', 'CUSTOMER', 'MAINTENANCE', '', null]) {
      const t = await setup([ticket({ room_id: 1 })], rooms(), { role });
      expect(t.buttons().map(b => b.textContent!.trim())).toEqual(['Actualizar']);
      TestBed.resetTestingModule();
    }
  });

  it('asks for a confirmation first and writes nothing until it is given; "Cancelar" backs out', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })]);
    await t.click(/Resolver falla de la habitación 101/);
    expect(t.resolution.resolveTicket).not.toHaveBeenCalled();
    await t.click(/Cancelar/);
    expect(t.buttons().some(b => /Confirmar resolución/.test(b.textContent!))).toBe(false);
    expect(t.resolution.loadRoomTickets).not.toHaveBeenCalled();
  });

  it('R1: resolving the last fault of a room in maintenance writes the ticket, then available + dirty, and says it went to cleaning', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })]);
    await resolveFlow(t);
    expect(t.resolution.resolveTicket).toHaveBeenCalledWith(101);
    expect(t.resolution.updateRoom).toHaveBeenCalledWith(1, { status: 'available', cleaning_status: 'dirty' });
    expect(t.el.querySelector('.h-banner--ok')?.textContent).toContain('La habitación 101 se envió a limpieza');
    expect(t.resolution.resolveTicket.mock.invocationCallOrder[0]).toBeLessThan(t.resolution.updateRoom.mock.invocationCallOrder[0]);
  });

  it('R2: with other open faults the room is not written and the message says how many remain', async () => {
    const t = await setup(two());
    await resolveFlow(t);
    expect(t.resolution.resolveTicket).toHaveBeenCalledWith(101);
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
    expect(t.el.querySelector('.h-banner--ok')?.textContent).toContain('sigue en mantenimiento: queda 1 falla pendiente');
  });

  it('decides on a fresh read: a fault added meanwhile keeps the room blocked even if the board did not know it', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), {
      fresh: async () => [ticket({ id: 101, room_id: 1 }), ticket({ id: 555, room_id: 1 })]
    });
    await resolveFlow(t);
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
  });

  it('an occupied room is never freed', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })], [{ id: 1, room_number: '101', type: 'DOBLE', status: 'occupied', cleaning_status: 'clean' }]);
    await resolveFlow(t);
    expect(t.resolution.resolveTicket).toHaveBeenCalledWith(101);
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
    expect(t.el.querySelector('.h-banner--ok')?.textContent).toContain('sigue ocupada');
  });

  it('a failed verification read changes nothing and says so', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { fresh: async () => { throw new Error('boom'); } });
    await resolveFlow(t);
    expect(t.resolution.resolveTicket).not.toHaveBeenCalled();
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
    expect(t.el.querySelector('.h-banner--error')?.textContent).toContain('No se hizo ningún cambio');
  });

  it('a fault that is no longer pending (or no longer exists) is not written again', async () => {
    for (const fresh of [async () => [ticket({ id: 101, room_id: 1, status: 'RESOLVED' })], async () => [{}]]) {
      const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { fresh });
      await resolveFlow(t);
      expect(t.resolution.resolveTicket).not.toHaveBeenCalled();
      expect(t.el.querySelector('.h-banner--error')?.textContent).toContain('ya no está pendiente');
      TestBed.resetTestingModule();
    }
  });

  it('a failed ticket write shows an error, writes no room, and the fault stays pending; raw gateway text is not shown', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { resolveTicket: async () => { throw new Error('Fallo DB: texto interno'); } });
    await resolveFlow(t);
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
    const text = t.el.querySelector('.h-banner--error')!.textContent!;
    expect(text).toContain('Sigue pendiente');
    expect(t.el.textContent).not.toContain('Fallo DB');
    expect(t.el.querySelector('.h-banner--ok')).toBeNull();
  });

  it('a failed room write after the ticket was resolved says so and offers a retry of the room step only', async () => {
    let fail = true;
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), {
      updateRoom: async () => { if (fail) throw new Error('boom'); },
      fresh: async () => (fail ? [ticket({ id: 101, room_id: 1 })] : [ticket({ id: 101, room_id: 1, status: 'RESOLVED' })])
    });
    await resolveFlow(t);
    expect(t.el.querySelector('.h-banner--error')?.textContent).toContain('La falla quedó resuelta, pero no se pudo enviar la habitación 101 a limpieza');
    fail = false;
    await t.click(/Reintentar/);
    await t.settle();
    expect(t.resolution.resolveTicket).toHaveBeenCalledTimes(1);
    expect(t.resolution.updateRoom).toHaveBeenCalledTimes(2);
    expect(t.resolution.updateRoom).toHaveBeenLastCalledWith(1, { status: 'available', cleaning_status: 'dirty' });
    expect(t.el.querySelector('.h-banner--ok')?.textContent).toContain('se envió a limpieza');
    expect(t.buttons().some(b => /Reintentar/.test(b.textContent!))).toBe(false);
  });

  it('the role is checked again inside resolve() and retryRoom(): no read, no write', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { role: 'EDITOR' });
    await t.fixture.componentInstance.resolve(101);
    await t.fixture.componentInstance.retryRoom();
    t.fixture.detectChanges();
    expect(t.resolution.loadRoomTickets).not.toHaveBeenCalled();
    expect(t.resolution.resolveTicket).not.toHaveBeenCalled();
    expect(t.resolution.updateRoom).not.toHaveBeenCalled();
    expect(t.el.querySelector('.h-banner--error')?.textContent).toContain('Solo un administrador');
  });

  it('offers no action for tickets without id, without a room, or with an unknown status', async () => {
    const t = await setup([ticket({ id: undefined }), ticket({ room_id: null }), ticket({ status: 'CANCELLED' })]);
    expect(t.buttons().map(b => b.textContent!.trim())).toEqual(['Actualizar']);
    await t.fixture.componentInstance.resolve(9999);
    expect(t.resolution.resolveTicket).not.toHaveBeenCalled();
  });

  it('ignores a second request while one is pending, and never shows cost or who resolved it (R9, R10)', async () => {
    let release!: () => void;
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { resolveTicket: () => new Promise<void>(res => { release = res; }) });
    const first = t.fixture.componentInstance.resolve(101);
    await t.fixture.whenStable();
    void t.fixture.componentInstance.resolve(101);
    await t.fixture.whenStable();
    expect(t.resolution.loadRoomTickets).toHaveBeenCalledTimes(1);
    release(); await first;
    expect(t.el.textContent).not.toMatch(/1234|\$|Costo|Resuelta por|Reportada por/i);
  });

  it('never writes anything but the ticket and the room', async () => {
    const t = await setup(two());
    await resolveFlow(t);
    expect(Object.keys(t.resolution).sort()).toEqual(['loadRoomTickets', 'resolveTicket', 'updateRoom']);
  });
});

describe('MaintenanceNextComponent: rendered confirmation flow (DOM)', () => {
  const ask = (el: HTMLElement) => el.querySelector<HTMLButtonElement>('button[aria-label="Resolver falla de la habitación 101"]')!;
  const confirmBtn = (el: HTMLElement) => Array.from(el.querySelectorAll<HTMLButtonElement>('button')).find(b => /Confirmar resolución/.test(b.textContent!));

  it('click "Resolver falla" renders the confirmation text, a "Confirmar resolución" control and "Cancelar"; clicking confirm sends the resolve request', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })]);
    expect(confirmBtn(t.el)).toBeUndefined();
    ask(t.el).click();
    t.fixture.detectChanges();
    await t.fixture.whenStable();
    t.fixture.detectChanges();
    const panel = t.el.querySelector('.mt-confirm')!;
    expect(panel).not.toBeNull();
    expect(panel.textContent).toContain('¿Marcar como resuelta la falla de la habitación 101?');
    expect(confirmBtn(t.el)).toBeDefined();
    expect(Array.from(panel.querySelectorAll('button')).map(b => b.textContent!.trim())).toEqual(['Confirmar resolución', 'Cancelar']);
    expect(t.resolution.resolveTicket).not.toHaveBeenCalled();

    confirmBtn(t.el)!.click();
    await t.settle();
    expect(t.resolution.loadRoomTickets).toHaveBeenCalledWith(1);
    expect(t.resolution.resolveTicket).toHaveBeenCalledWith(101);
    expect(t.el.querySelector('.h-banner--ok')?.textContent).toContain('se envió a limpieza');
  });

  it('keeps the "Resolver falla" control visible, exposes aria-expanded, and moves focus to the confirm control and back', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })]);
    document.body.appendChild(t.el); // focus needs the element to be attached to the document
    try {
      expect(ask(t.el).getAttribute('aria-expanded')).toBe('false');
      ask(t.el).click();
      t.fixture.detectChanges(); await t.fixture.whenStable(); t.fixture.detectChanges();
      expect(ask(t.el).getAttribute('aria-expanded')).toBe('true');
      expect(ask(t.el).getAttribute('aria-controls')).toBe(t.el.querySelector('.mt-confirm')!.id);
      expect(document.activeElement).toBe(confirmBtn(t.el));
      t.el.querySelector('.mt-confirm')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      t.fixture.detectChanges(); await t.fixture.whenStable(); t.fixture.detectChanges();
      expect(t.el.querySelector('.mt-confirm')).toBeNull();
      expect(ask(t.el).getAttribute('aria-expanded')).toBe('false');
      expect(document.activeElement).toBe(ask(t.el));
    } finally { t.el.remove(); }
  });

  it('scrolls the result banner into view after a resolution (the banner sits above the list the user is working in)', async () => {
    const scroll = vi.fn();
    (Element.prototype as any).scrollIntoView = scroll;
    try {
      const t = await setup([ticket({ id: 101, room_id: 1 })]);
      ask(t.el).click(); t.fixture.detectChanges(); await t.fixture.whenStable(); t.fixture.detectChanges();
      confirmBtn(t.el)!.click();
      await t.settle();
      expect(scroll).toHaveBeenCalled();
    } finally { delete (Element.prototype as any).scrollIntoView; }
  });

  it('moves focus to "Reintentar" when only the room step failed', async () => {
    let fail = true;
    const t = await setup([ticket({ id: 101, room_id: 1 })], rooms(), { updateRoom: async () => { if (fail) throw new Error('boom'); } });
    document.body.appendChild(t.el);
    try {
      ask(t.el).click(); t.fixture.detectChanges(); await t.fixture.whenStable(); t.fixture.detectChanges();
      confirmBtn(t.el)!.click();
      await t.settle(); await t.settle();
      const retry = Array.from(t.el.querySelectorAll<HTMLButtonElement>('button')).find(b => b.textContent!.trim() === 'Reintentar')!;
      expect(retry).toBeDefined();
      expect(document.activeElement).toBe(retry);
      fail = false;
    } finally { t.el.remove(); }
  });

  it('does not reuse the housekeeping button classes (their grid placement stacked the two confirmation buttons on top of each other)', async () => {
    const t = await setup([ticket({ id: 101, room_id: 1 })]);
    ask(t.el).click();
    t.fixture.detectChanges(); await t.fixture.whenStable(); t.fixture.detectChanges();
    expect(t.el.querySelectorAll('.h-hk__action').length).toBe(0);
  });
});
