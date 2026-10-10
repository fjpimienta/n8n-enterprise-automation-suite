import { describe, it, expect } from 'vitest';
import {
  formatAuthorizationTimestamp,
  getAuthorizationDeadline,
  parseGatewayTimestamp
} from './authorization-deadline.util';

/** Wall-clock in America/Mexico_City, e.g. "2026-10-09 18:00". */
const cdmx = (d: Date) =>
  new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'America/Mexico_City',
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
  }).format(d);

describe('parseGatewayTimestamp', () => {
  it('treats a value without offset as UTC', () => {
    expect(parseGatewayTimestamp('2026-10-09T19:52:00').toISOString()).toBe('2026-10-09T19:52:00.000Z');
  });

  it('accepts the Postgres text form (space separator, microseconds)', () => {
    expect(parseGatewayTimestamp('2026-10-09 19:52:00.123456').toISOString()).toBe('2026-10-09T19:52:00.123Z');
  });

  it('respects an explicit offset', () => {
    expect(parseGatewayTimestamp('2026-10-09T19:52:00Z').toISOString()).toBe('2026-10-09T19:52:00.000Z');
    expect(parseGatewayTimestamp('2026-10-09T13:52:00-06:00').toISOString()).toBe('2026-10-09T19:52:00.000Z');
  });

  it('does not mistake the day of a date-only value for an offset', () => {
    expect(parseGatewayTimestamp('2026-10-09').toISOString()).toBe('2026-10-09T00:00:00.000Z');
  });
});

describe('getAuthorizationDeadline (start of UTC day of fecha_solicitud + 24h)', () => {
  it('13:52 CDMX -> 18:00 CDMX the same day', () => {
    const deadline = getAuthorizationDeadline('2026-10-09T19:52:00');
    expect(deadline.toISOString()).toBe('2026-10-10T00:00:00.000Z');
    expect(cdmx(deadline)).toBe('2026-10-09 18:00');
  });

  it('19:00 CDMX -> 18:00 CDMX the next day', () => {
    const deadline = getAuthorizationDeadline('2026-10-10T01:00:00');
    expect(deadline.toISOString()).toBe('2026-10-11T00:00:00.000Z');
    expect(cdmx(deadline)).toBe('2026-10-10 18:00');
  });

  it('exactly 18:00 CDMX -> 18:00 CDMX the next day', () => {
    const deadline = getAuthorizationDeadline('2026-10-10T00:00:00');
    expect(deadline.toISOString()).toBe('2026-10-11T00:00:00.000Z');
    expect(cdmx(deadline)).toBe('2026-10-10 18:00');
  });
});

describe('formatAuthorizationTimestamp', () => {
  it('renders a UTC gateway value in America/Mexico_City', () => {
    expect(formatAuthorizationTimestamp('2026-10-09T19:52:00')).toContain('13:52');
  });

  it('returns a dash for empty or invalid values', () => {
    expect(formatAuthorizationTimestamp(null)).toBe('—');
    expect(formatAuthorizationTimestamp('not a date')).toBe('—');
  });
});
