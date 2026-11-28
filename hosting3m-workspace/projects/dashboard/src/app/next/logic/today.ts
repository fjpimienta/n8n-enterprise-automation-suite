import { datePart } from './es-mx';
import { RoomView } from './room-view';

export interface TodayItem { roomId: number; roomNumber: string; guest: string }

interface ReservationLike {
  room_id?: unknown; status?: unknown; check_in?: unknown; check_out?: unknown;
  hotel_guests_data?: { full_name?: unknown } | null;
}

/** Valid reservation rows only (drops the gateway's `[{}]` empty marker and non-objects). */
export function validReservations(rows: readonly unknown[] | null | undefined): ReservationLike[] {
  if (!Array.isArray(rows)) return [];
  return rows.filter((r): r is ReservationLike & { id: unknown } =>
    !!r && typeof r === 'object' && Number.isFinite(Number((r as Record<string, unknown>)['id'])) && Number((r as Record<string, unknown>)['id']) > 0);
}

function guestName(res: ReservationLike | undefined): string {
  const name = res?.hotel_guests_data?.full_name;
  return typeof name === 'string' && name.trim() !== '' ? name.trim() : '—';
}

function status(res: ReservationLike): string {
  return typeof res.status === 'string' ? res.status.toLowerCase().trim() : '';
}

/** Arrivals: the same rooms the "Llegan hoy" filter shows, decorated with the guest of today's pending/confirmed booking. */
export function arrivalsToday(rooms: readonly RoomView[], reservations: readonly ReservationLike[], today: string): TodayItem[] {
  return rooms.filter(r => r.hasIncomingToday && r.status === 'available').map(r => {
    const res = reservations.find(x => Number(x.room_id) === r.id && ['confirmed', 'pending'].includes(status(x)) && datePart(x.check_in) === today);
    return { roomId: r.id, roomNumber: r.room_number, guest: guestName(res) };
  });
}

/** Departures: the same rooms the "Salen hoy" filter shows, decorated with the checked-in guest. */
export function departuresToday(rooms: readonly RoomView[], reservations: readonly ReservationLike[]): TodayItem[] {
  return rooms.filter(r => r.isCheckoutDate && r.status === 'occupied').map(r => {
    const res = reservations.find(x => Number(x.room_id) === r.id && status(x) === 'checked_in');
    return { roomId: r.id, roomNumber: r.room_number, guest: guestName(res) };
  });
}
