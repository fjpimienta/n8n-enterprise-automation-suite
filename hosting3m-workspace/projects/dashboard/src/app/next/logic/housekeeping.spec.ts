import { describe, expect, it } from 'vitest';
import { RoomView, toRoomViews } from './room-view';
import {
  FINISHED_CLEANING, buildHousekeepingItems, buildSections, canFinishCleaning, classifyRoom,
  compareRoomNumbers, computeHousekeepingCounts, countText, isStayOver
} from './housekeeping';

let seq = 0;
const room = (o: Record<string, unknown> = {}): RoomView =>
  toRoomViews([{ id: ++seq, room_number: String(100 + seq), type: 'DOBLE', status: 'available', cleaning_status: 'clean',
    hasPendingTicket: false, isCheckoutDate: false, hasIncomingToday: false, ...o }])[0];

describe('classifyRoom: priority groups', () => {
  it('turnover: occupied, leaves today, arrival today', () => {
    expect(classifyRoom(room({ status: 'occupied', isCheckoutDate: true, hasIncomingToday: true })).group).toBe('turnover');
  });
  it('arrival: free, dirty, arrival today', () => {
    expect(classifyRoom(room({ cleaning_status: 'dirty', hasIncomingToday: true })).group).toBe('arrival');
  });
  it('dirty: free, dirty, no arrival today', () => {
    expect(classifyRoom(room({ cleaning_status: 'dirty' })).group).toBe('dirty');
  });
  it('departure: occupied, leaves today, no arrival', () => {
    expect(classifyRoom(room({ status: 'occupied', isCheckoutDate: true })).group).toBe('departure');
  });
  it('ready: clean or inspected, free', () => {
    expect(classifyRoom(room()).group).toBe('ready');
    expect(classifyRoom(room({ cleaning_status: 'inspected' })).group).toBe('ready');
  });
  it('blocked: maintenance, whatever the cleaning state', () => {
    expect(classifyRoom(room({ status: 'maintenance', cleaning_status: 'dirty' })).group).toBe('blocked');
  });
  it('stay-over: occupied, clean, not leaving today', () => {
    const r = room({ status: 'occupied' });
    expect(classifyRoom(r).group).toBe('stayover');
    expect(isStayOver(r)).toBe(true);
  });
  it('occupied and dirty is flagged for review (not hidden, not actionable)', () => {
    const stay = classifyRoom(room({ status: 'occupied', cleaning_status: 'dirty' }));
    expect(stay).toEqual({ group: 'review', needsReview: true });
    const leaving = classifyRoom(room({ status: 'occupied', cleaning_status: 'dirty', isCheckoutDate: true }));
    expect(leaving).toEqual({ group: 'departure', needsReview: true });
  });
  it('unknown status or cleaning value is flagged for review', () => {
    expect(classifyRoom(room({ status: 'dirty' }))).toEqual({ group: 'review', needsReview: true });
    expect(classifyRoom(room({ cleaning_status: '' }))).toEqual({ group: 'review', needsReview: true });
    expect(classifyRoom(room({ cleaning_status: 'in_progress' }))).toEqual({ group: 'review', needsReview: true });
  });
});

describe('canFinishCleaning: the only allowed transition', () => {
  it('allows only free + dirty', () => {
    expect(canFinishCleaning(room({ cleaning_status: 'dirty' }))).toBe(true);
  });
  it.each([
    ['occupied + dirty', { status: 'occupied', cleaning_status: 'dirty' }],
    ['maintenance + dirty', { status: 'maintenance', cleaning_status: 'dirty' }],
    ['free + clean', { cleaning_status: 'clean' }],
    ['free + inspected', { cleaning_status: 'inspected' }],
    ['free + unknown', { cleaning_status: 'in_progress' }],
    ['unknown status + dirty', { status: 'dirty', cleaning_status: 'dirty' }]
  ])('refuses %s', (_name, o) => expect(canFinishCleaning(room(o))).toBe(false));

  it('the written value is always "clean", never "inspected"', () => {
    expect(FINISHED_CLEANING).toBe('clean');
  });
  it('canFinish on items mirrors the rule, and no non-actionable group offers it', () => {
    const items = buildHousekeepingItems([
      room({ cleaning_status: 'dirty' }), room({ cleaning_status: 'dirty', hasIncomingToday: true }),
      room({ status: 'occupied', isCheckoutDate: true }), room({ status: 'maintenance', cleaning_status: 'dirty' }),
      room({ status: 'occupied', cleaning_status: 'dirty' }), room()
    ]);
    for (const i of items) {
      expect(i.canFinish).toBe(['arrival', 'dirty'].includes(i.group));
      if (i.needsReview) expect(i.canFinish).toBe(false);
    }
  });
});

describe('ordering', () => {
  it('orders groups by the documented priority', () => {
    const rooms = [
      room({ room_number: '106', status: 'maintenance' }),
      room({ room_number: '105' }),
      room({ room_number: '104', status: 'occupied', isCheckoutDate: true }),
      room({ room_number: '103', cleaning_status: 'dirty' }),
      room({ room_number: '102', cleaning_status: 'dirty', hasIncomingToday: true }),
      room({ room_number: '101', status: 'occupied', isCheckoutDate: true, hasIncomingToday: true }),
      room({ room_number: '107', status: 'occupied', cleaning_status: 'dirty' })
    ];
    expect(buildHousekeepingItems(rooms).map(i => i.group)).toEqual(
      ['turnover', 'arrival', 'dirty', 'departure', 'ready', 'blocked', 'review']);
  });

  it('orders room numbers as text numbers: "007" before "10", "9" before "10"', () => {
    const rooms = ['10', '9', '007', '101', '20'].map(n => room({ room_number: n, cleaning_status: 'dirty' }));
    expect(buildHousekeepingItems(rooms).map(i => i.room.room_number)).toEqual(['007', '9', '10', '20', '101']);
  });

  it('breaks ties (equal numbers, e.g. "007" and "7") by id, deterministically', () => {
    const a = room({ id: 50, room_number: '7' });
    const b = room({ id: 40, room_number: '007' });
    expect(compareRoomNumbers(a, b)).toBeGreaterThan(0);
    const ordered = buildHousekeepingItems([a, b]).map(i => i.room.id);
    expect(ordered).toEqual([40, 50]);
    expect(buildHousekeepingItems([b, a]).map(i => i.room.id)).toEqual([40, 50]);
  });

  it('never lists stay-overs', () => {
    expect(buildHousekeepingItems([room({ status: 'occupied' })])).toEqual([]);
  });

  it('buildSections keeps only non-empty groups, in order, with Spanish labels', () => {
    const items = buildHousekeepingItems([room({ cleaning_status: 'dirty' }), room()]);
    expect(buildSections(items).map(s => [s.group, s.label])).toEqual([['dirty', 'Por limpiar'], ['ready', 'Listas']]);
  });
});

describe('computeHousekeepingCounts', () => {
  const rooms = [
    room({ cleaning_status: 'dirty', hasIncomingToday: true }),
    room({ cleaning_status: 'dirty' }),
    room({ status: 'occupied', isCheckoutDate: true, hasIncomingToday: true }),
    room({ status: 'occupied', isCheckoutDate: true }),
    room({ status: 'occupied' }), room({ status: 'occupied' }),
    room(), room({ cleaning_status: 'inspected' }),
    room({ status: 'maintenance' }),
    room({ status: 'occupied', cleaning_status: 'dirty' })
  ];

  it('counts every bucket', () => {
    expect(computeHousekeepingCounts(rooms, true)).toEqual(
      { toClean: 2, urgent: 1, departures: 2, ready: 2, stayOvers: 2, blocked: 1, review: 1 });
  });
  it('is unknown (null), never 0, with no rooms', () => {
    const c = computeHousekeepingCounts([], true);
    expect(Object.values(c).every(v => v === null)).toBe(true);
    expect(countText(c.toClean)).toBe('—');
  });
  it('marks reservation-derived counts unknown when reservations are unknown', () => {
    const c = computeHousekeepingCounts(rooms, false);
    expect(c.urgent).toBeNull();
    expect(c.departures).toBeNull();
    expect(c.stayOvers).toBeNull();
    expect(c.toClean).toBe(2);
  });
  it('a real zero stays 0', () => {
    expect(countText(computeHousekeepingCounts([room()], true).toClean)).toBe('0');
  });
});

describe('malformed gateway input', () => {
  it('drops the empty-collection marker and handles string numerics and odd text', () => {
    const views = toRoomViews([{}, { id: '12', room_number: '007', status: 'AVAILABLE', cleaning_status: ' Dirty ' }, { id: 0, room_number: '1' }, null]);
    expect(views.length).toBe(1);
    const [item] = buildHousekeepingItems(views);
    expect(item.room.id).toBe(12);
    expect(item.group).toBe('dirty');
    expect(item.canFinish).toBe(true);
  });
  it('the literal text "null" or "undefined" as a cleaning value goes to review, not to a normal group', () => {
    expect(classifyRoom(room({ cleaning_status: 'null' })).needsReview).toBe(true);
    expect(classifyRoom(room({ cleaning_status: 'undefined' })).needsReview).toBe(true);
  });
});

describe('R5: "inspected" is shown as clean and never offered', () => {
  const r = (o: Record<string, unknown>) => toRoomViews([{ id: 1, room_number: '101', type: 'DOBLE', status: 'available', cleaning_status: 'inspected', ...o }])[0];
  it('a free inspected room is ready, like a clean one, with no finish action', () => {
    expect(classifyRoom(r({}))).toEqual({ group: 'ready', needsReview: false });
    expect(classifyRoom(r({ cleaning_status: 'clean' }))).toEqual({ group: 'ready', needsReview: false });
    expect(canFinishCleaning(r({}))).toBe(false);
  });
  it('an occupied inspected room is a stay-over, not a review item', () => {
    expect(classifyRoom(r({ status: 'occupied' }))).toEqual({ group: 'stayover', needsReview: false });
  });
  it('the only value this module writes is "clean"', () => {
    expect(FINISHED_CLEANING).toBe('clean');
  });
});
