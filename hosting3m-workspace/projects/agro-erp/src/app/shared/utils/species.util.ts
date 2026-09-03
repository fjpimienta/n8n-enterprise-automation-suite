/**
 * Criterio único de "especie" para el módulo de ganadería.
 *
 * La especie de un animal puede venir en la raíz del registro (`species`, vía
 * `vw_cattle_kpi`) o, en registros más antiguos, solo dentro del `metadata`
 * JSONB. Ambas pantallas que ofrecen el selector "Filtrar Especie" (el dashboard
 * ejecutivo y el "Censo Biológico Activo") deben derivar la lista de especies
 * disponibles de los datos reales del hato — nunca de una lista hardcodeada —
 * y leerla de esta misma fuente para no volver a desincronizarse.
 */

/** Valor centinela del selector: no filtra por especie. */
export const SPECIES_FILTER_ALL = 'TODOS';

/** Shape mínimo del que se puede extraer la especie. */
type SpeciesBearing = {
  species?: string | null;
  metadata?: string | { species?: unknown;[key: string]: unknown } | null;
};

/**
 * Extrae la especie de un animal de forma segura: primero la raíz, luego el
 * `metadata` (parseando si llega como string JSON). Devuelve `null` si no hay
 * especie o si el `metadata` no es JSON válido.
 */
export function getAnimalSpecies(animal: SpeciesBearing | null | undefined): string | null {
  if (!animal) return null;

  const root = (animal.species ?? '').toString().trim();
  if (root) return root;

  const meta = animal.metadata;
  if (!meta) return null;

  try {
    const parsed = typeof meta === 'string' ? JSON.parse(meta) : meta;
    const fromMeta = (parsed?.species ?? '').toString().trim();
    return fromMeta || null;
  } catch {
    return null;
  }
}

/**
 * Lista ordenada de especies distintas presentes en el hato, para poblar el
 * selector "Filtrar Especie". Blindada contra entradas no iterables.
 */
export function deriveAvailableSpecies(list: readonly SpeciesBearing[] | null | undefined): string[] {
  if (!Array.isArray(list)) {
    console.warn('⚠️ [deriveAvailableSpecies] Se recibió un tipo no iterable:', list);
    return [];
  }

  const speciesSet = new Set<string>();
  for (const animal of list) {
    const species = getAnimalSpecies(animal);
    if (species) speciesSet.add(species);
  }

  return Array.from(speciesSet).sort((a, b) =>
    a.localeCompare(b, 'es', { sensitivity: 'base' })
  );
}

/**
 * Aplica el filtro de especie a una lista de cabezas. `TODOS` (default) no
 * filtra. Se compone SOBRE el conjunto ya filtrado por estado de vida, no lo
 * reemplaza.
 */
export function filterBySpecies<T extends SpeciesBearing>(
  list: readonly T[],
  species: string
): T[] {
  if (!species || species === SPECIES_FILTER_ALL) return [...list];
  return list.filter(animal => getAnimalSpecies(animal) === species);
}
