import { parseMetadata } from './metadata-view.util';

/**
 * Claves de `cattle_livestock.metadata` (JSONB, sin shape fijo) que revelan información
 * financiera — no-ADMIN no debe verlas en el modal "Ver detalle". Confirmado contra el
 * contenido real de LOCAL (`SELECT DISTINCT jsonb_object_keys(metadata) FROM cattle_livestock`,
 * 29 claves distintas en total) y contra la única herramienta MCP que escribe aquí
 * (`register_livestock_purchase`, ver su INSERT: `purchase_price`, `seller_name`,
 * `purchase_date`). `nota_venta`/`venta_registrada_solo_en_libreta` vienen de los scripts de
 * carga histórica (`database/migrations/*.py`), no del Agente IA, pero son igual de
 * financieras por contenido. Deliberadamente NO incluye `notes`/`source`: son genéricos,
 * usados también para contenido no financiero (notas de salud, procedencia del registro), y
 * ocultarlos por completo perdería información legítima para el capataz.
 *
 * ⚠️ Riesgo residual, no cerrado por esta lista: el dato financiero sigue viajando completo en
 * la respuesta HTTP de `vw_cattle_kpi` (el gateway no filtra columnas ni claves de `metadata` —
 * ver Build Query, `buildSelectFields()` siempre hace `SELECT *`). Este archivo solo evita que
 * la UI lo RENDERICE para no-ADMIN; cualquiera con las herramientas de desarrollador del
 * navegador abiertas puede ver la respuesta cruda igual. El cierre real es una vista en
 * PostgreSQL que excluya estas claves de `metadata` antes de que el gateway las devuelva
 * (Fase 1, no implementada aquí).
 */
export const FINANCIAL_METADATA_KEYS: ReadonlySet<string> = new Set([
  'purchase_price',
  'seller_name',
  'purchase_date',
  'nota_venta',
  'venta_registrada_solo_en_libreta'
]);

/**
 * Copia de `raw` (metadata cruda, objeto o string JSON) sin las claves financieras — para
 * pasar a `<app-metadata-detail-modal>` cuando el viewer no es ADMIN. ADMIN sigue recibiendo
 * `animal.metadata` tal cual, sin pasar por esta función.
 */
export function withoutFinancialMetadata(raw: unknown): Record<string, unknown> {
  const obj = parseMetadata(raw);
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (!FINANCIAL_METADATA_KEYS.has(key)) {
      result[key] = value;
    }
  }
  return result;
}
