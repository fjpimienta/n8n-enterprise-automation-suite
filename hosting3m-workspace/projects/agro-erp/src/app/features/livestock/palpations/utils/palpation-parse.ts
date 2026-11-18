import {
  MappingStatus,
  PalpationEventRow,
  PalpationHerdRow,
  PalpationResult,
  RanchTerm,
  ReproCondition,
  ReportErrorReason,
} from '../models/palpation.types';
import { calendarDateOf } from './palpation-dates';

/**
 * Boundary parser for the palpation views. Pure: no HTTP, no signals, no clock.
 *
 * Contract (captured on LOCAL, 2026-11-18, synthetic company):
 *  - HTTP 200 body: `{ error, operation, message, data, execution_info }`.
 *  - An empty collection is `data: [{}]` (one empty object): it is a valid EMPTY result, not an error.
 *  - A body that is empty, not JSON, or has `error: true` is an ERROR. Never "zero rows".
 *  - Numbers arrive as JSON numbers; numeric strings are accepted too.
 *  - `event_date`, `last_event_date` and `created_at` arrive as ISO timestamps; the calendar day is their first ten characters.
 *
 * Strictness: values that drive the clinical figures (result, ranch term, booleans, identifiers) must match the contract or
 * the whole response is an `unexpected-shape` error. `mapping_status` and `repro_condition` are lenient on purpose: an unknown
 * value is treated as NOT interpreted (`UNMAPPED` / no sub-type), never as a clinical result.
 */

export type ParseOutcome<T> =
  | { readonly ok: true; readonly rows: readonly T[] }
  | { readonly ok: false; readonly reason: ReportErrorReason };

const RESULTS: readonly PalpationResult[] = ['PREÑADA', 'VACÍA'];
const RANCH_TERMS: readonly RanchTerm[] = ['NR', 'RP', 'NO APTO', 'MATRIZ OCUPADA'];
const REPRO_CONDITIONS: readonly ReproCondition[] = ['ESTATICA', 'CICLANDO', 'OTRO'];

type Json = Record<string, unknown>;

function isObject(v: unknown): v is Json {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Real rows only: `{}` is the gateway's empty-collection marker. */
function realRows(data: unknown[]): Json[] {
  return data.filter((r): r is Json => isObject(r) && Object.keys(r).length > 0);
}

/** Reads the gateway envelope. Returns the real rows, or the reason the body cannot be used. */
export function parseEnvelope(text: string | null | undefined): ParseOutcome<Json> {
  if (typeof text !== 'string' || text.trim() === '') return { ok: false, reason: 'empty-body' };
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return { ok: false, reason: 'unexpected-shape' };
  }
  if (!isObject(body)) return { ok: false, reason: 'unexpected-shape' };
  if (body['error'] === true) return { ok: false, reason: 'gateway-error' };
  const data = body['data'];
  if (!Array.isArray(data)) return { ok: false, reason: 'unexpected-shape' };
  return { ok: true, rows: realRows(data) };
}

class ShapeError extends Error {}

/** A date that is not the gateway's calendar-day shape. Reported on its own so the UI can say so. */
class DateShapeError extends Error {}

function toInt(v: unknown, field: string): number {
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isInteger(n)) throw new ShapeError(field);
  return n;
}

function toNonNegativeInt(v: unknown, field: string): number {
  const n = toInt(v, field);
  if (n < 0) throw new ShapeError(field);
  return n;
}

function toBool(v: unknown, field: string): boolean {
  if (typeof v === 'boolean') return v;
  if (v === 'true') return true;
  if (v === 'false') return false;
  throw new ShapeError(field);
}

function toBoolOrNull(v: unknown, field: string): boolean | null {
  return v === null || v === undefined ? null : toBool(v, field);
}

function toText(v: unknown, field: string): string {
  if (typeof v !== 'string' || v === '') throw new ShapeError(field);
  return v;
}

function toTextOrNull(v: unknown, field: string): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string') throw new ShapeError(field);
  return v === '' ? null : v;
}

function toDate(v: unknown, field: string): string {
  const d = calendarDateOf(typeof v === 'string' ? v : null);
  if (d === null) throw new DateShapeError(field);
  return d;
}

function toDateOrNull(v: unknown, field: string): string | null {
  return v === null || v === undefined ? null : toDate(v, field);
}

function toResultOrNull(v: unknown, field: string): PalpationResult | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string' && (RESULTS as readonly string[]).includes(v)) return v as PalpationResult;
  throw new ShapeError(field);
}

function toRanchOrNull(v: unknown, field: string): RanchTerm | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string' && (RANCH_TERMS as readonly string[]).includes(v)) return v as RanchTerm;
  throw new ShapeError(field);
}

/** Lenient: an unknown value is not interpreted. */
function toMapping(v: unknown): MappingStatus | null {
  if (v === null || v === undefined) return null;
  if (v === 'NOT_APPLICABLE' || v === 'EXPLICIT' || v === 'UNMAPPED') return v;
  return 'UNMAPPED';
}

/** Lenient: an unknown value means "no sub-type". */
function toReproOrNull(v: unknown): ReproCondition | null {
  return typeof v === 'string' && (REPRO_CONDITIONS as readonly string[]).includes(v) ? (v as ReproCondition) : null;
}

/** Ties every row to the active tenant. Any mismatch invalidates the WHOLE response (no partial data). */
function assertTenant(rows: readonly Json[], tenantId: number): void {
  for (const r of rows) {
    if (toInt(r['id_company'], 'id_company') !== tenantId) throw new ForeignCompany();
  }
}

class ForeignCompany extends Error {}

/** Parses `vw_palpation_events` rows for the active tenant. */
export function parseEventRows(text: string | null | undefined, tenantId: number): ParseOutcome<PalpationEventRow> {
  const env = parseEnvelope(text);
  if (!env.ok) return env;
  try {
    assertTenant(env.rows, tenantId);
    const rows = env.rows.map((r): PalpationEventRow => {
      const mapping = toMapping(r['mapping_status']);
      return {
        id_company: toInt(r['id_company'], 'id_company'),
        health_log_id: toText(r['health_log_id'], 'health_log_id'),
        livestock_id: toText(r['livestock_id'], 'livestock_id'),
        event_date: toDate(r['event_date'], 'event_date'),
        result: toResultOrNull(r['result'], 'result'),
        gestation_days: r['gestation_days'] === null || r['gestation_days'] === undefined
          ? null
          : toNonNegativeInt(r['gestation_days'], 'gestation_days'),
        is_historical_load: toBool(r['is_historical_load'], 'is_historical_load'),
        technician: toTextOrNull(r['technician'], 'technician'),
        mapping_status: mapping,
        repro_condition: toReproOrNull(r['repro_condition']),
        raw_code: toTextOrNull(r['raw_code'], 'raw_code'),
        // Never shown for an unconfirmed code: the parser drops it too, in case the view ever returns it.
        code_meaning: mapping === 'UNMAPPED' ? null : toTextOrNull(r['code_meaning'], 'code_meaning'),
        ranch_term: toRanchOrNull(r['ranch_term'], 'ranch_term'),
        counts_as_palpation: toBool(r['counts_as_palpation'], 'counts_as_palpation'),
        is_clinical_result: toBool(r['is_clinical_result'], 'is_clinical_result'),
        created_at: toText(r['created_at'], 'created_at'),
      };
    });
    return { ok: true, rows };
  } catch (e) {
    return { ok: false, reason: reasonOf(e) };
  }
}

/** Parses `vw_palpation_herd` rows for the active tenant. */
export function parseHerdRows(text: string | null | undefined, tenantId: number): ParseOutcome<PalpationHerdRow> {
  const env = parseEnvelope(text);
  if (!env.ok) return env;
  try {
    assertTenant(env.rows, tenantId);
    const rows = env.rows.map((r): PalpationHerdRow => ({
      id_company: toInt(r['id_company'], 'id_company'),
      livestock_id: toText(r['livestock_id'], 'livestock_id'),
      rfid_siniiga: toTextOrNull(r['rfid_siniiga'], 'rfid_siniiga'),
      numero_fuego: toTextOrNull(r['numero_fuego'], 'numero_fuego'),
      brand_code: toTextOrNull(r['brand_code'], 'brand_code'),
      category: toTextOrNull(r['category'], 'category'),
      species: toTextOrNull(r['species'], 'species'),
      current_status: toTextOrNull(r['current_status'], 'current_status'),
      last_event_date: toDateOrNull(r['last_event_date'], 'last_event_date'),
      last_result: toResultOrNull(r['last_result'], 'last_result'),
      last_is_historical: toBoolOrNull(r['last_is_historical'], 'last_is_historical'),
      last_repro_condition: toReproOrNull(r['last_repro_condition']),
      last_mapping_status: toMapping(r['last_mapping_status']),
      last_ranch_term: toRanchOrNull(r['last_ranch_term'], 'last_ranch_term'),
      palpation_count: toNonNegativeInt(r['palpation_count'], 'palpation_count'),
      created_at: toText(r['created_at'], 'created_at'),
    }));
    return { ok: true, rows };
  } catch (e) {
    return { ok: false, reason: reasonOf(e) };
  }
}

function reasonOf(e: unknown): ReportErrorReason {
  if (e instanceof ForeignCompany) return 'foreign-company';
  if (e instanceof DateShapeError) return 'unexpected-date-shape';
  return 'unexpected-shape';
}
