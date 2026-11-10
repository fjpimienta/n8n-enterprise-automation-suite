/**
 * Criterio único de "hato activo" para el módulo de ganadería.
 *
 * Alineado 2026-09-27 con el criterio de la tool `count_livestock` del Agente IA
 * (MCP Server Cattle, v6): un animal deja de contar como hato vivo solo al llegar
 * a un estado terminal — vendido, finalizado o dado de baja por depuración de
 * datos. Cualquier otro `current_status` (ACTIVO, PREÑADA, VACÍA, DESARROLLO,
 * RIESGO, CUARENTENA, EN_TRANSITO, BAJA_MORTANDAD, …) sigue siendo hato activo a
 * efectos de conteo y de la vista por defecto de inventario.
 *
 * Sobre BAJA_MORTANDAD: ese estado se asigna al APROBAR la baja (`sp_procesar_baja_mortandad`);
 * las solicitudes pendientes se llevan aparte, en `pending_authorizations`. Por eso un animal en
 * BAJA_MORTANDAD es una pérdida confirmada. Los conteos lo siguen incluyendo por ahora, a propósito
 * (alineado con `count_livestock` del Agente IA), hasta que esa regla se revise. El valor estimado
 * y la biomasa del hato SÍ lo excluyen: ver `isValuedHead`.
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

/** `true` si el animal suma al valor estimado y a la biomasa del hato: hato activo y sin baja por mortandad. */
export function isValuedHead(animal: { current_status?: string | null } | null | undefined): boolean {
  return isActiveHead(animal) && (animal?.current_status ?? '').trim().toUpperCase() !== 'BAJA_MORTANDAD';
}

/** Biomasa (kg) del hato valorable: suma el peso de los animales con `isValuedHead`; sin peso válido suma 0. */
export function valuedBiomassKg(list: ReadonlyArray<{ current_status?: string | null; current_weight_kg?: number | string | null }>): number {
  return list.reduce((sum, a) => {
    const w = Number(a.current_weight_kg ?? 0);
    return isValuedHead(a) && Number.isFinite(w) && w > 0 ? sum + w : sum;
  }, 0);
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
