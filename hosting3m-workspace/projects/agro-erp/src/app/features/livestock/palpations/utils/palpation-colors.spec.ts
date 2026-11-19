import { describe, expect, it } from 'vitest';
import {
  BUCKET_COLOR,
  EMPTY_COLOR,
  FAMILY_COLOR,
  NO_RESULT_COLOR,
  PREGNANT_MAX_MONTH,
  PREGNANT_WITHOUT_GESTATION,
  RANCH_COLOR,
  UNINTERPRETED_COLOR,
  bucketColor,
  colorForKey,
  gestationMonthOf,
  labelColorOn,
  luminance,
  pregnantColor,
  resultColorOf,
  resultKeyOf,
} from './palpation-colors';

const HEX = /^#[0-9a-f]{6}$/;

describe('pregnant colour scale', () => {
  it('is a valid hex colour for every month', () => {
    for (let m = 0; m <= 12; m++) expect(pregnantColor(m)).toMatch(HEX);
  });

  it('gets strictly darker with each month up to the last step (more months = darker)', () => {
    for (let m = 1; m <= PREGNANT_MAX_MONTH; m++) {
      expect(luminance(pregnantColor(m))).toBeLessThan(luminance(pregnantColor(m - 1)));
    }
  });

  it('shares the darkest tone from the last step on, and treats a negative month as month 0', () => {
    expect(pregnantColor(PREGNANT_MAX_MONTH + 3)).toBe(pregnantColor(PREGNANT_MAX_MONTH));
    expect(pregnantColor(-2)).toBe(pregnantColor(0));
  });

  it('keeps "no gestation data" outside the scale', () => {
    const all = Array.from({ length: PREGNANT_MAX_MONTH + 1 }, (_, m) => pregnantColor(m));
    expect(pregnantColor(null)).toBe(PREGNANT_WITHOUT_GESTATION);
    expect(all).not.toContain(PREGNANT_WITHOUT_GESTATION);
  });

  it('gives the 3 months of 90 days, 4 of 120 and 8 of 240 distinct tones', () => {
    const tones = [90, 120, 150, 180, 210, 240].map(d => pregnantColor(gestationMonthOf(d)));
    expect(new Set(tones).size).toBe(6);
  });
});

describe('gestationMonthOf', () => {
  it('floors days / 30 and returns null without usable days', () => {
    expect(gestationMonthOf(90)).toBe(3);
    expect(gestationMonthOf(119)).toBe(3);
    expect(gestationMonthOf(29)).toBe(0);
    expect(gestationMonthOf(0)).toBeNull();
    expect(gestationMonthOf(null)).toBeNull();
  });
});

describe('colorForKey: a colour belongs to a category, not to a position', () => {
  const keys = [
    'p-0', 'p-3', 'p-8', 'p-none',
    'v-CICLANDO', 'v-ESTATICA', 'v-OTRO', 'v-SIN_SUBTIPO', 'v-SIN_CONFIRMAR',
    'r-NR', 'r-RP', 'r-NO APTO', 'r-MATRIZ OCUPADA',
    'sin-resultado', 'sin-interpretar',
  ];

  it('returns the same colour for the same key every time, whatever was asked before', () => {
    const first = keys.map(colorForKey);
    const shuffled = [...keys].reverse().map(colorForKey).reverse();
    const again = keys.map(colorForKey);
    expect(shuffled).toEqual(first);
    expect(again).toEqual(first);
  });

  it('gives every category its own colour', () => {
    const colors = keys.map(colorForKey);
    expect(colors.every(c => HEX.test(c))).toBe(true);
    expect(new Set(colors).size).toBe(keys.length);
  });

  it('keeps each family in its own hue: pregnant greens, empty reds/pinks, ranch purples', () => {
    const hue = (hex: string): number => {
      const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
      return (r as number) > (g as number) && (r as number) > (b as number) ? 0 : (g as number) > (r as number) && (g as number) >= (b as number) ? 1 : 2;
    };
    // 1 = green dominant, 0 = red dominant
    expect(['p-1', 'p-5', 'p-8'].every(k => hue(colorForKey(k)) === 1)).toBe(true);
    expect(['v-CICLANDO', 'v-ESTATICA', 'v-OTRO', 'v-SIN_SUBTIPO'].every(k => hue(colorForKey(k)) === 0)).toBe(true);
  });

  it('the two greys of "no result" and "unconfirmed code" differ, and neither is a pregnant or empty colour', () => {
    expect(colorForKey('sin-resultado')).toBe(NO_RESULT_COLOR);
    expect(colorForKey('v-SIN_CONFIRMAR')).toBe(EMPTY_COLOR.SIN_CONFIRMAR);
    expect(NO_RESULT_COLOR).not.toBe(EMPTY_COLOR.SIN_CONFIRMAR);
    const taken = [...Object.values(RANCH_COLOR), ...Object.values(EMPTY_COLOR).filter(c => c !== EMPTY_COLOR.SIN_CONFIRMAR)];
    expect(taken).not.toContain(NO_RESULT_COLOR);
    expect(taken).not.toContain(EMPTY_COLOR.SIN_CONFIRMAR);
    expect(colorForKey('sin-interpretar')).toBe(UNINTERPRETED_COLOR);
  });

  it('falls back to a family colour or the grey for a key it does not know, never to something positional', () => {
    expect(colorForKey('r-ALGO NUEVO')).toBe(FAMILY_COLOR.ranch);
    expect(colorForKey('v-ALGO NUEVO')).toBe(FAMILY_COLOR.empty);
    expect(colorForKey('p-xyz')).toBe(NO_RESULT_COLOR);
    expect(colorForKey('otra-cosa')).toBe(NO_RESULT_COLOR);
    expect(colorForKey('')).toBe(NO_RESULT_COLOR);
  });

  it('has one colour per ranch term', () => {
    expect(new Set(Object.values(RANCH_COLOR)).size).toBe(4);
  });
});

describe('resultKeyOf / resultColorOf', () => {
  it('builds the key of each state and the chart, table and drawer all get the same colour from it', () => {
    expect(resultKeyOf({ state: 'PREÑADA', gestationDays: 150, subtype: null, ranchTerm: null })).toBe('p-5');
    expect(resultKeyOf({ state: 'PREÑADA', gestationDays: null, subtype: null, ranchTerm: null })).toBe('p-none');
    expect(resultKeyOf({ state: 'VACÍA', gestationDays: null, subtype: 'CICLANDO', ranchTerm: null })).toBe('v-CICLANDO');
    expect(resultKeyOf({ state: 'VACÍA', gestationDays: null, subtype: null, ranchTerm: null })).toBe('v-SIN_SUBTIPO');
    expect(resultKeyOf({ state: 'TERMINO_RANCHO', gestationDays: null, subtype: null, ranchTerm: 'RP' })).toBe('r-RP');
    expect(resultKeyOf({ state: 'TERMINO_RANCHO', gestationDays: null, subtype: null, ranchTerm: null })).toBeNull();
    expect(resultKeyOf({ state: 'SIN_RESULTADO', gestationDays: null, subtype: null, ranchTerm: null })).toBe('sin-resultado');
    expect(resultKeyOf({ state: 'SIN_INTERPRETAR', gestationDays: null, subtype: null, ranchTerm: null })).toBe('sin-interpretar');
    expect(resultColorOf({ state: 'PREÑADA', gestationDays: 150, subtype: null, ranchTerm: null })).toBe(colorForKey('p-5'));
    expect(resultColorOf({ state: 'TERMINO_RANCHO', gestationDays: null, subtype: null, ranchTerm: null })).toBe(NO_RESULT_COLOR);
  });

  it('colours the same gestation the same whether it comes as 90 or 119 days (same month)', () => {
    const a = resultColorOf({ state: 'PREÑADA', gestationDays: 90, subtype: null, ranchTerm: null });
    const b = resultColorOf({ state: 'PREÑADA', gestationDays: 119, subtype: null, ranchTerm: null });
    expect(a).toBe(b);
  });
});

describe('herd buckets and label contrast', () => {
  it('gives every herd bucket of the chart its own colour', () => {
    expect(new Set(Object.values(BUCKET_COLOR)).size).toBe(4);
    expect(bucketColor('vigente')).toBe(BUCKET_COLOR.vigente);
    expect(bucketColor('vendido')).toBe(NO_RESULT_COLOR);
  });

  it('picks white text on dark bars and dark text on light bars', () => {
    expect(labelColorOn(pregnantColor(8))).toBe('#ffffff');
    expect(labelColorOn(pregnantColor(0))).toBe('#1d273b');
    expect(labelColorOn(EMPTY_COLOR.OTRO)).toBe('#ffffff');
    expect(labelColorOn(EMPTY_COLOR.SIN_SUBTIPO)).toBe('#1d273b');
  });
});
