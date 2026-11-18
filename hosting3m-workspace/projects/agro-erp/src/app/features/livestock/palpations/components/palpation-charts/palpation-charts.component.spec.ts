import { Component, input } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { By } from '@angular/platform-browser';
import { NgApexchartsModule } from 'ng-apexcharts';
import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../../testing/palpation.fixtures';
import { PalpationChartsComponent } from './palpation-charts.component';

/** ApexCharts needs a real SVG engine; the test double keeps the inputs the template binds so they can be inspected. */
@Component({ selector: 'apx-chart', standalone: true, template: '<div class="apx-double"></div>' })
class ApexChartDouble {
  readonly series = input<unknown>();
  readonly chart = input<{ type?: string } | undefined>();
  readonly labels = input<string[] | undefined>();
  readonly plotOptions = input<unknown>();
  readonly xaxis = input<unknown>();
  readonly dataLabels = input<{ enabled?: boolean } | undefined>();
  readonly legend = input<unknown>();
  readonly colors = input<unknown>();
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
  TestBed.overrideComponent(PalpationChartsComponent, { remove: { imports: [NgApexchartsModule] }, add: { imports: [ApexChartDouble] } });
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
