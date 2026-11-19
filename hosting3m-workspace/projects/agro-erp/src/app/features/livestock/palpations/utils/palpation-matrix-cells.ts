import { CompareCategory } from './palpation-campaign-compare';
import { CATEGORY_SHORT } from './palpation-campaign-view';
import { Campaign, validateCampaigns } from './palpation-campaigns';
import { compareCalendarDates, isCalendarDate } from './palpation-dates';

/**
 * Identifiers of the cells of the transition matrix and the deep link that opens one of them. Pure functions, no state. A cell is named by the
 * category in A and the category in B, with ASCII slugs that are safe in a URL: `sin-registro.prenada` is "no record in A, Preñada in B".
 * A deep link carries ONLY the two date ranges and the cell id: never an animal, an identifier, a company or a result. When it is opened, the data
 * comes from the active company exactly as in any other visit; the link cannot select another company or add rows.
 */

export interface MatrixCell {
  readonly from: CompareCategory;
  readonly to: CompareCategory;
}

/** Text identifier of a cell, as written in the URL and in the name of the CSV file. */
export type CellId = string;

export const CATEGORY_SLUG: Readonly<Record<CompareCategory, string>> = {
  'PREÑADA': 'prenada',
  'VACÍA': 'vacia',
  RANCHO: 'rancho',
  SIN_INTERPRETAR: 'sin-interpretar',
  NO_PALPADA: 'sin-registro',
};

const BY_SLUG: ReadonlyMap<string, CompareCategory> = new Map((Object.entries(CATEGORY_SLUG) as [CompareCategory, string][]).map(([k, v]) => [v, k]));

export function cellIdOf(cell: MatrixCell): CellId {
  return `${CATEGORY_SLUG[cell.from]}.${CATEGORY_SLUG[cell.to]}`;
}

/** True for the one cell that can never hold an animal: no record in A and no record in B (such an animal is not in the comparison). */
export function isImpossibleCell(cell: MatrixCell): boolean {
  return cell.from === 'NO_PALPADA' && cell.to === 'NO_PALPADA';
}

/**
 * Reads a cell id. Strict: it must be a string made of two KNOWN slugs joined by one dot, in lower case, and not the impossible cell. Anything
 * else (a different type, an unknown or upper-case slug, extra parts, spaces) gives null.
 */
export function parseCellId(text: unknown): MatrixCell | null {
  if (typeof text !== 'string' || text.length > 40) return null;
  const parts = text.split('.');
  if (parts.length !== 2) return null;
  const from = BY_SLUG.get(parts[0] as string);
  const to = BY_SLUG.get(parts[1] as string);
  if (from === undefined || to === undefined) return null;
  const cell: MatrixCell = { from, to };
  return isImpossibleCell(cell) ? null : cell;
}

/** "Sin registro en A y Preñada en B", with the names of the campaigns (or "A" and "B"). */
export function cellLabel(cell: MatrixCell, aName = 'A', bName = 'B'): string {
  return `${CATEGORY_SHORT[cell.from]} en ${aName} y ${CATEGORY_SHORT[cell.to]} en ${bName}`;
}

// ---- deep link -------------------------------------------------------------------------------------------------------------------------------

export const DEEP_LINK_PARAM = { a: 'a', b: 'b', cell: 'cell' } as const;

export interface DeepLink {
  readonly a: Pick<Campaign, 'from' | 'to'>;
  readonly b: Pick<Campaign, 'from' | 'to'>;
  /** The open cell, or null when the link only selects the two campaigns. */
  readonly cell: MatrixCell | null;
}

/** What `ParamMap` of the Angular router offers: all the values of a parameter. */
export interface ParamReader {
  getAll(name: string): readonly string[];
}

const RANGE = /^(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})$/;

/** `2026-08-03_2026-08-03`, the value of the `a` and `b` parameters. */
export function rangeParam(c: Pick<Campaign, 'from' | 'to'>): string {
  return `${c.from}_${c.to}`;
}

function readRange(values: readonly string[]): Pick<Campaign, 'from' | 'to'> | null {
  if (values.length !== 1) return null;
  const m = RANGE.exec(values[0] as string);
  if (m === null) return null;
  const from = m[1] as string;
  const to = m[2] as string;
  return isCalendarDate(from) && isCalendarDate(to) && compareCalendarDates(from, to) <= 0 ? { from, to } : null;
}

/**
 * Reads a deep link from the query parameters, strictly. No parameter of ours means "no link" (null: the normal view). If any of ours is present
 * it must ALL be valid or the whole link is rejected (null): `a` and `b` exactly once each, each a `YYYY-MM-DD_YYYY-MM-DD` range of real dates
 * in order, the two ranges not overlapping (so they are two different campaigns), and `cell`, if present, exactly once and a known cell id.
 * Parameters that are not ours are ignored. The function never throws.
 */
export function parseDeepLink(params: ParamReader): DeepLink | null {
  const as = params.getAll(DEEP_LINK_PARAM.a);
  const bs = params.getAll(DEEP_LINK_PARAM.b);
  const cells = params.getAll(DEEP_LINK_PARAM.cell);
  if (as.length === 0 && bs.length === 0 && cells.length === 0) return null;

  const a = readRange(as);
  const b = readRange(bs);
  if (a === null || b === null) return null;
  if (validateCampaigns([{ id: 'link-a', label: 'A', ...a }, { id: 'link-b', label: 'B', ...b }]).length > 0) return null;

  if (cells.length === 0) return { a, b, cell: null };
  if (cells.length !== 1) return null;
  const cell = parseCellId(cells[0]);
  return cell === null ? null : { a, b, cell };
}

/**
 * The address that opens a cell: `base` (origin and path, no query and no hash) followed by `a`, `b` and `cell`. It holds only the two date ranges
 * and the cell id.
 */
export function buildDeepLink(base: string, a: Pick<Campaign, 'from' | 'to'>, b: Pick<Campaign, 'from' | 'to'>, cell: MatrixCell): string {
  const query = new URLSearchParams([[DEEP_LINK_PARAM.a, rangeParam(a)], [DEEP_LINK_PARAM.b, rangeParam(b)], [DEEP_LINK_PARAM.cell, cellIdOf(cell)]]);
  return `${base}?${query.toString()}`;
}

// ---- which campaigns are A and B ---------------------------------------------------------------------------------------------------------------

/** The campaign with this id, or else the one `fromEnd` positions from the end (the defaults are the two most recent). Null if there is none. */
export function pickCampaign(campaigns: readonly Campaign[], id: string | null, fromEnd: number): Campaign | null {
  return campaigns.find(c => c.id === id) ?? campaigns[campaigns.length + fromEnd] ?? null;
}

/** Campaign A and campaign B for a selection: the chosen ones while they exist, otherwise the second-to-last and the last campaign. */
export function resolvePair(campaigns: readonly Campaign[], aId: string | null, bId: string | null): { readonly a: Campaign; readonly b: Campaign } | null {
  const a = pickCampaign(campaigns, aId, -2);
  const b = pickCampaign(campaigns, bId, -1);
  return a === null || b === null ? null : { a, b };
}
