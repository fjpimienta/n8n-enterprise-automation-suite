/**
 * In-memory write store for the demo build (housekeeping only).
 *
 * Isolation rules, by design:
 * - Module-level state only: it lives for the life of the page and is gone on reload. No `localStorage`,
 *   `sessionStorage`, `IndexedDB`, cookies or service-worker cache are used, and nothing is ever sent anywhere.
 * - It accepts exactly one write: `hotel_rooms` / `update` with `fields` holding ONLY `cleaning_status`, set to a
 *   value of the allowed set, on a room that exists in the synthetic data. Everything else is refused.
 * - It mirrors what the gateway would accept; the business transition rule (only free + dirty becomes clean) is
 *   enforced by the UI logic layer, not here, so a test can prove the UI never asks for anything else.
 */
import { DemoRoom, buildDemoRooms } from './demo-data';

export type DemoCleaning = DemoRoom['cleaning_status'];

export const DEMO_CLEANING_VALUES: readonly DemoCleaning[] = ['clean', 'dirty', 'inspected'];

const overrides = new Map<number, DemoCleaning>();

/** Rooms with the in-memory cleaning changes applied (the seed itself is never mutated). */
export function withCleaningOverrides(rooms: readonly DemoRoom[]): DemoRoom[] {
  return rooms.map(r => (overrides.has(r.id) ? { ...r, cleaning_status: overrides.get(r.id)! } : r));
}

export type DemoWriteResult = { ok: true; id: number; cleaning_status: DemoCleaning } | { ok: false; message: string };

/** Validates and applies one `hotel_rooms` update body. Never throws. */
export function applyRoomUpdate(body: unknown): DemoWriteResult {
  if (!body || typeof body !== 'object') return { ok: false, message: 'Demo: invalid body' };
  const b = body as Record<string, unknown>;
  if (b['operation'] !== 'update') return { ok: false, message: 'Demo: unsupported operation' };

  const id = typeof b['id'] === 'number' || typeof b['id'] === 'string' ? Number(b['id']) : NaN;
  if (!Number.isInteger(id) || id <= 0) return { ok: false, message: 'Demo: invalid id' };
  if (!buildDemoRooms().some(r => r.id === id)) return { ok: false, message: 'Demo: unknown room' };

  const fields = b['fields'];
  if (!fields || typeof fields !== 'object' || Array.isArray(fields)) return { ok: false, message: 'Demo: invalid fields' };
  const keys = Object.keys(fields as object);
  if (keys.length !== 1 || keys[0] !== 'cleaning_status') return { ok: false, message: 'Demo: only cleaning_status can be updated' };

  const value = (fields as Record<string, unknown>)['cleaning_status'];
  if (typeof value !== 'string' || !DEMO_CLEANING_VALUES.includes(value as DemoCleaning)) {
    return { ok: false, message: 'Demo: invalid cleaning_status' };
  }
  overrides.set(id, value as DemoCleaning);
  return { ok: true, id, cleaning_status: value as DemoCleaning };
}

/** Clears every in-memory change (tests; a page reload does the same). */
export function resetDemoStore(): void {
  overrides.clear();
}
