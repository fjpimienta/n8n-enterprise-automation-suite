import { describe, expect, it } from 'vitest';
import { canUsePanelAlta, todayInMexicoCity, validatePanelWeight } from './panel-livestock.util';
import { PANEL_LIVESTOCK_ALTA_ENABLED } from './panel-livestock.switch';

describe('todayInMexicoCity', () => {
  it('returns the CDMX date in the evening, when UTC is already the next day', () => {
    // 2026-11-10 20:30 CDMX (UTC-6, no DST in November) = 2026-11-11 02:30 UTC
    const now = new Date('2026-11-11T02:30:00Z');
    expect(now.toISOString().split('T')[0]).toBe('2026-11-11');
    expect(todayInMexicoCity(now)).toBe('2026-11-10');
  });

  it('returns the same date in the morning', () => {
    expect(todayInMexicoCity(new Date('2026-11-10T15:00:00Z'))).toBe('2026-11-10');
  });

  it('handles the CDMX midnight boundary', () => {
    expect(todayInMexicoCity(new Date('2026-11-11T05:59:59Z'))).toBe('2026-11-10');
    expect(todayInMexicoCity(new Date('2026-11-11T06:00:00Z'))).toBe('2026-11-11');
  });

  it('pads month and day', () => {
    expect(todayInMexicoCity(new Date('2026-03-05T18:00:00Z'))).toBe('2026-03-05');
  });
});

describe('canUsePanelAlta', () => {
  it.each(['ADMIN', 'EDITOR', 'admin', ' Editor '])('allows %s', role => {
    expect(canUsePanelAlta(role)).toBe(true);
  });
  it.each(['OWNER', 'CUSTOMER', '', null, undefined])('denies %s', role => {
    expect(canUsePanelAlta(role as string | null | undefined)).toBe(false);
  });
});

describe('PANEL_LIVESTOCK_ALTA_ENABLED', () => {
  it('ships OFF', () => {
    expect(PANEL_LIVESTOCK_ALTA_ENABLED).toBe(false);
  });
});

describe('validatePanelWeight', () => {
  it.each(['', '  ', null, undefined, '412', '412.5', '412,5', ' 4 12,5 ', 450])('accepts %s', v => {
    expect(validatePanelWeight(v)).toBeNull();
  });
  it.each(['abc', '12kg', '-5', '1.2.3', '1,2,3'])('rejects %s', v => {
    expect(validatePanelWeight(v)).toMatch(/peso/i);
  });
});
