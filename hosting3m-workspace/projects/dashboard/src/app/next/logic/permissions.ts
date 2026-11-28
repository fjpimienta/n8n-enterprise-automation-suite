/**
 * Who may do what in the `next` UI. UI-only gating: it hides or refuses actions in the browser; it is not a
 * security control and says nothing about what any server enforces.
 *
 * The rules are DATA (`ROLE_ACTIONS`), not scattered role checks: adding a role later (for example a maintenance
 * or housekeeping role) is one new row here, with no change in any component.
 *
 * Owner decisions (2026-11-28): only ADMIN resolves a fault and sees repair cost; ADMIN and EDITOR mark a room clean.
 */
export type NextAction = 'resolveTicket' | 'finishCleaning' | 'viewRepairCost';

/** Role (upper-case) to the actions it may perform. A role that is not listed may do nothing. */
export const ROLE_ACTIONS: ReadonlyMap<string, ReadonlySet<NextAction>> = new Map<string, ReadonlySet<NextAction>>([
  ['ADMIN', new Set<NextAction>(['resolveTicket', 'finishCleaning', 'viewRepairCost'])],
  ['EDITOR', new Set<NextAction>(['finishCleaning'])]
]);

/** Trimmed, upper-cased role; `''` for anything that is not text. */
export function normalizeRole(role: unknown): string {
  return typeof role === 'string' ? role.trim().toUpperCase() : '';
}

/**
 * True only when the role is listed and holds the action. Fail-closed: a missing, empty, non-text or unknown role
 * (including names such as "constructor" that exist on every object) is denied.
 */
export function can(role: unknown, action: NextAction): boolean {
  return ROLE_ACTIONS.get(normalizeRole(role))?.has(action) ?? false;
}

export const DENIED_RESOLVE_TEXT = 'Solo un administrador puede resolver fallas. Aquí puedes consultarlas.';
export const DENIED_CLEANING_TEXT = 'Tu rol no puede marcar habitaciones como limpias.';
