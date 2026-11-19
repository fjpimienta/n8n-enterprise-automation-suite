import { isActiveHead } from '@shared/utils/herd-status.util';
import { PalpationEventRow, PalpationHerdRow, RanchTerm } from '../models/palpation.types';
import { addCalendarDays, compareCalendarDates } from './palpation-dates';

/**
 * Pure metrics of the palpation report. No HTTP, no signals, no DOM. Every figure shown in the UI comes from here, so each
 * one can be tested with synthetic rows. Display-only: nothing computed here is written back (CLAUDE.md, Zero-Compute Client).
 */

/** Days before the latest counted, non-historical palpation where the default "campaña reciente" window starts (inclusive). */
export const CAMPAIGN_WINDOW_DAYS = 60;

/** Categories the herd chart and the "por palpar" universe apply to. Every other category is "no aplica". */
export const APPLICABLE_CATEGORIES: readonly string[] = ['VACA', 'NOVILLONA'];

export interface Period {
  /** Inclusive lower bound (`YYYY-MM-DD`), or null for "todo". */
  readonly from: string | null;
  /** Inclusive upper bound (`YYYY-MM-DD`), or null for "todo". */
  readonly to: string | null;
}

/** Latest counted, non-historical palpation date, limited to `today`. Null when the company has none. */
export function maxCampaignDate(events: readonly PalpationEventRow[], today: string): string | null {
  let max: string | null = null;
  for (const e of events) {
    if (!e.counts_as_palpation || e.is_historical_load) continue;
    if (compareCalendarDates(e.event_date, today) > 0) continue;
    if (max === null || compareCalendarDates(e.event_date, max) > 0) max = e.event_date;
  }
  return max;
}

/** Start of the default "campaña reciente" window: `maxCampaignDate − 60 days`. Null when there is no campaign. */
export function campaignStart(events: readonly PalpationEventRow[], today: string): string | null {
  const max = maxCampaignDate(events, today);
  return max === null ? null : addCalendarDays(max, -CAMPAIGN_WINDOW_DAYS);
}

/** The default period: from the campaign start to the latest date, or null when there is no campaign (the UI offers "todo"). */
export function defaultPeriod(events: readonly PalpationEventRow[], today: string): Period | null {
  const start = campaignStart(events, today);
  if (start === null) return null;
  return { from: start, to: maxCampaignDate(events, today) };
}

/** True when the event is a counted palpation (NR is not) inside the period. */
export function isInPeriod(e: PalpationEventRow, period: Period): boolean {
  if (!e.counts_as_palpation) return false;
  if (period.from !== null && compareCalendarDates(e.event_date, period.from) < 0) return false;
  if (period.to !== null && compareCalendarDates(e.event_date, period.to) > 0) return false;
  return true;
}

/**
 * Latest counted event of each animal inside the period. Ties on the calendar day are broken by the creation timestamp and then
 * by the event key, so the same data always gives the same answer.
 */
export function latestPerAnimal(events: readonly PalpationEventRow[], period: Period): Map<string, PalpationEventRow> {
  const latest = new Map<string, PalpationEventRow>();
  for (const e of events) {
    if (!isInPeriod(e, period)) continue;
    const current = latest.get(e.livestock_id);
    if (current === undefined || isLater(e, current)) latest.set(e.livestock_id, e);
  }
  return latest;
}

function isLater(a: PalpationEventRow, b: PalpationEventRow): boolean {
  const byDay = compareCalendarDates(a.event_date, b.event_date);
  if (byDay !== 0) return byDay > 0;
  if (a.created_at !== b.created_at) return a.created_at > b.created_at;
  return a.health_log_id > b.health_log_id;
}

export type AnimalState = 'PREÑADA' | 'VACÍA' | 'TERMINO_RANCHO' | 'SIN_RESULTADO' | 'SIN_INTERPRETAR';

/**
 * State of an animal from its latest counted event. An unrecognised value is never interpreted: it is its own state, outside every
 * clinical figure. A ranch term takes precedence over the result, so it never counts as clinical.
 */
export function animalState(e: PalpationEventRow): AnimalState {
  if (e.uninterpreted) return 'SIN_INTERPRETAR';
  if (e.ranch_term !== null) return 'TERMINO_RANCHO';
  if (e.result === 'PREÑADA') return 'PREÑADA';
  if (e.result === 'VACÍA') return 'VACÍA';
  return 'SIN_RESULTADO';
}

/** Sub-type of an empty result. Structured only: an unconfirmed code is its own bucket, never a guessed sub-type. */
export type EmptySubtype = 'ESTATICA' | 'CICLANDO' | 'OTRO' | 'SIN_SUBTIPO' | 'SIN_CONFIRMAR';

export function emptySubtypeOf(e: PalpationEventRow): EmptySubtype {
  if (e.mapping_status === 'UNMAPPED') return 'SIN_CONFIRMAR';
  if (e.repro_condition !== null) return e.repro_condition;
  return 'SIN_SUBTIPO';
}

export type RanchTermCounts = Readonly<Record<RanchTerm, number>>;

export interface PeriodKpis {
  /** D: animals palpated in the period (latest counted event inside it). Every percentage is over C, not D. */
  readonly palpated: number;
  /** C: animals whose latest event is a clinical result (PREÑADA or VACÍA). */
  readonly clinical: number;
  readonly pregnant: number;
  readonly empty: number;
  /** pregnant / C × 100, or null when C = 0 (shown as "—", never 0 %). */
  readonly pctPregnant: number | null;
  /** empty / C × 100, or null when C = 0. */
  readonly pctEmpty: number | null;
  /** Animals whose latest event carries a ranch term, per term. Outside the clinical percentages. */
  readonly ranchTerms: RanchTermCounts;
  readonly ranchTotal: number;
  /** Animals whose latest event has no result and no ranch term. */
  readonly noResult: number;
  /** Animals whose latest event carries an unrecognised result or ranch term. Outside every percentage; the UI warns. */
  readonly uninterpreted: number;
  /** Animals whose latest event has an unconfirmed code (UNMAPPED). Shown as typed, never interpreted. */
  readonly unconfirmed: number;
  /** Sub-types of the empty animals. Sums to `empty`. */
  readonly emptySubtypes: Readonly<Record<EmptySubtype, number>>;
  /** Latest counted date inside the period, or null when there is none. */
  readonly lastPalpationDate: string | null;
  /** The identity D = C + ranch + no result + uninterpreted. The UI must not show the KPIs when it is false. */
  readonly identityHolds: boolean;
}

const EMPTY_RANCH: Record<RanchTerm, number> = { NR: 0, RP: 0, 'NO APTO': 0, 'MATRIZ OCUPADA': 0 };
const EMPTY_SUBTYPES: Record<EmptySubtype, number> = { ESTATICA: 0, CICLANDO: 0, OTRO: 0, SIN_SUBTIPO: 0, SIN_CONFIRMAR: 0 };

export function periodKpis(events: readonly PalpationEventRow[], period: Period): PeriodKpis {
  const latest = latestPerAnimal(events, period);
  const ranchTerms: Record<RanchTerm, number> = { ...EMPTY_RANCH };
  const emptySubtypes: Record<EmptySubtype, number> = { ...EMPTY_SUBTYPES };
  let pregnant = 0;
  let empty = 0;
  let noResult = 0;
  let uninterpreted = 0;
  let unconfirmed = 0;
  let last: string | null = null;

  for (const e of latest.values()) {
    if (e.mapping_status === 'UNMAPPED') unconfirmed += 1;
    if (last === null || compareCalendarDates(e.event_date, last) > 0) last = e.event_date;
    switch (animalState(e)) {
      case 'PREÑADA':
        pregnant += 1;
        break;
      case 'VACÍA':
        empty += 1;
        emptySubtypes[emptySubtypeOf(e)] += 1;
        break;
      case 'TERMINO_RANCHO':
        if (e.ranch_term !== null) ranchTerms[e.ranch_term] += 1;
        break;
      case 'SIN_RESULTADO':
        noResult += 1;
        break;
      case 'SIN_INTERPRETAR':
        uninterpreted += 1;
        break;
    }
  }

  const palpated = latest.size;
  const clinical = pregnant + empty;
  const ranchTotal = ranchTerms.NR + ranchTerms.RP + ranchTerms['NO APTO'] + ranchTerms['MATRIZ OCUPADA'];
  return {
    palpated,
    clinical,
    pregnant,
    empty,
    pctPregnant: clinical === 0 ? null : (pregnant / clinical) * 100,
    pctEmpty: clinical === 0 ? null : (empty / clinical) * 100,
    ranchTerms,
    ranchTotal,
    noResult,
    uninterpreted,
    unconfirmed,
    emptySubtypes,
    lastPalpationDate: last,
    identityHolds: palpated === clinical + ranchTotal + noResult + uninterpreted,
  };
}

/** Gestation of a PREÑADA animal: months as the main value, days in brackets. Null when the days are missing (shown as "—"). */
export function gestationOf(e: PalpationEventRow): { readonly months: number; readonly days: number } | null {
  if (e.result !== 'PREÑADA' || e.gestation_days === null || e.gestation_days <= 0) return null;
  return { months: e.gestation_days / 30, days: e.gestation_days };
}

export type HerdBucket =
  | 'vigente'
  | 'anterior'
  | 'historico'
  | 'sin-palpar'
  | 'no-aplica'
  | 'baja-mortandad'
  | 'vendido'
  | 'fuera-del-hato';

/**
 * Bucket of an animal in the herd chart, in this order:
 *  1. VENDIDO or BAJA_MORTANDAD: the separate legend. Terminal statuses shared with herd-status.util leave the herd.
 *  2. Any palpation (palpation_count > 0): its date bucket (histórico, vigente, anterior), whatever its category.
 *  3. No palpation and a category other than VACA or NOVILLONA: "no aplica".
 *  4. No palpation and VACA or NOVILLONA: "sin palpar".
 */
export function herdBucket(row: PalpationHerdRow, campaign: string | null): HerdBucket {
  const status = (row.current_status ?? '').trim().toUpperCase();
  if (status === 'VENDIDO') return 'vendido';
  if (status === 'BAJA_MORTANDAD') return 'baja-mortandad';
  if (!isActiveHead(row)) return 'fuera-del-hato';
  if (row.palpation_count > 0) {
    if (row.last_is_historical === true) return 'historico';
    if (campaign !== null && row.last_event_date !== null && compareCalendarDates(row.last_event_date, campaign) >= 0) return 'vigente';
    return 'anterior';
  }
  return isApplicable(row) ? 'sin-palpar' : 'no-aplica';
}

function isApplicable(row: PalpationHerdRow): boolean {
  return APPLICABLE_CATEGORIES.includes((row.category ?? '').trim().toUpperCase());
}

/**
 * "Por palpar" universe: active VACA and NOVILLONA animals that have no palpation in the campaign (not "vigente").
 * "Activa" is the single definition of herd-status.util.ts (`isActiveHead`); a mortality is excluded from it on purpose (see the report).
 */
export function porPalpar(herd: readonly PalpationHerdRow[], campaign: string | null): { readonly eligible: number; readonly porPalpar: number } {
  let eligible = 0;
  let pending = 0;
  for (const row of herd) {
    const status = (row.current_status ?? '').trim().toUpperCase();
    if (!isActiveHead(row) || status === 'BAJA_MORTANDAD' || !isApplicable(row)) continue;
    eligible += 1;
    if (herdBucket(row, campaign) !== 'vigente') pending += 1;
  }
  return { eligible, porPalpar: pending };
}

const RFID_OFFICIAL = /^\d{10}$/;

/** The 10-digit official SINIIGA tag of an animal, or null. A placeholder such as `S/N-00001` is not a SINIIGA. */
export function officialSiniiga(row: PalpationHerdRow): string | null {
  const rfid = (row.rfid_siniiga ?? '').trim();
  return RFID_OFFICIAL.test(rfid) ? rfid : null;
}

/**
 * Identifier shown to the user: the official 10-digit SINIIGA tag; otherwise brand + brand number (not unique, shown as a complement);
 * otherwise a neutral label with a short internal key. The internal key is always livestock_id.
 */
export function identifierOf(row: PalpationHerdRow): string {
  const rfid = (row.rfid_siniiga ?? '').trim();
  if (RFID_OFFICIAL.test(rfid)) return rfid;
  const brand = (row.brand_code ?? '').trim();
  const fire = (row.numero_fuego ?? '').trim();
  if (brand !== '' && fire !== '') return `${brand} ${fire}`;
  return `Sin identificador · ${row.livestock_id.slice(0, 8)}`;
}
