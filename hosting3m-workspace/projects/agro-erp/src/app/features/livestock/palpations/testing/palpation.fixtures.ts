/**
 * SYNTHETIC fixtures for the palpation report. Never copy real herd data here, in a test, a capture or a commit.
 * Shapes follow the gateway contract captured on LOCAL on 2026-11-18 (wire format: dates as local-midnight ISO timestamps,
 * numbers as JSON numbers, empty collection as `data: [{}]`). Identifiers are invented: SINIIGA values start with 9999, which is
 * not a state code, and company ids are fictitious.
 */

import { PalpationEventRow, PalpationHerdRow } from '../models/palpation.types';

export const SYNTHETIC_TENANT = 9101;
export const SYNTHETIC_OTHER_TENANT = 9102;

/** Wire format of a `date` value: the gateway's local midnight in UTC-6. */
export const wireDate = (day: string): string => `${day}T06:00:00.000Z`;

/** Wire format of a timestamp value. */
export const wireTs = (day: string, time = '09:00:00'): string => `${day}T${time}.000Z`;

/** Envelope of a successful gateway answer. */
export const envelope = (data: unknown[]): string =>
  JSON.stringify({ error: false, operation: 'getall', message: 'Ejecución satisfactoria', data, execution_info: { model: 'synthetic' } });

/** Envelope of an empty collection: exactly what the gateway sends. */
export const EMPTY_ENVELOPE = envelope([{}]);

/** Envelope of a gateway error reported on HTTP 200. */
export const ERROR_ENVELOPE = JSON.stringify({ error: true, operation: 'getall', message: 'Synthetic gateway error', data: null });

/** One event in wire format. Defaults describe a counted clinical VACÍA with no detail row. */
export function eventWire(over: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id_company: SYNTHETIC_TENANT,
    health_log_id: 'ev-0001',
    livestock_id: 'an-0001',
    event_date: wireDate('2026-11-10'),
    result: 'VACÍA',
    gestation_days: null,
    is_historical_load: false,
    technician: null,
    mapping_status: null,
    repro_condition: null,
    raw_code: null,
    code_meaning: null,
    ranch_term: null,
    counts_as_palpation: true,
    is_clinical_result: true,
    created_at: wireTs('2026-11-10'),
    ...over,
  };
}

/** One herd row in wire format. Defaults describe an active VACA, palpated once, clinically pregnant. */
export function herdWire(over: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    id_company: SYNTHETIC_TENANT,
    livestock_id: 'an-0001',
    rfid_siniiga: '9999000001',
    numero_fuego: null,
    brand_code: null,
    category: 'VACA',
    species: 'BOVINO',
    current_status: 'ACTIVO',
    last_event_date: wireDate('2026-11-10'),
    last_result: 'PREÑADA',
    last_is_historical: false,
    last_repro_condition: null,
    last_mapping_status: null,
    last_ranch_term: null,
    palpation_count: 1,
    created_at: wireTs('2026-11-01'),
    ...over,
  };
}

/** Typed rows (after parsing) for metric tests, built from the wire shape. */
export function eventRow(over: Partial<PalpationEventRow> & { wire?: Record<string, unknown> } = {}): PalpationEventRow {
  const { wire, ...rest } = over;
  const w = eventWire({ ...(wire ?? {}) });
  return {
    id_company: SYNTHETIC_TENANT,
    health_log_id: String(w['health_log_id']),
    livestock_id: String(w['livestock_id']),
    event_date: String(w['event_date']).slice(0, 10),
    result: (w['result'] as PalpationEventRow['result']) ?? null,
    gestation_days: (w['gestation_days'] as number | null) ?? null,
    is_historical_load: Boolean(w['is_historical_load']),
    technician: (w['technician'] as string | null) ?? null,
    mapping_status: (w['mapping_status'] as PalpationEventRow['mapping_status']) ?? null,
    repro_condition: (w['repro_condition'] as PalpationEventRow['repro_condition']) ?? null,
    raw_code: (w['raw_code'] as string | null) ?? null,
    code_meaning: (w['code_meaning'] as string | null) ?? null,
    ranch_term: (w['ranch_term'] as PalpationEventRow['ranch_term']) ?? null,
    uninterpreted: false,
    counts_as_palpation: Boolean(w['counts_as_palpation']),
    is_clinical_result: Boolean(w['is_clinical_result']),
    created_at: String(w['created_at']),
    ...rest,
  };
}

/** Herd row after parsing, built from the wire shape. */
export function herdRow(over: Partial<PalpationHerdRow> & { wire?: Record<string, unknown> } = {}): PalpationHerdRow {
  const { wire, ...rest } = over;
  const w = herdWire({ ...(wire ?? {}) });
  return {
    id_company: SYNTHETIC_TENANT,
    livestock_id: String(w['livestock_id']),
    rfid_siniiga: (w['rfid_siniiga'] as string | null) ?? null,
    numero_fuego: (w['numero_fuego'] as string | null) ?? null,
    brand_code: (w['brand_code'] as string | null) ?? null,
    category: (w['category'] as string | null) ?? null,
    species: (w['species'] as string | null) ?? null,
    current_status: (w['current_status'] as string | null) ?? null,
    last_event_date: w['last_event_date'] ? String(w['last_event_date']).slice(0, 10) : null,
    last_result: (w['last_result'] as PalpationHerdRow['last_result']) ?? null,
    last_is_historical: (w['last_is_historical'] as boolean | null) ?? null,
    last_repro_condition: (w['last_repro_condition'] as PalpationHerdRow['last_repro_condition']) ?? null,
    last_mapping_status: (w['last_mapping_status'] as PalpationHerdRow['last_mapping_status']) ?? null,
    last_ranch_term: (w['last_ranch_term'] as PalpationHerdRow['last_ranch_term']) ?? null,
    uninterpreted: false,
    palpation_count: Number(w['palpation_count']),
    created_at: String(w['created_at']),
    ...rest,
  };
}
