import { PalpationEventRow } from '../models/palpation.types';
import { compareCalendarDates, daysBetween, isCalendarDate } from './palpation-dates';
import { AnimalState, animalState, latestPerAnimal } from './palpation-metrics';

/**
 * Campaign comparison of the palpation report: pure functions only. No HTTP, no signals, no DOM, nothing stored. A campaign is a date range
 * the USER defines; `suggestCampaigns` only proposes ranges when the screen opens. Every state of an animal comes from `animalState`, the same
 * function the KPI cards use, so the comparison and the cards always agree. Display-only (CLAUDE.md, Zero-Compute Client).
 */

export const MIN_CAMPAIGNS = 2;
export const MAX_CAMPAIGNS = 6;
/** Two palpation dates further apart than this many days belong to different suggested campaigns. */
export const DEFAULT_GAP_DAYS = 7;
export const MAX_LABEL_LENGTH = 40;

/** A user-defined campaign: an inclusive range of calendar dates (`YYYY-MM-DD`). */
export interface Campaign {
  readonly id: string;
  readonly label: string;
  readonly from: string;
  readonly to: string;
}

/**
 * Proposes campaigns by clustering the distinct dates of the events that count as a palpation (the 2023 historical load included; an NR
 * does not count and is left out). A new cluster starts when the gap to the previous date is GREATER than `gapDays` (exactly `gapDays` stays
 * in the same cluster). With more than `MAX_CAMPAIGNS` clusters the most recent ones are proposed; with fewer than `MIN_CAMPAIGNS`, nothing.
 * Labels number the proposal from the oldest ("Campaña 1"). It never decides for the user: the screen lets them edit every range.
 */
export function suggestCampaigns(events: readonly PalpationEventRow[], gapDays: number = DEFAULT_GAP_DAYS): Campaign[] {
  const dates = [...new Set(events.filter(e => e.counts_as_palpation && isCalendarDate(e.event_date)).map(e => e.event_date))].sort(compareCalendarDates);
  if (dates.length === 0) return [];

  const clusters: { from: string; to: string }[] = [];
  for (const date of dates) {
    const last = clusters[clusters.length - 1];
    if (last !== undefined && daysBetween(last.to, date) <= gapDays) last.to = date;
    else clusters.push({ from: date, to: date });
  }
  if (clusters.length < MIN_CAMPAIGNS) return [];

  return clusters.slice(-MAX_CAMPAIGNS).map((c, i) => ({ id: `camp-${i + 1}`, label: `Campaña ${i + 1}`, from: c.from, to: c.to }));
}

export type CampaignErrorCode =
  | 'too-few'
  | 'too-many'
  | 'label-empty'
  | 'label-long'
  | 'label-duplicate'
  | 'from-invalid'
  | 'to-invalid'
  | 'range-order'
  | 'overlap';

export interface CampaignError {
  /** The campaign the error is about, or null for an error of the whole list. */
  readonly id: string | null;
  readonly code: CampaignErrorCode;
  /** For `overlap`: the label of the other campaign. */
  readonly other: string | null;
}

/** True when two inclusive ranges share at least one day. Both must be valid and ordered. */
function overlaps(a: Campaign, b: Campaign): boolean {
  return compareCalendarDates(a.from, b.to) <= 0 && compareCalendarDates(b.from, a.to) <= 0;
}

/**
 * Checks the campaigns the user defined. An empty list means they can be used to compare. Overlapping ranges are rejected, so an event
 * belongs to one campaign at most and no list can repeat it.
 */
export function validateCampaigns(campaigns: readonly Campaign[]): CampaignError[] {
  const errors: CampaignError[] = [];
  if (campaigns.length < MIN_CAMPAIGNS) errors.push({ id: null, code: 'too-few', other: null });
  if (campaigns.length > MAX_CAMPAIGNS) errors.push({ id: null, code: 'too-many', other: null });

  const seen = new Map<string, string>();
  for (const c of campaigns) {
    const label = c.label.trim();
    if (label === '') errors.push({ id: c.id, code: 'label-empty', other: null });
    else if (label.length > MAX_LABEL_LENGTH) errors.push({ id: c.id, code: 'label-long', other: null });
    else if (seen.has(label.toLowerCase())) errors.push({ id: c.id, code: 'label-duplicate', other: seen.get(label.toLowerCase()) ?? null });
    else seen.set(label.toLowerCase(), label);

    const fromOk = isCalendarDate(c.from);
    const toOk = isCalendarDate(c.to);
    if (!fromOk) errors.push({ id: c.id, code: 'from-invalid', other: null });
    if (!toOk) errors.push({ id: c.id, code: 'to-invalid', other: null });
    if (fromOk && toOk && compareCalendarDates(c.from, c.to) > 0) errors.push({ id: c.id, code: 'range-order', other: null });
  }

  const usable = campaigns.filter(c => isCalendarDate(c.from) && isCalendarDate(c.to) && compareCalendarDates(c.from, c.to) <= 0);
  for (let i = 0; i < usable.length; i++) {
    for (let j = i + 1; j < usable.length; j++) {
      const a = usable[i] as Campaign;
      const b = usable[j] as Campaign;
      if (overlaps(a, b)) errors.push({ id: b.id, code: 'overlap', other: a.label.trim() });
    }
  }
  return errors;
}

/** Latest counted event of each animal inside the campaign (inclusive). Same tie-break as the report: day, creation time, event key. */
export function latestPerCampaign(events: readonly PalpationEventRow[], campaign: Campaign): Map<string, PalpationEventRow> {
  return latestPerAnimal(events, { from: campaign.from, to: campaign.to });
}

/** What an animal is in one campaign: the state of its latest counted event, plus the flag of an unconfirmed code. */
export interface CampaignCell {
  readonly state: AnimalState;
  /** The latest event carries an unconfirmed code (`UNMAPPED`). Its state is still the one `animalState` gives: it is flagged, never reinterpreted. */
  readonly unconfirmed: boolean;
  readonly event: PalpationEventRow;
}

export function cellOf(event: PalpationEventRow): CampaignCell {
  return { state: animalState(event), unconfirmed: event.mapping_status === 'UNMAPPED', event };
}

/**
 * For each animal with a counted event in any campaign, its cell in each campaign (same order as `campaigns`), or null when it was not
 * palpated in that campaign. An animal appears once; the order of the map is stable (campaign order, then first appearance).
 */
export function animalCampaignCells(
  events: readonly PalpationEventRow[],
  campaigns: readonly Campaign[],
): Map<string, (CampaignCell | null)[]> {
  const perCampaign = campaigns.map(c => latestPerCampaign(events, c));
  const result = new Map<string, (CampaignCell | null)[]>();
  for (const latest of perCampaign) {
    for (const id of latest.keys()) {
      if (result.has(id)) continue;
      result.set(id, perCampaign.map(m => {
        const e = m.get(id);
        return e === undefined ? null : cellOf(e);
      }));
    }
  }
  return result;
}
