import { PalpationEventRow, PalpationHerdRow } from '../models/palpation.types';
import {
  EmptySubtype,
  Period,
  animalState,
  emptySubtypeOf,
  herdBucket,
  isInPeriod,
  latestPerAnimal,
  porPalpar,
} from './palpation-metrics';
import { bucketColor, colorForKey, gestationMonthOf } from './palpation-colors';
import { BUCKET_LABEL, SUBTYPE_LABEL } from './palpation-view';

/** Pure data of the three charts, plus the text that describes each one to a screen reader. No chart library here. */

export interface DistributionItem {
  /** Category key (`p-3`, `v-CICLANDO`, `r-RP`, ...). The colour depends on it and on nothing else. */
  readonly key: string;
  /** Full name: tooltip, table and screen-reader text. */
  readonly label: string;
  /** Short name for the axis of the chart: never needs an ellipsis. */
  readonly short: string;
  readonly color: string;
  readonly count: number;
}

const SUBTYPE_ORDER: readonly EmptySubtype[] = ['ESTATICA', 'CICLANDO', 'OTRO', 'SIN_SUBTIPO', 'SIN_CONFIRMAR'];

const SHORT_SUBTYPE: Readonly<Record<EmptySubtype, string>> = {
  ESTATICA: 'Vacía · Estática',
  CICLANDO: 'Vacía · Ciclando',
  OTRO: 'Vacía · Otro',
  SIN_SUBTIPO: 'Vacía · Sin detalle',
  SIN_CONFIRMAR: 'Vacía · Sin confirmar',
};

function shortMonths(months: number | null): string {
  if (months === null) return 'Preñada · sin dato';
  return months < 1 ? 'Preñada · <1 m' : `Preñada · ${months} m`;
}

function monthsLabel(months: number | null): string {
  if (months === null) return 'Preñada · sin dato de gestación';
  if (months < 1) return 'Preñada · menos de 1 mes';
  return `Preñada · ${months} ${months === 1 ? 'mes' : 'meses'}`;
}

/**
 * Chart 1: result of the latest counted event of each animal in the period. Pregnant animals by gestation month (an animal
 * with no usable gestation is its own item), empty animals by structured sub-type, ranch terms, and the animals with no result or an
 * unrecognised one. Zero items are left out. The counts add up to the animals palpated in the period.
 */
export function resultDistribution(events: readonly PalpationEventRow[], period: Period): DistributionItem[] {
  const buckets = new Map<string, { order: number; label: string; short: string; count: number }>();
  const add = (key: string, order: number, label: string, short: string): void => {
    const current = buckets.get(key);
    if (current) current.count += 1;
    else buckets.set(key, { order, label, short, count: 1 });
  };

  for (const e of latestPerAnimal(events, period).values()) {
    switch (animalState(e)) {
      case 'PREÑADA': {
        const months = gestationMonthOf(e.gestation_days);
        add(`p-${months ?? 'none'}`, months === null ? 99 : months, monthsLabel(months), shortMonths(months));
        break;
      }
      case 'VACÍA': {
        const subtype = emptySubtypeOf(e);
        add(`v-${subtype}`, 100 + SUBTYPE_ORDER.indexOf(subtype), `Vacía · ${SUBTYPE_LABEL[subtype]}`, SHORT_SUBTYPE[subtype]);
        break;
      }
      case 'TERMINO_RANCHO':
        if (e.ranch_term !== null) add(`r-${e.ranch_term}`, 200, `Definido por el rancho · ${e.ranch_term}`, `Rancho · ${e.ranch_term}`);
        break;
      case 'SIN_RESULTADO':
        add('sin-resultado', 300, 'Sin resultado', 'Sin resultado');
        break;
      case 'SIN_INTERPRETAR':
        add('sin-interpretar', 301, 'Sin interpretar', 'Sin interpretar');
        break;
    }
  }
  return [...buckets.entries()]
    .sort((a, b) => a[1].order - b[1].order || a[1].label.localeCompare(b[1].label, 'es'))
    .map(([key, v]) => ({ key, label: v.label, short: v.short, color: colorForKey(key), count: v.count }));
}

export interface MonthlySeries {
  readonly name: string;
  readonly data: readonly number[];
}

export interface MonthlyResults {
  /** `MM/YYYY`, ascending. */
  readonly months: readonly string[];
  readonly series: readonly MonthlySeries[];
}

const SERIES_NAMES = ['Preñada', 'Vacía', 'Término del rancho', 'Sin resultado o sin interpretar', 'Histórico (carga 2023)'] as const;

/**
 * Chart 2: counted events of the period by month of the palpation date. The 2023 bulk load is its own series, so its spike never hides
 * the rest. Counts events (not animals): an animal palpated twice appears twice.
 */
export function resultsByMonth(events: readonly PalpationEventRow[], period: Period): MonthlyResults {
  const byMonth = new Map<string, number[]>();
  for (const e of events) {
    if (!isInPeriod(e, period)) continue;
    const month = e.event_date.slice(0, 7); // YYYY-MM from the calendar date string
    const counts = byMonth.get(month) ?? [0, 0, 0, 0, 0];
    let index: number;
    if (e.is_historical_load) index = 4;
    else {
      switch (animalState(e)) {
        case 'PREÑADA': index = 0; break;
        case 'VACÍA': index = 1; break;
        case 'TERMINO_RANCHO': index = 2; break;
        default: index = 3;
      }
    }
    counts[index] = (counts[index] ?? 0) + 1;
    byMonth.set(month, counts);
  }
  const keys = [...byMonth.keys()].sort();
  return {
    months: keys.map(k => `${k.slice(5, 7)}/${k.slice(0, 4)}`),
    series: SERIES_NAMES.map((name, i) => ({ name, data: keys.map(k => byMonth.get(k)?.[i] ?? 0) })),
  };
}

export interface HerdBar {
  readonly bucket: 'vigente' | 'anterior' | 'historico' | 'sin-palpar';
  readonly label: string;
  readonly color: string;
  readonly count: number;
}

export interface HerdSummary {
  readonly bars: readonly HerdBar[];
  /** Outside the chart: sold and mortality in their own legend, and the animals the report does not apply to. */
  readonly legend: {
    readonly vendido: number;
    readonly bajaMortandad: number;
    readonly noAplica: number;
    readonly fueraDelHato: number;
  };
  readonly porPalpar: { readonly eligible: number; readonly porPalpar: number };
}

/** Chart 3: the whole herd of the company by palpation bucket. */
export function herdSummary(herd: readonly PalpationHerdRow[], campaign: string | null): HerdSummary {
  const counts = { vigente: 0, anterior: 0, historico: 0, 'sin-palpar': 0, 'no-aplica': 0, 'baja-mortandad': 0, vendido: 0, 'fuera-del-hato': 0 };
  for (const row of herd) counts[herdBucket(row, campaign)] += 1;
  const order: HerdBar['bucket'][] = ['vigente', 'anterior', 'historico', 'sin-palpar'];
  return {
    bars: order.map(bucket => ({ bucket, label: BUCKET_LABEL[bucket], color: bucketColor(bucket), count: counts[bucket] })),
    legend: {
      vendido: counts.vendido,
      bajaMortandad: counts['baja-mortandad'],
      noAplica: counts['no-aplica'],
      fueraDelHato: counts['fuera-del-hato'],
    },
    porPalpar: porPalpar(herd, campaign),
  };
}

/** Text for the `aria-label` of chart 1. */
export function describeDistribution(items: readonly DistributionItem[]): string {
  if (items.length === 0) return 'Resultado del último evento por animal: sin datos en el periodo.';
  return `Resultado del último evento por animal: ${items.map(i => `${i.label}, ${i.count}`).join('; ')}.`;
}

/** Text for the `aria-label` of chart 2. */
export function describeMonthly(data: MonthlyResults): string {
  if (data.months.length === 0) return 'Palpaciones por mes: sin datos en el periodo.';
  const parts = data.months.map((m, i) => {
    const detail = data.series.filter(s => (s.data[i] ?? 0) > 0).map(s => `${s.name} ${s.data[i]}`).join(', ');
    return `${m}: ${detail}`;
  });
  return `Palpaciones por mes: ${parts.join('; ')}.`;
}

/** Text for the `aria-label` of chart 3. */
export function describeHerd(s: HerdSummary): string {
  const bars = s.bars.map(b => `${b.label}, ${b.count}`).join('; ');
  const legend = `Aparte: vendidos ${s.legend.vendido}, baja por mortandad ${s.legend.bajaMortandad}, no aplica ${s.legend.noAplica}.`;
  return `Estado del hato: ${bars}. ${legend}`;
}
