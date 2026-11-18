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
import {
  describeDistribution,
  describeHerd,
  describeMonthly,
  herdSummary,
  resultDistribution,
  resultsByMonth,
} from '../../utils/palpation-chart-data';
import { Period } from '../../utils/palpation-metrics';

const BAR_COLORS = ['#2fb344', '#2fb344', '#2fb344', '#2fb344', '#d63939', '#d63939', '#d63939', '#d63939', '#ae3ec9', '#8b95a5', '#f76707'];
const MONTH_COLORS = ['#2fb344', '#d63939', '#ae3ec9', '#8b95a5', '#f76707'];
const HERD_COLORS = ['#2fb344', '#4299e1', '#f76707', '#8b95a5'];

/**
 * The three charts of the report. Each one sits in a `role="img"` container with a text summary in `aria-label`, shows its numbers as data
 * labels and legend text (colour is never the only signal), and has a button that reveals the same data as a table. Chart data comes from
 * pure functions; this component only shapes it for ApexCharts. Sold animals and mortality are in a separate legend, not in the bars.
 */
@Component({
  selector: 'app-palpation-charts',
  standalone: true,
  imports: [NgApexchartsModule],
  templateUrl: './palpation-charts.component.html',
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

  protected readonly distributionChart = computed(() => {
    const items = this.distribution();
    return {
      series: [{ name: 'Animales', data: items.map(i => i.count) }] as ApexAxisChartSeries,
      chart: { type: 'bar', height: Math.max(220, items.length * 44 + 60), toolbar: { show: false } } as ApexChart,
      plotOptions: { bar: { horizontal: true, distributed: true, borderRadius: 3 } } as ApexPlotOptions,
      xaxis: { categories: items.map(i => i.label) } as ApexXAxis,
      dataLabels: { enabled: true } as ApexDataLabels,
      legend: { show: false } as ApexLegend,
      colors: BAR_COLORS,
    };
  });

  protected readonly monthlyChart = computed(() => {
    const data = this.monthly();
    return {
      series: data.series.map(s => ({ name: s.name, data: [...s.data] })) as ApexAxisChartSeries,
      chart: { type: 'bar', stacked: true, height: 320, toolbar: { show: false } } as ApexChart,
      plotOptions: { bar: { columnWidth: '55%' } } as ApexPlotOptions,
      xaxis: { categories: [...data.months] } as ApexXAxis,
      dataLabels: { enabled: true } as ApexDataLabels,
      legend: { position: 'bottom' } as ApexLegend,
      colors: MONTH_COLORS,
    };
  });

  protected readonly herdChart = computed(() => {
    const bars = this.herdData().bars;
    return {
      series: bars.map(b => b.count) as ApexNonAxisChartSeries,
      labels: bars.map(b => `${b.label}: ${b.count}`),
      chart: { type: 'donut', height: 300 } as ApexChart,
      dataLabels: {
        enabled: true,
        formatter: (_value: number, opts: { seriesIndex: number; w: { config: { series: number[] } } }) =>
          String(opts.w.config.series[opts.seriesIndex] ?? 0),
      } as ApexDataLabels,
      legend: { position: 'bottom' } as ApexLegend,
      colors: HERD_COLORS,
    };
  });

  protected readonly herdTotal = computed(() => this.herdData().bars.reduce((sum, b) => sum + b.count, 0));
  protected readonly monthlyHasData = computed(() => this.monthly().months.length > 0);
}
