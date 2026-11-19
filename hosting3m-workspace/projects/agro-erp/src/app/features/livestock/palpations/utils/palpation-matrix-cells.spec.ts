import { describe, expect, it } from 'vitest';
import { COMPARE_CATEGORIES, CompareCategory, transitions } from './palpation-campaign-compare';
import { GOLDEN_A, GOLDEN_B, GOLDEN_MATRIX_ONLY_B, goldenData } from '../testing/palpation-golden.fixtures';
import { cellAnimals } from './palpation-campaign-pairs';
import {
  CATEGORY_SLUG,
  DEEP_LINK_PARAM,
  ParamReader,
  buildDeepLink,
  cellIdOf,
  cellLabel,
  isImpossibleCell,
  parseCellId,
  parseDeepLink,
  rangeParam,
} from './palpation-matrix-cells';

/** A query string as the router reads it: all the values of each name. */
function params(query: string): ParamReader {
  const search = new URLSearchParams(query);
  return { getAll: name => search.getAll(name) };
}
const A = '2026-08-03_2026-08-03';
const B = '2026-11-11_2026-11-12';

describe('cell identifiers', () => {
  const all = COMPARE_CATEGORIES.flatMap(from => COMPARE_CATEGORIES.map(to => ({ from, to })));

  it('writes a cell as two ASCII slugs joined by a dot and reads it back, for every possible cell', () => {
    const valid = all.filter(c => !isImpossibleCell(c));
    expect(valid.length).toBe(24);
    for (const cell of valid) {
      const id = cellIdOf(cell);
      expect(id).toMatch(/^[a-z-]+\.[a-z-]+$/);
      expect(parseCellId(id)).toEqual(cell);
    }
    expect(new Set(valid.map(cellIdOf)).size).toBe(24);
  });

  it('names the cells of the owner: "sin registro en A y preñada en B" is sin-registro.prenada', () => {
    expect(cellIdOf({ from: 'NO_PALPADA', to: 'PREÑADA' })).toBe('sin-registro.prenada');
    expect(cellIdOf({ from: 'NO_PALPADA', to: 'VACÍA' })).toBe('sin-registro.vacia');
    expect(cellIdOf({ from: 'VACÍA', to: 'NO_PALPADA' })).toBe('vacia.sin-registro');
    expect(Object.values(CATEGORY_SLUG).every(s => /^[a-z-]+$/.test(s))).toBe(true);
  });

  it('rejects anything that is not a known cell, and the cell that can never hold an animal', () => {
    const bad: unknown[] = [
      '', 'x', 'vacia', 'vacia.', '.vacia', 'vacia.vacia.vacia', 'VACIA.vacia', 'Vacia.vacia', 'vacía.vacia', 'vacia.vacia ', ' vacia.vacia',
      'vacia,vacia', 'vacia>vacia', 'sin-registro.sin-registro', 'prenada.unknown', '__proto__.vacia', 'constructor.vacia', 'vacia.__proto__',
      'a'.repeat(200), null, undefined, 3, {}, ['vacia.vacia'], '%76acia.vacia', 'vacia.vacia\n',
    ];
    for (const value of bad) expect(parseCellId(value)).toBeNull();
    expect(isImpossibleCell({ from: 'NO_PALPADA', to: 'NO_PALPADA' })).toBe(true);
  });

  it('labels a cell with the names of the campaigns', () => {
    expect(cellLabel({ from: 'NO_PALPADA', to: 'PREÑADA' })).toBe('Sin registro en A y Preñada en B');
    expect(cellLabel({ from: 'VACÍA', to: 'VACÍA' }, 'Agosto', 'Noviembre')).toBe('Vacía en Agosto y Vacía en Noviembre');
  });
});

describe('deep link: building', () => {
  const a = { from: '2026-08-03', to: '2026-08-03' };
  const b = { from: '2026-11-11', to: '2026-11-12' };
  const cell = { from: 'NO_PALPADA', to: 'PREÑADA' } as const;

  it('writes only the two date ranges and the cell id', () => {
    const link = buildDeepLink('https://app.example.test/ganaderia/palpaciones', a, b, cell);
    expect(link).toBe('https://app.example.test/ganaderia/palpaciones?a=2026-08-03_2026-08-03&b=2026-11-11_2026-11-12&cell=sin-registro.prenada');
    const url = new URL(link);
    expect([...url.searchParams.keys()]).toEqual(['a', 'b', 'cell']);
    expect(url.hash).toBe('');
  });

  it('holds no animal data, no company and no result: the only values are dates and a slug', () => {
    const link = buildDeepLink('https://app.example.test/x', a, b, { from: 'VACÍA', to: 'VACÍA' });
    const values = [...new URL(link).searchParams.values()];
    for (const v of values) expect(v).toMatch(/^[0-9a-z._-]+$/);
    expect(link).not.toMatch(/tenant|company|empresa|livestock|siniiga|token/i);
  });

  it('is read back to the same campaigns and cell', () => {
    const link = new URL(buildDeepLink('https://app.example.test/x', a, b, cell));
    expect(parseDeepLink({ getAll: n => link.searchParams.getAll(n) })).toEqual({ a, b, cell });
  });

  it('writes a range as FROM_TO', () => {
    expect(rangeParam(b)).toBe(B);
    expect(DEEP_LINK_PARAM).toEqual({ a: 'a', b: 'b', cell: 'cell' });
  });
});

describe('deep link: reading is strict and fails closed', () => {
  it('gives no link when none of our parameters is present, whatever else the URL has', () => {
    expect(parseDeepLink(params(''))).toBeNull();
    expect(parseDeepLink(params('foo=1&utm_source=x'))).toBeNull();
  });

  it('accepts two valid ranges, with or without a cell, and ignores parameters that are not ours', () => {
    const withCell = parseDeepLink(params(`a=${A}&b=${B}&cell=vacia.vacia&utm_source=x`));
    expect(withCell?.cell).toEqual({ from: 'VACÍA', to: 'VACÍA' });
    expect(withCell?.a).toEqual({ from: '2026-08-03', to: '2026-08-03' });
    expect(withCell?.b).toEqual({ from: '2026-11-11', to: '2026-11-12' });
    expect(parseDeepLink(params(`a=${A}&b=${B}`))).toEqual({ a: { from: '2026-08-03', to: '2026-08-03' }, b: { from: '2026-11-11', to: '2026-11-12' }, cell: null });
  });

  it.each([
    ['a missing', `b=${B}&cell=vacia.vacia`],
    ['b missing', `a=${A}&cell=vacia.vacia`],
    ['only a cell', 'cell=vacia.vacia'],
    ['a empty', `a=&b=${B}`],
    ['a repeated', `a=${A}&a=${A}&b=${B}`],
    ['b repeated', `a=${A}&b=${B}&b=${B}`],
    ['cell repeated', `a=${A}&b=${B}&cell=vacia.vacia&cell=vacia.vacia`],
    ['an impossible month', `a=2026-13-01_2026-13-02&b=${B}`],
    ['an impossible day', `a=2026-02-30_2026-02-30&b=${B}`],
    ['a reversed range', `a=2026-08-05_2026-08-03&b=${B}`],
    ['a range with one date', `a=2026-08-03&b=${B}`],
    ['a range with a time', `a=2026-08-03T00:00:00_2026-08-03&b=${B}`],
    ['a range with extra text', `a=${A}x&b=${B}`],
    ['a range with spaces', `a=${encodeURIComponent(' ' + A)}&b=${B}`],
    ['a slash instead of the underscore', `a=2026-08-03/2026-08-03&b=${B}`],
    ['the same range twice (they overlap)', `a=${A}&b=${A}`],
    ['overlapping ranges', 'a=2026-08-01_2026-08-10&b=2026-08-10_2026-08-20'],
    ['a range inside the other', 'a=2026-08-01_2026-12-31&b=2026-11-11_2026-11-12'],
    ['an unknown cell', `a=${A}&b=${B}&cell=vacia.otra`],
    ['an upper-case cell', `a=${A}&b=${B}&cell=VACIA.VACIA`],
    ['the impossible cell', `a=${A}&b=${B}&cell=sin-registro.sin-registro`],
    ['an empty cell value', `a=${A}&b=${B}&cell=`],
    ['markup in a value', `a=${encodeURIComponent('<script>alert(1)</script>')}&b=${B}`],
    ['a path trick', `a=${encodeURIComponent('../../x')}&b=${B}`],
    ['a SQL-looking value', `a=${A}&b=${encodeURIComponent("2026-11-11_2026-11-12' OR 1=1")}`],
    ['a very long value', `a=${'1'.repeat(5000)}&b=${B}`],
    ['a formula-looking cell', `a=${A}&b=${B}&cell=${encodeURIComponent('=1+1.vacia')}`],
  ])('rejects the whole link: %s', (_name, query) => {
    expect(parseDeepLink(params(query))).toBeNull();
  });

  it('never throws, even with a reader that misbehaves', () => {
    expect(parseDeepLink({ getAll: () => [] })).toBeNull();
    expect(parseDeepLink({ getAll: name => (name === 'a' ? [undefined as unknown as string] : []) })).toBeNull();
    expect(parseDeepLink({ getAll: () => [null as unknown as string] })).toBeNull();
  });

  it('does not accept a link that names a company or an animal: such parameters are not read at all', () => {
    const link = parseDeepLink(params(`a=${A}&b=${B}&cell=vacia.vacia&id_company=5&livestock_id=abc&tenant=7`));
    expect(Object.keys(link ?? {})).toEqual(['a', 'b', 'cell']);
    expect(JSON.stringify(link)).not.toMatch(/company|livestock|tenant|abc/);
  });
});

describe('cellAnimals: the list behind each cell of the matrix (golden, synthetic)', () => {
  const { events, herd } = goldenData(GOLDEN_MATRIX_ONLY_B);
  const t = transitions(events, GOLDEN_A, GOLDEN_B);
  const list = (from: CompareCategory, to: CompareCategory) => cellAnimals(events, herd, GOLDEN_A, GOLDEN_B, from, to);

  it.each([
    ['Preñada en A y Preñada en B', 'PREÑADA', 'PREÑADA', 7],
    ['Preñada en A y Vacía en B', 'PREÑADA', 'VACÍA', 11],
    ['Vacía en A y Preñada en B', 'VACÍA', 'PREÑADA', 25],
    ['Vacía en A y Vacía en B', 'VACÍA', 'VACÍA', 31],
    ['Preñada en A y sin registro en B', 'PREÑADA', 'NO_PALPADA', 27],
    ['Vacía en A y sin registro en B', 'VACÍA', 'NO_PALPADA', 19],
    ['sin registro en A y Preñada en B', 'NO_PALPADA', 'PREÑADA', 32],
    ['sin registro en A y Vacía en B', 'NO_PALPADA', 'VACÍA', 52],
  ] as [string, CompareCategory, CompareCategory, number][])('%s has %i animals, as many as the matrix counts', (_name, from, to, expected) => {
    expect(list(from, to).length).toBe(expected);
    expect(t.matrix[from][to]).toBe(expected);
  });

  it('has, for ALL 25 cells, a list with exactly as many animals as the matrix counts, and the lists add up to the animals compared', () => {
    let total = 0;
    for (const from of COMPARE_CATEGORIES) {
      for (const to of COMPARE_CATEGORIES) {
        const rows = list(from, to);
        expect(rows.length, `${from} > ${to}`).toBe(t.matrix[from][to]);
        total += rows.length;
      }
    }
    expect(total).toBe(t.universe);
  });

  it('puts every animal in exactly one cell', () => {
    const ids = COMPARE_CATEGORIES.flatMap(from => COMPARE_CATEGORIES.flatMap(to => list(from, to).map(r => r.livestockId)));
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.length).toBe(t.universe);
  });

  it('has a row per animal with the category of each campaign matching the cell, and "sin registro" as an empty campaign cell', () => {
    const rows = list('NO_PALPADA', 'PREÑADA');
    expect(rows.every(r => r.group === 'CELL' && r.a.category === 'NO_PALPADA' && r.a.date === null && r.b.category === 'PREÑADA' && r.b.date !== null)).toBe(true);
    const vv = list('VACÍA', 'VACÍA');
    expect(vv.every(r => r.a.category === 'VACÍA' && r.b.category === 'VACÍA')).toBe(true);
  });

  it('the cell sin registro / sin registro is always empty: an animal in neither campaign is not in the comparison', () => {
    expect(list('NO_PALPADA', 'NO_PALPADA')).toEqual([]);
    expect(t.matrix['NO_PALPADA']['NO_PALPADA']).toBe(0);
  });

  it('carries SINIIGA, fuego, brand, category and status, and the code and the unconfirmed flag of each campaign, like the follow-up lists', () => {
    const rows = list('VACÍA', 'VACÍA');
    expect(rows.some(r => r.a.rawCode === 'UNE' && r.a.condition === 'ESTATICA')).toBe(true);
    expect(rows.some(r => r.a.unconfirmed || r.b.unconfirmed)).toBe(true);
    expect(rows.every(r => r.category !== null && r.currentStatus !== null && r.herdMatched)).toBe(true);
    expect(rows.some(r => r.siniiga === null && r.brand === 'ZZ1' && r.fuego !== null)).toBe(true);
  });

  it('keeps animals whose rows could not be matched to the herd: they stay in the list (the counts come from the events), flagged as not matched', () => {
    const missing = new Set(['golden-001', 'golden-002', 'golden-110']);
    const partialHerd = herd.filter(h => !missing.has(h.livestock_id));
    const rows = cellAnimals(events, partialHerd, GOLDEN_A, GOLDEN_B, 'VACÍA', 'VACÍA');
    expect(rows.length).toBe(31); // unchanged: the list does not depend on the herd rows
    const unmatched = rows.filter(r => !r.herdMatched);
    expect(unmatched.length).toBe(2);
    expect(unmatched.every(r => r.siniiga === null && r.fuego === null && r.brand === null && r.category === null && r.currentStatus === null)).toBe(true);
    const other = cellAnimals(events, partialHerd, GOLDEN_A, GOLDEN_B, 'NO_PALPADA', 'VACÍA');
    expect(other.length).toBe(52);
  });

  it('leaves an animal whose only event in the window is an NR out of every list, and keeps an NR animal of A in its cell', () => {
    const inNrOnly = (id: string) => COMPARE_CATEGORIES.some(from => COMPARE_CATEGORIES.some(to => list(from, to).some(r => r.livestockId === id)));
    const nrOnlyB = events.find(e => e.health_log_id.startsWith('nrb-'))?.livestock_id as string;
    const nrOnlyA = events.find(e => e.health_log_id.startsWith('nra-'))?.livestock_id as string;
    expect(inNrOnly(nrOnlyB)).toBe(false);
    expect(inNrOnly(nrOnlyA)).toBe(false);
    const pendingWithNr = events.find(e => e.health_log_id.startsWith('nr-'))?.livestock_id as string;
    expect(list('VACÍA', 'NO_PALPADA').some(r => r.livestockId === pendingWithNr)).toBe(true); // an NR in B does not make it palpated
  });

  it('is the same for any order of the rows and does not change what it receives', () => {
    const copy = [...events];
    const forward = list('NO_PALPADA', 'VACÍA');
    expect(events).toEqual(copy);
    expect(cellAnimals([...events].reverse(), [...herd].reverse(), GOLDEN_A, GOLDEN_B, 'NO_PALPADA', 'VACÍA')).toEqual(forward);
  });

  it('is ordered by identifier, in a stable way', () => {
    const rows = list('NO_PALPADA', 'VACÍA');
    const ids = rows.map(r => r.siniiga ?? `${r.brand} ${r.fuego}`);
    expect(ids).toEqual([...ids].sort((x, y) => x.localeCompare(y, 'es', { numeric: true })));
  });

  it('is empty without events', () => {
    expect(cellAnimals([], [], GOLDEN_A, GOLDEN_B, 'VACÍA', 'VACÍA')).toEqual([]);
  });
});
