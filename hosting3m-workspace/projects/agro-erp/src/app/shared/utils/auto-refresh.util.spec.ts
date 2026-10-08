import { describe, it, expect } from 'vitest';
import { isAutoRefreshDue } from './auto-refresh.util';

describe('isAutoRefreshDue', () => {
  const INTERVAL_MS = 5 * 60 * 1000;
  const NOW = new Date('2026-10-08T12:00:00.000Z').getTime();

  it('is due when never refreshed before', () => {
    expect(isAutoRefreshDue(null, NOW, INTERVAL_MS)).toBe(true);
  });

  it('is not due when less time than the interval has elapsed', () => {
    const lastRefreshedAt = new Date(NOW - (INTERVAL_MS - 1));
    expect(isAutoRefreshDue(lastRefreshedAt, NOW, INTERVAL_MS)).toBe(false);
  });

  it('is due exactly at the interval boundary (inclusive)', () => {
    const lastRefreshedAt = new Date(NOW - INTERVAL_MS);
    expect(isAutoRefreshDue(lastRefreshedAt, NOW, INTERVAL_MS)).toBe(true);
  });

  it('is due when more time than the interval has elapsed (tab was hidden past due)', () => {
    const lastRefreshedAt = new Date(NOW - INTERVAL_MS - 60_000);
    expect(isAutoRefreshDue(lastRefreshedAt, NOW, INTERVAL_MS)).toBe(true);
  });

  it('is not due immediately after a refresh', () => {
    expect(isAutoRefreshDue(new Date(NOW), NOW, INTERVAL_MS)).toBe(false);
  });
});
