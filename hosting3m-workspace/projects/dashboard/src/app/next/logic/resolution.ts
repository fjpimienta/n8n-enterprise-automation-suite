import { TicketView } from './maintenance';

/**
 * What happens to a room when one of its faults is resolved. Pure functions only (no writes here).
 *
 * Owner decisions (2026-11-28):
 *  - R1: resolving the LAST open fault of a room sends it to cleaning: status `available` and cleaning `dirty`.
 *  - R2: if other faults are still open the room is NOT freed (a room in maintenance stays in maintenance).
 *  - A ticket with an unknown or missing status counts as open; `DELETED` never counts; `RESOLVED` is not open.
 *  - An occupied room is never freed or changed: only the fault is resolved.
 *  - Nothing records who resolved a fault (R9); the only fields written are `status` and `resolved_at`.
 */
export const TICKET_RESOLVED = 'RESOLVED';
const TICKET_DELETED = 'DELETED';

/** Open = anything that is not resolved and not deleted (unknown or empty status is open, on purpose). */
export function countsAsOpen(status: string): boolean {
  const s = status.trim().toUpperCase();
  return s !== TICKET_RESOLVED && s !== TICKET_DELETED;
}

/** Fields the UI may write on a room after a resolution. Never anything else. */
export interface RoomWrite { status?: 'available'; cleaning_status: 'dirty' }

export type ResolutionOutcome = 'sent-to-cleaning' | 'faults-remain' | 'room-occupied' | 'room-unknown' | 'room-status-unknown';

export interface ResolutionPlan {
  /** Other open faults of the room, not counting the one being resolved. */
  remaining: number;
  outcome: ResolutionOutcome;
  /** `null` = the room is not written. */
  roomWrite: RoomWrite | null;
  /** Spanish confirmation text for the user. */
  message: string;
}

export interface ResolutionRoom { number: string; status: string; cleaning_status: string }

export interface ResolutionInput {
  /** Fresh tickets of the room (re-read right before deciding). */
  tickets: readonly TicketView[];
  /** The ticket being resolved; `null` when re-checking a room after a partial failure. */
  ticketId: number | null;
  roomId: number;
  /** `null` when the room is not in the (active) room list. */
  room: ResolutionRoom | null;
}

export function remainingFaultsText(n: number): string {
  return n === 1 ? 'queda 1 falla pendiente' : `quedan ${n} fallas pendientes`;
}

/** Other open faults of the room: the ticket being resolved is excluded, rows without id are counted (conservative). */
export function otherOpenFaults(tickets: readonly TicketView[], roomId: number, ticketId: number | null): number {
  return tickets.filter(t => t.roomId === roomId && (ticketId === null || t.id !== ticketId) && countsAsOpen(t.status)).length;
}

export function planResolution(input: ResolutionInput): ResolutionPlan {
  const { tickets, ticketId, roomId, room } = input;
  const remaining = otherOpenFaults(tickets, roomId, ticketId);
  if (room === null) {
    return {
      remaining, outcome: 'room-unknown', roomWrite: null,
      message: 'Falla resuelta. No se encontró la habitación en la lista; revisa su estado.'
    };
  }
  const n = room.number;
  if (remaining > 0) {
    return {
      remaining, outcome: 'faults-remain', roomWrite: null,
      message: room.status === 'maintenance'
        ? `Falla resuelta. La habitación ${n} sigue en mantenimiento: ${remainingFaultsText(remaining)}.`
        : `Falla resuelta. En la habitación ${n} ${remainingFaultsText(remaining)}.`
    };
  }
  if (room.status === 'maintenance') {
    return {
      remaining, outcome: 'sent-to-cleaning', roomWrite: { status: 'available', cleaning_status: 'dirty' },
      message: `Falla resuelta. La habitación ${n} se envió a limpieza.`
    };
  }
  if (room.status === 'available') {
    return {
      remaining, outcome: 'sent-to-cleaning',
      roomWrite: room.cleaning_status === 'dirty' ? null : { cleaning_status: 'dirty' },
      message: `Falla resuelta. La habitación ${n} se envió a limpieza.`
    };
  }
  if (room.status === 'occupied') {
    return {
      remaining, outcome: 'room-occupied', roomWrite: null,
      message: `Falla resuelta. La habitación ${n} sigue ocupada; no se cambió su estado.`
    };
  }
  return {
    remaining, outcome: 'room-status-unknown', roomWrite: null,
    message: `Falla resuelta. La habitación ${n} tiene un estado desconocido; revisa su estado.`
  };
}

/** Request body for resolving a ticket: exactly `status` and `resolved_at`, in the format the classic flow writes. */
export function buildResolveFields(now: Date): { status: typeof TICKET_RESOLVED; resolved_at: string } {
  return { status: TICKET_RESOLVED, resolved_at: now.toISOString() };
}
