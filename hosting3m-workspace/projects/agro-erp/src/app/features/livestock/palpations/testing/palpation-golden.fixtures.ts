/**
 * SYNTHETIC golden dataset for the campaign comparison. Never copy real herd data here, in a test, a capture or a commit. Every identifier is
 * invented (SINIIGA values start with 9999, which is not a state code) and the company id is fictitious.
 *
 * Campaign A is a single date and campaign B spans two dates (a range), with the proportions the ranch validated by hand:
 *   120 animals palpated in A
 *     31 Vacía in A and Vacía in B           27 Preñada in A and not palpated in B
 *     19 Vacía in A and not palpated in B     7 Preñada in A and Preñada in B
 *     25 Vacía in A and Preñada in B         11 Preñada in A and Vacía in B
 * plus animals that are only in B, ranch terms, NR events and events outside both windows, to exercise the coverage and the window rules.
 */

import { PalpationEventRow, PalpationHerdRow } from '../models/palpation.types';
import { Campaign } from '../utils/palpation-campaigns';
import { eventRow, herdRow } from './palpation.fixtures';

export const GOLDEN_A: Campaign = { id: 'golden-a', label: 'Campaña A', from: '2026-08-03', to: '2026-08-03' };
export const GOLDEN_B: Campaign = { id: 'golden-b', label: 'Campaña B', from: '2026-11-01', to: '2026-11-30' };

export const GOLDEN = {
  vaciaVacia: 31,
  vaciaNoPalpada: 19,
  vaciaPrenada: 25,
  prenadaNoPalpada: 27,
  prenadaPrenada: 7,
  prenadaVacia: 11,
  palpatedA: 120,
  /** Animals palpated only in B: 3 Vacía, 2 Preñada, 1 with RP and 1 with MATRIZ OCUPADA. */
  onlyB: 7,
  /** NR events (not a palpation): one on an animal of the "not palpated in B" group, one on an animal with no other event. */
  nrA: 1,
  nrB: 2,
} as const;

type Over = Parameters<typeof eventRow>[0];

const A_DAY = '2026-08-03';
const B_DAYS = ['2026-11-11', '2026-11-12'] as const;

const vacia = (over: Over = {}): Over => ({ result: 'VACÍA', mapping_status: 'NOT_APPLICABLE', raw_code: null, repro_condition: null, ...over });
const prenada = (days: number): Over => ({ result: 'PREÑADA', gestation_days: days, mapping_status: 'NOT_APPLICABLE' });
/** August records the condition as the code UNE; November records the same condition as ESTATICA. */
const une: Over = vacia({ mapping_status: 'EXPLICIT', raw_code: 'UNE', repro_condition: 'ESTATICA' });
const estatica: Over = vacia({ mapping_status: 'EXPLICIT', raw_code: 'ESTATICA', repro_condition: 'ESTATICA' });
const UNMAPPED_CODES = ['DF15', 'YF15', 'DCL1', 'YCL1'] as const;
const unmapped = (i: number): Over => vacia({ mapping_status: 'UNMAPPED', raw_code: UNMAPPED_CODES[i % UNMAPPED_CODES.length] });

/** How many animals are palpated only in B (no record in A): Vacía and Preñada. The default is the small set of the original golden case. */
export interface GoldenOptions {
  readonly onlyBVacia?: number;
  readonly onlyBPrenada?: number;
}

/**
 * The matrix of the owner's two campaigns also has big "no record in A" cells: 32 animals Preñada in B and 52 Vacía in B. This dataset reproduces
 * them with the same A and B windows, on top of the original golden proportions.
 */
export const GOLDEN_MATRIX_ONLY_B = { onlyBVacia: 52, onlyBPrenada: 32 } as const;

export function goldenData(options: GoldenOptions = {}): { events: PalpationEventRow[]; herd: PalpationHerdRow[] } {
  const onlyBVacia = options.onlyBVacia ?? 3;
  const onlyBPrenada = options.onlyBPrenada ?? 2;
  const events: PalpationEventRow[] = [];
  const herd: PalpationHerdRow[] = [];
  let n = 0;

  const animal = (): string => {
    n += 1;
    const id = `golden-${String(n).padStart(3, '0')}`;
    const withSiniiga = n % 5 !== 0; // every fifth animal has no SINIIGA: brand + fuego instead
    herd.push(herdRow({
      livestock_id: id,
      rfid_siniiga: withSiniiga ? `9999${String(n).padStart(6, '0')}` : null,
      numero_fuego: n % 3 === 0 ? `F${String(n).padStart(3, '0')}` : n % 5 === 0 ? `Q${String(n).padStart(3, '0')}` : null,
      brand_code: n % 5 === 0 || n % 3 === 0 ? 'ZZ1' : null,
      category: n % 7 === 0 ? 'NOVILLONA' : 'VACA',
      current_status: n % 11 === 0 ? 'VENDIDO' : 'ACTIVO',
    }));
    return id;
  };
  const add = (id: string, tag: string, day: string, over: Over): void => {
    events.push(eventRow({ health_log_id: `${tag}-${id}`, livestock_id: id, event_date: day, counts_as_palpation: true, is_clinical_result: true, ...over }));
  };
  const inB = (id: string, i: number, over: Over): void => add(id, 'b', B_DAYS[i % 2] as string, over);

  // 31 Vacía in A, Vacía in B (some UNE then ESTATICA, some unconfirmed codes, B across two dates, some noise outside the windows)
  for (let i = 0; i < GOLDEN.vaciaVacia; i++) {
    const id = animal();
    add(id, 'a', A_DAY, i < 10 ? une : i < 14 ? unmapped(i) : vacia());
    inB(id, i, i < 6 ? estatica : i < 9 ? unmapped(i) : vacia());
    if (i < 10) add(id, 'pre', '2026-05-10', vacia()); // before A: never the latest inside a window
    if (i >= 20 && i < 25) add(id, 'mid', '2026-10-30', prenada(40)); // between the windows: ignored
  }
  // 19 Vacía in A, not palpated in B (events outside B and an NR inside B do not change that)
  for (let i = 0; i < GOLDEN.vaciaNoPalpada; i++) {
    const id = animal();
    add(id, 'a', A_DAY, i < 4 ? une : i < 6 ? unmapped(i) : vacia());
    if (i === 0) {
      add(id, 'out1', '2026-10-30', prenada(30));
      add(id, 'out2', '2026-12-02', prenada(30));
    }
    if (i === 1) add(id, 'nr', B_DAYS[1], { result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false });
  }
  // 25 Vacía in A, Preñada in B
  for (let i = 0; i < GOLDEN.vaciaPrenada; i++) {
    const id = animal();
    add(id, 'a', A_DAY, i < 5 ? une : vacia());
    inB(id, i, prenada(20 + i));
  }
  // 27 Preñada in A, not palpated in B
  for (let i = 0; i < GOLDEN.prenadaNoPalpada; i++) add(animal(), 'a', A_DAY, prenada(60 + i));
  // 7 Preñada in A, Preñada in B
  for (let i = 0; i < GOLDEN.prenadaPrenada; i++) {
    const id = animal();
    add(id, 'a', A_DAY, prenada(60));
    inB(id, i, prenada(160));
  }
  // 11 Preñada in A, Vacía in B
  for (let i = 0; i < GOLDEN.prenadaVacia; i++) {
    const id = animal();
    add(id, 'a', A_DAY, prenada(70));
    inB(id, i, i < 3 ? estatica : vacia());
  }

  // Only in B: 3 Vacía, 2 Preñada, one ranch term (RP) and one MATRIZ OCUPADA (neither Vacía nor Preñada)
  for (let i = 0; i < onlyBVacia; i++) inB(animal(), i, vacia());
  for (let i = 0; i < onlyBPrenada; i++) inB(animal(), i, prenada(45));
  inB(animal(), 0, { result: 'VACÍA', mapping_status: 'NOT_APPLICABLE', raw_code: 'RP', ranch_term: 'RP', is_clinical_result: false });
  inB(animal(), 1, { result: 'PREÑADA', mapping_status: 'NOT_APPLICABLE', raw_code: 'MATRIZ OCUPADA', ranch_term: 'MATRIZ OCUPADA', is_clinical_result: false });
  // NR only: not examined, not palpated, in no list
  add(animal(), 'nrb', B_DAYS[0], { result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false });
  add(animal(), 'nra', A_DAY, { result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false });

  return { events, herd };
}
