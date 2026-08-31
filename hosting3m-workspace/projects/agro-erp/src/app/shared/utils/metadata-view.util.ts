/**
 * Utilidades de presentación para el campo `metadata` (JSONB) de cattle_livestock.
 *
 * El shape de `metadata` NO es fijo: cada animal puede traer claves distintas
 * (raza, edad_declarada, `procedencia` anidada de la migración 038, notas de
 * transcripción, flags técnicos, etc.). Estas funciones lo normalizan a una
 * estructura de árbol legible sin asumir claves concretas.
 */

/**
 * Claves puramente técnicas, sin valor informativo para el ganadero.
 * Se siguen mostrando dentro del modal, pero NO cuentan para decidir si la fila
 * merece un ícono de "Detalle" (ver `hasDisplayableMetadata`).
 */
const TECHNICAL_KEYS = new Set<string>(['peso_no_registrado']);

export interface MetadataNode {
  label: string;
  /** Presente solo en hojas. */
  value?: string;
  /** Presente solo en ramas (objeto/arreglo anidado). */
  children?: MetadataNode[];
}

/** Convierte el `metadata` crudo (objeto, string JSON, null…) en un objeto plano seguro. */
export function parseMetadata(raw: unknown): Record<string, unknown> {
  if (!raw) return {};

  let value: unknown = raw;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (!trimmed) return {};
    try {
      value = JSON.parse(trimmed);
    } catch {
      return {};
    }
  }

  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

/**
 * `true` si, tras excluir claves puramente técnicas, queda algo que mostrarle al
 * ganadero. Se usa para ocultar el ícono de "Detalle" en filas sin info útil.
 */
export function hasDisplayableMetadata(raw: unknown): boolean {
  const obj = parseMetadata(raw);
  return Object.keys(obj).some((key) => !TECHNICAL_KEYS.has(key));
}

/** `edad_declarada` -> `Edad declarada` */
export function humanizeKey(key: string): string {
  const spaced = key.replace(/[_-]+/g, ' ').trim();
  return spaced ? spaced.charAt(0).toUpperCase() + spaced.slice(1) : key;
}

function formatScalar(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Sí' : 'No';
  if (value === 'true') return 'Sí';
  if (value === 'false') return 'No';
  return String(value);
}

/** Árbol de pares clave-valor legibles a partir del `metadata` crudo. */
export function buildMetadataNodes(raw: unknown): MetadataNode[] {
  return objectToNodes(parseMetadata(raw));
}

function objectToNodes(obj: Record<string, unknown>): MetadataNode[] {
  return Object.entries(obj).map(([key, value]) => valueToNode(humanizeKey(key), value));
}

function valueToNode(label: string, value: unknown): MetadataNode {
  if (value && typeof value === 'object') {
    const children = Array.isArray(value)
      ? value.map((item, index) => valueToNode(String(index + 1), item))
      : objectToNodes(value as Record<string, unknown>);
    return children.length ? { label, children } : { label, value: '—' };
  }
  return { label, value: formatScalar(value) };
}
