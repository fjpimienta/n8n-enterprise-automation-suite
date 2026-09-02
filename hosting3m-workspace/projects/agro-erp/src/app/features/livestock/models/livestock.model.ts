export interface Livestock {
  id: string;
  business_model: 'CRIA' | 'ENGORDA';
  species?: string;
  category?: string;
  current_status?: string;
  current_weight_kg?: number;
  adg_lifetime_kg?: number;
  rfid_siniiga?: string;
  numero_fuego?: string;
  electronic_rfid?: string;
  upp_origen?: string;
  /** FK real a la unidad de producción (production_units.id). Fuente de verdad de "tiene UPP":
   *  se puebla para el 100% del hato de una UPP, a diferencia de `upp_origen` (texto libre, parcial). */
  production_unit_id?: string | null;
  /** Código UPP oficial de la unidad asignada (production_units.upp_code), vía vw_cattle_kpi. */
  upp_code?: string | null;
  /** Lote dentro de la UPP (production_unit_lots, migración 050). `null` si el animal aún no tiene lote asignado. */
  lot_name?: string | null;
  metadata?: string | { species?: string; [key: string]: unknown };
  last_palpation_result?: string;
  current_gestation_days?: number;
  condicion_utero?: string;
}
