import { describe, it, expect } from 'vitest';
import {
  formatAuthorizationTimestamp,
  formatInstantInCdmx,
  authorizationLocalDate,
  getAuthorizationDeadline,
  isAuthorizationExpired,
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

  it('takes a numeric offset as a real instant', () => {
    expect(parseGatewayTimestamp('2026-10-09T13:52:00-06:00').toISOString()).toBe('2026-10-09T19:52:00.000Z');
  });

  it('undoes the n8n shift of a top-level column ("Z" = naive UTC read as CDMX time)', () => {
    // Real case (execution 720200): naive 2026-10-11 00:40:50.364 UTC arrives as 06:40:50.364Z.
    expect(parseGatewayTimestamp('2026-10-11T06:40:50.364Z').toISOString()).toBe('2026-10-11T00:40:50.364Z');
    // Across a CDMX day boundary: naive 2026-10-10 01:00 UTC (19:00 CDMX on the 9th).
    expect(parseGatewayTimestamp('2026-10-10T07:00:00.000Z').toISOString()).toBe('2026-10-10T01:00:00.000Z');
  });

  it('does not mistake the day of a date-only value for an offset', () => {
    expect(parseGatewayTimestamp('2026-10-09').toISOString()).toBe('2026-10-09T00:00:00.000Z');
  });
});

// America/Mexico_City is UTC-6 (no DST since 2022): CDMX wall clock = UTC - 6h.
describe('getAuthorizationDeadline (23:59:59.999 CDMX of the request day, migration 072)', () => {
  it('requested 17:45 CDMX -> deadline 23:59:59.999 CDMX the same day', () => {
    // 2026-10-09 17:45 CDMX = 2026-10-09 23:45 UTC
    const deadline = getAuthorizationDeadline('2026-10-09T23:45:00');
    expect(deadline.toISOString()).toBe('2026-10-10T05:59:59.999Z');
    expect(cdmx(deadline)).toBe('2026-10-09 23:59');
  });

  it('requested 23:30 CDMX (already the next UTC day) still belongs to its CDMX day', () => {
    // 2026-10-09 23:30 CDMX = 2026-10-10 05:30 UTC
    expect(authorizationLocalDate('2026-10-10T05:30:00')).toBe('2026-10-09');
    expect(getAuthorizationDeadline('2026-10-10T05:30:00').toISOString()).toBe('2026-10-10T05:59:59.999Z');
  });

  it('rolls over month and year ends', () => {
    // 2026-12-31 20:00 CDMX = 2027-01-01 02:00 UTC
    expect(getAuthorizationDeadline('2027-01-01T02:00:00').toISOString()).toBe('2027-01-01T05:59:59.999Z');
  });
});

describe('formatAuthorizationTimestamp', () => {
  it('renders a UTC gateway value in America/Mexico_City', () => {
    expect(formatAuthorizationTimestamp('2026-10-09T19:52:00')).toContain('13:52');
  });

  it('fecha_resolucion: 18:40 CDMX is shown as 18:40, not the 00:40 UTC wall clock', () => {
    // Same row in both shapes the gateway uses: top-level column ("Z", shifted) and naive text.
    const shown = formatAuthorizationTimestamp('2026-10-11T06:40:50.364Z');
    expect(shown).toContain('18:40');
    expect(shown).toContain('10/10/26');
    expect(formatAuthorizationTimestamp('2026-10-11T00:40:50.364565')).toBe(shown);
  });

  it('returns a dash for empty or invalid values', () => {
    expect(formatAuthorizationTimestamp(null)).toBe('—');
    expect(formatAuthorizationTimestamp('not a date')).toBe('—');
  });
});

describe('isAuthorizationExpired (same rule as fn_authorization_expired, migration 072)', () => {
  it('requested 17:45 CDMX -> not expired at 23:30 CDMX the same day', () => {
    // now = 2026-10-09 23:30 CDMX = 2026-10-10 05:30 UTC
    expect(isAuthorizationExpired('2026-10-09T23:45:00', Date.parse('2026-10-10T05:30:00Z'))).toBe(false);
  });

  it('requested 23:30 CDMX -> expired at 00:01 CDMX the next day', () => {
    // requested 2026-10-09 23:30 CDMX = 2026-10-10 05:30 UTC; now = 2026-10-10 00:01 CDMX = 06:01 UTC
    expect(isAuthorizationExpired('2026-10-10T05:30:00', Date.parse('2026-10-10T06:01:00Z'))).toBe(true);
  });

  it('switches exactly at CDMX midnight', () => {
    expect(isAuthorizationExpired('2026-10-09T23:45:00', Date.parse('2026-10-10T05:59:59.999Z'))).toBe(false);
    expect(isAuthorizationExpired('2026-10-09T23:45:00', Date.parse('2026-10-10T06:00:00.000Z'))).toBe(true);
  });

  it('is no longer the obsolete 18:00 CDMX rule', () => {
    // requested 13:52 CDMX; 19:00 CDMX the same day (2026-10-10 01:00 UTC) is still valid
    expect(isAuthorizationExpired('2026-10-09T19:52:00', Date.parse('2026-10-10T01:00:00Z'))).toBe(false);
  });
});

describe('expiry with the shape the gateway really sends', () => {
  it('a request at 19:00 CDMX keeps its own CDMX day (no day jump from the +6 h shift)', () => {
    // naive 2026-10-10 01:00 UTC = 2026-10-09 19:00 CDMX, delivered as 07:00Z
    expect(authorizationLocalDate('2026-10-10T07:00:00.000Z')).toBe('2026-10-09');
    expect(isAuthorizationExpired('2026-10-10T07:00:00.000Z', Date.parse('2026-10-10T05:30:00Z'))).toBe(false);
    expect(isAuthorizationExpired('2026-10-10T07:00:00.000Z', Date.parse('2026-10-10T06:01:00Z'))).toBe(true);
  });
});

describe('formatInstantInCdmx', () => {
  it('formats a real instant without the gateway correction', () => {
    expect(formatInstantInCdmx(new Date('2026-10-10T05:59:59.999Z'))).toContain('23:59');
  });
});
