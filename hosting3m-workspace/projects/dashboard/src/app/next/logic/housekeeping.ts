import { RoomView } from './room-view';

/**
 * Housekeeping ("Limpieza") priority and transition rules for the `next` UI. Pure functions only.
 *
 * Priority order (owner decision, 2026-11-27). Lower rank = shown first:
 *  1. `turnover`  – occupied, leaves today AND a booking arrives today (same-day turnover; not actionable yet).
 *  2. `arrival`   – free and dirty, a booking arrives today (actionable, urgent).
 *  3. `dirty`     – free and dirty, no arrival today (actionable).
 *  4. `departure` – occupied, leaves today, no arrival today (upcoming; not actionable).
 *  5. `ready`     – free and clean or inspected (same predicate as the rack's "available").
 *  6. `blocked`   – status "maintenance" (no action).
 *  7. `review`    – data that does not add up (occupied but dirty, unknown status or cleaning state). Shown with a
 *                   "Revisar datos" marker and no action; never hidden.
 * Occupied rooms that do not leave today (stay-overs) are only counted, never listed.
 */
export type HkGroup = 'turnover' | 'arrival' | 'dirty' | 'departure' | 'ready' | 'blocked' | 'review';

export const HK_GROUP_ORDER: readonly HkGroup[] = ['turnover', 'arrival', 'dirty', 'departure', 'ready', 'blocked', 'review'];

export const HK_GROUP_LABEL: Record<HkGroup, string> = {
  turnover: 'Salida y llegada hoy',
  arrival: 'Sucias con llegada hoy',
  dirty: 'Por limpiar',
  departure: 'Salidas de hoy',
  ready: 'Listas',
  blocked: 'Bloqueadas por mantenimiento',
  review: 'Revisar datos'
};

export const HK_GROUP_HINT: Record<HkGroup, string> = {
  turnover: 'Ocupadas que salen hoy y reciben otra llegada',
  arrival: 'Límpialas primero',
  dirty: 'Libres y sucias',
  departure: 'Ocupadas: aún no se pueden limpiar',
  ready: 'Limpias',
  blocked: 'Sin acción desde esta pantalla',
  review: 'Estado inconsistente: confirma con recepción'
};

/** The only cleaning value this module may ever write. `inspected` is never written. */
export const FINISHED_CLEANING = 'clean' as const;

export interface HkItem {
  room: RoomView;
  group: HkGroup;
  /** True only when "Finalizar limpieza" may be offered. */
  canFinish: boolean;
  /** True when the row carries the "Revisar datos" marker. */
  needsReview: boolean;
}

const READY_VALUES = ['clean', 'inspected'];

/** Transition rule, enforced here and not in the template: only free + dirty becomes clean. */
export function canFinishCleaning(room: Pick<RoomView, 'status' | 'cleaning_status'>): boolean {
  return room.status === 'available' && room.cleaning_status === 'dirty';
}

/** Group of one room, or `stayover` (occupied, clean, not leaving today: counted but never listed). */
export function classifyRoom(room: RoomView): { group: HkGroup | 'stayover'; needsReview: boolean } {
  const cleaning = room.cleaning_status;
  const cleaningKnown = cleaning === 'dirty' || READY_VALUES.includes(cleaning);

  if (room.status === 'maintenance') return { group: 'blocked', needsReview: false };

  if (room.status === 'occupied') {
    const leaving: HkGroup = room.hasIncomingToday ? 'turnover' : 'departure';
    if (cleaningKnown && cleaning !== 'dirty') {
      return { group: room.isCheckoutDate ? leaving : 'stayover', needsReview: false };
    }
    // An occupied room is never expected to be dirty or unknown (check-in marks it clean): flag it, offer no action.
    return { group: room.isCheckoutDate ? leaving : 'review', needsReview: true };
  }

  if (room.status === 'available') {
    if (cleaning === 'dirty') return { group: room.hasIncomingToday ? 'arrival' : 'dirty', needsReview: false };
    if (READY_VALUES.includes(cleaning)) return { group: 'ready', needsReview: false };
  }
  return { group: 'review', needsReview: true };
}

/** Occupied, clean and not leaving today. */
export function isStayOver(room: RoomView): boolean {
  return classifyRoom(room).group === 'stayover';
}

/** Natural room-number order for text numbers ("007" before "10"); ties broken by id so the order is stable. */
export function compareRoomNumbers(a: RoomView, b: RoomView): number {
  const byNumber = a.room_number.localeCompare(b.room_number, 'es', { numeric: true, sensitivity: 'base' });
  return byNumber !== 0 ? byNumber : a.id - b.id;
}

export function buildHousekeepingItems(rooms: readonly RoomView[]): HkItem[] {
  const items: HkItem[] = [];
  for (const room of rooms) {
    const { group, needsReview } = classifyRoom(room);
    if (group === 'stayover') continue;
    items.push({ room, group, needsReview, canFinish: canFinishCleaning(room) });
  }
  const rank = (g: HkGroup) => HK_GROUP_ORDER.indexOf(g);
  return items.sort((a, b) => rank(a.group) - rank(b.group) || compareRoomNumbers(a.room, b.room));
}

export interface HkSection { group: HkGroup; label: string; hint: string; items: HkItem[] }

/** Only non-empty groups, in priority order. */
export function buildSections(items: readonly HkItem[]): HkSection[] {
  return HK_GROUP_ORDER
    .map(group => ({ group, label: HK_GROUP_LABEL[group], hint: HK_GROUP_HINT[group], items: items.filter(i => i.group === group) }))
    .filter(s => s.items.length > 0);
}

/** `null` = unknown. The UI renders it as "—", never as 0. */
export interface HkCounts {
  /** Dirty and free, to be cleaned now (arrival + dirty). */
  toClean: number | null;
  /** Dirty, free and arriving today. */
  urgent: number | null;
  /** Occupied rooms that leave today (turnover + departure). */
  departures: number | null;
  ready: number | null;
  stayOvers: number | null;
  blocked: number | null;
  review: number | null;
}

const UNKNOWN: HkCounts = { toClean: null, urgent: null, departures: null, ready: null, stayOvers: null, blocked: null, review: null };

/**
 * Counters. With no rooms everything is unknown. Without reservations data (an empty list cannot be told
 * apart from a failed load) the arrival/departure-derived counts are unknown, because the room flags that
 * feed them (`hasIncomingToday`, `isCheckoutDate`) default to false.
 */
export function computeHousekeepingCounts(rooms: readonly RoomView[], reservationsKnown: boolean): HkCounts {
  if (rooms.length === 0) return UNKNOWN;
  const items = buildHousekeepingItems(rooms);
  const count = (g: HkGroup) => items.filter(i => i.group === g).length;
  const dirtyFree = count('arrival') + count('dirty');
  return {
    toClean: dirtyFree,
    urgent: reservationsKnown ? count('arrival') : null,
    departures: reservationsKnown ? count('turnover') + count('departure') : null,
    ready: count('ready'),
    stayOvers: reservationsKnown ? rooms.filter(isStayOver).length : null,
    blocked: count('blocked'),
    review: count('review')
  };
}

export function countText(value: number | null): string {
  return value === null ? '—' : String(value);
}
