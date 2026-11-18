import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { ThemeService } from '@core/services/theme.service';
import {
  ApexAxisChartSeries,
  ApexChart,
  ApexDataLabels,
  ApexLegend,
  ApexNonAxisChartSeries,
  ApexPlotOptions,
  ApexXAxis,
  NgApexchartsModule,
} from 'ng-apexcharts';
import { PalpationEventRow, PalpationHerdRow } from '../../models/palpation.types';
import { FAMILY_COLOR, labelColorOn } from '../../utils/palpation-colors';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';
import {
  describeDistribution,
  describeHerd,
  describeMonthly,
  herdSummary,
  resultDistribution,
  resultsByMonth,
} from '../../utils/palpation-chart-data';
import { Period } from '../../utils/palpation-metrics';

/** Colours of the monthly series, one per family, in the order of `resultsByMonth`: the same families as the cards and the table. */
const MONTH_COLORS: readonly string[] = [FAMILY_COLOR.pregnant, FAMILY_COLOR.empty, FAMILY_COLOR.ranch, FAMILY_COLOR.noResult, FAMILY_COLOR.historical];

/** Text, grid and tooltip colours per theme. The chart background is always transparent so it takes the colour of its card. */
const THEME_TOKENS = {
  dark: { fore: '#cbd5e1', grid: '#2d3a4f' },
  light: { fore: '#374151', grid: '#e3e6ea' },
} as const;

/**
 * Phone breakpoint of the horizontal bar chart and the width reserved for its axis labels. ApexCharts cuts a label that is wider than this
 * with "..." and keeps the full text in a <title>; the longest short name ("Rancho · MATRIZ OCUPADA") has to fit, so it is measured in a real
 * browser at both sizes (desktop 12px, phone 11px) and not guessed.
 */
const PHONE_MAX_WIDTH = 576;
const AXIS_LABEL_MAX_WIDTH = 215;
const AXIS_LABEL_MAX_WIDTH_PHONE = 200;

/**
 * The three charts of the report. Each one sits in a `role="img"` container with a text summary in `aria-label`, shows its numbers as data
 * labels and legend text (colour is never the only signal), and has a button that reveals the same data as a table. Chart data comes from
 * pure functions; this component only shapes it for ApexCharts. Sold animals and mortality are in a separate legend, not in the bars.
 */
@Component({
  selector: 'app-palpation-charts',
  standalone: true,
  imports: [NgApexchartsModule, PalpationSwatchComponent],
  templateUrl: './palpation-charts.component.html',
  // In the dark theme the stock outline-secondary button is grey on near-black (low contrast): lighten text and border there only.
  styles: [
    `
      :host-context([data-bs-theme='dark']) .palp-toggle {
        color: #c3cedc;
        border-color: #8696ab;
      }
      :host-context([data-bs-theme='dark']) .palp-toggle:hover {
        color: #ffffff;
        background-color: #4a5a70;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationChartsComponent {
  protected readonly themeService = inject(ThemeService);

  readonly events = input.required<readonly PalpationEventRow[]>();
  readonly herd = input.required<readonly PalpationHerdRow[]>();
  readonly period = input.required<Period>();
  /** Start of the campaign (`YYYY-MM-DD`), or null when the company has none. */
  readonly campaign = input<string | null>(null);

  protected readonly distribution = computed(() => resultDistribution(this.events(), this.period()));
  protected readonly monthly = computed(() => resultsByMonth(this.events(), this.period()));
  protected readonly herdData = computed(() => herdSummary(this.herd(), this.campaign()));

  protected readonly distributionLabel = computed(() => describeDistribution(this.distribution()));
  protected readonly monthlyLabel = computed(() => describeMonthly(this.monthly()));
  protected readonly herdLabel = computed(() => describeHerd(this.herdData()));

  protected readonly showDistributionTable = signal(false);
  protected readonly showMonthlyTable = signal(false);
  protected readonly showHerdTable = signal(false);

  protected readonly themeMode = computed(() => ({ mode: this.themeService.currentTheme() }));
  protected readonly tokens = computed(() => THEME_TOKENS[this.themeService.currentTheme()]);
  protected readonly monthlyColors = MONTH_COLORS;

  protected readonly distributionChart = computed(() => {
    const items = this.distribution();
    const t = this.tokens();
    const fullNames = items.map(i => i.label);
    const max = Math.max(1, ...items.map(i => i.count));
    return {
      series: [{ name: 'Animales', data: items.map(i => i.count) }] as ApexAxisChartSeries,
      chart: {
        type: 'bar',
        height: Math.max(220, items.length * 40 + 60),
        toolbar: { show: false },
        background: 'transparent',
        foreColor: t.fore,
      } as ApexChart,
      plotOptions: { bar: { horizontal: true, distributed: true, borderRadius: 3, barHeight: '72%' } } as ApexPlotOptions,
      xaxis: { categories: items.map(i => i.short), tickAmount: Math.min(max, 5), labels: { formatter: (v: string) => String(Math.round(Number(v))) } } as ApexXAxis,
      yaxis: { labels: { maxWidth: AXIS_LABEL_MAX_WIDTH, style: { fontSize: '12px' } } },
      // Each bar's own colour comes from its category; the number inside is dark or white depending on that colour.
      dataLabels: { enabled: true, style: { colors: items.map(i => labelColorOn(i.color)), fontSize: '12px' } } as ApexDataLabels,
      legend: { show: false } as ApexLegend,
      colors: items.map(i => i.color),
      grid: { borderColor: t.grid },
      stroke: { show: true, width: 1, colors: ['transparent'] },
      tooltip: {
        x: { formatter: (_value: unknown, opts?: { dataPointIndex?: number }) => fullNames[opts?.dataPointIndex ?? -1] ?? '' },
        y: {
          title: { formatter: () => '' },
          formatter: (v: number) => `${v} ${v === 1 ? 'animal' : 'animales'}`,
        },
      },
      responsive: [{ breakpoint: PHONE_MAX_WIDTH, options: { yaxis: { labels: { maxWidth: AXIS_LABEL_MAX_WIDTH_PHONE, style: { fontSize: '11px' } } }, dataLabels: { style: { fontSize: '11px' } } } }],
    };
  });

  protected readonly monthlyChart = computed(() => {
    const data = this.monthly();
    const t = this.tokens();
    return {
      series: data.series.map(s => ({ name: s.name, data: [...s.data] })) as ApexAxisChartSeries,
      chart: { type: 'bar', stacked: true, height: 320, toolbar: { show: false }, background: 'transparent', foreColor: t.fore } as ApexChart,
      plotOptions: { bar: { columnWidth: '55%' } } as ApexPlotOptions,
      xaxis: { categories: [...data.months] } as ApexXAxis,
      yaxis: { labels: { formatter: (v: number) => String(Math.round(v)) } },
      dataLabels: { enabled: true, style: { colors: ['#ffffff'] } } as ApexDataLabels,
      legend: { position: 'bottom', labels: { colors: t.fore } } as ApexLegend,
      colors: [...MONTH_COLORS],
      grid: { borderColor: t.grid },
      stroke: { show: true, width: 1, colors: ['transparent'] },
      tooltip: { y: { formatter: (v: number) => `${v} ${v === 1 ? 'evento' : 'eventos'}` } },
    };
  });

  protected readonly herdChart = computed(() => {
    const bars = this.herdData().bars;
    const t = this.tokens();
    return {
      series: bars.map(b => b.count) as ApexNonAxisChartSeries,
      labels: bars.map(b => `${b.label}: ${b.count}`),
      chart: { type: 'donut', height: 300, background: 'transparent', foreColor: t.fore } as ApexChart,
      plotOptions: {
        pie: {
          donut: {
            size: '62%',
            labels: {
              show: true,
              name: { color: t.fore },
              value: { color: t.fore },
              total: { show: true, label: 'En el gráfico', color: t.fore, formatter: () => String(this.herdTotal()) },
            },
          },
        },
      } as ApexPlotOptions,
      stroke: { show: true, width: 2, colors: ['transparent'] },
      dataLabels: {
        enabled: true,
        formatter: (_value: number, opts: { seriesIndex: number; w: { config: { series: number[] } } }) =>
          String(opts.w.config.series[opts.seriesIndex] ?? 0),
      } as ApexDataLabels,
      legend: { position: 'bottom', labels: { colors: t.fore } } as ApexLegend,
      colors: bars.map(b => b.color),
    };
  });

  protected readonly herdTotal = computed(() => this.herdData().bars.reduce((sum, b) => sum + b.count, 0));
  protected readonly monthlyHasData = computed(() => this.monthly().months.length > 0);
}
