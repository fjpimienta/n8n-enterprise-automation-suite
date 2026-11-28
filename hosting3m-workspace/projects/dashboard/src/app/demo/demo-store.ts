/**
 * In-memory write store for the demo build (housekeeping and maintenance only).
 *
 * Isolation rules, by design:
 * - Module-level state only: it lives for the life of the page and is gone on reload. No `localStorage`,
 *   `sessionStorage`, `IndexedDB`, cookies or service-worker cache are used, and nothing is ever sent anywhere.
 * - It accepts exactly two kinds of write, each on a record that exists in the synthetic data:
 *   1. `hotel_rooms` / `update` whose `fields` hold ONLY `cleaning_status` (a value of the allowed set) and/or
 *      `status` set to `available`;
 *   2. `hotel_maintenance_tickets` / `update` whose `fields` hold EXACTLY `status: 'RESOLVED'` and a readable
 *      `resolved_at` instant.
 *   Everything else is refused.
 * - It mirrors what the gateway would accept; the business rules (who may do it, when a room is freed) are enforced
 *   by the UI logic layer, not here, so a test can prove the UI never asks for anything else.
 */
import { DemoRoom, DemoTicket, buildDemoRooms, buildDemoTickets } from './demo-data';

export type DemoCleaning = DemoRoom['cleaning_status'];

export const DEMO_CLEANING_VALUES: readonly DemoCleaning[] = ['clean', 'dirty', 'inspected'];

interface RoomOverlay { cleaning_status?: DemoCleaning; status?: 'available' }
const roomOverrides = new Map<number, RoomOverlay>();
const ticketOverrides = new Map<number, { status: 'RESOLVED'; resolved_at: string }>();

/** Rooms with the in-memory changes applied (the seed itself is never mutated). */
export function withRoomOverrides(rooms: readonly DemoRoom[]): DemoRoom[] {
  return rooms.map(r => (roomOverrides.has(r.id) ? { ...r, ...roomOverrides.get(r.id)! } : r));
}

/** Kept for the cleaning-only callers and tests; same overlay. */
export const withCleaningOverrides = withRoomOverrides;

/** Tickets with the in-memory resolutions applied. */
export function withTicketOverrides(tickets: readonly DemoTicket[]): (DemoTicket & { resolved_at?: string })[] {
  return tickets.map(t => (t.id !== undefined && ticketOverrides.has(t.id) ? { ...t, ...ticketOverrides.get(t.id)! } : t));
}

export type DemoWriteResult =
  | { ok: true; id: number; fields: Record<string, string> }
  | { ok: false; message: string };

function parseId(b: Record<string, unknown>): number {
  return typeof b['id'] === 'number' || typeof b['id'] === 'string' ? Number(b['id']) : NaN;
}

function plainFields(b: Record<string, unknown>): Record<string, unknown> | null {
  const f = b['fields'];
  return f && typeof f === 'object' && !Array.isArray(f) ? (f as Record<string, unknown>) : null;
}

/** Validates and applies one `hotel_rooms` update body. Never throws. */
export function applyRoomUpdate(body: unknown): DemoWriteResult {
  if (!body || typeof body !== 'object') return { ok: false, message: 'Demo: invalid body' };
  const b = body as Record<string, unknown>;
  if (b['operation'] !== 'update') return { ok: false, message: 'Demo: unsupported operation' };

  const id = parseId(b);
  if (!Number.isInteger(id) || id <= 0) return { ok: false, message: 'Demo: invalid id' };
  if (!buildDemoRooms().some(r => r.id === id)) return { ok: false, message: 'Demo: unknown room' };

  const fields = plainFields(b);
  if (!fields) return { ok: false, message: 'Demo: invalid fields' };
  const keys = Object.keys(fields);
  if (keys.length === 0 || keys.some(k => k !== 'cleaning_status' && k !== 'status')) {
    return { ok: false, message: 'Demo: only cleaning_status and status can be updated' };
  }
  const overlay: RoomOverlay = {};
  if ('cleaning_status' in fields) {
    const value = fields['cleaning_status'];
    if (typeof value !== 'string' || !DEMO_CLEANING_VALUES.includes(value as DemoCleaning)) {
      return { ok: false, message: 'Demo: invalid cleaning_status' };
    }
    overlay.cleaning_status = value as DemoCleaning;
  }
  if ('status' in fields) {
    if (fields['status'] !== 'available') return { ok: false, message: 'Demo: invalid status' };
    overlay.status = 'available';
  }
  roomOverrides.set(id, { ...roomOverrides.get(id), ...overlay });
  return { ok: true, id, fields: { ...overlay } as Record<string, string> };
}

/** Validates and applies one `hotel_maintenance_tickets` update body (resolution only). Never throws. */
export function applyTicketUpdate(body: unknown): DemoWriteResult {
  if (!body || typeof body !== 'object') return { ok: false, message: 'Demo: invalid body' };
  const b = body as Record<string, unknown>;
  if (b['operation'] !== 'update') return { ok: false, message: 'Demo: unsupported operation' };

  const id = parseId(b);
  if (!Number.isInteger(id) || id <= 0) return { ok: false, message: 'Demo: invalid id' };
  if (!buildDemoTickets().some(t => t.id === id)) return { ok: false, message: 'Demo: unknown ticket' };

  const fields = plainFields(b);
  if (!fields) return { ok: false, message: 'Demo: invalid fields' };
  const keys = Object.keys(fields).sort();
  if (keys.length !== 2 || keys[0] !== 'resolved_at' || keys[1] !== 'status') {
    return { ok: false, message: 'Demo: only status and resolved_at can be updated' };
  }
  const resolvedAt = fields['resolved_at'];
  if (fields['status'] !== 'RESOLVED') return { ok: false, message: 'Demo: invalid status' };
  if (typeof resolvedAt !== 'string' || Number.isNaN(Date.parse(resolvedAt))) return { ok: false, message: 'Demo: invalid resolved_at' };

  ticketOverrides.set(id, { status: 'RESOLVED', resolved_at: resolvedAt });
  return { ok: true, id, fields: { status: 'RESOLVED', resolved_at: resolvedAt } };
}

/** Clears every in-memory change (tests; a page reload does the same). */
export function resetDemoStore(): void {
  roomOverrides.clear();
  ticketOverrides.clear();
}
