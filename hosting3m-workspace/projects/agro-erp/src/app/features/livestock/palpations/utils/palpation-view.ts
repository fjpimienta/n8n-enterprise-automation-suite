import { PalpationEventRow, PalpationHerdRow, RanchTerm, ReportErrorReason } from '../models/palpation.types';
import {
  AnimalState,
  EmptySubtype,
  HerdBucket,
  Period,
  animalState,
  emptySubtypeOf,
  gestationOf,
  identifierOf,
  latestPerAnimal,
} from './palpation-metrics';

/**
 * View model of the palpation report: Spanish labels, number and date formatting, and the rows of the table. Pure functions only.
 * Dates are `YYYY-MM-DD` strings and are formatted by splitting the string, never through a Date (no zone can move them).
 */

export const STATE_LABEL: Readonly<Record<AnimalState, string>> = {
  'PREÑADA': 'Preñada',
  'VACÍA': 'Vacía',
  TERMINO_RANCHO: 'Término del rancho',
  SIN_RESULTADO: 'Sin resultado',
  SIN_INTERPRETAR: 'Sin interpretar',
};

export const SUBTYPE_LABEL: Readonly<Record<EmptySubtype, string>> = {
  ESTATICA: 'Estática (UNE)',
  CICLANDO: 'Ciclando',
  OTRO: 'Otro',
  SIN_SUBTIPO: 'Sin detalle de subtipo',
  SIN_CONFIRMAR: 'Código sin confirmar',
};

export const BUCKET_LABEL: Readonly<Record<HerdBucket, string>> = {
  vigente: 'Vigente (campaña reciente)',
  anterior: 'Anterior',
  historico: 'Histórico (carga 2023)',
  'sin-palpar': 'Sin palpar',
  'no-aplica': 'No aplica',
  'baja-mortandad': 'Baja por mortandad',
  vendido: 'Vendido',
  'fuera-del-hato': 'Fuera del hato',
};

/** Label shown on the badge of a ranch term. The wording of the term itself is the ranch's, shown as typed. */
export const RANCH_BADGE = 'Definido por el rancho';
export const HISTORICAL_BADGE = 'histórico (carga 2023)';
export const UNCONFIRMED_BADGE = 'código sin confirmar';

/** Spanish text of an error reason. A generic message: the response body is never shown. */
export function reasonText(reason: ReportErrorReason | null): string {
  switch (reason) {
    case 'empty-body':
      return 'El servidor respondió sin datos.';
    case 'gateway-error':
      return 'El servidor reportó un error al consultar las palpaciones.';
    case 'http-error':
      return 'El servidor no está disponible en este momento.';
    case 'network':
      return 'No hay conexión con el servidor.';
    case 'session-expired':
      return 'Tu sesión venció. Inicia sesión de nuevo.';
    case 'foreign-company':
      return 'La respuesta incluía datos de otra empresa y se descartó por completo.';
    case 'unexpected-date-shape':
      return 'La respuesta trae una fecha con un formato inesperado y se descartó.';
    case 'unexpected-shape':
      return 'La respuesta tiene un formato inesperado y se descartó.';
    case 'no-tenant':
      return 'No hay una empresa activa.';
    case 'no-permission':
      return 'Tu rol no permite ver este reporte.';
    default:
      return 'No se pudo completar la consulta.';
  }
}

/** `2026-11-12` → `12/11/2026`. Any other text is returned as is. */
export function formatDate(day: string | null): string {
  if (day === null) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : day;
}

/** Spanish decimal comma with one decimal place. */
export function formatDecimal(value: number): string {
  return value.toFixed(1).replace('.', ',');
}

/** `33,3 %`, or an em dash when there is nothing to divide (never `0 %`). */
export function formatPercent(value: number | null): string {
  return value === null ? '—' : `${formatDecimal(value)} %`;
}

/** Gestation of a PREÑADA animal: months first, days in brackets. An em dash when the days are missing. */
export function formatGestation(g: { readonly months: number; readonly days: number } | null): string {
  if (g === null) return '—';
  return `${formatDecimal(g.months)} meses (${g.days} días)`;
}

/** One row of the table: the latest counted palpation of one animal in the period, joined with the herd data. */
export interface PalpationTableRow {
  readonly livestockId: string;
  readonly identifier: string;
  readonly category: string;
  readonly currentStatus: string;
  readonly lastDate: string;
  readonly state: AnimalState;
  /** Sub-type of an empty result; null for any other state. */
  readonly subtype: EmptySubtype | null;
  readonly ranchTerm: RanchTerm | null;
  readonly gestation: { readonly months: number; readonly days: number } | null;
  readonly technician: string | null;
  /** The code as typed, only when it is unconfirmed (UNMAPPED). Never interpreted. */
  readonly unconfirmedCode: string | null;
  readonly historical: boolean;
  readonly uninterpreted: boolean;
}

export function buildTableRows(
  events: readonly PalpationEventRow[],
  herd: readonly PalpationHerdRow[],
  period: Period,
): PalpationTableRow[] {
  const byId = new Map(herd.map(h => [h.livestock_id, h] as const));
  const rows: PalpationTableRow[] = [];
  for (const e of latestPerAnimal(events, period).values()) {
    const animal = byId.get(e.livestock_id);
    const state = animalState(e);
    rows.push({
      livestockId: e.livestock_id,
      identifier: animal ? identifierOf(animal) : `Sin identificador · ${e.livestock_id.slice(0, 8)}`,
      category: animal?.category ?? '—',
      currentStatus: animal?.current_status ?? '—',
      lastDate: e.event_date,
      state,
      subtype: state === 'VACÍA' ? emptySubtypeOf(e) : null,
      ranchTerm: e.ranch_term,
      gestation: state === 'PREÑADA' ? gestationOf(e) : null,
      technician: e.technician,
      unconfirmedCode: e.mapping_status === 'UNMAPPED' ? e.raw_code : null,
      historical: e.is_historical_load,
      uninterpreted: e.uninterpreted,
    });
  }
  return rows;
}

/** One event of the timeline of an animal, newest first. NR entries are listed but do not count as a palpation. */
export interface TimelineEntry {
  readonly id: string;
  readonly date: string;
  readonly state: AnimalState;
  readonly ranchTerm: RanchTerm | null;
  readonly subtype: EmptySubtype | null;
  readonly gestation: { readonly months: number; readonly days: number } | null;
  readonly technician: string | null;
  /** The code as typed, only when it is unconfirmed. Never interpreted. */
  readonly unconfirmedCode: string | null;
  readonly unconfirmed: boolean;
  readonly historical: boolean;
  /** False for NR: the animal was not examined. */
  readonly counts: boolean;
}

export function buildTimeline(rows: readonly PalpationEventRow[]): TimelineEntry[] {
  return [...rows]
    .sort((a, b) =>
      a.event_date !== b.event_date ? (a.event_date < b.event_date ? 1 : -1)
        : a.created_at !== b.created_at ? (a.created_at < b.created_at ? 1 : -1)
          : a.health_log_id < b.health_log_id ? 1 : -1)
    .map((e): TimelineEntry => {
      const state = animalState(e);
      const subtype = state === 'VACÍA' ? emptySubtypeOf(e) : null;
      return {
        id: e.health_log_id,
        date: e.event_date,
        state,
        ranchTerm: e.ranch_term,
        subtype,
        gestation: state === 'PREÑADA' ? gestationOf(e) : null,
        technician: e.technician,
        unconfirmedCode: e.mapping_status === 'UNMAPPED' ? e.raw_code : null,
        unconfirmed: e.mapping_status === 'UNMAPPED',
        historical: e.is_historical_load,
        counts: e.counts_as_palpation,
      };
    });
}

export type RowFilterResult = 'TODOS' | AnimalState;

export interface RowFilter {
  readonly result: RowFilterResult;
  /** `TODOS` or an exact current_status value. */
  readonly status: string;
}

export function filterRows(rows: readonly PalpationTableRow[], f: RowFilter): PalpationTableRow[] {
  return rows.filter(r => (f.result === 'TODOS' || r.state === f.result) && (f.status === 'TODOS' || r.currentStatus === f.status));
}

/** Distinct current_status values of the rows, sorted, for the status filter. */
export function distinctStatuses(rows: readonly PalpationTableRow[]): string[] {
  return [...new Set(rows.map(r => r.currentStatus))].sort((a, b) => a.localeCompare(b, 'es'));
}

export type SortKey = 'identifier' | 'lastDate' | 'state' | 'gestation' | 'technician' | 'currentStatus';
export type SortDir = 'asc' | 'desc';

/** Stable sort. Missing values (no gestation, no technician) always go last, whatever the direction. */
export function sortRows(rows: readonly PalpationTableRow[], key: SortKey, dir: SortDir): PalpationTableRow[] {
  const sign = dir === 'asc' ? 1 : -1;
  const value = (r: PalpationTableRow): string | number | null => {
    switch (key) {
      case 'identifier': return r.identifier;
      case 'lastDate': return r.lastDate;
      case 'state': return STATE_LABEL[r.state];
      case 'gestation': return r.gestation === null ? null : r.gestation.days;
      case 'technician': return r.technician;
      case 'currentStatus': return r.currentStatus;
    }
  };
  return rows
    .map((r, i) => ({ r, i, v: value(r) }))
    .sort((a, b) => {
      if (a.v === null && b.v === null) return a.i - b.i;
      if (a.v === null) return 1;
      if (b.v === null) return -1;
      const cmp = typeof a.v === 'number' && typeof b.v === 'number'
        ? a.v - b.v
        : String(a.v).localeCompare(String(b.v), 'es', { numeric: true });
      return cmp !== 0 ? sign * cmp : a.i - b.i;
    })
    .map(x => x.r);
}
