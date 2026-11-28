import { ChipKind } from './es-mx';

/** Validated, typed room shape used by the `next` UI. Inactive rooms never reach it (see `toRoomViews`). */
export interface RoomView {
  id: number;
  room_number: string;
  type: string;
  status: string;
  cleaning_status: string;
  description: string;
  displayDate: string | null;
  isCheckoutDate: boolean;
  hasIncomingToday: boolean;
  /** `true`/`false` when the tickets radar answered, `null` when it did not (unknown). */
  hasPendingTicket: boolean | null;
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '';
}

/** `is_active` is false only when it says so: missing or unreadable means active. */
export function isActiveRoom(raw: Record<string, unknown>): boolean {
  const v = raw['is_active'];
  return !(v === false || v === 'false' || v === 'f' || v === 0 || v === '0');
}

/**
 * Adapter from the service's loosely typed rows. Drops rows without an identifier (the gateway
 * returns `data: [{}]` for empty collections) and never throws on malformed input. Numeric ids that
 * arrive as strings are parsed explicitly. Inactive rooms (`is_active` false) are dropped: the rooms model has no
 * default filter, so the gateway sends them, and they must not count in the occupancy denominator or any list.
 */
export function toRoomViews(rows: readonly unknown[] | null | undefined): RoomView[] {
  if (!Array.isArray(rows)) return [];
  const out: RoomView[] = [];
  for (const raw of rows) {
    if (!raw || typeof raw !== 'object') continue;
    const r = raw as Record<string, unknown>;
    if (!isActiveRoom(r)) continue;
    const id = Number(r['id']);
    const number = str(r['room_number']).trim();
    if (!Number.isFinite(id) || id <= 0 || number === '') continue;
    out.push({
      id,
      room_number: number,
      type: str(r['type']).toUpperCase().trim(),
      status: str(r['status']).toLowerCase().trim(),
      cleaning_status: str(r['cleaning_status']).toLowerCase().trim(),
      description: str(r['description']),
      displayDate: typeof r['displayDate'] === 'string' ? (r['displayDate'] as string) : null,
      isCheckoutDate: r['isCheckoutDate'] === true,
      hasIncomingToday: r['hasIncomingToday'] === true,
      hasPendingTicket: typeof r['hasPendingTicket'] === 'boolean' ? (r['hasPendingTicket'] as boolean) : null
    });
  }
  return out;
}

/** The single status shown as the card chip. */
export function chipKind(room: RoomView): ChipKind {
  if (room.status === 'maintenance') return 'maintenance';
  if (room.status === 'occupied') return 'occupied';
  if (room.cleaning_status === 'dirty') return 'cleaning';
  if (room.hasIncomingToday) return 'reserved';
  return 'available';
}

export type RackFilter = 'all' | 'available' | 'arrivals' | 'departures' | 'occupied' | 'cleaning' | 'maintenance';

/** Same predicates as the classic Room Rack filters, so both UIs agree on every count. */
export const RACK_FILTERS: { value: RackFilter; label: string; test: (r: RoomView) => boolean }[] = [
  { value: 'all', label: 'Todas', test: () => true },
  { value: 'available', label: 'Disponibles', test: r => r.status === 'available' && r.cleaning_status !== 'dirty' && !r.hasIncomingToday },
  { value: 'arrivals', label: 'Llegan hoy', test: r => r.hasIncomingToday && r.status === 'available' },
  { value: 'departures', label: 'Salen hoy', test: r => r.isCheckoutDate && r.status === 'occupied' },
  { value: 'occupied', label: 'Ocupadas', test: r => r.status === 'occupied' },
  { value: 'cleaning', label: 'Limpieza', test: r => r.cleaning_status === 'dirty' },
  { value: 'maintenance', label: 'Mantenimiento', test: r => r.status === 'maintenance' || r.hasPendingTicket === true }
];

export function filterPredicate(filter: RackFilter): (r: RoomView) => boolean {
  return (RACK_FILTERS.find(f => f.value === filter) ?? RACK_FILTERS[0]).test;
}

export function filterCounts(rooms: readonly RoomView[]): Record<RackFilter, number> {
  const counts = {} as Record<RackFilter, number>;
  for (const f of RACK_FILTERS) counts[f.value] = rooms.filter(f.test).length;
  return counts;
}

export function matchesQuery(room: RoomView, query: string): boolean {
  const q = query.trim().toLowerCase();
  return q === '' || room.room_number.toLowerCase().includes(q);
}

export interface RackGroup { key: string; label: string; rooms: RoomView[] }

const GROUP_ORDER: { key: string; label: string }[] = [
  { key: 'SENCILLA', label: 'Sencilla' },
  { key: 'KING', label: 'King size' },
  { key: 'DOBLE', label: 'Doble' },
  { key: 'TRIPLE', label: 'Triple' },
  { key: 'INDIVIDUAL', label: 'Individual' }
];

function groupKey(type: string): string {
  const t = type.toUpperCase();
  if (t.includes('KING')) return 'KING';
  if (t.includes('SENCILLA')) return 'SENCILLA';
  if (t.includes('DOBLE')) return 'DOBLE';
  if (t.includes('TRIPLE')) return 'TRIPLE';
  return t === '' ? 'OTRAS' : t;
}

function titleCase(key: string): string {
  return key.charAt(0) + key.slice(1).toLowerCase();
}

/** Groups by room type (known order first, then others), rooms sorted numerically by number. */
export function groupRooms(rooms: readonly RoomView[]): RackGroup[] {
  const map = new Map<string, RoomView[]>();
  for (const room of rooms) {
    const key = groupKey(room.type);
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(room);
  }
  const sort = (a: RoomView, b: RoomView) => a.room_number.localeCompare(b.room_number, 'es', { numeric: true });
  const groups: RackGroup[] = [];
  for (const g of GROUP_ORDER) {
    const list = map.get(g.key);
    if (list?.length) { groups.push({ key: g.key, label: g.label, rooms: [...list].sort(sort) }); map.delete(g.key); }
  }
  for (const [key, list] of map) groups.push({ key, label: titleCase(key), rooms: [...list].sort(sort) });
  return groups;
}
