import { describe, expect, it } from 'vitest';
import { RoomView, toRoomViews } from './room-view';
import {
  MT_OLD_AFTER_DAYS, ageText, buildMaintenanceItems, buildMaintenanceSections, computeMaintenanceCounts, countText,
  isOldTicket, issueLabel, mexicoCityDateKey, reviewReasons, ticketAgeDays, toTicketViews
} from './maintenance';

const NOW = new Date('2026-11-28T18:00:00.000Z'); // 12:00 in Mexico City
const stamp = (daysAgo: number) => new Date(NOW.getTime() - daysAgo * 86_400_000).toISOString();

let seq = 0;
const ticket = (o: Record<string, unknown> = {}) => ({
  id: ++seq, room_id: 1, status: 'PENDING', priority: 'NORMAL', issue_type: 'PLOMERIA', description: 'Fuga',
  created_at: stamp(1), cost: '999.00', ...o
});
const room = (o: Record<string, unknown> = {}): RoomView => toRoomViews([{
  id: 1, room_number: '101', type: 'DOBLE', status: 'available', cleaning_status: 'clean', hasPendingTicket: true, ...o }])[0];
const items = (rows: unknown[], rooms: RoomView[] = [room()]) => buildMaintenanceItems(toTicketViews(rows), rooms, NOW);

describe('toTicketViews', () => {
  it('drops the gateway empty marker and non-objects, keeps rows without id', () => {
    const v = toTicketViews([{}, null, 'x', 5, [], { room_id: 1, description: 'a' }]);
    expect(v.length).toBe(1);
    expect(v[0].id).toBeNull();
  });
  it('parses numeric strings and normalises case', () => {
    const [v] = toTicketViews([{ id: '7', room_id: '3', priority: ' critical ', status: 'pending', issue_type: ' ELECTRICO ', description: ' x ', created_at: 'z' }]);
    expect(v).toMatchObject({ id: 7, roomId: 3, priority: 'CRITICAL', status: 'PENDING', issueType: 'ELECTRICO', description: 'x' });
  });
  it('treats invalid ids as missing', () => {
    expect(toTicketViews([{ id: 'abc', room_id: -1, description: 'x' }])[0]).toMatchObject({ id: null, roomId: null });
  });
  it('is safe on null, undefined and non-arrays', () => {
    expect(toTicketViews(null)).toEqual([]);
    expect(toTicketViews(undefined)).toEqual([]);
    expect(toTicketViews({} as never)).toEqual([]);
  });
  it('never carries cost', () => {
    expect(Object.keys(toTicketViews([ticket()])[0])).not.toContain('cost');
  });
});

describe('ticket age (America/Mexico_City calendar days)', () => {
  it('uses the Mexico City date of the instant, not UTC', () => {
    expect(mexicoCityDateKey(new Date('2026-11-28T05:59:59.000Z'))).toBe('2026-11-27'); // 23:59 CDMX
    expect(mexicoCityDateKey(new Date('2026-11-28T06:00:00.000Z'))).toBe('2026-11-28'); // 00:00 CDMX
  });
  it('is 0 for a ticket reported today and 1 across midnight CDMX', () => {
    const justAfterMidnight = new Date('2026-11-28T06:00:00.000Z');
    expect(ticketAgeDays('2026-11-28T06:00:00.000Z', justAfterMidnight)).toBe(0);
    expect(ticketAgeDays('2026-11-28T05:59:59.000Z', justAfterMidnight)).toBe(1);
  });
  it('around the threshold: 3 days is not old, 4 days is', () => {
    const lateNight = new Date('2026-11-28T05:59:59.000Z'); // 23:59 CDMX on the 27th
    expect(ticketAgeDays('2026-11-25T05:59:59.000Z', lateNight)).toBe(3); // 23:59 CDMX on the 24th
    expect(ticketAgeDays('2026-11-24T05:59:59.000Z', lateNight)).toBe(4);
    expect(MT_OLD_AFTER_DAYS).toBe(3);
    expect(isOldTicket(3)).toBe(false);
    expect(isOldTicket(4)).toBe(true);
    expect(isOldTicket(null)).toBe(false);
  });
  it('does not depend on the time of day (a day is a calendar day)', () => {
    expect(ticketAgeDays('2026-11-27T23:59:00.000Z', new Date('2026-11-28T18:00:00.000Z'))).toBe(1);
  });
  it('unreadable or empty dates are unknown; future dates clamp to 0', () => {
    expect(ticketAgeDays('', NOW)).toBeNull();
    expect(ticketAgeDays('not a date', NOW)).toBeNull();
    expect(ticketAgeDays(stamp(-2), NOW)).toBe(0);
  });
  it('Spanish age text', () => {
    expect([ageText(0), ageText(1), ageText(4), ageText(null)]).toEqual(['Hoy', 'Ayer', 'Hace 4 días', '—']);
  });
});

describe('issue labels', () => {
  it('maps the six known types', () => {
    expect(['PLOMERIA', 'ELECTRICO', 'AIRE_ACONDICIONADO', 'ALBAÑILERIA', 'MOBILIARIO', 'TECNOLOGIA'].map(issueLabel)).toEqual(
      ['Plomería', 'Eléctrico', 'Aire acondicionado', 'Albañilería', 'Mobiliario', 'Tecnología']);
  });
  it('is case-insensitive; unknown or missing is "Otro"', () => {
    expect(issueLabel('plomeria')).toBe('Plomería');
    expect(issueLabel('JARDINERIA')).toBe('Otro');
    expect(issueLabel('')).toBe('Otro');
  });
});

describe('classification', () => {
  it('groups by priority', () => {
    const r = items([ticket({ priority: 'LOW' }), ticket({ priority: 'CRITICAL' }), ticket({ priority: 'NORMAL' })]);
    expect(r.map(i => i.group)).toEqual(['critical', 'normal', 'low']);
  });
  it('resolved tickets are not shown', () => {
    expect(items([ticket({ status: 'RESOLVED' })])).toEqual([]);
  });
  it('unknown priority, unknown status, no id, no content and no room go to review with a reason', () => {
    const r = items([
      ticket({ priority: 'URGENTE' }),
      ticket({ status: 'CANCELLED' }),
      ticket({ id: undefined }),
      ticket({ description: '', issue_type: '' }),
      ticket({ room_id: null })
    ]);
    expect(r.every(i => i.group === 'review')).toBe(true);
    expect(r.flatMap(i => i.reasons).sort()).toEqual(['no-content', 'no-id', 'no-room', 'unknown-priority', 'unknown-status']);
  });
  it('a type alone or a description alone is enough content', () => {
    expect(reviewReasons(toTicketViews([ticket({ description: '' })])[0])).toEqual([]);
    expect(reviewReasons(toTicketViews([ticket({ issue_type: '' })])[0])).toEqual([]);
  });
  it('a missing or unknown type is "Otro" and is not a review reason', () => {
    expect(items([ticket({ issue_type: 'JARDINERIA' })])[0].group).toBe('normal');
  });
});

describe('ordering', () => {
  it('priority first, then oldest first, then id; unknown age last', () => {
    const r = items([
      ticket({ id: 1, priority: 'NORMAL', created_at: stamp(1) }),
      ticket({ id: 2, priority: 'NORMAL', created_at: stamp(9) }),
      ticket({ id: 3, priority: 'CRITICAL', created_at: stamp(0) }),
      ticket({ id: 4, priority: 'NORMAL', created_at: '' }),
      ticket({ id: 5, priority: 'NORMAL', created_at: stamp(9) })
    ]);
    expect(r.map(i => i.ticket.id)).toEqual([3, 2, 5, 1, 4]);
  });
  it('tickets without id get distinct stable keys', () => {
    const r = items([ticket({ id: undefined }), ticket({ id: undefined })]);
    expect(new Set(r.map(i => i.key)).size).toBe(2);
  });
});

describe('room state', () => {
  it('blocked when the room is in maintenance, "pending" otherwise, unknown when the room is not found', () => {
    const rooms = [room({ id: 1, status: 'maintenance' }), room({ id: 2, room_number: '102', status: 'available' }), room({ id: 3, room_number: '103', status: 'occupied' })];
    const r = items([ticket({ room_id: 1 }), ticket({ room_id: 2 }), ticket({ room_id: 3 }), ticket({ room_id: 99 })], rooms);
    expect(r.map(i => i.roomState).sort()).toEqual(['blocked', 'pending', 'pending', 'unknown']);
    expect(r.find(i => i.ticket.roomId === 99)!.room).toBeNull();
  });
});

describe('counts', () => {
  const rooms = [room({ id: 1, status: 'maintenance' }), room({ id: 2, room_number: '102' }), room({ id: 3, room_number: '103' })];
  it('counts open, critical, old, review, blocked and pending rooms', () => {
    const it = items([
      ticket({ room_id: 1, priority: 'CRITICAL', created_at: stamp(4) }),
      ticket({ room_id: 2, created_at: stamp(3) }),
      ticket({ room_id: 2, priority: 'LOW', created_at: stamp(0) }),
      ticket({ room_id: 3, priority: 'WHAT' })
    ], rooms);
    expect(computeMaintenanceCounts(it, rooms, true)).toEqual({ open: 3, critical: 1, old: 1, review: 1, blockedRooms: 1, pendingRooms: 2 });
  });
  it('only resolved tickets: a known, real zero', () => {
    const it = items([ticket({ status: 'RESOLVED' })], rooms);
    expect(computeMaintenanceCounts(it, rooms, true)).toMatchObject({ open: 0, critical: 0, old: 0, review: 0, pendingRooms: 0 });
  });
  it('no readable ticket row at all: ticket counts are unknown, never 0', () => {
    const c = computeMaintenanceCounts([], rooms, false);
    expect(c).toEqual({ open: null, critical: null, old: null, review: null, blockedRooms: 1, pendingRooms: null });
    expect(countText(c.open)).toBe('—');
  });
  it('no rooms: room-derived counts are unknown', () => {
    const c = computeMaintenanceCounts(items([ticket()], []), [], true);
    expect(c.blockedRooms).toBeNull();
    expect(c.pendingRooms).toBeNull();
    expect(c.open).toBe(1);
  });
});

describe('sections', () => {
  it('lists only non-empty groups in priority order with Spanish labels', () => {
    const s = buildMaintenanceSections(items([ticket({ priority: 'LOW' }), ticket({ priority: 'CRITICAL' }), ticket({ priority: 'XX' })]));
    expect(s.map(x => x.label)).toEqual(['Crítica', 'Baja', 'Revisar datos']);
  });
});
