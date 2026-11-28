import { describe, expect, it } from 'vitest';
import { datePart, formatDayMonth, formatLongDate, paymentLabel } from './es-mx';
import { RACK_FILTERS, chipKind, filterCounts, groupRooms, matchesQuery, toRoomViews } from './room-view';
import { computeKpis, kpiText, occupancyHint, occupancyPercent, occupancyText } from './kpis';
import { arrivalsToday, departuresToday, validReservations } from './today';
import { buildNav, pageTitle } from './nav';

const room = (o: Record<string, unknown>) => ({ id: 1, room_number: '101', type: 'doble', status: 'available', cleaning_status: 'clean', hasPendingTicket: false, ...o });

describe('es-mx helpers', () => {
  it('reads the day from the text so midnight UTC never shifts', () => {
    expect(datePart('2026-11-27T00:00:00.000Z')).toBe('2026-11-27');
    expect(datePart('2026-11-27 00:00:00+00')).toBe('2026-11-27');
    expect(datePart(null)).toBeNull();
    expect(datePart('null')).toBeNull();
    expect(datePart('undefined')).toBeNull();
    expect(formatDayMonth('2026-12-18T00:00:00.000Z')).toBe('18 dic');
    expect(formatDayMonth(undefined)).toBe('—');
  });
  it('formats the long date from local calendar fields (23:30 local stays the same day)', () => {
    expect(formatLongDate(new Date(2026, 10, 27, 23, 30))).toBe('viernes 27 de noviembre');
    expect(formatLongDate(new Date(2026, 10, 27, 0, 5))).toBe('viernes 27 de noviembre');
  });
  it('translates payment status and falls back to a dash', () => {
    expect(paymentLabel('paid')).toBe('Pagado');
    expect(paymentLabel('PAID')).toBe('Pagado');
    expect(paymentLabel('weird')).toBe('—');
    expect(paymentLabel(null)).toBe('—');
  });
});

describe('toRoomViews', () => {
  it('drops the empty-collection marker and rows without id or number', () => {
    expect(toRoomViews([{}])).toEqual([]);
    expect(toRoomViews([{ id: 0, room_number: '1' }, { id: 1, room_number: '' }, null, 'x'])).toEqual([]);
    expect(toRoomViews(undefined)).toEqual([]);
  });
  it('parses numeric strings explicitly and keeps leading zeros in room numbers', () => {
    const [v] = toRoomViews([room({ id: '7', room_number: '007' })]);
    expect(v.id).toBe(7);
    expect(v.room_number).toBe('007');
  });
  it('marks tickets as unknown (null) when the radar flag is missing', () => {
    const [v] = toRoomViews([{ id: 1, room_number: '1', status: 'available' }]);
    expect(v.hasPendingTicket).toBeNull();
  });
});

describe('chips, filters and groups', () => {
  const views = toRoomViews([
    room({ id: 1, room_number: '101', status: 'occupied', isCheckoutDate: true }),
    room({ id: 2, room_number: '102' }),
    room({ id: 3, room_number: '103', cleaning_status: 'dirty' }),
    room({ id: 4, room_number: '104', hasIncomingToday: true }),
    room({ id: 5, room_number: '105', status: 'maintenance', hasPendingTicket: true }),
    room({ id: 6, room_number: '9', type: 'KING' })
  ]);
  it('maps one chip per room', () => {
    expect(views.map(chipKind)).toEqual(['occupied', 'available', 'cleaning', 'reserved', 'maintenance', 'available']);
  });
  it('counts per filter with the classic predicates', () => {
    const c = filterCounts(views);
    expect(c).toMatchObject({ all: 6, available: 2, arrivals: 1, departures: 1, occupied: 1, cleaning: 1, maintenance: 1 });
    expect(RACK_FILTERS.length).toBe(7);
  });
  it('sorts rooms numerically and keeps known groups first', () => {
    const groups = groupRooms(toRoomViews([room({ id: 1, room_number: '10' }), room({ id: 2, room_number: '9' }), room({ id: 3, room_number: '5', type: 'KING' }), room({ id: 4, room_number: '1', type: 'suite' })]));
    expect(groups.map(g => g.label)).toEqual(['King size', 'Doble', 'Suite']);
    expect(groups[1].rooms.map(r => r.room_number)).toEqual(['9', '10']);
  });
  it('searches by room number', () => {
    expect(matchesQuery(views[0], '10')).toBe(true);
    expect(matchesQuery(views[0], ' 9')).toBe(false);
    expect(matchesQuery(views[0], '')).toBe(true);
  });
});

describe('computeKpis', () => {
  const rooms = toRoomViews([
    room({ id: 1, status: 'occupied', isCheckoutDate: true, room_number: '1' }),
    room({ id: 2, room_number: '2', hasIncomingToday: true }),
    room({ id: 3, room_number: '3', cleaning_status: 'dirty', hasPendingTicket: true }),
    room({ id: 4, room_number: '4', status: 'maintenance' })
  ]);
  it('computes with all rooms as the occupancy denominator', () => {
    const k = computeKpis({ rooms, reservationsKnown: true });
    expect(k).toMatchObject({ occupiedRooms: 1, totalRooms: 4, occupancyPercent: 25, arrivalsToday: 1, departuresToday: 1, roomsToClean: 1, roomsWithOpenTicket: 1 });
    expect(occupancyHint(k)).toBe('1 de 4 habitaciones');
    expect(occupancyText(k)).toBe('25%');
  });
  it('shows unknown (null / "—"), never 0, when data is missing', () => {
    const none = computeKpis({ rooms: [], reservationsKnown: false });
    expect(Object.values(none).every(v => v === null)).toBe(true);
    expect(kpiText(none.arrivalsToday)).toBe('—');
    expect(occupancyText(none)).toBe('—');
    const noRes = computeKpis({ rooms, reservationsKnown: false });
    expect(noRes.arrivalsToday).toBeNull();
    expect(noRes.departuresToday).toBeNull();
    expect(noRes.roomsToClean).toBe(1);
  });
  it('treats the tickets KPI as unknown when any room lacks the radar flag', () => {
    const partial = toRoomViews([room({ id: 1, room_number: '1' }), { id: 2, room_number: '2', status: 'available' }]);
    expect(computeKpis({ rooms: partial, reservationsKnown: true }).roomsWithOpenTicket).toBeNull();
  });
  it('keeps zero as a real zero when data is known', () => {
    const calm = toRoomViews([room({ id: 1, room_number: '1' })]);
    const k = computeKpis({ rooms: calm, reservationsKnown: true });
    expect(k.arrivalsToday).toBe(0);
    expect(kpiText(k.arrivalsToday)).toBe('0');
    expect(occupancyPercent(0, 0)).toBeNull();
  });
});

describe('today lists', () => {
  const rooms = toRoomViews([
    room({ id: 1, room_number: '101', status: 'occupied', isCheckoutDate: true }),
    room({ id: 2, room_number: '102', hasIncomingToday: true })
  ]);
  const reservations = validReservations([
    {}, null,
    { id: 1, room_id: '1', status: 'checked_in', check_in: '2026-11-25T00:00:00.000Z', check_out: '2026-11-27T00:00:00.000Z', hotel_guests_data: { full_name: 'A. B.' } },
    { id: 2, room_id: 2, status: 'confirmed', check_in: '2026-11-27T00:00:00.000Z', check_out: '2026-11-29T00:00:00.000Z' }
  ]);
  it('ignores empty-marker rows', () => { expect(reservations.length).toBe(2); });
  it('decorates arrivals and departures, using a dash when the guest is unknown', () => {
    expect(arrivalsToday(rooms, reservations, '2026-11-27')).toEqual([{ roomId: 2, roomNumber: '102', guest: '—' }]);
    expect(departuresToday(rooms, reservations)).toEqual([{ roomId: 1, roomNumber: '101', guest: 'A. B.' }]);
  });
});

describe('nav', () => {
  it('hides ADMIN-only entries for non-admins and keeps all groups for admins', () => {
    const labels = (admin: boolean) => buildNav(admin).flatMap(g => g.links.map(l => l.label));
    expect(labels(false)).toEqual(['Panel', 'Mantenimiento', 'Reservas', 'Huéspedes']);
    expect(labels(true)).toContain('Caja y gastos');
    expect(buildNav(false).map(g => g.title)).toEqual(['Operaciones', 'Administración']);
  });
  it('titles pages', () => {
    expect(pageTitle('/dashboard')).toBe('Panel de operación');
    expect(pageTitle('/dashboard/reservas?x=1')).toBe('Reservas');
    expect(pageTitle('/otro')).toBe('Hotel San José');
  });
});
