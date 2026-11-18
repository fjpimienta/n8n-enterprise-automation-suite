/**
 * Domain types of the palpation report. They mirror the gateway views of migration 108 (`vw_palpation_events`,
 * `vw_palpation_herd`) as captured on LOCAL on 2026-11-18: dates arrive as ISO timestamps (the gateway serialises
 * a `date` as local midnight), numbers arrive as JSON numbers. The parser normalises them; the rest of the feature
 * works with the types below only.
 */

/** Roles allowed to read the report. Any other role (OWNER, CUSTOMER, anything unknown) gets the "sin permiso" state and no request. */
export const PALPATION_ALLOWED_ROLES: readonly string[] = ['ADMIN', 'EDITOR'];

export type PalpationResult = 'PREÑADA' | 'VACÍA';

/** Ranch terms are a FIXED list in the view (migration 108). Adding one needs a new version of the view. */
export type RanchTerm = 'NR' | 'RP' | 'NO APTO' | 'MATRIZ OCUPADA';

/** Structured sub-type of an empty result. Only from `palpation_repro_details`, never from text. */
export type ReproCondition = 'ESTATICA' | 'CICLANDO' | 'OTRO';

/**
 * Mapping status of an event. Only these three exist in the view. Any other value received from the gateway is
 * normalised to `UNMAPPED` by the parser: it is shown as "código sin confirmar" and never interpreted.
 */
export type MappingStatus = 'NOT_APPLICABLE' | 'EXPLICIT' | 'UNMAPPED';

/** One row of `vw_palpation_events`: one PALPACION event. */
export interface PalpationEventRow {
  readonly id_company: number;
  readonly health_log_id: string;
  readonly livestock_id: string;
  /** Calendar date `YYYY-MM-DD` (the gateway's midnight is read as its calendar day). */
  readonly event_date: string;
  readonly result: PalpationResult | null;
  readonly gestation_days: number | null;
  /** The 2023 bulk load: JSON key `resultado` without `result`. Shown with the badge "histórico (carga 2023)". */
  readonly is_historical_load: boolean;
  readonly technician: string | null;
  readonly mapping_status: MappingStatus | null;
  readonly repro_condition: ReproCondition | null;
  /** Raw code as typed. Shown verbatim when UNMAPPED; never interpreted. */
  readonly raw_code: string | null;
  /** Forced to null in SQL when UNMAPPED. The UI never reads it for an unconfirmed code. */
  readonly code_meaning: string | null;
  readonly ranch_term: RanchTerm | null;
  /** False only for NR (an animal not examined is not a palpated animal). */
  readonly counts_as_palpation: boolean;
  /** True when there is a clinical result (PREÑADA or VACÍA) and no ranch term. */
  readonly is_clinical_result: boolean;
  /** ISO timestamp as sent by the gateway; used only to break ties. */
  readonly created_at: string;
}

/** One row of `vw_palpation_herd`: one animal of the company, including animals never palpated. */
export interface PalpationHerdRow {
  readonly id_company: number;
  readonly livestock_id: string;
  readonly rfid_siniiga: string | null;
  readonly numero_fuego: string | null;
  readonly brand_code: string | null;
  readonly category: string | null;
  readonly species: string | null;
  readonly current_status: string | null;
  /** Calendar date of the latest counted palpation of the animal, or null when never palpated. */
  readonly last_event_date: string | null;
  readonly last_result: PalpationResult | null;
  readonly last_is_historical: boolean | null;
  readonly last_repro_condition: ReproCondition | null;
  readonly last_mapping_status: MappingStatus | null;
  readonly last_ranch_term: RanchTerm | null;
  readonly palpation_count: number;
  readonly created_at: string;
}

/** States of the report screen. "sin-tenant" and "sin-permiso" never send a request. */
export type ReportStatus =
  | 'sin-tenant'
  | 'sin-permiso'
  | 'cargando'
  | 'listo'
  | 'vacio'
  | 'error'
  | 'truncado';

/** Why a response could not be used. The UI shows a generic message; the body is never shown. */
export type ReportErrorReason =
  | 'empty-body'        // HTTP 200 with no body: the gateway failed silently
  | 'gateway-error'     // HTTP 200 with error:true
  | 'http-error'        // any other HTTP status
  | 'unexpected-shape'  // data is not an array, or a row does not match the contract
  | 'unexpected-date-shape' // a date is not the gateway's calendar-day shape (for example a UTC time after 12:00)
  | 'foreign-company'   // a row belongs to another company: the whole response is discarded
  | 'network'           // offline or interrupted
  | 'session-expired'   // the session changed while the request was in flight, or it is expired
  | 'no-tenant'         // no active company: nothing is requested
  | 'no-permission';    // the active role may not read the report: nothing is requested
