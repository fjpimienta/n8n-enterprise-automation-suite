import { describe, expect, it } from 'vitest';
import {
  EMPTY_ENVELOPE,
  ERROR_ENVELOPE,
  SYNTHETIC_OTHER_TENANT,
  SYNTHETIC_TENANT,
  envelope,
  eventWire,
  herdWire,
} from '../testing/palpation.fixtures';
import { parseEnvelope, parseEventRows, parseHerdRows } from './palpation-parse';

describe('parseEnvelope', () => {
  it('treats an empty or blank body as an error, never as zero rows', () => {
    expect(parseEnvelope('')).toEqual({ ok: false, reason: 'empty-body' });
    expect(parseEnvelope('   \n')).toEqual({ ok: false, reason: 'empty-body' });
    expect(parseEnvelope(null)).toEqual({ ok: false, reason: 'empty-body' });
  });

  it('treats a body that is not JSON as an unexpected shape', () => {
    expect(parseEnvelope('<html>blocked</html>')).toEqual({ ok: false, reason: 'unexpected-shape' });
  });

  it('treats error:true on HTTP 200 as a gateway error', () => {
    expect(parseEnvelope(ERROR_ENVELOPE)).toEqual({ ok: false, reason: 'gateway-error' });
  });

  it('reads data:[{}] as an empty collection (valid, no rows)', () => {
    expect(parseEnvelope(EMPTY_ENVELOPE)).toEqual({ ok: true, rows: [] });
  });

  it('reads data:[] as an empty collection too', () => {
    expect(parseEnvelope(envelope([]))).toEqual({ ok: true, rows: [] });
  });

  it('rejects a data field that is not an array', () => {
    expect(parseEnvelope(JSON.stringify({ error: false, data: { id: 1 } }))).toEqual({ ok: false, reason: 'unexpected-shape' });
  });
});

describe('parseEventRows', () => {
  it('parses a counted clinical event and keeps the calendar day of the gateway date', () => {
    const r = parseEventRows(envelope([eventWire({ event_date: '2026-11-12T06:00:00.000Z' })]), SYNTHETIC_TENANT);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.rows[0]?.event_date).toBe('2026-11-12');
    expect(r.rows[0]?.result).toBe('VACÍA');
    expect(r.rows[0]?.counts_as_palpation).toBe(true);
  });

  it('accepts numbers as JSON numbers and as numeric strings', () => {
    const asString = parseEventRows(envelope([eventWire({ gestation_days: '90' })]), SYNTHETIC_TENANT);
    const asNumber = parseEventRows(envelope([eventWire({ gestation_days: 90 })]), SYNTHETIC_TENANT);
    expect(asString.ok && asString.rows[0]?.gestation_days).toBe(90);
    expect(asNumber.ok && asNumber.rows[0]?.gestation_days).toBe(90);
  });

  it('normalises an unknown mapping_status to UNMAPPED and never keeps its meaning', () => {
    const r = parseEventRows(
      envelope([eventWire({ mapping_status: 'SOMETHING_NEW', raw_code: 'DF15', code_meaning: 'UNFIT' })]),
      SYNTHETIC_TENANT,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.rows[0]?.mapping_status).toBe('UNMAPPED');
    expect(r.rows[0]?.raw_code).toBe('DF15');
    expect(r.rows[0]?.code_meaning).toBeNull();
  });

  it('drops code_meaning for UNMAPPED even when the view sends it', () => {
    const r = parseEventRows(envelope([eventWire({ mapping_status: 'UNMAPPED', code_meaning: 'NOT_EXAMINED' })]), SYNTHETIC_TENANT);
    expect(r.ok && r.rows[0]?.code_meaning).toBeNull();
  });

  it('treats an unknown repro_condition as no sub-type', () => {
    const r = parseEventRows(envelope([eventWire({ repro_condition: 'FOLICULO' })]), SYNTHETIC_TENANT);
    expect(r.ok && r.rows[0]?.repro_condition).toBeNull();
  });

  it('keeps a row with an unknown clinical result as "sin interpretar": no result, not clinical, flagged', () => {
    const r = parseEventRows(envelope([eventWire({ result: 'INDETERMINADA', is_clinical_result: true })]), SYNTHETIC_TENANT);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.rows).toHaveLength(1);
    expect(r.rows[0]?.result).toBeNull();
    expect(r.rows[0]?.uninterpreted).toBe(true);
    expect(r.rows[0]?.is_clinical_result).toBe(false);
    expect(r.rows[0]?.counts_as_palpation).toBe(true);
  });

  it('keeps a row with an unknown ranch term as "sin interpretar" too', () => {
    const r = parseEventRows(envelope([eventWire({ ranch_term: 'INVOLUCIONANDO', is_clinical_result: false, result: 'VACÍA' })]), SYNTHETIC_TENANT);
    expect(r.ok && r.rows[0]?.ranch_term).toBeNull();
    expect(r.ok && r.rows[0]?.uninterpreted).toBe(true);
  });

  it('marks a row as recognised when its values are known', () => {
    const r = parseEventRows(envelope([eventWire()]), SYNTHETIC_TENANT);
    expect(r.ok && r.rows[0]?.uninterpreted).toBe(false);
  });

  it('still rejects an invalid JSON type for a clinical field (a number is not an unknown value)', () => {
    expect(parseEventRows(envelope([eventWire({ result: 1 })]), SYNTHETIC_TENANT)).toEqual({ ok: false, reason: 'unexpected-shape' });
    expect(parseEventRows(envelope([eventWire({ ranch_term: { code: 'NR' } })]), SYNTHETIC_TENANT)).toEqual({ ok: false, reason: 'unexpected-shape' });
  });

  it('rejects the whole response when a row belongs to another company', () => {
    const r = parseEventRows(
      envelope([eventWire(), eventWire({ id_company: SYNTHETIC_OTHER_TENANT, health_log_id: 'ev-foreign' })]),
      SYNTHETIC_TENANT,
    );
    expect(r).toEqual({ ok: false, reason: 'foreign-company' });
  });

  it('rejects an invalid event date as an unexpected date shape', () => {
    const r = parseEventRows(envelope([eventWire({ event_date: 'not-a-date' })]), SYNTHETIC_TENANT);
    expect(r).toEqual({ ok: false, reason: 'unexpected-date-shape' });
  });

  it('accepts the gateway midnight (06:00Z) and rejects a date whose UTC time is after 12:00 as unexpected date shape', () => {
    const ok = parseEventRows(envelope([eventWire({ event_date: '2026-11-12T06:00:00.000Z' })]), SYNTHETIC_TENANT);
    expect(ok.ok && ok.rows[0]?.event_date).toBe('2026-11-12');
    const bad = parseEventRows(envelope([eventWire({ event_date: '2026-11-12T18:00:00.000Z' })]), SYNTHETIC_TENANT);
    expect(bad).toEqual({ ok: false, reason: 'unexpected-date-shape' });
  });

  it('accepts booleans sent as text', () => {
    const r = parseEventRows(envelope([eventWire({ counts_as_palpation: 'true', is_clinical_result: 'false' })]), SYNTHETIC_TENANT);
    expect(r.ok && r.rows[0]?.counts_as_palpation).toBe(true);
    expect(r.ok && r.rows[0]?.is_clinical_result).toBe(false);
  });
});

describe('parseHerdRows', () => {
  it('parses an animal never palpated (count 0, no last event)', () => {
    const r = parseHerdRows(
      envelope([herdWire({ palpation_count: 0, last_event_date: null, last_result: null, last_is_historical: null })]),
      SYNTHETIC_TENANT,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.rows[0]?.palpation_count).toBe(0);
    expect(r.rows[0]?.last_event_date).toBeNull();
  });

  it('rejects a last_event_date after 12:00 UTC as unexpected date shape', () => {
    const r = parseHerdRows(envelope([herdWire({ last_event_date: '2026-11-10T18:00:00.000Z' })]), SYNTHETIC_TENANT);
    expect(r).toEqual({ ok: false, reason: 'unexpected-date-shape' });
  });

  it('keeps an unknown last result or ranch term as "sin interpretar" for the animal', () => {
    const r = parseHerdRows(envelope([herdWire({ last_result: 'INDETERMINADA' }), herdWire({ livestock_id: 'an-2', last_ranch_term: 'XYZ' })]), SYNTHETIC_TENANT);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.rows.map(x => x.uninterpreted)).toEqual([true, true]);
    expect(r.rows.map(x => x.last_result)).toEqual([null, 'PREÑADA']);
  });

  it('rejects a last_result that is not a string', () => {
    expect(parseHerdRows(envelope([herdWire({ last_result: 2 })]), SYNTHETIC_TENANT)).toEqual({ ok: false, reason: 'unexpected-shape' });
  });

  it('rejects a negative palpation count', () => {
    expect(parseHerdRows(envelope([herdWire({ palpation_count: -1 })]), SYNTHETIC_TENANT)).toEqual({ ok: false, reason: 'unexpected-shape' });
  });

  it('rejects the whole herd when a row belongs to another company', () => {
    const r = parseHerdRows(envelope([herdWire({ id_company: SYNTHETIC_OTHER_TENANT })]), SYNTHETIC_TENANT);
    expect(r).toEqual({ ok: false, reason: 'foreign-company' });
  });

  it('reads the empty herd collection as empty, not as an error', () => {
    expect(parseHerdRows(EMPTY_ENVELOPE, SYNTHETIC_TENANT)).toEqual({ ok: true, rows: [] });
  });
});
