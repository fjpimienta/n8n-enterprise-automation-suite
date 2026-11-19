import { PalpationEventRow, PalpationHerdRow, ReproCondition } from '../models/palpation.types';
import { CompareCategory, categoryOfCell, categoryOfState } from './palpation-campaign-compare';
import { Campaign, CampaignCell, cellOf, latestPerCampaign } from './palpation-campaigns';
import { compareCalendarDates } from './palpation-dates';
import { identifierOf, officialSiniiga } from './palpation-metrics';

/**
 * Follow-up lists for ONE selected pair of campaigns (A then B): the cows that were Vacía in A and are still Vacía in B (persistent), and the
 * cows that were Vacía in A and were not palpated in B (pending follow-up), plus a coverage summary so nobody reads the lists as complete.
 * Pure functions over the rows the gateway returned; nothing is stored. The state of an animal in a campaign always comes from `animalState`
 * (through `cellOf`), the single source of truth shared with the KPI cards: an unconfirmed code with result VACÍA is Vacía and only carries a
 * flag. Ranch terms (RP, NO APTO, MATRIZ OCUPADA) are neither Vacía nor Preñada, and an NR is not a palpation: both stay as the report defines them.
 */

/** `CELL` is a row of the list behind one cell of the transition matrix (see `cellAnimals`). */
export type PairGroup = 'PERSISTENT' | 'PENDING' | 'CELL';

/** What an animal was in one campaign: the category of its latest counted event, with the data to show and to export. */
export interface PairCell {
  readonly category: CompareCategory;
  /** Calendar date of that event, or null when the animal was not palpated in the campaign. */
  readonly date: string | null;
  /** The code exactly as typed (for example UNE, ESTATICA, DF15, RP). Never interpreted. */
  readonly rawCode: string | null;
  /** Structured condition of an empty result (ESTATICA covers UNE and ESTATICA, as the clinic records it). Null for an unconfirmed code. */
  readonly condition: ReproCondition | null;
  /** The code is not confirmed by the vet (UNMAPPED). It is flagged, never reinterpreted. */
  readonly unconfirmed: boolean;
}

export interface PairRow {
  readonly group: PairGroup;
  readonly livestockId: string;
  /** Official 10-digit SINIIGA tag, or null. */
  readonly siniiga: string | null;
  /** Brand number ("quemado" / fuego), as recorded. */
  readonly fuego: string | null;
  readonly brand: string | null;
  readonly category: string | null;
  readonly currentStatus: string | null;
  readonly a: PairCell;
  readonly b: PairCell;
  /**
   * The animal has a row in the herd view. False means its events could not be matched to a herd row (identifier, category and status are then
   * missing); the animal is still counted, because the counts come from the events.
   */
  readonly herdMatched: boolean;
}

/** Animals that left the lists or never entered them, counted so the lists are not read as the whole herd. */
export interface PairCoverage {
  /** Animals with a counted palpation in A / in B. */
  readonly palpatedA: number;
  readonly palpatedB: number;
  /** In both, only in A (not palpated in B), only in B (no record in A). */
  readonly both: number;
  readonly onlyA: number;
  readonly onlyB: number;
  /** Per category of the latest counted event: `PREÑADA`, `VACÍA`, `RANCHO` (RP, NO APTO, MATRIZ OCUPADA) and `SIN_INTERPRETAR`. */
  readonly categoriesA: Readonly<Record<PalpatedCategory, number>>;
  readonly categoriesB: Readonly<Record<PalpatedCategory, number>>;
  /** Animals with a ranch term (not NR) in A, in B, and in either: neither Vacía nor Preñada. */
  readonly ranchoEither: number;
  /** Animals with an NR event inside the window: not examined, they do not count as palpated. */
  readonly nrA: number;
  readonly nrB: number;
  /** Vacía in A and a result other than Vacía in B (Preñada, rancho or sin interpretar): in neither list. */
  readonly vaciaAOtherInB: number;
}

export type PalpatedCategory = Exclude<CompareCategory, 'NO_PALPADA'>;

export interface PairLists {
  readonly persistent: readonly PairRow[];
  readonly pending: readonly PairRow[];
  readonly coverage: PairCoverage;
}

const EMPTY_CELL: PairCell = { category: 'NO_PALPADA', date: null, rawCode: null, condition: null, unconfirmed: false };

function toCell(cell: CampaignCell | null): PairCell {
  if (cell === null) return EMPTY_CELL;
  const e = cell.event;
  return {
    category: categoryOfState(cell.state),
    date: e.event_date,
    rawCode: e.raw_code,
    condition: e.repro_condition,
    unconfirmed: cell.unconfirmed,
  };
}

const zeroCategories = (): Record<PalpatedCategory, number> => ({ 'PREÑADA': 0, 'VACÍA': 0, RANCHO: 0, SIN_INTERPRETAR: 0 });

/** Distinct animals with an NR event dated inside the campaign. An NR is not a palpation, so it never enters the lists. */
function nrAnimals(events: readonly PalpationEventRow[], c: Campaign): Set<string> {
  const ids = new Set<string>();
  for (const e of events) {
    if (e.ranch_term === 'NR' && compareCalendarDates(e.event_date, c.from) >= 0 && compareCalendarDates(e.event_date, c.to) <= 0) ids.add(e.livestock_id);
  }
  return ids;
}

type HerdIndex = ReadonlyMap<string, PalpationHerdRow>;

function rowOf(group: PairGroup, id: string, cellA: CampaignCell | null, cellB: CampaignCell | null, byId: HerdIndex): PairRow {
  const animal = byId.get(id);
  return {
    group,
    livestockId: id,
    siniiga: animal ? officialSiniiga(animal) : null,
    fuego: animal?.numero_fuego?.trim() || null,
    brand: animal?.brand_code?.trim() || null,
    category: animal?.category ?? null,
    currentStatus: animal?.current_status ?? null,
    a: toCell(cellA),
    b: toCell(cellB),
    herdMatched: animal !== undefined,
  };
}

/** Stable order of a list: by identifier (numeric-aware), then by the internal key. */
function sortRows(rows: PairRow[], byId: HerdIndex): PairRow[] {
  const identifier = (r: PairRow): string => {
    const animal = byId.get(r.livestockId);
    return animal ? identifierOf(animal) : `Sin identificador · ${r.livestockId.slice(0, 8)}`;
  };
  return rows.sort((x, y) => identifier(x).localeCompare(identifier(y), 'es', { numeric: true }) || x.livestockId.localeCompare(y.livestockId));
}

export function pairLists(
  events: readonly PalpationEventRow[],
  herd: readonly PalpationHerdRow[],
  a: Campaign,
  b: Campaign,
): PairLists {
  const byId: HerdIndex = new Map(herd.map(h => [h.livestock_id, h] as const));
  const latestA = latestPerCampaign(events, a);
  const latestB = latestPerCampaign(events, b);

  const persistent: PairRow[] = [];
  const pending: PairRow[] = [];
  const categoriesA = zeroCategories();
  const categoriesB = zeroCategories();
  const rancho = new Set<string>();
  let both = 0;
  let vaciaAOtherInB = 0;

  for (const [id, ea] of latestA) {
    const cellA = cellOf(ea);
    const catA = categoryOfState(cellA.state);
    categoriesA[catA] += 1;
    if (catA === 'RANCHO') rancho.add(id);
    const eb = latestB.get(id);
    const cellB = eb === undefined ? null : cellOf(eb);
    if (cellB !== null) both += 1;
    if (catA !== 'VACÍA') continue;

    if (cellB === null) pending.push(rowOf('PENDING', id, cellA, null, byId));
    else if (categoryOfState(cellB.state) === 'VACÍA') persistent.push(rowOf('PERSISTENT', id, cellA, cellB, byId));
    else vaciaAOtherInB += 1;
  }
  for (const [id, eb] of latestB) {
    const catB = categoryOfState(cellOf(eb).state);
    categoriesB[catB] += 1;
    if (catB === 'RANCHO') rancho.add(id);
  }

  sortRows(persistent, byId);
  sortRows(pending, byId);

  const palpatedA = latestA.size;
  const palpatedB = latestB.size;
  return {
    persistent,
    pending,
    coverage: {
      palpatedA,
      palpatedB,
      both,
      onlyA: palpatedA - both,
      onlyB: palpatedB - both,
      categoriesA,
      categoriesB,
      ranchoEither: rancho.size,
      nrA: nrAnimals(events, a).size,
      nrB: nrAnimals(events, b).size,
      vaciaAOtherInB,
    },
  };
}

/**
 * The animals behind ONE cell of the transition matrix: those whose category in A is `from` and whose category in B is `to`. It is built from the
 * same `latestPerCampaign` as `transitions()`, so for every cell the list has exactly as many animals as the matrix counts (a test checks all 25
 * cells). "Sin registro" (`NO_PALPADA`) means no counted palpation record in that campaign: it covers animals that were not palpated, animals
 * whose only event is an NR, and animals whose rows could not be matched or loaded; the herd data only completes the identifiers, it never decides
 * who is in the list. The cell sin registro / sin registro is always empty (an animal in neither campaign is not in the comparison).
 */
export function cellAnimals(
  events: readonly PalpationEventRow[],
  herd: readonly PalpationHerdRow[],
  a: Campaign,
  b: Campaign,
  from: CompareCategory,
  to: CompareCategory,
): PairRow[] {
  const byId: HerdIndex = new Map(herd.map(h => [h.livestock_id, h] as const));
  const latestA = latestPerCampaign(events, a);
  const latestB = latestPerCampaign(events, b);
  const ids = new Set<string>([...latestA.keys(), ...latestB.keys()]);

  const rows: PairRow[] = [];
  for (const id of ids) {
    const ea = latestA.get(id);
    const eb = latestB.get(id);
    const cellA = ea === undefined ? null : cellOf(ea);
    const cellB = eb === undefined ? null : cellOf(eb);
    if (categoryOfCell(cellA) === from && categoryOfCell(cellB) === to) rows.push(rowOf('CELL', id, cellA, cellB, byId));
  }
  return sortRows(rows, byId);
}
