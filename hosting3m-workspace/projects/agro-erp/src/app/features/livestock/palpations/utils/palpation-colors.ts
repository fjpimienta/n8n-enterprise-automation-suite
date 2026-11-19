import { RanchTerm } from '../models/palpation.types';
import { AnimalState, EmptySubtype, HerdBucket } from './palpation-metrics';

/**
 * Fixed colours of the palpation report. A colour belongs to a CATEGORY, never to a position in a list: the same category has the same colour
 * in the charts, the KPI cards, the table and the drawer, whatever the period, the filters or the order of the data.
 *
 * Families (hue): pregnant = green, empty = red/pink, ranch terms = purple, unresolved = greys (and amber for "unrecognised").
 * Pregnant is a SEQUENTIAL scale by gestation month (more months = darker). Colour is never the only signal: every place that uses these colours
 * also writes the name and the number.
 */

/** Result key of a latest-event bucket: `p-<months|none>`, `v-<SUBTYPE>`, `r-<TERM>`, `sin-resultado`, `sin-interpretar`. */
export type ResultKey = string;

/** Last month step of the pregnant scale: 8 months or more share the darkest tone. */
export const PREGNANT_MAX_MONTH = 8;

function hslToHex(h: number, s: number, l: number): string {
  const sat = s / 100;
  const light = l / 100;
  const a = sat * Math.min(light, 1 - light);
  const channel = (n: number): string => {
    const k = (n + h / 30) % 12;
    const v = light - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
    return Math.round(v * 255).toString(16).padStart(2, '0');
  };
  return `#${channel(0)}${channel(8)}${channel(4)}`;
}

/** Whole gestation months of a PREÑADA animal (`floor(days / 30)`), or null when there is no usable gestation. */
export function gestationMonthOf(days: number | null): number | null {
  return days !== null && days > 0 ? Math.floor(days / 30) : null;
}

/** Green scale: month 0 (under one month) is the lightest, `PREGNANT_MAX_MONTH` or more the darkest. */
export function pregnantColor(months: number | null): string {
  if (months === null) return PREGNANT_WITHOUT_GESTATION;
  const step = Math.max(0, Math.min(PREGNANT_MAX_MONTH, Math.floor(months)));
  return hslToHex(134, 42, 72 - 6 * step);
}

/** Pregnant with no usable gestation: a desaturated green-grey, outside the scale. */
export const PREGNANT_WITHOUT_GESTATION = '#86a08f';

export const EMPTY_COLOR: Readonly<Record<EmptySubtype, string>> = {
  CICLANDO: '#f28b82',
  ESTATICA: '#d63939',
  OTRO: '#8c1d1d',
  SIN_SUBTIPO: '#f5b5cd',
  /** An unconfirmed code is never interpreted, so it leaves the red family and goes grey. */
  SIN_CONFIRMAR: '#5f6b7a',
};

export const RANCH_COLOR: Readonly<Record<RanchTerm, string>> = {
  NR: '#d9b8e8',
  RP: '#bf59d9',
  'MATRIZ OCUPADA': '#8f2fa8',
  'NO APTO': '#5b1f6e',
};

export const NO_RESULT_COLOR = '#9aa4b2';
export const UNINTERPRETED_COLOR = '#d39e00';

/** One colour per family, for the monthly chart (its series are families) and for headings. */
export const FAMILY_COLOR = {
  pregnant: pregnantColor(4),
  empty: '#d63939',
  ranch: '#bf59d9',
  noResult: NO_RESULT_COLOR,
  historical: '#f76707',
} as const;

/** Colour of a result key. An unknown key falls back to the grey of "no result": a colour is never taken from a position. */
export function colorForKey(key: ResultKey): string {
  if (key === 'sin-resultado') return NO_RESULT_COLOR;
  if (key === 'sin-interpretar') return UNINTERPRETED_COLOR;
  if (key.startsWith('p-')) {
    const rest = key.slice(2);
    return rest === 'none' ? PREGNANT_WITHOUT_GESTATION : /^\d+$/.test(rest) ? pregnantColor(Number(rest)) : NO_RESULT_COLOR;
  }
  if (key.startsWith('v-')) return (EMPTY_COLOR as Record<string, string | undefined>)[key.slice(2)] ?? FAMILY_COLOR.empty;
  if (key.startsWith('r-')) return (RANCH_COLOR as Record<string, string | undefined>)[key.slice(2)] ?? FAMILY_COLOR.ranch;
  return NO_RESULT_COLOR;
}

export interface ResultKeyInput {
  readonly state: AnimalState;
  readonly gestationDays: number | null;
  readonly subtype: EmptySubtype | null;
  readonly ranchTerm: RanchTerm | null;
}

/** The result key of an animal's latest event. The same function builds the chart items and colours the table and the drawer. */
export function resultKeyOf(i: ResultKeyInput): ResultKey | null {
  switch (i.state) {
    case 'PREÑADA':
      return `p-${gestationMonthOf(i.gestationDays) ?? 'none'}`;
    case 'VACÍA':
      return `v-${i.subtype ?? 'SIN_SUBTIPO'}`;
    case 'TERMINO_RANCHO':
      return i.ranchTerm === null ? null : `r-${i.ranchTerm}`;
    case 'SIN_RESULTADO':
      return 'sin-resultado';
    case 'SIN_INTERPRETAR':
      return 'sin-interpretar';
  }
}

/** Colour of the badge of a result, or the grey of "no result" for a term-less ranch state. */
export function resultColorOf(i: ResultKeyInput): string {
  const key = resultKeyOf(i);
  return key === null ? NO_RESULT_COLOR : colorForKey(key);
}

/** Herd buckets (chart 3) are their own palette: blue = palpated (this campaign dark, older light), orange = historical load, slate = not palpated. */
export const BUCKET_COLOR: Readonly<Record<'vigente' | 'anterior' | 'historico' | 'sin-palpar', string>> = {
  vigente: '#206bc4',
  anterior: '#74b0e8',
  historico: '#f76707',
  'sin-palpar': '#6c7a89',
};

export function bucketColor(bucket: HerdBucket): string {
  return (BUCKET_COLOR as Record<string, string | undefined>)[bucket] ?? NO_RESULT_COLOR;
}

/** Relative luminance (WCAG) of a `#rrggbb` colour. */
export function luminance(hex: string): number {
  const c = [1, 3, 5].map(i => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * (c[0] ?? 0) + 0.7152 * (c[1] ?? 0) + 0.0722 * (c[2] ?? 0);
}

/** Text colour that reads on a bar of the given colour. */
export function labelColorOn(hex: string): string {
  return luminance(hex) > 0.35 ? '#1d273b' : '#ffffff';
}
