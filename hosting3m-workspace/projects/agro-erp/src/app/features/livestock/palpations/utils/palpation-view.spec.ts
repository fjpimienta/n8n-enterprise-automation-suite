import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import {
  HISTORICAL_BADGE,
  STATE_LABEL,
  buildTableRows,
  buildTimeline,
  distinctStatuses,
  filterRows,
  formatDate,
  formatDecimal,
  formatGestation,
  formatPercent,
  reasonText,
  sortRows,
} from './palpation-view';

const PERIOD = { from: '2026-09-11', to: '2026-11-10' };

const herd = [
  herdRow({ livestock_id: 'A1', rfid_siniiga: '9999000001', category: 'VACA', current_status: 'VACÍA' }),
  herdRow({ livestock_id: 'A2', rfid_siniiga: '9999000002', category: 'VACA', current_status: 'PREÑADA' }),
  herdRow({ livestock_id: 'A5', rfid_siniiga: '9999000005', category: 'NOVILLONA', current_status: 'ACTIVO' }),
  herdRow({ livestock_id: 'A6', rfid_siniiga: null, brand_code: 'ZZ1', numero_fuego: '7', category: 'VACA', current_status: 'RIESGO' }),
];

const events = [
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT', technician: 'Técnico sintético' }),
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90 }),
  eventRow({ livestock_id: 'A5', health_log_id: 'e5', event_date: '2026-10-05', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
  eventRow({ livestock_id: 'A6', health_log_id: 'e6', event_date: '2026-10-20', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
  eventRow({ livestock_id: 'A9', health_log_id: 'e9', event_date: '2026-10-22', result: null, is_clinical_result: false }),
];

describe('formatting', () => {
  it('formats a calendar date by splitting the string', () => {
    expect(formatDate('2026-11-12')).toBe('12/11/2026');
    expect(formatDate(null)).toBe('—');
  });

  it('uses the Spanish decimal comma and never "0 %" for a missing percentage', () => {
    expect(formatDecimal(3)).toBe('3,0');
    expect(formatPercent(33.333)).toBe('33,3 %');
    expect(formatPercent(0)).toBe('0,0 %');
    expect(formatPercent(null)).toBe('—');
  });

  it('shows gestation as months with the days in brackets, or an em dash', () => {
    expect(formatGestation({ months: 3, days: 90 })).toBe('3,0 meses (90 días)');
    expect(formatGestation(null)).toBe('—');
  });

  it('has a Spanish text for every error reason and never mentions a body', () => {
    const reasons = ['empty-body', 'gateway-error', 'http-error', 'unexpected-shape', 'unexpected-date-shape', 'foreign-company', 'network', 'session-expired', 'no-tenant', 'no-permission'] as const;
    for (const r of reasons) expect(reasonText(r).length).toBeGreaterThan(10);
    expect(new Set(reasons.map(reasonText)).size).toBe(reasons.length);
    expect(reasonText(null)).toContain('consulta');
  });

  it('labels the historical badge as agreed', () => {
    expect(HISTORICAL_BADGE).toBe('histórico (carga 2023)');
    expect(STATE_LABEL.TERMINO_RANCHO).toBe('Término del rancho');
  });
});

describe('table rows', () => {
  const rows = buildTableRows(events, herd, PERIOD);
  const by = (id: string) => rows.find(r => r.livestockId === id)!;

  it('builds one row per animal with its latest counted palpation in the period', () => {
    expect(rows.length).toBe(5);
  });

  it('joins the identifier and the herd data, with a neutral label for an animal missing from the herd', () => {
    expect(by('A1').identifier).toBe('9999000001');
    expect(by('A6').identifier).toBe('ZZ1 7');
    expect(by('A9').identifier).toBe('Sin identificador · A9');
    expect(by('A9').category).toBe('—');
  });

  it('keeps the sub-type only for an empty result, from structured data', () => {
    expect(by('A1').subtype).toBe('ESTATICA');
    expect(by('A2').subtype).toBeNull();
    expect(by('A6').subtype).toBe('SIN_CONFIRMAR');
  });

  it('shows gestation only for a pregnant animal', () => {
    expect(by('A2').gestation).toEqual({ months: 3, days: 90 });
    expect(by('A1').gestation).toBeNull();
  });

  it('keeps the unconfirmed code as typed only when it is unconfirmed', () => {
    expect(by('A6').unconfirmedCode).toBe('DF15');
    expect(by('A1').unconfirmedCode).toBeNull();
  });

  it('carries the technician, the ranch term and the state', () => {
    expect(by('A1').technician).toBe('Técnico sintético');
    expect(by('A5').ranchTerm).toBe('RP');
    expect(by('A5').state).toBe('TERMINO_RANCHO');
    expect(by('A9').state).toBe('SIN_RESULTADO');
  });
});

describe('timeline of one animal', () => {
  const rows = [
    eventRow({ livestock_id: 'A', health_log_id: 'a', event_date: '2026-10-01', result: 'VACÍA', repro_condition: 'CICLANDO', mapping_status: 'EXPLICIT' }),
    eventRow({ livestock_id: 'A', health_log_id: 'b', event_date: '2026-11-05', result: 'PREÑADA', gestation_days: 60, technician: 'Técnico sintético' }),
    eventRow({ livestock_id: 'A', health_log_id: 'c', event_date: '2026-10-20', result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false }),
    eventRow({ livestock_id: 'A', health_log_id: 'd', event_date: '2023-07-20', result: 'VACÍA', is_historical_load: true }),
  ];

  it('lists the events newest first', () => {
    expect(buildTimeline(rows).map(e => e.id)).toEqual(['b', 'c', 'a', 'd']);
  });

  it('keeps gestation for a pregnant entry, the sub-type for an empty one and the technician', () => {
    const t = buildTimeline(rows);
    expect(t[0]?.gestation).toEqual({ months: 2, days: 60 });
    expect(t[0]?.technician).toBe('Técnico sintético');
    expect(t[2]?.subtype).toBe('CICLANDO');
    expect(t[2]?.gestation).toBeNull();
  });

  it('lists NR but marks it as not counted, and flags the historical load', () => {
    const t = buildTimeline(rows);
    expect(t[1]?.counts).toBe(false);
    expect(t[1]?.ranchTerm).toBe('NR');
    expect(t[3]?.historical).toBe(true);
  });

  it('keeps an unconfirmed code as typed and nothing else', () => {
    const t = buildTimeline([eventRow({ livestock_id: 'A', health_log_id: 'u', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'IF15' })]);
    expect(t[0]?.unconfirmed).toBe(true);
    expect(t[0]?.unconfirmedCode).toBe('IF15');
  });

  it('is empty for an animal without events', () => {
    expect(buildTimeline([])).toEqual([]);
  });
});

describe('filter and sort', () => {
  const rows = buildTableRows(events, herd, PERIOD);

  it('filters by result and by current status', () => {
    expect(filterRows(rows, { result: 'PREÑADA', status: 'TODOS' }).map(r => r.livestockId)).toEqual(['A2']);
    expect(filterRows(rows, { result: 'TODOS', status: 'RIESGO' }).map(r => r.livestockId)).toEqual(['A6']);
    expect(filterRows(rows, { result: 'TODOS', status: 'TODOS' }).length).toBe(5);
  });

  it('lists the distinct statuses for the filter', () => {
    expect(distinctStatuses(rows)).toEqual(['—', 'ACTIVO', 'PREÑADA', 'RIESGO', 'VACÍA']);
  });

  it('sorts by date in both directions', () => {
    expect(sortRows(rows, 'lastDate', 'desc')[0]?.livestockId).toBe('A1');
    expect(sortRows(rows, 'lastDate', 'asc')[0]?.livestockId).toBe('A2');
  });

  it('puts a missing value last in either direction', () => {
    expect(sortRows(rows, 'gestation', 'asc')[0]?.livestockId).toBe('A2');
    expect(sortRows(rows, 'gestation', 'desc')[0]?.livestockId).toBe('A2');
    expect(sortRows(rows, 'technician', 'asc')[0]?.livestockId).toBe('A1');
    expect(sortRows(rows, 'technician', 'desc')[0]?.livestockId).toBe('A1');
  });

  it('sorts identifiers numerically and is stable on ties', () => {
    const ids = sortRows(rows, 'identifier', 'asc').map(r => r.identifier);
    expect(ids.indexOf('9999000001')).toBeLessThan(ids.indexOf('9999000002'));
    const same = sortRows(rows, 'currentStatus', 'asc');
    expect(same.length).toBe(rows.length);
  });
});
