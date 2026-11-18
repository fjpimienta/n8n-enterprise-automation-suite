import { describe, expect, it } from 'vitest';
import { addCalendarDays, calendarDateOf, compareCalendarDates, isCalendarDate } from './palpation-dates';

describe('palpation-dates', () => {
  it('reads the calendar day of a gateway date (local midnight in UTC-6)', () => {
    expect(calendarDateOf('2026-11-12T06:00:00.000Z')).toBe('2026-11-12');
    expect(calendarDateOf('2026-11-12')).toBe('2026-11-12');
  });

  it('rejects values that do not start with a valid calendar date', () => {
    expect(calendarDateOf('2026-02-30T06:00:00.000Z')).toBeNull();
    expect(calendarDateOf('no-date')).toBeNull();
    expect(calendarDateOf(null)).toBeNull();
    expect(calendarDateOf(undefined)).toBeNull();
    expect(isCalendarDate('2026-13-01')).toBe(false);
  });

  it('adds calendar days across month and leap-year boundaries', () => {
    expect(addCalendarDays('2026-03-01', -1)).toBe('2026-02-28');
    expect(addCalendarDays('2028-03-01', -1)).toBe('2028-02-29');
    expect(addCalendarDays('2026-11-10', -60)).toBe('2026-09-11');
    expect(addCalendarDays('2026-09-11', 60)).toBe('2026-11-10');
  });

  it('compares calendar dates as strings in day order', () => {
    expect(compareCalendarDates('2026-09-10', '2026-09-11')).toBeLessThan(0);
    expect(compareCalendarDates('2026-09-11', '2026-09-11')).toBe(0);
    expect(compareCalendarDates('2026-10-01', '2026-09-30')).toBeGreaterThan(0);
  });
});
