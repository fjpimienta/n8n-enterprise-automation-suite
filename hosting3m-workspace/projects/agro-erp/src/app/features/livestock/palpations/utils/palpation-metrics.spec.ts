import { describe, expect, it } from 'vitest';
import { isActiveHead } from '@shared/utils/herd-status.util';
import { SYNTHETIC_CATEGORIES, SYNTHETIC_STATUSES, eventRow, herdRow } from '../testing/palpation.fixtures';
import { PalpationEventRow, PalpationHerdRow } from '../models/palpation.types';
import {
  campaignStart,
  defaultPeriod,
  emptySubtypeOf,
  gestationOf,
  herdBucket,
  identifierOf,
  animalState,
  latestPerAnimal,
  maxCampaignDate,
  periodKpis,
  porPalpar,
} from './palpation-metrics';

/**
 * Synthetic scenario. "Today" is 2026-11-18. Campaign = latest counted non-historical date (2026-11-10) minus 60 days = 2026-09-11.
 */
const TODAY = '2026-11-18';

const scenario: PalpationEventRow[] = [
  // A1: latest clinical VACÍA with structured sub-type ESTATICA (inside the campaign)
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
  // A2: PREÑADA 90 days (inside the campaign)
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90, mapping_status: 'NOT_APPLICABLE', is_clinical_result: true }),
  // A3: 2023 bulk load, historical (outside the default period)
  eventRow({ livestock_id: 'A3', health_log_id: 'e3', event_date: '2023-07-20', result: 'PREÑADA', is_historical_load: true }),
  // A4: NR, not examined: does not count as palpated
  eventRow({ livestock_id: 'A4', health_log_id: 'e4', event_date: '2026-10-01', result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false }),
  // A5: ranch term RP: outside the clinical percentages
  eventRow({ livestock_id: 'A5', health_log_id: 'e5', event_date: '2026-10-05', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
  // A6: unconfirmed code DF15: shown as typed, never interpreted; counts as an empty result with sub-type "sin confirmar"
  eventRow({ livestock_id: 'A6', health_log_id: 'e6', event_date: '2026-10-20', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15', code_meaning: null }),
  // A7: no result and no ranch term
  eventRow({ livestock_id: 'A7', health_log_id: 'e7', event_date: '2026-10-22', result: null, is_clinical_result: false }),
];

const DEFAULT = defaultPeriod(scenario, TODAY)!;

describe('campaign window', () => {
  it('uses the latest counted, non-historical date as the anchor', () => {
    expect(maxCampaignDate(scenario, TODAY)).toBe('2026-11-10');
  });

  it('starts 60 days before the anchor (2026-11-10 − 60 = 2026-09-11)', () => {
    expect(campaignStart(scenario, TODAY)).toBe('2026-09-11');
    expect(DEFAULT).toEqual({ from: '2026-09-11', to: '2026-11-10' });
  });

  it('ignores the historical load, NR and dates after today when choosing the anchor', () => {
    const extra = [
      eventRow({ livestock_id: 'H', health_log_id: 'h1', event_date: '2026-12-01', result: 'VACÍA' }), // after today
      eventRow({ livestock_id: 'N', health_log_id: 'h2', event_date: '2026-11-15', result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false }),
      eventRow({ livestock_id: 'I', health_log_id: 'h3', event_date: '2026-11-16', result: 'PREÑADA', is_historical_load: true }),
    ];
    expect(maxCampaignDate([...scenario, ...extra], TODAY)).toBe('2026-11-10');
  });

  it('returns null when the company has no counted, non-historical palpation (the UI offers "todo")', () => {
    const onlyHistory = [eventRow({ livestock_id: 'X', health_log_id: 'x1', event_date: '2023-07-20', result: 'PREÑADA', is_historical_load: true })];
    expect(campaignStart(onlyHistory, TODAY)).toBeNull();
    expect(defaultPeriod(onlyHistory, TODAY)).toBeNull();
  });

  it('includes an event exactly on the window start and excludes the day before', () => {
    const edge = [
      eventRow({ livestock_id: 'E1', health_log_id: 'b1', event_date: '2026-09-11', result: 'VACÍA' }),
      eventRow({ livestock_id: 'E2', health_log_id: 'b2', event_date: '2026-09-10', result: 'VACÍA' }),
      eventRow({ livestock_id: 'E3', health_log_id: 'b3', event_date: '2026-11-10', result: 'VACÍA' }),
    ];
    const kpis = periodKpis(edge, DEFAULT);
    expect(kpis.palpated).toBe(2);
    expect(latestPerAnimal(edge, DEFAULT).has('E2')).toBe(false);
  });
});

describe('latest palpation per animal', () => {
  it('breaks a tie on the calendar day with the creation timestamp, then with the event key', () => {
    const tie = [
      eventRow({ livestock_id: 'T', health_log_id: 'a', event_date: '2026-11-01', result: 'VACÍA', created_at: '2026-11-01T09:00:00.000Z' }),
      eventRow({ livestock_id: 'T', health_log_id: 'b', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: 30, created_at: '2026-11-01T11:00:00.000Z' }),
    ];
    expect(latestPerAnimal(tie, DEFAULT).get('T')?.result).toBe('PREÑADA');
  });

  it('takes the latest counted event by day, so an earlier clinical result does not hide a later ranch term', () => {
    const seq = [
      eventRow({ livestock_id: 'S', health_log_id: 'p', event_date: '2026-10-01', result: 'PREÑADA', gestation_days: 60 }),
      eventRow({ livestock_id: 'S', health_log_id: 'q', event_date: '2026-10-20', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
    ];
    expect(latestPerAnimal(seq, DEFAULT).get('S')?.ranch_term).toBe('RP');
  });
});

describe('periodKpis', () => {
  const kpis = periodKpis(scenario, DEFAULT);

  it('counts the animals palpated in the period (D), without NR and without the historical load', () => {
    expect(kpis.palpated).toBe(5); // A1, A2, A5, A6, A7
  });

  it('counts the clinical results (C) and the pregnant / empty animals', () => {
    expect(kpis.clinical).toBe(3); // A1 and A6 empty, A2 pregnant
    expect(kpis.pregnant).toBe(1);
    expect(kpis.empty).toBe(2);
  });

  it('computes the percentages over C, with absolute numbers available beside them', () => {
    expect(kpis.pctPregnant).toBeCloseTo(33.333, 2);
    expect(kpis.pctEmpty).toBeCloseTo(66.666, 2);
  });

  it('keeps ranch terms outside the clinical figures, one count per term', () => {
    expect(kpis.ranchTotal).toBe(1);
    expect(kpis.ranchTerms.RP).toBe(1);
    expect(kpis.ranchTerms.NR).toBe(0); // NR never reaches the latest-per-animal set
  });

  it('holds the identity D = C + ranch terms + no result', () => {
    expect(kpis.noResult).toBe(1);
    expect(kpis.identityHolds).toBe(true);
    expect(kpis.palpated).toBe(kpis.clinical + kpis.ranchTotal + kpis.noResult);
  });

  it('counts the unconfirmed codes of the latest events, shown as typed', () => {
    expect(kpis.unconfirmed).toBe(1);
  });

  it('splits the empty animals into sub-types from the structured data only', () => {
    expect(kpis.emptySubtypes.ESTATICA).toBe(1);
    expect(kpis.emptySubtypes.SIN_CONFIRMAR).toBe(1);
    const sum = Object.values(kpis.emptySubtypes).reduce((a, b) => a + b, 0);
    expect(sum).toBe(kpis.empty);
  });

  it('reports the latest counted date of the period', () => {
    expect(kpis.lastPalpationDate).toBe('2026-11-10');
  });

  it('shows "—" (null) for the percentages when there is no clinical result, never 0 %', () => {
    const onlyRanch = [eventRow({ livestock_id: 'R', health_log_id: 'r1', event_date: '2026-11-02', result: 'VACÍA', ranch_term: 'NO APTO', is_clinical_result: false })];
    const k = periodKpis(onlyRanch, DEFAULT);
    expect(k.clinical).toBe(0);
    expect(k.pctPregnant).toBeNull();
    expect(k.pctEmpty).toBeNull();
    expect(k.identityHolds).toBe(true);
  });

  it('with "todo" the historical load enters the figures, labelled by the row flag, and NR still does not count', () => {
    const all = periodKpis(scenario, { from: null, to: null });
    expect(all.palpated).toBe(6); // + A3 (historical)
    expect(all.pregnant).toBe(2);  // A2 and A3
    expect(all.identityHolds).toBe(true);
  });
});

describe('unrecognised values', () => {
  it('counts a row with an unknown result apart: palpated, not clinical, outside the percentages, identity still holds', () => {
    const rows = [
      eventRow({ livestock_id: 'U1', health_log_id: 'u1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA' }),
      eventRow({ livestock_id: 'U2', health_log_id: 'u2', event_date: '2026-11-11', result: null, uninterpreted: true, is_clinical_result: false }),
    ];
    const k = periodKpis(rows, { from: null, to: null });
    expect(k.palpated).toBe(2);
    expect(k.clinical).toBe(1);
    expect(k.uninterpreted).toBe(1);
    expect(k.pctEmpty).toBe(100);
    expect(k.identityHolds).toBe(true);
    expect(animalState(rows[1]!)).toBe('SIN_INTERPRETAR');
  });
});

describe('gestation', () => {
  it('gives months as the main value and the days beside it, for PREÑADA only', () => {
    expect(gestationOf(eventRow({ result: 'PREÑADA', gestation_days: 90 }))).toEqual({ months: 3, days: 90 });
    expect(gestationOf(eventRow({ result: 'VACÍA', gestation_days: 90 }))).toBeNull();
  });

  it('returns null ("—") when the days are missing or zero', () => {
    expect(gestationOf(eventRow({ result: 'PREÑADA', gestation_days: null }))).toBeNull();
    expect(gestationOf(eventRow({ result: 'PREÑADA', gestation_days: 0 }))).toBeNull();
  });
});

describe('sub-type of an empty result', () => {
  it('uses the structured sub-type, and "sin confirmar" for an unconfirmed code', () => {
    expect(emptySubtypeOf(eventRow({ result: 'VACÍA', repro_condition: 'CICLANDO' }))).toBe('CICLANDO');
    expect(emptySubtypeOf(eventRow({ result: 'VACÍA', mapping_status: 'UNMAPPED', repro_condition: 'OTRO' }))).toBe('SIN_CONFIRMAR');
    expect(emptySubtypeOf(eventRow({ result: 'VACÍA' }))).toBe('SIN_SUBTIPO');
  });
});

const CAMPAIGN = '2026-09-11';

function herd(over: Partial<PalpationHerdRow> & { wire?: Record<string, unknown> } = {}): PalpationHerdRow {
  return herdRow(over);
}

describe('herd buckets', () => {
  it('puts VENDIDO and BAJA_MORTANDAD in their own legend, outside the bars', () => {
    expect(herdBucket(herd({ current_status: 'VENDIDO' }), CAMPAIGN)).toBe('vendido');
    expect(herdBucket(herd({ current_status: 'BAJA_MORTANDAD' }), CAMPAIGN)).toBe('baja-mortandad');
  });

  it('leaves the herd for the terminal statuses shared with herd-status.util (FINALIZADO, BAJA_DEPURACION_DATOS)', () => {
    expect(herdBucket(herd({ current_status: 'FINALIZADO' }), CAMPAIGN)).toBe('fuera-del-hato');
    expect(herdBucket(herd({ current_status: 'BAJA_DEPURACION_DATOS' }), CAMPAIGN)).toBe('fuera-del-hato');
  });

  it('marks a bull, calf or steer without palpations as "no aplica"', () => {
    for (const category of ['TORO', 'BECERRO', 'BECERRA', 'NOVILLO']) {
      expect(herdBucket(herd({ category, palpation_count: 0, last_event_date: null, last_result: null }), CAMPAIGN)).toBe('no-aplica');
    }
  });

  it('puts a steer WITH palpations in its date bucket, not in "no aplica"', () => {
    expect(herdBucket(herd({ category: 'NOVILLO', palpation_count: 2, last_event_date: '2026-11-01' }), CAMPAIGN)).toBe('vigente');
    expect(herdBucket(herd({ category: 'NOVILLO', palpation_count: 1, last_event_date: '2023-07-20', last_is_historical: true }), CAMPAIGN)).toBe('historico');
  });

  it('marks a VACA or NOVILLONA without palpations as "sin palpar"', () => {
    expect(herdBucket(herd({ category: 'VACA', palpation_count: 0, last_event_date: null }), CAMPAIGN)).toBe('sin-palpar');
    expect(herdBucket(herd({ category: 'NOVILLONA', palpation_count: 0, last_event_date: null }), CAMPAIGN)).toBe('sin-palpar');
  });

  it('marks an animal never palpated as "sin palpar" (palpation_count 0)', () => {
    expect(herdBucket(herd({ palpation_count: 0, last_event_date: null, last_result: null }), CAMPAIGN)).toBe('sin-palpar');
  });

  it('marks the 2023 load as "histórico" and an event inside the campaign as "vigente", otherwise "anterior"', () => {
    expect(herdBucket(herd({ last_is_historical: true, last_event_date: '2023-07-20' }), CAMPAIGN)).toBe('historico');
    expect(herdBucket(herd({ last_event_date: '2026-09-11' }), CAMPAIGN)).toBe('vigente');
    expect(herdBucket(herd({ last_event_date: '2026-09-10' }), CAMPAIGN)).toBe('anterior');
  });

  it('has no "vigente" without a campaign', () => {
    expect(herdBucket(herd({ last_event_date: '2026-11-10' }), null)).toBe('anterior');
  });
});

describe('vocabulary of the herd (synthetic)', () => {
  const applicable = ['VACA', 'NOVILLONA'];

  it('counts an animal in RIESGO as active, as herd-status.util does: it stays in the herd', () => {
    expect(isActiveHead({ current_status: 'RIESGO' })).toBe(true);
    expect(herdBucket(herd({ current_status: 'RIESGO', category: 'VACA', palpation_count: 0, last_event_date: null }), CAMPAIGN)).toBe('sin-palpar');
    expect(herdBucket(herd({ current_status: 'RIESGO', category: 'VACA', last_event_date: '2026-11-01' }), CAMPAIGN)).toBe('vigente');
    const r = porPalpar([herd({ livestock_id: 'r1', current_status: 'RIESGO', category: 'VACA', palpation_count: 0, last_event_date: null })], CAMPAIGN);
    expect(r).toEqual({ eligible: 1, porPalpar: 1 });
  });

  it('puts every real category without palpations either in "sin palpar" or in "no aplica", never anywhere else', () => {
    for (const category of SYNTHETIC_CATEGORIES) {
      const bucket = herdBucket(herd({ category, current_status: 'ACTIVO', palpation_count: 0, last_event_date: null }), CAMPAIGN);
      expect(bucket).toBe(applicable.includes(category) ? 'sin-palpar' : 'no-aplica');
    }
  });

  it('classifies every real status: VENDIDO and BAJA_MORTANDAD in their legend, the rest stay in the herd', () => {
    for (const current_status of SYNTHETIC_STATUSES) {
      const bucket = herdBucket(herd({ current_status, category: 'VACA', palpation_count: 0, last_event_date: null }), CAMPAIGN);
      if (current_status === 'VENDIDO') expect(bucket).toBe('vendido');
      else if (current_status === 'BAJA_MORTANDAD') expect(bucket).toBe('baja-mortandad');
      else expect(bucket).toBe('sin-palpar');
    }
  });

  it('has no brand code in the synthetic vocabulary (brand_code is null)', () => {
    expect(herd().brand_code).toBeNull();
  });
});

describe('por palpar universe', () => {
  const list: PalpationHerdRow[] = [
    herd({ livestock_id: 'v1', category: 'VACA', current_status: 'ACTIVO', last_event_date: '2026-11-01' }), // vigente: not pending
    herd({ livestock_id: 'v2', category: 'VACA', current_status: 'PREÑADA', palpation_count: 0, last_event_date: null }), // pending
    herd({ livestock_id: 'v3', category: 'NOVILLONA', current_status: 'ACTIVO', last_event_date: '2026-08-01', last_is_historical: false }), // anterior: pending
    herd({ livestock_id: 'v4', category: 'VACA', current_status: 'VENDIDO' }), // not active
    herd({ livestock_id: 'v5', category: 'VACA', current_status: 'BAJA_MORTANDAD' }), // legend, not universe
    herd({ livestock_id: 'v6', category: 'VACA', current_status: 'FINALIZADO' }), // not active
    herd({ livestock_id: 'v7', category: 'TORO', current_status: 'ACTIVO' }), // no aplica
    herd({ livestock_id: 'v8', category: 'BECERRA', current_status: 'ACTIVO' }), // no aplica
    herd({ livestock_id: 'v9', category: 'VACA', current_status: '', palpation_count: 0, last_event_date: null, last_result: null }), // empty status counts as active in herd-status.util
  ];

  it('counts active VACA and NOVILLONA animals without a palpation in the campaign', () => {
    const r = porPalpar(list, CAMPAIGN);
    expect(r.eligible).toBe(4); // v1, v2, v3, v9
    expect(r.porPalpar).toBe(3); // v2, v3, v9
  });

  it('excludes a baja por mortandad from the universe even though herd-status.util counts it as active (agreed legend rule)', () => {
    const onlyMortality = [herd({ livestock_id: 'm1', category: 'VACA', current_status: 'BAJA_MORTANDAD', palpation_count: 0, last_event_date: null })];
    expect(porPalpar(onlyMortality, CAMPAIGN)).toEqual({ eligible: 0, porPalpar: 0 });
  });
});

describe('identifier', () => {
  it('shows the official 10-digit SINIIGA tag first', () => {
    expect(identifierOf(herd({ rfid_siniiga: '9999000001', brand_code: 'ZZ1', numero_fuego: '7' }))).toBe('9999000001');
  });

  it('rejects the placeholder "S/N-…" and falls back to brand + brand number', () => {
    expect(identifierOf(herd({ rfid_siniiga: 'S/N-123', brand_code: 'ZZ1', numero_fuego: '7' }))).toBe('ZZ1 7');
  });

  it('falls back to a neutral label with the first 8 characters of the internal key', () => {
    expect(identifierOf(herd({ rfid_siniiga: null, brand_code: null, numero_fuego: '7', livestock_id: 'abcdef1234' }))).toBe('Sin identificador · abcdef12');
  });
});
