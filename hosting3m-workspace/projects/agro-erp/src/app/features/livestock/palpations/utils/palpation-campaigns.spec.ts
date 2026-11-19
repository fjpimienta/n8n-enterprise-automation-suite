import { describe, expect, it } from 'vitest';
import { eventRow } from '../testing/palpation.fixtures';
import {
  Campaign,
  DEFAULT_GAP_DAYS,
  MAX_CAMPAIGNS,
  MAX_LABEL_LENGTH,
  animalCampaignCells,
  cellOf,
  latestPerCampaign,
  sortCampaigns,
  suggestCampaigns,
  validateCampaigns,
} from './palpation-campaigns';

/** One synthetic event on a day. */
const ev = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  eventRow({ health_log_id: id, livestock_id: animal, event_date: day, result: 'VACÍA', ...over });

const camp = (id: string, from: string, to: string, label = id): Campaign => ({ id, label, from, to });

describe('suggestCampaigns', () => {
  it('keeps two dates exactly 7 days apart in the same cluster, and splits them at 8 days (the boundary)', () => {
    const same = suggestCampaigns([ev('a', 'A1', '2026-10-01'), ev('b', 'A2', '2026-10-08'), ev('c', 'A3', '2026-11-20')]);
    expect(same.map(c => [c.from, c.to])).toEqual([['2026-10-01', '2026-10-08'], ['2026-11-20', '2026-11-20']]);
    const split = suggestCampaigns([ev('a', 'A1', '2026-10-01'), ev('b', 'A2', '2026-10-09')]);
    expect(split.map(c => [c.from, c.to])).toEqual([['2026-10-01', '2026-10-01'], ['2026-10-09', '2026-10-09']]);
  });

  it('chains dates: each gap is measured to the PREVIOUS date, not to the start of the cluster', () => {
    // 1 -> 7 -> 14 -> 21 are 6/7/7-day gaps: one cluster of 20 days; then a gap of 8 starts another
    const out = suggestCampaigns([
      ev('a', 'A', '2026-09-01'), ev('b', 'A', '2026-09-07'), ev('c', 'A', '2026-09-14'), ev('d', 'A', '2026-09-21'), ev('e', 'A', '2026-09-29'),
    ]);
    expect(out.map(c => [c.from, c.to])).toEqual([['2026-09-01', '2026-09-21'], ['2026-09-29', '2026-09-29']]);
  });

  it('honours a different gap and exposes the default', () => {
    const events = [ev('a', 'A', '2026-10-01'), ev('b', 'B', '2026-10-04'), ev('c', 'C', '2026-10-10')];
    expect(DEFAULT_GAP_DAYS).toBe(7);
    expect(suggestCampaigns(events, 2).length).toBe(3);
    expect(suggestCampaigns(events, 3).length).toBe(2);
    expect(suggestCampaigns(events, 6)).toEqual([]); // one cluster only: nothing to compare
  });

  it('includes the 2023 historical load as its own campaign', () => {
    const out = suggestCampaigns([
      ev('h1', 'A', '2023-07-20', { is_historical_load: true }),
      ev('h2', 'B', '2023-07-21', { is_historical_load: true }),
      ev('n1', 'A', '2026-10-02'),
    ]);
    expect(out.map(c => [c.from, c.to])).toEqual([['2023-07-20', '2023-07-21'], ['2026-10-02', '2026-10-02']]);
  });

  it('leaves out events that do not count as a palpation (NR)', () => {
    const out = suggestCampaigns([
      ev('a', 'A', '2026-09-01'),
      ev('nr', 'B', '2026-09-20', { ranch_term: 'NR', counts_as_palpation: false }),
      ev('b', 'C', '2026-10-15'),
    ]);
    expect(out.map(c => [c.from, c.to])).toEqual([['2026-09-01', '2026-09-01'], ['2026-10-15', '2026-10-15']]);
  });

  it('does not depend on the order of the rows and ignores repeated dates', () => {
    const rows = [ev('c', 'A', '2026-11-20'), ev('a', 'B', '2026-10-01'), ev('d', 'C', '2026-11-20'), ev('b', 'D', '2026-10-03')];
    const forward = suggestCampaigns(rows);
    expect(suggestCampaigns([...rows].reverse())).toEqual(forward);
    expect(forward.map(c => [c.from, c.to])).toEqual([['2026-10-01', '2026-10-03'], ['2026-11-20', '2026-11-20']]);
  });

  it('proposes nothing with fewer than two clusters (none, or a single one)', () => {
    expect(suggestCampaigns([])).toEqual([]);
    expect(suggestCampaigns([ev('a', 'A', '2026-10-01'), ev('b', 'B', '2026-10-05')])).toEqual([]);
    expect(suggestCampaigns([ev('nr', 'A', '2026-10-01', { counts_as_palpation: false, ranch_term: 'NR' })])).toEqual([]);
  });

  it('proposes only the 6 most recent clusters when there are more, labelled from the oldest of those', () => {
    const days = ['2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01', '2026-05-01', '2026-06-01', '2026-07-01', '2026-08-01'];
    const out = suggestCampaigns(days.map((d, i) => ev(`e${i}`, `A${i}`, d)));
    expect(out.length).toBe(MAX_CAMPAIGNS);
    expect(out.map(c => c.from)).toEqual(days.slice(2));
    expect(out.map(c => c.label)).toEqual(['Campaña 1', 'Campaña 2', 'Campaña 3', 'Campaña 4', 'Campaña 5', 'Campaña 6']);
    expect(new Set(out.map(c => c.id)).size).toBe(6);
  });

  it('proposes ranges that pass validation', () => {
    const out = suggestCampaigns([ev('a', 'A', '2026-09-01'), ev('b', 'B', '2026-09-30'), ev('c', 'C', '2026-11-15')]);
    expect(validateCampaigns(out)).toEqual([]);
  });
});

describe('validateCampaigns', () => {
  const ok = [camp('a', '2026-09-01', '2026-09-10', 'Septiembre'), camp('b', '2026-11-01', '2026-11-10', 'Noviembre')];
  const codes = (list: Campaign[]) => validateCampaigns(list).map(e => `${e.id ?? '*'}:${e.code}`);

  it('accepts 2 to 6 valid, ordered, separate ranges', () => {
    expect(validateCampaigns(ok)).toEqual([]);
    const six = Array.from({ length: 6 }, (_, i) => camp(`c${i}`, `2026-0${i + 1}-01`, `2026-0${i + 1}-05`, `Campaña ${i + 1}`));
    expect(validateCampaigns(six)).toEqual([]);
  });

  it('requires at least 2 and at most 6 campaigns', () => {
    expect(codes([])).toEqual(['*:too-few']);
    expect(codes([ok[0] as Campaign])).toEqual(['*:too-few']);
    const seven = Array.from({ length: 7 }, (_, i) => camp(`c${i}`, `2026-0${i + 1}-01`, `2026-0${i + 1}-05`, `Campaña ${i + 1}`));
    expect(codes(seven)).toEqual(['*:too-many']);
  });

  it('rejects an invalid date, a reversed range and a label that is empty, too long or repeated', () => {
    expect(codes([camp('a', '2026-13-01', '2026-09-10', 'A'), camp('b', '2026-11-01', 'x', 'B')])).toEqual(['a:from-invalid', 'b:to-invalid']);
    expect(codes([camp('a', '2026-09-10', '2026-09-01', 'A'), ok[1] as Campaign])).toEqual(['a:range-order']);
    expect(codes([camp('a', '2026-09-01', '2026-09-10', '   '), ok[1] as Campaign])).toEqual(['a:label-empty']);
    expect(codes([camp('a', '2026-09-01', '2026-09-10', 'x'.repeat(MAX_LABEL_LENGTH + 1)), ok[1] as Campaign])).toEqual(['a:label-long']);
    expect(codes([camp('a', '2026-09-01', '2026-09-10', 'Hato'), camp('b', '2026-11-01', '2026-11-10', ' hato ')])).toEqual(['b:label-duplicate']);
    expect(validateCampaigns([camp('a', '2026-09-01', '2026-09-10', 'x'.repeat(MAX_LABEL_LENGTH)), ok[1] as Campaign])).toEqual([]);
  });

  it('rejects overlapping ranges, including ranges that touch on one day (the ends are inclusive)', () => {
    const e = validateCampaigns([camp('a', '2026-09-01', '2026-09-10', 'Primera'), camp('b', '2026-09-10', '2026-09-20', 'Segunda')]);
    expect(e).toEqual([{ id: 'b', code: 'overlap', other: 'Primera' }]);
    expect(codes([camp('a', '2026-09-01', '2026-09-10'), camp('b', '2026-09-11', '2026-09-20')])).toEqual([]);
    expect(codes([camp('a', '2026-09-01', '2026-12-31'), camp('b', '2026-10-01', '2026-10-02')])).toEqual(['b:overlap']);
  });

  it('does not call a campaign with a bad date an overlap', () => {
    expect(codes([camp('a', '2026-09-01', '2026-09-10'), camp('b', 'x', '2026-09-05')])).toEqual(['b:from-invalid']);
  });
});

describe('sortCampaigns', () => {
  it('orders by start date, then end date, then id, without touching the list it receives', () => {
    const list = [camp('c', '2026-11-01', '2026-11-10'), camp('a', '2026-09-01', '2026-09-20'), camp('b', '2026-09-01', '2026-09-05'), camp('d', '2026-09-01', '2026-09-05')];
    const copy = [...list];
    expect(sortCampaigns(list).map(c => c.id)).toEqual(['b', 'd', 'a', 'c']);
    expect(list).toEqual(copy);
  });
});

describe('latestPerCampaign', () => {
  const c1 = camp('c1', '2026-09-01', '2026-09-15');

  it('takes the latest counted event of each animal inside the range, ends included', () => {
    const events = [
      ev('a1', 'A', '2026-09-01', { result: 'VACÍA' }),
      ev('a2', 'A', '2026-09-15', { result: 'PREÑADA', gestation_days: 90 }),
      ev('a3', 'A', '2026-09-16', { result: 'VACÍA' }), // outside
      ev('b1', 'B', '2026-08-31', { result: 'VACÍA' }), // outside
    ];
    const out = latestPerCampaign(events, c1);
    expect([...out.keys()]).toEqual(['A']);
    expect(out.get('A')?.health_log_id).toBe('a2');
  });

  it('breaks a tie on the same day by creation time, then by event key, the same way every time', () => {
    const early = ev('x1', 'A', '2026-09-05', { created_at: '2026-09-05T08:00:00.000Z', result: 'VACÍA' });
    const late = ev('x2', 'A', '2026-09-05', { created_at: '2026-09-05T20:00:00.000Z', result: 'PREÑADA' });
    expect(latestPerCampaign([early, late], c1).get('A')?.health_log_id).toBe('x2');
    expect(latestPerCampaign([late, early], c1).get('A')?.health_log_id).toBe('x2');
    const k1 = ev('k-a', 'B', '2026-09-05', { created_at: '2026-09-05T08:00:00.000Z' });
    const k2 = ev('k-b', 'B', '2026-09-05', { created_at: '2026-09-05T08:00:00.000Z' });
    expect(latestPerCampaign([k1, k2], c1).get('B')?.health_log_id).toBe('k-b');
    expect(latestPerCampaign([k2, k1], c1).get('B')?.health_log_id).toBe('k-b');
  });

  it('does not count an NR as a palpation: an animal with only an NR is not palpated in that campaign', () => {
    const nr = ev('nr', 'A', '2026-09-05', { ranch_term: 'NR', counts_as_palpation: false });
    expect(latestPerCampaign([nr], c1).size).toBe(0);
    const real = ev('r', 'A', '2026-09-03', { result: 'VACÍA' });
    expect(latestPerCampaign([real, nr], c1).get('A')?.health_log_id).toBe('r');
  });

  it('keeps the historical-load rules: the 2023 load is an ordinary counted event when its date is in the range', () => {
    const h = ev('h', 'A', '2023-07-20', { is_historical_load: true, result: 'PREÑADA', gestation_days: 150 });
    expect(latestPerCampaign([h], camp('old', '2023-07-01', '2023-07-31')).get('A')?.health_log_id).toBe('h');
    expect(latestPerCampaign([h], c1).size).toBe(0);
  });
});

describe('cellOf: one source of truth for the state of an animal', () => {
  it('an unconfirmed code with result VACÍA is Vacía, and is flagged', () => {
    const cell = cellOf(ev('u', 'A', '2026-09-05', { result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15' }));
    expect(cell.state).toBe('VACÍA');
    expect(cell.unconfirmed).toBe(true);
  });

  it('an unconfirmed code that carries PREÑADA is handled by animalState (Preñada) and flagged, never silently reinterpreted', () => {
    const cell = cellOf(ev('u', 'A', '2026-09-05', { result: 'PREÑADA', gestation_days: 120, mapping_status: 'UNMAPPED', raw_code: 'XY9' }));
    expect(cell.state).toBe('PREÑADA');
    expect(cell.unconfirmed).toBe(true);
    expect(cell.event.raw_code).toBe('XY9');
  });

  it('a ranch term, an unrecognised value and a missing result keep the states animalState gives them', () => {
    expect(cellOf(ev('r', 'A', '2026-09-05', { ranch_term: 'RP', is_clinical_result: false })).state).toBe('TERMINO_RANCHO');
    expect(cellOf(ev('s', 'A', '2026-09-05', { result: null, is_clinical_result: false })).state).toBe('SIN_RESULTADO');
    expect(cellOf(ev('i', 'A', '2026-09-05', { result: null, uninterpreted: true, is_clinical_result: false })).state).toBe('SIN_INTERPRETAR');
    expect(cellOf(ev('c', 'A', '2026-09-05', { result: 'VACÍA' })).unconfirmed).toBe(false);
  });
});

describe('animalCampaignCells', () => {
  const campaigns = [camp('c1', '2026-09-01', '2026-09-15'), camp('c2', '2026-11-01', '2026-11-15')];

  it('gives each animal one cell per campaign, null where it was not palpated, and lists each animal once', () => {
    const events = [
      ev('a1', 'A', '2026-09-05', { result: 'VACÍA' }),
      ev('a2', 'A', '2026-11-05', { result: 'PREÑADA', gestation_days: 60 }),
      ev('b1', 'B', '2026-11-06', { result: 'VACÍA' }),
      ev('c1', 'C', '2026-09-06', { result: 'PREÑADA', gestation_days: 90 }),
      ev('out', 'D', '2026-10-10', { result: 'VACÍA' }), // between the campaigns
    ];
    const cells = animalCampaignCells(events, campaigns);
    expect([...cells.keys()]).toEqual(['A', 'C', 'B']);
    expect(cells.get('A')?.map(c => c?.state ?? null)).toEqual(['VACÍA', 'PREÑADA']);
    expect(cells.get('B')?.map(c => c?.state ?? null)).toEqual([null, 'VACÍA']);
    expect(cells.get('C')?.map(c => c?.state ?? null)).toEqual(['PREÑADA', null]);
    expect(cells.has('D')).toBe(false);
  });

  it('is the same for any order of the rows', () => {
    const events = [ev('a1', 'A', '2026-09-05'), ev('b1', 'B', '2026-11-06'), ev('a2', 'A', '2026-11-05', { result: 'PREÑADA', gestation_days: 30 })];
    const f = animalCampaignCells(events, campaigns);
    const r = animalCampaignCells([...events].reverse(), campaigns);
    const summary = (m: typeof f) => [...m.entries()].map(([id, cs]) => [id, cs.map(c => c?.event.health_log_id ?? null)]).sort();
    expect(summary(r)).toEqual(summary(f));
  });
});
