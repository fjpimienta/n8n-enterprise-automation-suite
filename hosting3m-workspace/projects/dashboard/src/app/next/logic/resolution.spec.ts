import { describe, expect, it } from 'vitest';
import { toTicketViews } from './maintenance';
import { buildResolveFields, countsAsOpen, otherOpenFaults, planResolution, remainingFaultsText } from './resolution';

let seq = 0;
const t = (o: Record<string, unknown> = {}) => ({ id: ++seq, room_id: 1, status: 'PENDING', priority: 'NORMAL', description: 'x', ...o });
const views = (rows: Record<string, unknown>[]) => toTicketViews(rows);
const room = (status: string, cleaning = 'clean', number = '105') => ({ number, status, cleaning_status: cleaning });
const plan = (rows: Record<string, unknown>[], ticketId: number, r: ReturnType<typeof room> | null) =>
  planResolution({ tickets: views(rows), ticketId, roomId: 1, room: r });

describe('which tickets count as open', () => {
  it('PENDING, unknown and empty statuses are open; RESOLVED and DELETED never are', () => {
    expect(['PENDING', 'CANCELLED', '', ' pending '].map(countsAsOpen)).toEqual([true, true, true, true]);
    expect(['RESOLVED', 'DELETED', ' deleted ', 'resolved'].map(countsAsOpen)).toEqual([false, false, false, false]);
  });
  it('other open faults exclude the ticket itself, other rooms, resolved and deleted ones; rows without id count', () => {
    const rows = [t({ id: 10 }), t({ id: 11 }), t({ id: 12, status: 'RESOLVED' }), t({ id: 13, status: 'DELETED' }),
      t({ id: 14, room_id: 2 }), t({ id: undefined }), t({ id: 15, status: null })];
    expect(otherOpenFaults(views(rows), 1, 10)).toBe(3); // 11, the one without id, and 15 (null status)
    expect(otherOpenFaults(views(rows), 1, null)).toBe(4);
  });
});

describe('R1: the last fault sends the room to cleaning', () => {
  it('a room in maintenance becomes available and dirty', () => {
    const p = plan([t({ id: 1 })], 1, room('maintenance'));
    expect(p).toMatchObject({ remaining: 0, outcome: 'sent-to-cleaning', roomWrite: { status: 'available', cleaning_status: 'dirty' } });
    expect(p.message).toBe('Falla resuelta. La habitación 105 se envió a limpieza.');
  });
  it('an available clean (or inspected) room with its last fault only becomes dirty; status is not written', () => {
    for (const cleaning of ['clean', 'inspected']) {
      expect(plan([t({ id: 1 })], 1, room('available', cleaning)).roomWrite).toEqual({ cleaning_status: 'dirty' });
    }
  });
  it('an available room that is already dirty needs no write', () => {
    expect(plan([t({ id: 1 })], 1, room('available', 'dirty'))).toMatchObject({ roomWrite: null, outcome: 'sent-to-cleaning' });
  });
  it('resolved and deleted tickets of the room do not stop it', () => {
    const rows = [t({ id: 1 }), t({ status: 'RESOLVED' }), t({ status: 'DELETED' })];
    expect(plan(rows, 1, room('maintenance')).roomWrite).toEqual({ status: 'available', cleaning_status: 'dirty' });
  });
});

describe('R2: other open faults keep the room as it is', () => {
  it('a room in maintenance stays blocked and the message says how many remain', () => {
    const rows = [t({ id: 1 }), t({ id: 2 }), t({ id: 3 }), t({ id: 4 })];
    const p = plan(rows, 1, room('maintenance'));
    expect(p).toMatchObject({ remaining: 3, outcome: 'faults-remain', roomWrite: null });
    expect(p.message).toBe('Falla resuelta. La habitación 105 sigue en mantenimiento: quedan 3 fallas pendientes.');
  });
  it('singular wording for one remaining fault, and an available room is described without "mantenimiento"', () => {
    expect(plan([t({ id: 1 }), t({ id: 2 })], 1, room('maintenance')).message).toContain('queda 1 falla pendiente');
    const p = plan([t({ id: 1 }), t({ id: 2 })], 1, room('available'));
    expect(p.message).toBe('Falla resuelta. En la habitación 105 queda 1 falla pendiente.');
    expect(remainingFaultsText(2)).toBe('quedan 2 fallas pendientes');
  });
  it('a ticket with unknown or null status counts as open; DELETED does not', () => {
    expect(plan([t({ id: 1 }), t({ id: 2, status: null })], 1, room('maintenance')).remaining).toBe(1);
    expect(plan([t({ id: 1 }), t({ id: 2, status: 'DELETED' })], 1, room('maintenance')).remaining).toBe(0);
  });
  it('a ticket without id on the same room keeps the room blocked', () => {
    expect(plan([t({ id: 1 }), t({ id: undefined })], 1, room('maintenance')).roomWrite).toBeNull();
  });
});

describe('rooms that must not be freed', () => {
  it('an occupied room is never written, even after its last fault', () => {
    const p = plan([t({ id: 1 })], 1, room('occupied'));
    expect(p).toMatchObject({ outcome: 'room-occupied', roomWrite: null });
    expect(p.message).toContain('sigue ocupada');
  });
  it('a room that is not in the list (for example inactive) or has an unknown status is not written', () => {
    expect(plan([t({ id: 1 })], 1, null)).toMatchObject({ outcome: 'room-unknown', roomWrite: null });
    expect(plan([t({ id: 1 })], 1, room('closed'))).toMatchObject({ outcome: 'room-status-unknown', roomWrite: null });
  });
  it('re-checking after a partial failure (no ticket id) uses every open fault', () => {
    expect(planResolution({ tickets: views([t({ id: 1, status: 'RESOLVED' })]), ticketId: null, roomId: 1, room: room('maintenance') }).roomWrite)
      .toEqual({ status: 'available', cleaning_status: 'dirty' });
    expect(planResolution({ tickets: views([t({ id: 2 })]), ticketId: null, roomId: 1, room: room('maintenance') }).roomWrite).toBeNull();
  });
});

describe('what a resolution writes (R9)', () => {
  it('only status and resolved_at, as an ISO instant like the classic flow', () => {
    const f = buildResolveFields(new Date('2026-11-28T18:30:15.123Z'));
    expect(f).toEqual({ status: 'RESOLVED', resolved_at: '2026-11-28T18:30:15.123Z' });
    expect(Object.keys(f).sort()).toEqual(['resolved_at', 'status']);
  });
});
