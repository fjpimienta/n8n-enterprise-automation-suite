import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import {
  COMPARE_CATEGORIES,
  CampaignEventRow,
  campaignEventRows,
  categoryOfState,
  filterEventsByCampaign,
  neverPregnant,
  sortCampaignEventRows,
  transitions,
} from './palpation-campaign-compare';
import { CATEGORY_LABEL, COMPARE_NOTE, campaignErrorText, formatRange, neverPregnantLabel, uninterpretedLabel } from './palpation-campaign-view';
import { Campaign } from './palpation-campaigns';

const camp = (id: string, from: string, to: string, label = id): Campaign => ({ id, label, from, to });
const ev = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  eventRow({ health_log_id: id, livestock_id: animal, event_date: day, result: 'VACÍA', ...over });
const preg = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  ev(id, animal, day, { result: 'PREÑADA', gestation_days: 90, ...over });

const A = camp('A', '2026-09-01', '2026-09-15', 'Septiembre');
const B = camp('B', '2026-11-01', '2026-11-15', 'Noviembre');

describe('transitions (A to B)', () => {
  const events = [
    preg('p1a', 'P1', '2026-09-05'), preg('p1b', 'P1', '2026-11-05'),
    preg('p2a', 'P2', '2026-09-05'), ev('p2b', 'P2', '2026-11-05'),
    ev('v1a', 'V1', '2026-09-05'), preg('v1b', 'V1', '2026-11-05'),
    ev('v2a', 'V2', '2026-09-05'), ev('v2b', 'V2', '2026-11-05'),
    ev('v3a', 'V3', '2026-09-05'),
    ev('n1b', 'N1', '2026-11-05'),
    ev('r1a', 'R1', '2026-09-05', { ranch_term: 'RP', is_clinical_result: false }), preg('r1b', 'R1', '2026-11-05'),
    ev('s1a', 'S1', '2026-09-05', { result: null, is_clinical_result: false }), ev('s1b', 'S1', '2026-11-05', { result: null, uninterpreted: true, is_clinical_result: false }),
    ev('u1a', 'U1', '2026-09-05', { mapping_status: 'UNMAPPED', raw_code: 'DF15' }), ev('u1b', 'U1', '2026-11-05'),
    ev('out', 'X', '2026-10-10'), // between the campaigns: not in the universe
  ];
  const t = transitions(events, A, B);

  it('counts the animals with at least one counted event in A or B as the universe', () => {
    expect(t.universe).toBe(9);
    expect(t.identityHolds).toBe(true);
  });

  it('counts the denominators of each row (state in A) and each column (state in B), both adding up to the universe', () => {
    expect(t.rowTotals).toEqual({ 'PREÑADA': 2, 'VACÍA': 4, RANCHO: 1, SIN_INTERPRETAR: 1, NO_PALPADA: 1 });
    expect(t.colTotals).toEqual({ 'PREÑADA': 3, 'VACÍA': 4, RANCHO: 0, SIN_INTERPRETAR: 1, NO_PALPADA: 1 });
    expect(Object.values(t.rowTotals).reduce((a, b) => a + b, 0)).toBe(t.universe);
    expect(Object.values(t.colTotals).reduce((a, b) => a + b, 0)).toBe(t.universe);
  });

  it('puts each animal in the cell of its state in A and its state in B', () => {
    expect(t.matrix['PREÑADA']['PREÑADA']).toBe(1);
    expect(t.matrix['PREÑADA']['VACÍA']).toBe(1);
    expect(t.matrix['VACÍA']['PREÑADA']).toBe(1);
    expect(t.matrix['VACÍA']['VACÍA']).toBe(2); // V2 and U1
    expect(t.matrix['VACÍA']['NO_PALPADA']).toBe(1); // V3
    expect(t.matrix['NO_PALPADA']['VACÍA']).toBe(1); // N1
    expect(t.matrix['RANCHO']['PREÑADA']).toBe(1);
    expect(t.matrix['SIN_INTERPRETAR']['SIN_INTERPRETAR']).toBe(1); // no result, then an unrecognised value
    expect(t.matrix['NO_PALPADA']['NO_PALPADA']).toBe(0);
  });

  it('keeps an unconfirmed code with result VACÍA in Vacía, like the KPI cards, and only flags it', () => {
    expect(t.matrix['VACÍA']['VACÍA']).toBeGreaterThanOrEqual(1);
    expect(t.unconfirmedFrom).toBe(1);
    expect(t.unconfirmedTo).toBe(0);
  });

  it('an unconfirmed code that carries PREÑADA stays Preñada (animalState decides) and is flagged', () => {
    const odd = [
      preg('o1', 'O', '2026-09-05', { mapping_status: 'UNMAPPED', raw_code: 'XY9' }),
      ev('o2', 'O', '2026-11-05'),
    ];
    const r = transitions(odd, A, B);
    expect(r.matrix['PREÑADA']['VACÍA']).toBe(1);
    expect(r.matrix['VACÍA']['VACÍA']).toBe(0);
    expect(r.unconfirmedFrom).toBe(1);
  });

  it('does not depend on the order of the rows', () => {
    expect(transitions([...events].reverse(), A, B)).toEqual(t);
  });

  it('is empty and consistent when neither campaign has events, and every row of the matrix is a known category', () => {
    const empty = transitions([], A, B);
    expect(empty.universe).toBe(0);
    expect(empty.identityHolds).toBe(true);
    expect(Object.keys(t.matrix)).toEqual([...COMPARE_CATEGORIES]);
  });

  it('maps every state to a category: no result and unrecognised values both go to "Sin interpretar"', () => {
    expect(categoryOfState('PREÑADA')).toBe('PREÑADA');
    expect(categoryOfState('VACÍA')).toBe('VACÍA');
    expect(categoryOfState('TERMINO_RANCHO')).toBe('RANCHO');
    expect(categoryOfState('SIN_RESULTADO')).toBe('SIN_INTERPRETAR');
    expect(categoryOfState('SIN_INTERPRETAR')).toBe('SIN_INTERPRETAR');
  });
});

describe('neverPregnant ("Sin indicios de preñez en ninguna campaña")', () => {
  const c1 = camp('c1', '2026-01-01', '2026-01-10', 'Enero');
  const c2 = camp('c2', '2026-04-01', '2026-04-10', 'Abril');
  const c3 = camp('c3', '2026-08-01', '2026-08-10', 'Agosto');
  const campaigns = [c1, c2, c3];
  const herd = ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10'].map((id, i) =>
    herdRow({ livestock_id: id, rfid_siniiga: `99990000${String(i).padStart(2, '0')}`, category: 'VACA', current_status: 'ACTIVO' }));
  const events = [
    ev('a1', 'A1', '2026-01-05'),                                                    // empty, only in c1
    ev('a2c1', 'A2', '2026-01-05'), ev('a2c2', 'A2', '2026-04-05'),                  // empty in 2
    ev('a3c1', 'A3', '2026-01-05'), preg('a3c2', 'A3', '2026-04-05'),                 // pregnant once: out
    ev('a4c1', 'A4', '2026-01-05'), ev('a4c3', 'A4', '2026-08-05'),                  // empty in c1 and c3, not palpated in c2
    ev('a5c1', 'A5', '2026-01-05'), ev('a5c2', 'A5', '2026-04-05', { ranch_term: 'RP', is_clinical_result: false }), // mixed
    ev('a6', 'A6', '2026-01-05', { ranch_term: 'RP', is_clinical_result: false }),   // ranch term only
    ev('a7', 'A7', '2026-01-05', { mapping_status: 'UNMAPPED', raw_code: 'DF15' }),   // unconfirmed code, result VACÍA
    ev('a8c1', 'A8', '2026-01-05', { result: null, is_clinical_result: false }),
    ev('a8c2', 'A8', '2026-04-05', { result: null, uninterpreted: true, is_clinical_result: false }),
    preg('a9', 'A9', '2026-04-05', { mapping_status: 'UNMAPPED', raw_code: 'XY9' }), // unconfirmed code carrying PREÑADA: Preñada, out
    ev('a10', 'A10', '2026-06-01'),                                                  // outside every campaign
    ev('a1-dup', 'A1', '2026-01-02'),                                                // second event in the same campaign
  ];
  const out = neverPregnant(events, herd, campaigns);
  const ids = (rows: readonly { livestockId: string }[]) => rows.map(r => r.livestockId).sort();

  it('lists the animals with at least one clinical Vacía and no Preñada in any campaign', () => {
    expect(ids(out.main)).toEqual(['A1', 'A2', 'A4', 'A5', 'A7']);
  });

  it('leaves out an animal that is Preñada in some campaign, flagged or not, and one that is in none of the campaigns', () => {
    const all = [...out.main, ...out.uninterpreted].map(r => r.livestockId);
    expect(all).not.toContain('A3');
    expect(all).not.toContain('A9');
    expect(all).not.toContain('A10');
  });

  it('puts ranch terms, no result and unrecognised values in a separate group, never counted as vacía', () => {
    expect(ids(out.uninterpreted)).toEqual(['A6', 'A8']);
    expect(out.uninterpreted.every(r => r.emptyIn === 0)).toBe(true);
    expect(ids(out.main)).not.toContain('A6');
    expect(ids(out.main)).not.toContain('A8');
  });

  it('an animal that is Vacía in one campaign and has a ranch term in another stays in the main list, vacía only once', () => {
    const a5 = out.main.find(r => r.livestockId === 'A5');
    expect(a5?.emptyIn).toBe(1);
    expect(a5?.appearsIn).toBe(2);
    expect(neverPregnantLabel(a5 as NonNullable<typeof a5>)).toBe('Vacía en 1 campaña');
  });

  it('uses "Vacía en la única campaña" when the animal appears in only one campaign, and "Vacía en N campañas" otherwise', () => {
    const label = (id: string) => neverPregnantLabel(out.main.find(r => r.livestockId === id) as NonNullable<(typeof out.main)[number]>);
    expect(label('A1')).toBe('Vacía en la única campaña');
    expect(label('A7')).toBe('Vacía en la única campaña');
    expect(label('A2')).toBe('Vacía en 2 campañas');
    expect(label('A4')).toBe('Vacía en 2 campañas'); // c1 and c3; it was not palpated in c2
    expect(neverPregnantLabel({ appearsIn: 3, emptyIn: 3 })).toBe('Vacía en 3 campañas');
  });

  it('flags the animals with an unconfirmed code, counts them as vacía and does not interpret the code', () => {
    const a7 = out.main.find(r => r.livestockId === 'A7');
    expect(a7?.withUnconfirmed).toBe(true);
    expect(a7?.emptyIn).toBe(1);
    expect(out.main.filter(r => r.withUnconfirmed).map(r => r.livestockId)).toEqual(['A7']);
    expect(a7?.cells[0]?.event.raw_code).toBe('DF15');
  });

  it('lists each animal once, with one cell per campaign, and orders the list in a stable way (more campaigns first, then identifier)', () => {
    expect(new Set(out.main.map(r => r.livestockId)).size).toBe(out.main.length);
    expect(out.main.every(r => r.cells.length === 3)).toBe(true);
    expect(out.main.map(r => r.livestockId)).toEqual(['A2', 'A4', 'A1', 'A5', 'A7']);
    expect(neverPregnant([...events].reverse(), herd, campaigns)).toEqual(out);
    expect(out.main.find(r => r.livestockId === 'A1')?.lastDate).toBe('2026-01-05');
  });

  it('shows the neutral wording of the uninterpreted group and the visible note', () => {
    expect(uninterpretedLabel({ appearsIn: 1 })).toBe('Sin interpretar en la única campaña');
    expect(uninterpretedLabel({ appearsIn: 2 })).toBe('Sin interpretar en 2 campañas');
    expect(COMPARE_NOTE).toBe('Compara resultados de palpación; no explica causas.');
  });

  it('falls back to a short identifier for an animal that is not in the herd rows', () => {
    const r = neverPregnant([ev('z', 'ZZZZZZZZ-0000', '2026-01-05')], [], campaigns);
    expect(r.main[0]?.identifier).toBe('Sin identificador · ZZZZZZZZ');
  });
});

describe('campaignEventRows (full list)', () => {
  const campaigns = [camp('c1', '2026-09-01', '2026-09-15', 'Septiembre'), camp('c2', '2026-11-01', '2026-11-15', 'Noviembre')];
  const herd = [herdRow({ livestock_id: 'A', rfid_siniiga: '9999000001', category: 'VACA', current_status: 'ACTIVO' })];
  const events = [
    ev('e1', 'A', '2026-09-03', { technician: 'Técnico demo 1' }),
    preg('e2', 'A', '2026-11-04', { technician: 'Técnico demo 2' }),
    ev('nr', 'A', '2026-11-05', { ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false }),
    ev('u', 'B', '2026-09-04', { mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
    ev('out', 'A', '2026-10-10'),
    ev('e1', 'A', '2026-09-03'), // the same event key twice
  ];
  const rows = campaignEventRows(events, herd, campaigns);

  it('has one row per event inside a campaign, each event once, and leaves out the events outside every campaign', () => {
    expect(rows.map(r => r.id).sort()).toEqual(['e1', 'e2', 'nr', 'u']);
    expect(new Set(rows.map(r => r.id)).size).toBe(rows.length);
  });

  it('assigns each event to its campaign and carries the identifier of the animal', () => {
    expect(rows.find(r => r.id === 'e1')).toMatchObject({ campaignId: 'c1', campaignLabel: 'Septiembre', campaignOrder: 0, identifier: '9999000001', category: 'VACA' });
    expect(rows.find(r => r.id === 'e2')).toMatchObject({ campaignId: 'c2', state: 'PREÑADA', gestation: { months: 3, days: 90 } });
  });

  it('lists an NR as an event that does not count as a palpation, and an unconfirmed code as typed with its flag', () => {
    expect(rows.find(r => r.id === 'nr')).toMatchObject({ counts: false, ranchTerm: 'NR', state: 'TERMINO_RANCHO' });
    expect(rows.find(r => r.id === 'u')).toMatchObject({ unconfirmed: true, unconfirmedCode: 'DF15', state: 'VACÍA', identifier: 'Sin identificador · B' });
  });

  it('has no technician anywhere in a row', () => {
    for (const r of rows) {
      expect(Object.keys(r)).not.toContain('technician');
      expect(JSON.stringify(r)).not.toContain('Técnico demo');
    }
  });

  it('lists an event once even if two campaigns were to overlap (the first one wins)', () => {
    const overlapping = [camp('a', '2026-09-01', '2026-09-20'), camp('b', '2026-09-10', '2026-09-30')];
    const r = campaignEventRows([ev('x', 'A', '2026-09-12')], herd, overlapping);
    expect(r.length).toBe(1);
    expect(r[0]?.campaignId).toBe('a');
  });

  describe('sorting and filtering', () => {
    const mk = (id: string, order: number, date: string, over: Partial<CampaignEventRow> = {}): CampaignEventRow => ({
      id, livestockId: id, identifier: id, category: 'VACA', currentStatus: 'ACTIVO', campaignId: `c${order}`, campaignLabel: `C${order}`, campaignOrder: order,
      date, state: 'VACÍA', subtype: 'SIN_SUBTIPO', ranchTerm: null, gestation: null, unconfirmedCode: null, unconfirmed: false, historical: false,
      uninterpreted: false, counts: true, ...over,
    });
    const list = [mk('a', 1, '2026-11-02'), mk('b', 0, '2026-09-02'), mk('c', 1, '2026-11-09'), mk('d', 0, '2026-09-09')];

    it('by campaign: campaign ascending, and the newest date first inside each campaign, in both directions', () => {
      expect(sortCampaignEventRows(list, 'campaign', 'asc').map(r => r.id)).toEqual(['d', 'b', 'c', 'a']);
      expect(sortCampaignEventRows(list, 'campaign', 'desc').map(r => r.id)).toEqual(['c', 'a', 'd', 'b']);
    });

    it('by date, by identifier and by state, with the event key as the last tie-break', () => {
      expect(sortCampaignEventRows(list, 'date', 'asc').map(r => r.id)).toEqual(['b', 'd', 'a', 'c']);
      expect(sortCampaignEventRows(list, 'date', 'desc').map(r => r.id)).toEqual(['c', 'a', 'd', 'b']);
      expect(sortCampaignEventRows(list, 'identifier', 'desc').map(r => r.id)).toEqual(['d', 'c', 'b', 'a']);
      const states = [mk('p', 0, '2026-09-01', { state: 'PREÑADA' }), mk('v', 0, '2026-09-01', { state: 'VACÍA' }), mk('r', 0, '2026-09-01', { state: 'TERMINO_RANCHO' })];
      expect(sortCampaignEventRows(states, 'state', 'asc').map(r => r.id)).toEqual(['p', 'v', 'r']);
    });

    it('puts a missing gestation last, whatever the direction', () => {
      const g = [mk('n', 0, '2026-09-01'), mk('g1', 0, '2026-09-02', { gestation: { months: 3, days: 90 } }), mk('g2', 0, '2026-09-03', { gestation: { months: 6, days: 180 } })];
      expect(sortCampaignEventRows(g, 'gestation', 'asc').map(r => r.id)).toEqual(['g1', 'g2', 'n']);
      expect(sortCampaignEventRows(g, 'gestation', 'desc').map(r => r.id)).toEqual(['g2', 'g1', 'n']);
    });

    it('does not change the rows it receives', () => {
      const copy = [...list];
      sortCampaignEventRows(list, 'date', 'desc');
      expect(list).toEqual(copy);
    });

    it('filters by campaign, or keeps all of them', () => {
      expect(filterEventsByCampaign(list, 'c1').map(r => r.id).sort()).toEqual(['a', 'c']);
      expect(filterEventsByCampaign(list, 'TODAS').length).toBe(4);
      expect(filterEventsByCampaign(list, 'nope')).toEqual([]);
    });
  });
});

describe('texts of the campaign views', () => {
  it('names the categories and writes a range in Spanish', () => {
    expect(CATEGORY_LABEL['NO_PALPADA']).toBe('Sin registro en esa campaña');
    expect(CATEGORY_LABEL['RANCHO']).toBe('Definido por el rancho');
    expect(formatRange({ from: '2026-09-01', to: '2026-09-15' })).toBe('01/09/2026 a 15/09/2026');
  });

  it('writes a Spanish message for every validation error, naming the other campaign for an overlap', () => {
    const codes = ['too-few', 'too-many', 'label-empty', 'label-long', 'label-duplicate', 'from-invalid', 'to-invalid', 'range-order', 'overlap'] as const;
    for (const code of codes) expect(campaignErrorText({ id: 'x', code, other: 'Otra' }).length).toBeGreaterThan(10);
    expect(campaignErrorText({ id: 'x', code: 'overlap', other: 'Primera' })).toContain('Primera');
    expect(campaignErrorText({ id: null, code: 'too-few', other: null })).toContain('2 campañas');
  });

  it('never states a diagnosis: no text of the views mentions infertility or a cause', () => {
    const all = [COMPARE_NOTE, ...Object.values(CATEGORY_LABEL), neverPregnantLabel({ appearsIn: 1, emptyIn: 1 }), neverPregnantLabel({ appearsIn: 4, emptyIn: 3 }), uninterpretedLabel({ appearsIn: 2 })].join(' ');
    expect(all.toLowerCase()).not.toMatch(/infertil|diagn[oó]stic|estéril|problema/);
  });
});
