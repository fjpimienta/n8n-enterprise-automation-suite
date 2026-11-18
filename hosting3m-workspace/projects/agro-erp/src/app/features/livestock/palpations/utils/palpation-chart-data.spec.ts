import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import { describeDistribution, describeHerd, describeMonthly, herdSummary, resultDistribution, resultsByMonth } from './palpation-chart-data';

const PERIOD = { from: '2026-09-11', to: '2026-11-10' };
const ALL = { from: null, to: null };

const events = [
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90 }),
  eventRow({ livestock_id: 'A3', health_log_id: 'e3', event_date: '2023-07-20', result: 'PREÑADA', is_historical_load: true, gestation_days: 120 }),
  eventRow({ livestock_id: 'A4', health_log_id: 'e4', event_date: '2026-10-01', result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false }),
  eventRow({ livestock_id: 'A5', health_log_id: 'e5', event_date: '2026-10-05', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
  eventRow({ livestock_id: 'A6', health_log_id: 'e6', event_date: '2026-10-20', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
  eventRow({ livestock_id: 'A7', health_log_id: 'e7', event_date: '2026-10-22', result: null, is_clinical_result: false }),
];

describe('resultDistribution (chart 1)', () => {
  it('counts the latest event of each animal and adds up to the animals palpated', () => {
    const items = resultDistribution(events, PERIOD);
    expect(items.map(i => [i.label, i.count])).toEqual([
      ['Preñada · 3 meses', 1],
      ['Vacía · Estática (UNE)', 1],
      ['Vacía · Código sin confirmar', 1],
      ['Definido por el rancho · RP', 1],
      ['Sin resultado', 1],
    ]);
    expect(items.reduce((a, i) => a + i.count, 0)).toBe(5);
  });

  it('keeps a pregnant animal without a usable gestation as its own item', () => {
    const rows = [
      eventRow({ livestock_id: 'P1', health_log_id: 'p1', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: null }),
      eventRow({ livestock_id: 'P2', health_log_id: 'p2', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: 20 }),
      eventRow({ livestock_id: 'P3', health_log_id: 'p3', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: 35 }),
    ];
    expect(resultDistribution(rows, ALL).map(i => i.label)).toEqual([
      'Preñada · menos de 1 mes',
      'Preñada · 1 mes',
      'Preñada · sin dato de gestación',
    ]);
  });

  it('puts an unrecognised value in its own item, never in a clinical one', () => {
    const rows = [eventRow({ livestock_id: 'U', health_log_id: 'u', event_date: '2026-11-01', result: null, uninterpreted: true, is_clinical_result: false })];
    expect(resultDistribution(rows, ALL).map(i => i.label)).toEqual(['Sin interpretar']);
  });

  it('is empty when there is nothing in the period', () => {
    expect(resultDistribution([], PERIOD)).toEqual([]);
    expect(describeDistribution([])).toContain('sin datos');
  });
});

describe('resultsByMonth (chart 2)', () => {
  it('groups counted events by month in the default period, NR excluded, ranch terms apart', () => {
    const r = resultsByMonth(events, PERIOD);
    expect(r.months).toEqual(['09/2026', '10/2026', '11/2026']);
    const by = Object.fromEntries(r.series.map(s => [s.name, s.data]));
    expect(by['Preñada']).toEqual([1, 0, 0]);
    expect(by['Vacía']).toEqual([0, 1, 1]);
    expect(by['Término del rancho']).toEqual([0, 1, 0]);
    expect(by['Sin resultado o sin interpretar']).toEqual([0, 1, 0]);
    expect(by['Histórico (carga 2023)']).toEqual([0, 0, 0]);
  });

  it('shows the 2023 load as its own series when the period is "todo"', () => {
    const r = resultsByMonth(events, ALL);
    expect(r.months[0]).toBe('07/2023');
    const hist = r.series.find(s => s.name === 'Histórico (carga 2023)')!;
    expect(hist.data).toEqual([1, 0, 0, 0]);
    const preg = r.series.find(s => s.name === 'Preñada')!;
    expect(preg.data[0]).toBe(0); // the historical event is not counted as an ordinary pregnant one
  });

  it('describes itself for a screen reader', () => {
    expect(describeMonthly(resultsByMonth(events, PERIOD))).toContain('10/2026');
    expect(describeMonthly({ months: [], series: [] })).toContain('sin datos');
  });
});

describe('herdSummary (chart 3)', () => {
  const herd = [
    herdRow({ livestock_id: 'h1', category: 'VACA', last_event_date: '2026-11-01' }),
    herdRow({ livestock_id: 'h2', category: 'VACA', last_event_date: '2026-08-01' }),
    herdRow({ livestock_id: 'h3', category: 'VACA', last_event_date: '2023-07-20', last_is_historical: true }),
    herdRow({ livestock_id: 'h4', category: 'VACA', palpation_count: 0, last_event_date: null }),
    herdRow({ livestock_id: 'h5', category: 'NOVILLO', palpation_count: 0, last_event_date: null }),
    herdRow({ livestock_id: 'h6', category: 'TORO', palpation_count: 0, last_event_date: null }),
    herdRow({ livestock_id: 'h7', category: 'NOVILLO', palpation_count: 2, last_event_date: '2026-10-01' }),
    herdRow({ livestock_id: 'h8', category: 'VACA', current_status: 'VENDIDO' }),
    herdRow({ livestock_id: 'h9', category: 'VACA', current_status: 'BAJA_MORTANDAD' }),
    herdRow({ livestock_id: 'h10', category: 'VACA', current_status: 'FINALIZADO' }),
    herdRow({ livestock_id: 'h11', category: 'VACA', current_status: 'RIESGO', palpation_count: 0, last_event_date: null }),
  ];
  const s = herdSummary(herd, '2026-09-11');

  it('counts the four date buckets, a steer with palpations included', () => {
    expect(Object.fromEntries(s.bars.map(b => [b.bucket, b.count]))).toEqual({ vigente: 2, anterior: 1, historico: 1, 'sin-palpar': 2 });
  });

  it('keeps sold and mortality in their own legend, with "no aplica" and the animals that left the herd', () => {
    expect(s.legend).toEqual({ vendido: 1, bajaMortandad: 1, noAplica: 2, fueraDelHato: 1 });
  });

  it('computes the "por palpar" universe from VACA and NOVILLONA only', () => {
    expect(s.porPalpar).toEqual({ eligible: 5, porPalpar: 4 });
  });

  it('describes itself, with sold and mortality apart', () => {
    const text = describeHerd(s);
    expect(text).toContain('Vigente (campaña reciente), 2');
    expect(text).toContain('vendidos 1');
    expect(text).toContain('baja por mortandad 1');
  });
});
