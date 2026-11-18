import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import { describeDistribution, describeHerd, describeMonthly, herdSummary, resultDistribution, resultsByMonth } from './palpation-chart-data';
import { BUCKET_COLOR, colorForKey } from './palpation-colors';

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

describe('resultDistribution: short names and fixed colours', () => {
  const all = [
    eventRow({ livestock_id: 'a', health_log_id: 'a', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: 180 }),
    eventRow({ livestock_id: 'b', health_log_id: 'b', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: null }),
    eventRow({ livestock_id: 'c', health_log_id: 'c', event_date: '2026-11-01', result: 'PREÑADA', gestation_days: 20 }),
    eventRow({ livestock_id: 'd', health_log_id: 'd', event_date: '2026-11-01', result: 'VACÍA', repro_condition: 'CICLANDO', mapping_status: 'EXPLICIT' }),
    eventRow({ livestock_id: 'e', health_log_id: 'e', event_date: '2026-11-01', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
    eventRow({ livestock_id: 'f', health_log_id: 'f', event_date: '2026-11-01', result: 'VACÍA', repro_condition: 'OTRO', mapping_status: 'EXPLICIT' }),
    eventRow({ livestock_id: 'g', health_log_id: 'g', event_date: '2026-11-01', result: 'VACÍA' }),
    eventRow({ livestock_id: 'h', health_log_id: 'h', event_date: '2026-11-01', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
    eventRow({ livestock_id: 'i', health_log_id: 'i', event_date: '2026-11-01', result: 'VACÍA', ranch_term: 'MATRIZ OCUPADA', is_clinical_result: false }),
    eventRow({ livestock_id: 'j', health_log_id: 'j', event_date: '2026-11-01', result: null, is_clinical_result: false }),
    eventRow({ livestock_id: 'k', health_log_id: 'k', event_date: '2026-11-01', result: null, uninterpreted: true, is_clinical_result: false }),
  ];

  it('gives each item a short axis name and keeps the full name apart for the tooltip and the table', () => {
    const items = resultDistribution(all, ALL);
    expect(items.map(i => i.short)).toEqual([
      'Preñada · <1 m', 'Preñada · 6 m', 'Preñada · sin dato',
      'Vacía · Estática', 'Vacía · Ciclando', 'Vacía · Otro', 'Vacía · Sin detalle', 'Vacía · Sin confirmar',
      'Rancho · MATRIZ OCUPADA', 'Sin resultado', 'Sin interpretar',
    ]);
    expect(items.find(i => i.key === 'v-ESTATICA')?.label).toBe('Vacía · Estática (UNE)');
    expect(items.find(i => i.key === 'r-MATRIZ OCUPADA')?.label).toBe('Definido por el rancho · MATRIZ OCUPADA');
    expect(items.find(i => i.key === 'v-SIN_SUBTIPO')?.label).toBe('Vacía · Sin detalle de subtipo');
  });

  it('keeps every short name free of an ellipsis and under 24 characters, so desktop and phone never truncate it', () => {
    for (const i of resultDistribution(all, ALL)) {
      expect(i.short.includes('…')).toBe(false);
      expect(i.short.length).toBeLessThanOrEqual(24);
    }
  });

  it('colours an item by its category: the same colour whatever the period, the data or the order', () => {
    const everything = resultDistribution(all, ALL);
    const onlyTwo = resultDistribution([...all].reverse().filter(e => ['e', 'i'].includes(e.livestock_id)), ALL);
    for (const item of onlyTwo) expect(item.color).toBe(everything.find(i => i.key === item.key)?.color);
    for (const item of everything) expect(item.color).toBe(colorForKey(item.key));
    expect(new Set(everything.map(i => i.color)).size).toBe(everything.length);
  });
});

describe('herdSummary colours', () => {
  it('gives each bar the fixed colour of its bucket', () => {
    const bars = herdSummary([], '2026-09-11').bars;
    expect(bars.map(b => [b.bucket, b.color])).toEqual([
      ['vigente', BUCKET_COLOR.vigente],
      ['anterior', BUCKET_COLOR.anterior],
      ['historico', BUCKET_COLOR.historico],
      ['sin-palpar', BUCKET_COLOR['sin-palpar']],
    ]);
  });
});

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
