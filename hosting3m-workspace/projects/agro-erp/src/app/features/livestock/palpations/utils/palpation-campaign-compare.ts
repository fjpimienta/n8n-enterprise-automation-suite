import { PalpationEventRow, PalpationHerdRow, RanchTerm } from '../models/palpation.types';
import { Campaign, CampaignCell, animalCampaignCells, cellOf, latestPerCampaign } from './palpation-campaigns';
import { compareCalendarDates } from './palpation-dates';
import { AnimalState, EmptySubtype, emptySubtypeOf, gestationOf, identifierOf } from './palpation-metrics';

/**
 * Comparison between campaigns: transition table, animals without signs of pregnancy, and the rows of the full event list. Pure functions
 * over the rows the gateway returned; nothing is stored. The state of every animal comes from `animalState` (through `cellOf`), the single
 * source of truth shared with the KPI cards: an unconfirmed code with result VACÍA is Vacía and only carries a flag.
 */

/** Categories of the transition table. `NO_PALPADA` = no counted event in that campaign. */
export type CompareCategory = 'PREÑADA' | 'VACÍA' | 'RANCHO' | 'SIN_INTERPRETAR' | 'NO_PALPADA';

export const COMPARE_CATEGORIES: readonly CompareCategory[] = ['PREÑADA', 'VACÍA', 'RANCHO', 'SIN_INTERPRETAR', 'NO_PALPADA'];

/** Maps the state of an animal to a category: no result and unrecognised values both go to `SIN_INTERPRETAR`, so every row adds up. */
export function categoryOfState(state: AnimalState): Exclude<CompareCategory, 'NO_PALPADA'> {
  switch (state) {
    case 'PREÑADA': return 'PREÑADA';
    case 'VACÍA': return 'VACÍA';
    case 'TERMINO_RANCHO': return 'RANCHO';
    default: return 'SIN_INTERPRETAR';
  }
}

export function categoryOfCell(cell: CampaignCell | null): CompareCategory {
  return cell === null ? 'NO_PALPADA' : categoryOfState(cell.state);
}

type Counts = Record<CompareCategory, number>;

const zeroCounts = (): Counts => ({ PREÑADA: 0, VACÍA: 0, RANCHO: 0, SIN_INTERPRETAR: 0, NO_PALPADA: 0 });

export interface TransitionTable {
  readonly from: Campaign;
  readonly to: Campaign;
  /** Animals with at least one counted event in `from` or `to`. */
  readonly universe: number;
  /** Animals per category in `from` (the denominator of each row). Sums to `universe`. */
  readonly rowTotals: Readonly<Counts>;
  /** Animals per category in `to`. Sums to `universe`. */
  readonly colTotals: Readonly<Counts>;
  /** `matrix[category in from][category in to]`. */
  readonly matrix: Readonly<Record<CompareCategory, Readonly<Counts>>>;
  /** Animals whose latest event in the campaign carries an unconfirmed code (a flag, not a category). */
  readonly unconfirmedFrom: number;
  readonly unconfirmedTo: number;
  /** The matrix adds up to the universe. The UI must not show the table when it does not. */
  readonly identityHolds: boolean;
}

/** Transition of every animal of the universe from the state it had in `from` to the state it had in `to`. */
export function transitions(events: readonly PalpationEventRow[], from: Campaign, to: Campaign): TransitionTable {
  const a = latestPerCampaign(events, from);
  const b = latestPerCampaign(events, to);
  const ids = new Set<string>([...a.keys(), ...b.keys()]);

  const matrix = Object.fromEntries(COMPARE_CATEGORIES.map(c => [c, zeroCounts()])) as Record<CompareCategory, Counts>;
  const rowTotals = zeroCounts();
  const colTotals = zeroCounts();
  let unconfirmedFrom = 0;
  let unconfirmedTo = 0;
  for (const id of ids) {
    const ea = a.get(id);
    const eb = b.get(id);
    const ca = ea === undefined ? null : cellOf(ea);
    const cb = eb === undefined ? null : cellOf(eb);
    const rowCat = categoryOfCell(ca);
    const colCat = categoryOfCell(cb);
    matrix[rowCat][colCat] += 1;
    rowTotals[rowCat] += 1;
    colTotals[colCat] += 1;
    if (ca?.unconfirmed) unconfirmedFrom += 1;
    if (cb?.unconfirmed) unconfirmedTo += 1;
  }
  const sum = COMPARE_CATEGORIES.reduce((acc, r) => acc + COMPARE_CATEGORIES.reduce((s, c) => s + matrix[r][c], 0), 0);
  return { from, to, universe: ids.size, rowTotals, colTotals, matrix, unconfirmedFrom, unconfirmedTo, identityHolds: sum === ids.size };
}

/** One animal of the "sin indicios de preñez" list. */
export interface NeverPregnantRow {
  readonly livestockId: string;
  readonly identifier: string;
  readonly category: string | null;
  readonly currentStatus: string | null;
  /** Campaigns where the animal has a counted event. */
  readonly appearsIn: number;
  /** Campaigns where its latest counted event is Vacía. */
  readonly emptyIn: number;
  /** One cell per campaign, in the order of the campaigns given; null = not palpated there. */
  readonly cells: readonly (CampaignCell | null)[];
  /** At least one of its events in the campaigns carries an unconfirmed code. */
  readonly withUnconfirmed: boolean;
  /** Latest counted date across the campaigns. */
  readonly lastDate: string;
}

export interface NeverPregnantResult {
  /** At least one clinical Vacía and no Preñada in any campaign. */
  readonly main: readonly NeverPregnantRow[];
  /**
   * No Preñada and no Vacía in any campaign, only ranch terms, no result or unrecognised values: not counted as vacía. An animal that is Vacía
   * in one campaign and has a ranch term in another is in `main` (it has a clinical result) and is counted vacía only for that campaign.
   */
  readonly uninterpreted: readonly NeverPregnantRow[];
}

/**
 * Animals with no Preñada in ANY of the campaigns, split in the two groups above. It only compares results; it explains nothing.
 * An animal whose latest event is Preñada in some campaign (even one flagged with an unconfirmed code) is not in either list.
 */
export function neverPregnant(
  events: readonly PalpationEventRow[],
  herd: readonly PalpationHerdRow[],
  campaigns: readonly Campaign[],
): NeverPregnantResult {
  const byId = new Map(herd.map(h => [h.livestock_id, h] as const));
  const main: NeverPregnantRow[] = [];
  const uninterpreted: NeverPregnantRow[] = [];

  for (const [id, cells] of animalCampaignCells(events, campaigns)) {
    const present = cells.filter((c): c is CampaignCell => c !== null);
    if (present.some(c => c.state === 'PREÑADA')) continue;
    const emptyIn = present.filter(c => c.state === 'VACÍA').length;
    const animal = byId.get(id);
    const row: NeverPregnantRow = {
      livestockId: id,
      identifier: animal ? identifierOf(animal) : `Sin identificador · ${id.slice(0, 8)}`,
      category: animal?.category ?? null,
      currentStatus: animal?.current_status ?? null,
      appearsIn: present.length,
      emptyIn,
      cells,
      withUnconfirmed: present.some(c => c.unconfirmed),
      lastDate: present.map(c => c.event.event_date).reduce((m, d) => (compareCalendarDates(d, m) > 0 ? d : m)),
    };
    (emptyIn > 0 ? main : uninterpreted).push(row);
  }
  const byIdentifier = (a: NeverPregnantRow, b: NeverPregnantRow) => a.identifier.localeCompare(b.identifier, 'es', { numeric: true }) || a.livestockId.localeCompare(b.livestockId);
  main.sort((a, b) => b.emptyIn - a.emptyIn || byIdentifier(a, b));
  uninterpreted.sort(byIdentifier);
  return { main, uninterpreted };
}

/** One row of the full list: one event, in the campaign whose range contains its date. There is no technician field on purpose. */
export interface CampaignEventRow {
  readonly id: string;
  readonly livestockId: string;
  readonly identifier: string;
  readonly category: string;
  readonly currentStatus: string;
  readonly campaignId: string;
  readonly campaignLabel: string;
  /** Position of the campaign in the list given (oldest first when the caller sorts them). */
  readonly campaignOrder: number;
  readonly date: string;
  readonly state: AnimalState;
  readonly subtype: EmptySubtype | null;
  readonly ranchTerm: RanchTerm | null;
  readonly gestation: { readonly months: number; readonly days: number } | null;
  /** The code as typed, only when it is unconfirmed (UNMAPPED). Never interpreted. */
  readonly unconfirmedCode: string | null;
  readonly unconfirmed: boolean;
  readonly historical: boolean;
  readonly uninterpreted: boolean;
  /** False only for NR: listed, but it does not count as a palpation. */
  readonly counts: boolean;
}

/**
 * Every event whose date is inside a campaign, once each (by event key). Campaigns that overlap are rejected by `validateCampaigns`, so an
 * event belongs to one campaign; if they did overlap, the first campaign wins and the row is still listed once.
 */
export function campaignEventRows(
  events: readonly PalpationEventRow[],
  herd: readonly PalpationHerdRow[],
  campaigns: readonly Campaign[],
): CampaignEventRow[] {
  const byId = new Map(herd.map(h => [h.livestock_id, h] as const));
  const seen = new Set<string>();
  const rows: CampaignEventRow[] = [];
  for (const e of events) {
    if (seen.has(e.health_log_id)) continue;
    const order = campaigns.findIndex(c => compareCalendarDates(e.event_date, c.from) >= 0 && compareCalendarDates(e.event_date, c.to) <= 0);
    if (order < 0) continue;
    seen.add(e.health_log_id);
    const campaign = campaigns[order] as Campaign;
    const animal = byId.get(e.livestock_id);
    const cell = cellOf(e);
    rows.push({
      id: e.health_log_id,
      livestockId: e.livestock_id,
      identifier: animal ? identifierOf(animal) : `Sin identificador · ${e.livestock_id.slice(0, 8)}`,
      category: animal?.category ?? '—',
      currentStatus: animal?.current_status ?? '—',
      campaignId: campaign.id,
      campaignLabel: campaign.label,
      campaignOrder: order,
      date: e.event_date,
      state: cell.state,
      subtype: cell.state === 'VACÍA' ? emptySubtypeOf(e) : null,
      ranchTerm: e.ranch_term,
      gestation: cell.state === 'PREÑADA' ? gestationOf(e) : null,
      unconfirmedCode: cell.unconfirmed ? e.raw_code : null,
      unconfirmed: cell.unconfirmed,
      historical: e.is_historical_load,
      uninterpreted: e.uninterpreted,
      counts: e.counts_as_palpation,
    });
  }
  return rows;
}

export type EventSortKey = 'campaign' | 'date' | 'identifier' | 'state' | 'currentStatus' | 'gestation';
export type EventSortDir = 'asc' | 'desc';

const STATE_ORDER: Readonly<Record<AnimalState, number>> = { 'PREÑADA': 0, 'VACÍA': 1, TERMINO_RANCHO: 2, SIN_RESULTADO: 3, SIN_INTERPRETAR: 4 };

/**
 * Stable sort. The default view is campaign ascending, then date descending: when sorting by campaign, the date inside each campaign is
 * always newest first (whatever the direction), and the event key breaks every remaining tie, so the order is the same for the same data.
 * A missing gestation always goes last.
 */
export function sortCampaignEventRows(rows: readonly CampaignEventRow[], key: EventSortKey, dir: EventSortDir): CampaignEventRow[] {
  const sign = dir === 'asc' ? 1 : -1;
  const primary = (a: CampaignEventRow, b: CampaignEventRow): number => {
    switch (key) {
      case 'campaign': return sign * (a.campaignOrder - b.campaignOrder);
      case 'date': return sign * compareCalendarDates(a.date, b.date);
      case 'identifier': return sign * a.identifier.localeCompare(b.identifier, 'es', { numeric: true });
      case 'state': return sign * (STATE_ORDER[a.state] - STATE_ORDER[b.state]);
      case 'currentStatus': return sign * a.currentStatus.localeCompare(b.currentStatus, 'es');
      case 'gestation': {
        if (a.gestation === null && b.gestation === null) return 0;
        if (a.gestation === null) return 1;
        if (b.gestation === null) return -1;
        return sign * (a.gestation.days - b.gestation.days);
      }
    }
  };
  return rows
    .map((r, i) => ({ r, i }))
    .sort((x, y) => {
      const p = primary(x.r, y.r);
      if (p !== 0) return p;
      const byDate = key === 'date' ? 0 : compareCalendarDates(y.r.date, x.r.date); // newest first inside any other key
      if (byDate !== 0) return byDate;
      return x.r.id < y.r.id ? -1 : x.r.id > y.r.id ? 1 : x.i - y.i;
    })
    .map(x => x.r);
}

/** Rows of one campaign, or all of them. */
export function filterEventsByCampaign(rows: readonly CampaignEventRow[], campaignId: string): CampaignEventRow[] {
  return campaignId === 'TODAS' ? [...rows] : rows.filter(r => r.campaignId === campaignId);
}
