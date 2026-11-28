import { RoomView } from './room-view';

/** `null` = unknown. The UI renders it as "—", never as 0. */
export interface Kpis {
  occupiedRooms: number | null;
  totalRooms: number | null;
  /** Whole percent, or null. */
  occupancyPercent: number | null;
  arrivalsToday: number | null;
  departuresToday: number | null;
  roomsToClean: number | null;
  roomsWithOpenTicket: number | null;
}

export interface KpiInput {
  rooms: readonly RoomView[];
  /** True when the reservations list has at least one valid row (an empty list cannot be told apart from a failed load). */
  reservationsKnown: boolean;
}

/**
 * Occupancy rule, kept in one place (owner decision, 2026-11-28): denominator = ALL ACTIVE rooms, rooms in
 * maintenance included. Inactive rooms are already dropped by `toRoomViews`.
 */
export function occupancyPercent(occupied: number, total: number): number | null {
  return total > 0 ? Math.round((occupied / total) * 100) : null;
}

export function computeKpis(input: KpiInput): Kpis {
  const { rooms, reservationsKnown } = input;
  if (rooms.length === 0) {
    return { occupiedRooms: null, totalRooms: null, occupancyPercent: null, arrivalsToday: null, departuresToday: null, roomsToClean: null, roomsWithOpenTicket: null };
  }
  const occupied = rooms.filter(r => r.status === 'occupied').length;
  const ticketsKnown = rooms.every(r => r.hasPendingTicket !== null);
  return {
    occupiedRooms: occupied,
    totalRooms: rooms.length,
    occupancyPercent: occupancyPercent(occupied, rooms.length),
    arrivalsToday: reservationsKnown ? rooms.filter(r => r.hasIncomingToday && r.status === 'available').length : null,
    departuresToday: reservationsKnown ? rooms.filter(r => r.isCheckoutDate && r.status === 'occupied').length : null,
    roomsToClean: rooms.filter(r => r.cleaning_status === 'dirty').length,
    roomsWithOpenTicket: ticketsKnown ? rooms.filter(r => r.hasPendingTicket === true).length : null
  };
}

/** Display text for a KPI count: "—" when unknown. */
export function kpiText(value: number | null): string {
  return value === null ? '—' : String(value);
}

export function occupancyText(k: Kpis): string {
  return k.occupancyPercent === null ? '—' : `${k.occupancyPercent}%`;
}

export function occupancyHint(k: Kpis): string {
  return k.occupiedRooms === null || k.totalRooms === null ? 'Sin datos' : `${k.occupiedRooms} de ${k.totalRooms} habitaciones`;
}
