/**
 * Criterio único de "lote" para el módulo de ganadería.
 *
 * Un lote (`production_unit_lots`) es una parcela físicamente distinta dentro de
 * una UPP (ej. "El Triunfo", "Rancho 54", "La Calzada" en UPP 54) — no confundir
 * con un potrero (`production_unit_paddocks`, subdivisión de pastoreo dentro de
 * una parcela). `cattle_livestock.lot_id` referencia siempre un lote de la MISMA
 * `production_unit_id` que el animal (`fn_guard_livestock_lot`, migración 050), y
 * `lot_name` es único por `production_unit_id` (índice `uq_lot_name_per_unit`).
 *
 * El frontend nunca consulta `production_unit_lots` directamente: `vw_cattle_kpi`
 * (la vista real que consume la app, migración 056) ya trae `lot_name` aplanado
 * en cada registro de `Livestock`, igual que `species` — por eso el selector
 * "Filtrar Lote" se deriva de los datos ya cargados, sin nuevo endpoint. Como
 * `cattleList` llega desde `CattleDataService` ya acotado al tenant activo, un
 * lote de otro tenant nunca puede aparecer en la lista derivada.
 *
 * Ambas pantallas que ofrecen "Filtrar Lote" (el dashboard ejecutivo y el "Censo
 * Biológico Activo") deben leer de esta misma fuente — mismo patrón que
 * @shared/utils/species.util.
 */

/** Valor centinela del selector: no filtra por lote. */
export const LOT_FILTER_ALL = 'TODOS';

/** Shape mínimo del que se puede extraer el lote. */
type LotBearing = {
  lot_name?: string | null;
};

/** Extrae el lote de un animal de forma segura. Devuelve `null` si no tiene lote asignado. */
export function getAnimalLot(animal: LotBearing | null | undefined): string | null {
  const lot = (animal?.lot_name ?? '').toString().trim();
  return lot || null;
}

/**
 * Lista ordenada de lotes distintos presentes en el hato, para poblar el
 * selector "Filtrar Lote". Solo incluye lotes con al menos una cabeza real en
 * los datos ya cargados (nunca lotes vacíos de `production_unit_lots`), y
 * blindada contra entradas no iterables.
 */
export function deriveAvailableLots(list: readonly LotBearing[] | null | undefined): string[] {
  if (!Array.isArray(list)) {
    console.warn('⚠️ [deriveAvailableLots] Se recibió un tipo no iterable:', list);
    return [];
  }

  const lotSet = new Set<string>();
  for (const animal of list) {
    const lot = getAnimalLot(animal);
    if (lot) lotSet.add(lot);
  }

  return Array.from(lotSet).sort((a, b) =>
    a.localeCompare(b, 'es', { sensitivity: 'base' })
  );
}

/**
 * Aplica el filtro de lote a una lista de cabezas. `TODOS` (default) no
 * filtra. Se compone SOBRE el conjunto ya filtrado por estado/especie, no lo
 * reemplaza.
 */
export function filterByLot<T extends LotBearing>(
  list: readonly T[],
  lot: string
): T[] {
  if (!lot || lot === LOT_FILTER_ALL) return [...list];
  return list.filter(animal => getAnimalLot(animal) === lot);
}
