/**
 * Criterio único de "hato activo" para el módulo de ganadería.
 *
 * Alineado 2026-09-27 con el criterio de la tool `count_livestock` del Agente IA
 * (MCP Server Cattle, v6): un animal deja de contar como hato vivo solo al llegar
 * a un estado terminal — vendido, finalizado o dado de baja por depuración de
 * datos. Cualquier otro `current_status` (ACTIVO, PREÑADA, VACÍA, DESARROLLO,
 * RIESGO, CUARENTENA, EN_TRANSITO, BAJA_MORTANDAD, …) sigue siendo hato activo a
 * efectos de conteo y de la vista por defecto de inventario — incluye
 * BAJA_MORTANDAD porque es una baja pendiente de aprobación, no una salida
 * confirmada del hato (misma decisión de negocio que count_livestock).
 *
 * El historial de venta/baja no se oculta de forma permanente: las pantallas
 * exponen un selector (`HERD_STATUS_FILTER_OPTIONS`) para auditarlo cuando haga falta.
 */

/** Estados que sacan al animal del hato vivo. Comparación normalizada a MAYÚSCULAS. */
export const INACTIVE_HERD_STATUSES: readonly string[] = ['VENDIDO', 'FINALIZADO', 'BAJA_DEPURACION_DATOS'];

/** Opciones del selector "Estado" visible en las tablas de inventario. */
export type HerdStatusFilter = 'ACTIVOS' | 'TODOS' | 'BAJAS';

export const HERD_STATUS_FILTER_OPTIONS: ReadonlyArray<{ value: HerdStatusFilter; label: string }> = [
  { value: 'ACTIVOS', label: 'Activos' },
  { value: 'TODOS', label: 'Todos' },
  { value: 'BAJAS', label: 'Solo bajas y ventas' },
];

/** `true` si el animal cuenta como hato vivo (no vendido ni baja por mortandad). */
export function isActiveHead(animal: { current_status?: string | null } | null | undefined): boolean {
  const status = (animal?.current_status ?? '').trim().toUpperCase();
  return status === '' || !INACTIVE_HERD_STATUSES.includes(status);
}

/**
 * Aplica el filtro de estado de vida a una lista de cabezas.
 * `ACTIVOS` (default) es la vista viva; `BAJAS` solo venta/mortandad; `TODOS` no filtra.
 */
export function filterByHerdStatus<T extends { current_status?: string | null }>(
  list: readonly T[],
  filter: HerdStatusFilter
): T[] {
  switch (filter) {
    case 'TODOS':
      return [...list];
    case 'BAJAS':
      return list.filter(animal => !isActiveHead(animal));
    case 'ACTIVOS':
    default:
      return list.filter(isActiveHead);
  }
}
