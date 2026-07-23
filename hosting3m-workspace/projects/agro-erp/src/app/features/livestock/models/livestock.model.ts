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
  metadata?: string | { species?: string; [key: string]: unknown };
  last_palpation_result?: string;
  current_gestation_days?: number;
  condicion_utero?: string;
}
