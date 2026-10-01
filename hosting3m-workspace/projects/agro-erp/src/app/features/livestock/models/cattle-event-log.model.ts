export type CattleEventType = 'PESO' | 'SALUD' | 'PARTO' | 'NACIMIENTO' | 'COMPRA' | 'DESTETE' | 'SOLICITUD_BAJA' | 'SOLICITUD_VENTA';

/**
 * Raw row shape returned by the Meta-CRUD gateway for the `cattle_event_log` model
 * (vw_cattle_event_log, migration 060) — a read-only union of cattle_weight_logs,
 * cattle_health_logs and birth_events. A single birth_events row can surface as up to two
 * entries here (PARTO under the dam, NACIMIENTO under the calf), never merged into one,
 * because dam_id/calf_id are independently nullable in the source table.
 *
 * Numeric fields arrive as strings from the gateway — parse explicitly, never compare or
 * sort as text (Contrato Meta-CRUD).
 */
export interface CattleEventLogRow {
  id: string;
  tenant_id: number | string;
  livestock_id: string;
  rfid_siniiga?: string | null;
  numero_fuego?: string | null;
  event_type: CattleEventType;
  event_date: string;
  weight_kg?: string | number | null;
  health_event_type?: string | null;
  description?: string | null;
  medicines_json?: Record<string, unknown> | null;
  calf_sex?: string | null;
  birth_date?: string | null;
  calf_weight_kg?: string | number | null;
  source_device?: string | null;
  created_at: string;
  /** Migration 062 — populated only on NACIMIENTO rows (calf's cattle_livestock.category). */
  calf_category?: string | null;
  /** Migration 062 — populated only on NACIMIENTO rows: dam's rfid_siniiga/numero_fuego, falling
   *  back to birth_events.dam_ear_tag/dam_fire_number when dam_id is not linked. Null if the
   *  birth has no dam reference at all (allowed for BORREGO). */
  dam_identifier?: string | null;
}
