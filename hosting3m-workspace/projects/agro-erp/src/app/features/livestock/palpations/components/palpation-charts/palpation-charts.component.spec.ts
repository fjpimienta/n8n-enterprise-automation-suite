import { Component, input } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { By } from '@angular/platform-browser';
import { NgApexchartsModule } from 'ng-apexcharts';
import { beforeEach, describe, expect, it } from 'vitest';
import { ThemeService } from '@core/services/theme.service';
import { eventRow, herdRow } from '../../testing/palpation.fixtures';
import { BUCKET_COLOR, FAMILY_COLOR, colorForKey } from '../../utils/palpation-colors';
import { PalpationChartsComponent } from './palpation-charts.component';

/** ApexCharts needs a real SVG engine; the test double keeps the inputs the template binds so they can be inspected. */
@Component({ selector: 'apx-chart', standalone: true, template: '<div class="apx-double"></div>' })
class ApexChartDouble {
  readonly series = input<unknown>();
  readonly chart = input<{ type?: string; background?: string; foreColor?: string } | undefined>();
  readonly labels = input<string[] | undefined>();
  readonly plotOptions = input<unknown>();
  readonly yaxis = input<unknown>();
  readonly grid = input<unknown>();
  readonly stroke = input<unknown>();
  readonly tooltip = input<{ x?: { formatter?: (v: unknown, o?: { dataPointIndex?: number }) => string } } | undefined>();
  readonly responsive = input<unknown>();
  readonly xaxis = input<{ categories?: string[] } | undefined>();
  readonly dataLabels = input<{ enabled?: boolean } | undefined>();
  readonly legend = input<unknown>();
  readonly colors = input<string[] | undefined>();
  readonly theme = input<{ mode?: string } | undefined>();
}

const PERIOD = { from: '2026-09-11', to: '2026-11-10' };
const events = [
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90 }),
  eventRow({ livestock_id: 'A5', health_log_id: 'e5', event_date: '2026-10-05', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
];
const herd = [
  herdRow({ livestock_id: 'h1', category: 'VACA', last_event_date: '2026-11-01' }),
  herdRow({ livestock_id: 'h2', category: 'VACA', palpation_count: 0, last_event_date: null }),
  herdRow({ livestock_id: 'h3', category: 'TORO', palpation_count: 0, last_event_date: null }),
  herdRow({ livestock_id: 'h4', category: 'VACA', current_status: 'VENDIDO' }),
  herdRow({ livestock_id: 'h5', category: 'VACA', current_status: 'BAJA_MORTANDAD' }),
];

function render(over: { events?: typeof events; herd?: typeof herd } = {}): ComponentFixture<PalpationChartsComponent> {
  const fixture = TestBed.createComponent(PalpationChartsComponent);
  fixture.componentRef.setInput('events', over.events ?? events);
  fixture.componentRef.setInput('herd', over.herd ?? herd);
  fixture.componentRef.setInput('period', PERIOD);
  fixture.componentRef.setInput('campaign', '2026-09-11');
  fixture.detectChanges();
  return fixture;
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const click = (f: ComponentFixture<unknown>, testId: string) => {
  (el(f).querySelector(`[data-testid="${testId}"]`) as HTMLButtonElement).click();
  f.detectChanges();
};

describe('PalpationChartsComponent', () => {
  beforeEach(() => {
    TestBed.overrideComponent(PalpationChartsComponent, { remove: { imports: [NgApexchartsModule] }, add: { imports: [ApexChartDouble] } });
  });

  it('renders the three charts, each in a role="img" container with a text summary of its data', () => {
    const f = render();
    const imgs = [...el(f).querySelectorAll('[role="img"]')];
    expect(imgs.length).toBe(3);
    const labels = imgs.map(i => i.getAttribute('aria-label') ?? '');
    expect(labels[0]).toContain('Preñada · 3 meses, 1');
    expect(labels[1]).toContain('10/2026');
    expect(labels[2]).toContain('Vigente (campaña reciente), 1');
  });

  it('never depends on colour alone: every chart shows its numbers as data labels', () => {
    const f = render();
    const doubles = f.debugElement.queryAll(By.directive(ApexChartDouble)).map(d => d.componentInstance as ApexChartDouble);
    expect(doubles.length).toBe(3);
    for (const d of doubles) expect(d.dataLabels()?.enabled).toBe(true);
  });

  it('puts the count in the donut labels so the legend carries the number as text', () => {
    const f = render();
    const donut = f.debugElement.queryAll(By.directive(ApexChartDouble)).map(d => d.componentInstance as ApexChartDouble)[2]!;
    expect(donut.chart()?.type).toBe('donut');
    expect(donut.labels()?.every(l => /: \d+$/.test(l))).toBe(true);
  });

  it('follows the app theme', () => {
    const f = render();
    const first = f.debugElement.query(By.directive(ApexChartDouble)).componentInstance as ApexChartDouble;
    expect(['light', 'dark']).toContain(first.theme()?.mode);
  });

  const doubles = (f: ComponentFixture<unknown>) =>
    f.debugElement.queryAll(By.directive(ApexChartDouble)).map(d => d.componentInstance as ApexChartDouble);

  it('colours each bar of chart 1 by its category, not by its position', () => {
    const f = render();
    const bars = doubles(f)[0]!;
    // events: pregnant 3 months, empty UNE, ranch RP (the order of the items does not matter for the colour)
    expect(bars.colors()).toEqual([colorForKey('p-3'), colorForKey('v-ESTATICA'), colorForKey('r-RP')]);
    // adding an animal with another result must not change the colour of the existing categories
    const g = render({
      events: [...events, eventRow({ livestock_id: 'A9', health_log_id: 'e9', event_date: '2026-10-10', result: 'PREÑADA', gestation_days: 30 })],
    });
    const more = doubles(g)[0]!;
    expect(more.colors()).toContain(colorForKey('p-1'));
    for (const c of bars.colors() ?? []) expect(more.colors()).toContain(c);
  });

  it('uses the family colours in the monthly chart and the bucket colours in the donut', () => {
    const f = render();
    const [, monthly, donut] = doubles(f);
    expect(monthly!.colors()).toEqual([FAMILY_COLOR.pregnant, FAMILY_COLOR.empty, FAMILY_COLOR.ranch, FAMILY_COLOR.noResult, FAMILY_COLOR.historical]);
    expect(donut!.colors()).toEqual([BUCKET_COLOR.vigente, BUCKET_COLOR.anterior, BUCKET_COLOR.historico, BUCKET_COLOR['sin-palpar']]);
  });

  it('writes short names on the axis (no ellipsis) and the full name in the tooltip and in the table', () => {
    const f = render();
    const bars = doubles(f)[0]!;
    expect(bars.xaxis()?.categories).toEqual(['Preñada · 3 m', 'Vacía · Estática', 'Rancho · RP']);
    expect((bars.xaxis()?.categories ?? []).some(c => c.includes('…'))).toBe(false);
    const tooltip = bars.tooltip()?.x?.formatter;
    expect(tooltip?.(0, { dataPointIndex: 1 })).toBe('Vacía · Estática (UNE)');
    expect(tooltip?.(0, { dataPointIndex: 2 })).toBe('Definido por el rancho · RP');
    expect(tooltip?.(0, {})).toBe('');
    click(f, 'toggle-distribution');
    expect(el(f).querySelector('[data-testid="table-distribution"]')?.textContent).toContain('Vacía · Estática (UNE)');
  });

  it('repeats the chart colours as colour samples in the equivalent tables', () => {
    const f = render();
    click(f, 'toggle-distribution');
    const dots = [...el(f).querySelectorAll('[data-testid="table-distribution"] .palp-swatch')] as HTMLElement[];
    expect(dots.length).toBe(3);
    expect(dots.every(d => d.getAttribute('aria-hidden') === 'true')).toBe(true);
  });

  it('gives the charts a transparent background and theme-dependent text, so they sit on the card in dark and light', () => {
    const theme = TestBed.inject(ThemeService);
    theme.currentTheme.set('dark');
    const dark = render();
    const darkFore = doubles(dark)[0]!.chart()?.foreColor;
    expect(doubles(dark).every(d => d.chart()?.background === 'transparent')).toBe(true);
    expect(doubles(dark)[0]!.theme()?.mode).toBe('dark');
    theme.currentTheme.set('light');
    const light = render();
    expect(doubles(light).every(d => d.chart()?.background === 'transparent')).toBe(true);
    expect(doubles(light)[0]!.theme()?.mode).toBe('light');
    expect(doubles(light)[0]!.chart()?.foreColor).not.toBe(darkFore);
  });

  it('shows the equivalent table for each chart when its button is pressed, and hides it again', () => {
    const f = render();
    for (const [toggle, table] of [['toggle-distribution', 'table-distribution'], ['toggle-monthly', 'table-monthly'], ['toggle-herd', 'table-herd']] as const) {
      const btn = el(f).querySelector(`[data-testid="${toggle}"]`) as HTMLButtonElement;
      expect(btn.getAttribute('aria-expanded')).toBe('false');
      expect(el(f).querySelector(`[data-testid="${table}"]`)).toBeNull();
      click(f, toggle);
      expect(btn.getAttribute('aria-expanded')).toBe('true');
      expect(btn.textContent).toContain('Ocultar tabla');
      const t = el(f).querySelector(`[data-testid="${table}"]`) as HTMLTableElement;
      expect(t).not.toBeNull();
      expect(t.querySelector('caption')?.textContent?.length).toBeGreaterThan(5);
      expect(t.querySelectorAll('th[scope="col"]').length).toBeGreaterThan(1);
      click(f, toggle);
      expect(el(f).querySelector(`[data-testid="${table}"]`)).toBeNull();
    }
  });

  it('lists the same numbers in the alternative tables', () => {
    const f = render();
    click(f, 'toggle-distribution');
    const rows = [...el(f).querySelectorAll('[data-testid="table-distribution"] tbody tr')].map(
      r => `${r.querySelector('th')?.textContent?.trim()} | ${r.querySelector('td')?.textContent?.trim()}`,
    );
    expect(rows).toContain('Preñada · 3 meses | 1');
    expect(rows).toContain('Vacía · Estática (UNE) | 1');
    expect(rows).toContain('Definido por el rancho · RP | 1');
    click(f, 'toggle-monthly');
    expect(el(f).querySelector('[data-testid="table-monthly"] tbody')?.textContent).toContain('09/2026');
  });

  it('keeps sold animals and mortality in their own legend, with the "por palpar" figure and its denominator', () => {
    const f = render();
    const legend = el(f).querySelector('[data-testid="herd-legend"]')?.textContent?.replace(/\s+/g, ' ') ?? '';
    expect(legend).toContain('Vendidos: 1');
    expect(legend).toContain('Baja por mortandad: 1');
    expect(legend).toContain('No aplica');
    const por = el(f).querySelector('[data-testid="por-palpar"]')?.textContent?.replace(/\s+/g, ' ') ?? '';
    expect(por).toContain('Por palpar en la campaña: 1 de 2 vacas y novillonas activas.');
  });

  it('shows a text instead of an empty chart when there is nothing in the period', () => {
    const f = render({ events: [] });
    expect(el(f).textContent).toContain('Sin datos en el periodo.');
    expect(el(f).querySelectorAll('[role="img"]').length).toBe(1); // only the herd chart remains
  });
});
