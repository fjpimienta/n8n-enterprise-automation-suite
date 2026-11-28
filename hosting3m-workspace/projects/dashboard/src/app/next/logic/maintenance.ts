import { RoomView } from './room-view';

/**
 * Maintenance board ("Mantenimiento") rules for the `next` UI. Pure functions only; read-only (no writes).
 *
 * Owner decisions (2026-11-28):
 *  - Groups by priority: Crítica, Normal, Baja. Unknown or inconsistent data goes to "Revisar datos" (never hidden).
 *  - Order inside a group: oldest first. A ticket older than `MT_OLD_AFTER_DAYS` whole days is "Antiguo".
 *  - Ages are whole days between America/Mexico_City calendar dates (Timezone Armor: `created_at` arrives as an ISO
 *    instant and is converted to its Mexico City date before comparing; no `toISOString()` date keys).
 *  - Only open tickets (`PENDING`). Resolved tickets are not shown. Cost is not shown.
 *  - A room with an open ticket that is not in maintenance is "Con falla pendiente"; one in maintenance is "Bloqueada".
 */
export const MT_OLD_AFTER_DAYS = 3;
export const MT_TIMEZONE = 'America/Mexico_City';

export type MtPriority = 'CRITICAL' | 'NORMAL' | 'LOW';
export type MtGroup = 'critical' | 'normal' | 'low' | 'review';

export const MT_GROUP_ORDER: readonly MtGroup[] = ['critical', 'normal', 'low', 'review'];

export const MT_GROUP_LABEL: Record<MtGroup, string> = {
  critical: 'Crítica',
  normal: 'Normal',
  low: 'Baja',
  review: 'Revisar datos'
};

export const MT_GROUP_HINT: Record<MtGroup, string> = {
  critical: 'Atender primero',
  normal: 'Fallas abiertas de prioridad normal',
  low: 'Fallas abiertas de prioridad baja',
  review: 'Datos incompletos o desconocidos: confirma con mantenimiento'
};

const PRIORITY_GROUP: Record<MtPriority, MtGroup> = { CRITICAL: 'critical', NORMAL: 'normal', LOW: 'low' };

/** Known issue types (as the classic report form stores them) and their Spanish labels. */
export const MT_ISSUE_LABEL: Record<string, string> = {
  PLOMERIA: 'Plomería',
  ELECTRICO: 'Eléctrico',
  AIRE_ACONDICIONADO: 'Aire acondicionado',
  ALBAÑILERIA: 'Albañilería',
  MOBILIARIO: 'Mobiliario',
  TECNOLOGIA: 'Tecnología'
};

export const MT_OTHER_LABEL = 'Otro';

/** Spanish label for an issue type. Unknown or missing types are "Otro". */
export function issueLabel(issueType: string): string {
  return MT_ISSUE_LABEL[issueType.trim().toUpperCase()] ?? MT_OTHER_LABEL;
}

export type MtReviewReason = 'no-id' | 'no-content' | 'unknown-priority' | 'unknown-status' | 'no-room';

export const MT_REASON_LABEL: Record<MtReviewReason, string> = {
  'no-id': 'Sin identificador',
  'no-content': 'Sin descripción ni tipo',
  'unknown-priority': 'Prioridad desconocida',
  'unknown-status': 'Estado desconocido',
  'no-room': 'Sin habitación'
};

/** Validated ticket shape used by the `next` UI (never carries `cost`). */
export interface TicketView {
  id: number | null;
  roomId: number | null;
  /** Upper-cased, trimmed; may be anything the gateway sent. */
  priority: string;
  status: string;
  issueType: string;
  description: string;
  createdAt: string;
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '';
}

function positiveInt(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? n : null;
}

/**
 * Adapter from the service's loosely typed rows. Drops non-objects and empty objects (the gateway returns
 * `data: [{}]` for empty collections); never throws. Numeric ids that arrive as strings are parsed explicitly.
 * Rows without an id are KEPT (they are shown under "Revisar datos").
 */
export function toTicketViews(rows: readonly unknown[] | null | undefined): TicketView[] {
  if (!Array.isArray(rows)) return [];
  const out: TicketView[] = [];
  for (const raw of rows) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw) || Object.keys(raw).length === 0) continue;
    const r = raw as Record<string, unknown>;
    out.push({
      id: positiveInt(r['id']),
      roomId: positiveInt(r['room_id']),
      priority: str(r['priority']).trim().toUpperCase(),
      status: str(r['status']).trim().toUpperCase(),
      issueType: str(r['issue_type']).trim(),
      description: str(r['description']).trim(),
      createdAt: str(r['created_at']).trim()
    });
  }
  return out;
}

/** "YYYY-MM-DD" of an instant in Mexico City, from Intl parts (never `toISOString()`). `null` for an invalid date. */
export function mexicoCityDateKey(instant: Date): string | null {
  if (Number.isNaN(instant.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: MT_TIMEZONE, year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(instant);
  const get = (type: string) => parts.find(p => p.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function dayNumber(key: string): number {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d) / 86_400_000;
}

/** Whole days between the Mexico City dates of `createdAt` and `now` (0 = reported today). `null` if unreadable. */
export function ticketAgeDays(createdAt: string, now: Date): number | null {
  if (createdAt === '') return null;
  const created = mexicoCityDateKey(new Date(createdAt));
  const today = mexicoCityDateKey(now);
  if (created === null || today === null) return null;
  return Math.max(0, dayNumber(today) - dayNumber(created));
}

export function isOldTicket(ageDays: number | null): boolean {
  return ageDays !== null && ageDays > MT_OLD_AFTER_DAYS;
}

/** Spanish age text: "Hoy", "Ayer", "Hace 4 días"; "—" when unknown. */
export function ageText(ageDays: number | null): string {
  if (ageDays === null) return '—';
  if (ageDays === 0) return 'Hoy';
  if (ageDays === 1) return 'Ayer';
  return `Hace ${ageDays} días`;
}

/** Only `PENDING` tickets are open; `RESOLVED` is excluded; anything else is flagged for review. */
export function isResolved(t: TicketView): boolean {
  return t.status === 'RESOLVED';
}

export function reviewReasons(t: TicketView): MtReviewReason[] {
  const reasons: MtReviewReason[] = [];
  if (t.id === null) reasons.push('no-id');
  if (t.description === '' && t.issueType === '') reasons.push('no-content');
  if (!(t.priority in PRIORITY_GROUP)) reasons.push('unknown-priority');
  if (t.status !== 'PENDING') reasons.push('unknown-status');
  if (t.roomId === null) reasons.push('no-room');
  return reasons;
}

export interface MtRoomRef { number: string; status: string }
/** `blocked`: room status is maintenance. `pending`: open ticket but the room is in another status. `unknown`: room not found. */
export type MtRoomState = 'blocked' | 'pending' | 'unknown';

export interface MtItem {
  ticket: TicketView;
  group: MtGroup;
  reasons: MtReviewReason[];
  ageDays: number | null;
  old: boolean;
  room: MtRoomRef | null;
  roomState: MtRoomState;
  /** Stable key for list tracking (tickets without an id get a position-based key). */
  key: string;
}

function roomMap(rooms: readonly RoomView[]): Map<number, MtRoomRef> {
  return new Map(rooms.map(r => [r.id, { number: r.room_number, status: r.status }]));
}

/** Oldest first; unknown age last; then id (missing last); then input order (the sort is stable). */
function compareAge(a: MtItem, b: MtItem): number {
  const ageA = a.ageDays ?? -1;
  const ageB = b.ageDays ?? -1;
  if (ageA !== ageB) return ageB - ageA;
  return (a.ticket.id ?? Number.MAX_SAFE_INTEGER) - (b.ticket.id ?? Number.MAX_SAFE_INTEGER);
}

/** Open tickets as board items: resolved ones are dropped; the rest are grouped and sorted (priority, then oldest first). */
export function buildMaintenanceItems(tickets: readonly TicketView[], rooms: readonly RoomView[], now: Date): MtItem[] {
  const byRoom = roomMap(rooms);
  const items: MtItem[] = [];
  tickets.forEach((ticket, index) => {
    if (isResolved(ticket)) return;
    const reasons = reviewReasons(ticket);
    const group: MtGroup = reasons.length > 0 ? 'review' : PRIORITY_GROUP[ticket.priority as MtPriority];
    const room = ticket.roomId === null ? null : (byRoom.get(ticket.roomId) ?? null);
    const ageDays = ticketAgeDays(ticket.createdAt, now);
    items.push({
      ticket, group, reasons, ageDays, old: isOldTicket(ageDays), room,
      roomState: room === null ? 'unknown' : room.status === 'maintenance' ? 'blocked' : 'pending',
      key: ticket.id !== null ? `t${ticket.id}` : `n${index}`
    });
  });
  const rank = (g: MtGroup) => MT_GROUP_ORDER.indexOf(g);
  return items.sort((a, b) => rank(a.group) - rank(b.group) || compareAge(a, b));
}

export interface MtSection { group: MtGroup; label: string; hint: string; items: MtItem[] }

/** Only non-empty groups, in priority order. */
export function buildMaintenanceSections(items: readonly MtItem[]): MtSection[] {
  return MT_GROUP_ORDER
    .map(group => ({ group, label: MT_GROUP_LABEL[group], hint: MT_GROUP_HINT[group], items: items.filter(i => i.group === group) }))
    .filter(s => s.items.length > 0);
}

/** `null` = unknown. The UI renders it as "—", never as 0. */
export interface MtCounts {
  /** Open tickets with consistent data (critical + normal + low). */
  open: number | null;
  critical: number | null;
  /** Open tickets older than `MT_OLD_AFTER_DAYS` days (any group; unknown ages are not counted). */
  old: number | null;
  /** Tickets under "Revisar datos". */
  review: number | null;
  /** Rooms whose status is maintenance. */
  blockedRooms: number | null;
  /** Rooms with an open ticket whose status is not maintenance. */
  pendingRooms: number | null;
}

const UNKNOWN: MtCounts = { open: null, critical: null, old: null, review: null, blockedRooms: null, pendingRooms: null };

/**
 * Counters. `ticketsKnown` is false when the ticket list came back with no readable row at all: an empty answer
 * cannot be told apart from a failed load (the service hides `error:true`), so ticket counts are unknown ("—").
 * A list that holds only resolved tickets IS known: zero open tickets is then a real zero.
 */
export function computeMaintenanceCounts(items: readonly MtItem[], rooms: readonly RoomView[], ticketsKnown: boolean): MtCounts {
  const roomsKnown = rooms.length > 0;
  const blockedRooms = roomsKnown ? rooms.filter(r => r.status === 'maintenance').length : null;
  if (!ticketsKnown) return { ...UNKNOWN, blockedRooms };
  const count = (g: MtGroup) => items.filter(i => i.group === g).length;
  const pendingIds = new Set(items.filter(i => i.roomState === 'pending' && i.ticket.roomId !== null).map(i => i.ticket.roomId));
  return {
    open: count('critical') + count('normal') + count('low'),
    critical: count('critical'),
    old: items.filter(i => i.old).length,
    review: count('review'),
    blockedRooms,
    pendingRooms: roomsKnown ? pendingIds.size : null
  };
}

export function countText(value: number | null): string {
  return value === null ? '—' : String(value);
}
