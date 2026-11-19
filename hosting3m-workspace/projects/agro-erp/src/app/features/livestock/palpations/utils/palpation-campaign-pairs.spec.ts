import { describe, expect, it } from 'vitest';
import { GOLDEN, GOLDEN_A, GOLDEN_B, goldenData } from '../testing/palpation-golden.fixtures';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import { transitions } from './palpation-campaign-compare';
import { pairLists } from './palpation-campaign-pairs';
import { Campaign } from './palpation-campaigns';

const camp = (id: string, from: string, to: string): Campaign => ({ id, label: id, from, to });

describe('golden dataset: the proportions validated by the ranch', () => {
  const { events, herd } = goldenData();

  it('reproduces the transition table exactly: 31 / 19 / 25 / 27 / 7 / 11, with 120 animals palpated in A', () => {
    const t = transitions(events, GOLDEN_A, GOLDEN_B);
    expect(t.matrix['VACÍA']['VACÍA']).toBe(GOLDEN.vaciaVacia);
    expect(t.matrix['VACÍA']['NO_PALPADA']).toBe(GOLDEN.vaciaNoPalpada);
    expect(t.matrix['VACÍA']['PREÑADA']).toBe(GOLDEN.vaciaPrenada);
    expect(t.matrix['PREÑADA']['NO_PALPADA']).toBe(GOLDEN.prenadaNoPalpada);
    expect(t.matrix['PREÑADA']['PREÑADA']).toBe(GOLDEN.prenadaPrenada);
    expect(t.matrix['PREÑADA']['VACÍA']).toBe(GOLDEN.prenadaVacia);
    expect(t.universe - t.rowTotals['NO_PALPADA']).toBe(GOLDEN.palpatedA);
    expect(t.identityHolds).toBe(true);
  });

  it('puts the 31 persistent and the 19 pending animals in two separate groups', () => {
    const { persistent, pending } = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    expect(persistent.length).toBe(GOLDEN.vaciaVacia);
    expect(pending.length).toBe(GOLDEN.vaciaNoPalpada);
    expect(persistent.every(r => r.group === 'PERSISTENT' && r.a.category === 'VACÍA' && r.b.category === 'VACÍA')).toBe(true);
    expect(pending.every(r => r.group === 'PENDING' && r.a.category === 'VACÍA' && r.b.category === 'NO_PALPADA' && r.b.date === null)).toBe(true);
    const ids = [...persistent, ...pending].map(r => r.livestockId);
    expect(new Set(ids).size).toBe(ids.length); // no animal in both groups, none twice
  });

  it('the 25 Vacía→Preñada and the 11 Preñada→Vacía animals are in neither list, and the 27 and 7 Preñada animals neither', () => {
    const { persistent, pending, coverage } = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    expect(persistent.length + pending.length).toBe(GOLDEN.vaciaVacia + GOLDEN.vaciaNoPalpada);
    expect(coverage.vaciaAOtherInB).toBe(GOLDEN.vaciaPrenada);
  });

  it('gives the coverage: palpated in A, in B, in both, only in A, only in B', () => {
    const { coverage } = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    const inBoth = GOLDEN.vaciaVacia + GOLDEN.vaciaPrenada + GOLDEN.prenadaPrenada + GOLDEN.prenadaVacia;
    expect(coverage.palpatedA).toBe(120);
    expect(coverage.palpatedB).toBe(inBoth + GOLDEN.onlyB);
    expect(coverage.both).toBe(inBoth);
    expect(coverage.onlyA).toBe(GOLDEN.vaciaNoPalpada + GOLDEN.prenadaNoPalpada);
    expect(coverage.onlyB).toBe(GOLDEN.onlyB);
    expect(coverage.palpatedA).toBe(coverage.both + coverage.onlyA);
    expect(coverage.palpatedB).toBe(coverage.both + coverage.onlyB);
  });

  it('gives the categories of each campaign, adding up to the animals palpated', () => {
    const { coverage } = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    expect(coverage.categoriesA).toEqual({ 'PREÑADA': 45, 'VACÍA': 75, RANCHO: 0, SIN_INTERPRETAR: 0 });
    // B: 7 + 25 + 2 Preñada, 31 + 11 + 3 Vacía, and the RP and MATRIZ OCUPADA animals are ranch terms (neither Vacía nor Preñada)
    expect(coverage.categoriesB).toEqual({ 'PREÑADA': 34, 'VACÍA': 45, RANCHO: 2, SIN_INTERPRETAR: 0 });
    expect(Object.values(coverage.categoriesA).reduce((x, y) => x + y, 0)).toBe(coverage.palpatedA);
    expect(Object.values(coverage.categoriesB).reduce((x, y) => x + y, 0)).toBe(coverage.palpatedB);
  });

  it('counts the animals with a ranch term apart (neither Vacía nor Preñada) and the NR animals apart (not palpated)', () => {
    const { coverage } = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    expect(coverage.ranchoEither).toBe(2);
    expect(coverage.nrA).toBe(GOLDEN.nrA);
    expect(coverage.nrB).toBe(GOLDEN.nrB);
    // an NR inside B does not make the animal palpated: it stays in the pending group
    const nrAnimal = events.find(e => e.health_log_id.startsWith('nr-'))?.livestock_id;
    expect(pairLists(events, herd, GOLDEN_A, GOLDEN_B).pending.some(r => r.livestockId === nrAnimal)).toBe(true);
  });

  it('is the same for any order of the rows and does not touch what it receives', () => {
    const copy = [...events];
    const forward = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
    expect(events).toEqual(copy);
    expect(pairLists([...events].reverse(), [...herd].reverse(), GOLDEN_A, GOLDEN_B)).toEqual(forward);
  });

  it('keeps a campaign of two dates as one campaign: the latest event of the animal inside the range wins', () => {
    const e = [
      eventRow({ health_log_id: 'a', livestock_id: 'X', event_date: '2026-08-03', result: 'VACÍA' }),
      eventRow({ health_log_id: 'b1', livestock_id: 'X', event_date: '2026-11-11', result: 'VACÍA' }),
      eventRow({ health_log_id: 'b2', livestock_id: 'X', event_date: '2026-11-12', result: 'PREÑADA', gestation_days: 30 }),
    ];
    const out = pairLists(e, [], GOLDEN_A, GOLDEN_B);
    expect(out.persistent.length).toBe(0); // the later event is Preñada
    expect(out.coverage.vaciaAOtherInB).toBe(1);
    const reversed = [e[0], e[1], eventRow({ health_log_id: 'b2', livestock_id: 'X', event_date: '2026-11-12', result: 'VACÍA' })].map(x => x as typeof e[0]);
    expect(pairLists(reversed, [], GOLDEN_A, GOLDEN_B).persistent.length).toBe(1);
  });
});

describe('pairLists: what each row carries', () => {
  const { events, herd } = goldenData();
  const lists = pairLists(events, herd, GOLDEN_A, GOLDEN_B);
  const rows = [...lists.persistent, ...lists.pending];

  it('shows UNE in August and ESTATICA in November as the same condition (ESTATICA), each with its raw code as typed', () => {
    const une = rows.find(r => r.a.rawCode === 'UNE' && r.b.rawCode === 'ESTATICA');
    expect(une?.a.condition).toBe('ESTATICA');
    expect(une?.b.condition).toBe('ESTATICA');
    expect(une?.a.unconfirmed).toBe(false);
    expect(une?.a.category).toBe('VACÍA');
  });

  it('flags the unconfirmed codes (DF15, YF15, DCL1, YCL1) as Vacía with the code as typed, never converted', () => {
    const flagged = rows.filter(r => r.a.unconfirmed || r.b.unconfirmed);
    expect(flagged.length).toBeGreaterThan(0);
    const codes = new Set(flagged.flatMap(r => [r.a, r.b]).filter(c => c.unconfirmed).map(c => c.rawCode));
    expect([...codes].sort()).toEqual(['DCL1', 'DF15', 'YCL1', 'YF15']);
    expect(flagged.every(r => [r.a, r.b].filter(c => c.unconfirmed).every(c => c.category === 'VACÍA' && c.condition === null))).toBe(true);
    expect(flagged.some(r => r.a.rawCode?.startsWith('Y'))).toBe(true); // Y is not turned into D
  });

  it('carries the SINIIGA, the fuego, the brand, the category and the current status, and the date of each campaign', () => {
    const withSiniiga = rows.find(r => r.siniiga !== null);
    expect(withSiniiga?.siniiga).toMatch(/^9999\d{6}$/);
    const noSiniiga = rows.find(r => r.siniiga === null);
    expect(noSiniiga?.brand).toBe('ZZ1');
    expect(noSiniiga?.fuego).toMatch(/^[FQ]\d{3}$/);
    expect(rows.every(r => r.category !== null && r.currentStatus !== null)).toBe(true);
    expect(rows.every(r => r.a.date === '2026-08-03')).toBe(true);
    expect(new Set(lists.persistent.map(r => r.b.date))).toEqual(new Set(['2026-11-11', '2026-11-12']));
  });

  it('does not count a placeholder such as S/N-00001 as a SINIIGA', () => {
    const e = [eventRow({ health_log_id: 'p', livestock_id: 'P', event_date: '2026-08-03', result: 'VACÍA' })];
    const h = [herdRow({ livestock_id: 'P', rfid_siniiga: 'S/N-00001', numero_fuego: '77', brand_code: 'ZZ1' })];
    const out = pairLists(e, h, GOLDEN_A, GOLDEN_B);
    expect(out.pending[0]?.siniiga).toBeNull();
    expect(out.pending[0]?.fuego).toBe('77');
  });

  it('has no technician anywhere in a row', () => {
    const withTechnician = events.map(e => ({ ...e, technician: 'Técnico demo 1' }));
    const out = pairLists(withTechnician, herd, GOLDEN_A, GOLDEN_B);
    expect(JSON.stringify(out)).not.toContain('Técnico');
    expect(Object.keys(out.persistent[0] ?? {})).not.toContain('technician');
  });

  it('orders each group by identifier, the same way for the same data', () => {
    const ids = lists.persistent.map(r => r.siniiga ?? `${r.brand} ${r.fuego}`);
    const sorted = [...ids].sort((x, y) => x.localeCompare(y, 'es', { numeric: true }));
    expect(ids).toEqual(sorted);
  });

  it('an animal with a ranch term in B is in neither group and is counted as rancho; an animal with no result in B is not Vacía either', () => {
    const e = [
      eventRow({ health_log_id: 'a1', livestock_id: 'R', event_date: '2026-08-03', result: 'VACÍA' }),
      eventRow({ health_log_id: 'b1', livestock_id: 'R', event_date: '2026-11-11', result: 'VACÍA', ranch_term: 'NO APTO', is_clinical_result: false }),
      eventRow({ health_log_id: 'a2', livestock_id: 'S', event_date: '2026-08-03', result: 'VACÍA' }),
      eventRow({ health_log_id: 'b2', livestock_id: 'S', event_date: '2026-11-11', result: null, is_clinical_result: false }),
    ];
    const out = pairLists(e, [], GOLDEN_A, GOLDEN_B);
    expect(out.persistent.length + out.pending.length).toBe(0);
    expect(out.coverage.ranchoEither).toBe(1);
    expect(out.coverage.categoriesB.RANCHO).toBe(1);
    expect(out.coverage.categoriesB.SIN_INTERPRETAR).toBe(1);
    expect(out.coverage.vaciaAOtherInB).toBe(2);
  });

  it('is empty and consistent without events', () => {
    const out = pairLists([], [], GOLDEN_A, GOLDEN_B);
    expect(out.persistent).toEqual([]);
    expect(out.pending).toEqual([]);
    expect(out.coverage.palpatedA).toBe(0);
    expect(out.coverage.both + out.coverage.onlyA).toBe(0);
  });

  it('works with campaigns that are ranges on both sides and with A later than B (the order is the caller\'s choice)', () => {
    const e = [
      eventRow({ health_log_id: 'x1', livestock_id: 'Z', event_date: '2026-11-11', result: 'VACÍA' }),
      eventRow({ health_log_id: 'x2', livestock_id: 'Z', event_date: '2026-11-20', result: 'VACÍA' }),
    ];
    const out = pairLists(e, [], camp('a', '2026-11-01', '2026-11-15'), camp('b', '2026-11-16', '2026-11-30'));
    expect(out.persistent.map(r => r.livestockId)).toEqual(['Z']);
    expect(out.persistent[0]?.a.date).toBe('2026-11-11');
    expect(out.persistent[0]?.b.date).toBe('2026-11-20');
  });
});
