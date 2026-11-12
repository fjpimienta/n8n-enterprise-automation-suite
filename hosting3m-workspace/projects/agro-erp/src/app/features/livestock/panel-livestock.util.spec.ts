import { describe, expect, it } from 'vitest';
import { canUsePanelAlta, orderPanelEntries, todayInMexicoCity, validatePanelWeight } from './panel-livestock.util';
import { PANEL_LIVESTOCK_ALTA_TENANTS, isPanelAltaEnabledForTenant } from './panel-livestock.switch';

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

describe('validatePanelWeight', () => {
  it.each(['', '  ', null, undefined, '412', '412.5', '412,5', ' 4 12,5 ', 450])('accepts %s', v => {
    expect(validatePanelWeight(v)).toBeNull();
  });
  it.each(['abc', '12kg', '-5', '1.2.3', '1,2,3', '1,234.5', '.5'])('rejects %s as not a number', v => {
    expect(validatePanelWeight(v)).toBe('El peso debe ser un número (por ejemplo 412.5).');
  });
  it.each(['0', '0,0', '0.00', ' 0 ', 0])('rejects zero %j', v => {
    expect(validatePanelWeight(v)).toBe('El peso debe ser un número de kilos mayor que 0 (o déjalo vacío).');
  });
  it('accepts a small positive weight', () => {
    expect(validatePanelWeight('0,5')).toBeNull();
  });
});

describe('isPanelAltaEnabledForTenant', () => {
  it('ships with company 3 only', () => {
    expect(PANEL_LIVESTOCK_ALTA_TENANTS).toEqual([3]);
  });
  it.each([3, '3', ' 3 '])('enables %j', v => {
    expect(isPanelAltaEnabledForTenant(v)).toBe(true);
  });
  it.each([1, 5, 6, 8, null, undefined, '', NaN, '3abc', 3.5, '3.5', true, 'abc', [3], {}, -3])('disables %j', v => {
    expect(isPanelAltaEnabledForTenant(v)).toBe(false);
  });
  it('an empty list is the kill switch, even for 3', () => {
    expect(isPanelAltaEnabledForTenant(3, [])).toBe(false);
    expect(isPanelAltaEnabledForTenant('3', [])).toBe(false);
  });
  it('honors a custom list', () => {
    expect(isPanelAltaEnabledForTenant(5, [3, 5])).toBe(true);
    expect(isPanelAltaEnabledForTenant(6, [3, 5])).toBe(false);
  });
});

describe('orderPanelEntries', () => {
  it('puts known keys in the fixed order and unknown ones last, as received', () => {
    const out = orderPanelEntries({ zeta: 1, notas: 'n', peso_kg: '400', alfa: 2, empresa: 'E', arete: 'A', upp: 'U' });
    expect(out.map(([k]) => k)).toEqual(['empresa', 'upp', 'arete', 'peso_kg', 'notas', 'zeta', 'alfa']);
  });
  it('handles null', () => {
    expect(orderPanelEntries(null)).toEqual([]);
  });
});
