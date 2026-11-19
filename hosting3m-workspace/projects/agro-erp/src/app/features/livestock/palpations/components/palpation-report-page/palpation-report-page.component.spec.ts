import { Component, computed, input, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Params, Router, convertToParamMap } from '@angular/router';
import { NgApexchartsModule } from 'ng-apexcharts';
import { describe, expect, it, vi } from 'vitest';
import { PalpationEventRow, PalpationHerdRow, ReportErrorReason, ReportStatus } from '../../models/palpation.types';
import { PalpationReportService } from '../../services/palpation-report.service';
import { eventRow, herdRow } from '../../testing/palpation.fixtures';
import { PalpationChartsComponent } from '../palpation-charts/palpation-charts.component';
import { PALPATION_TODAY, PalpationReportPageComponent } from './palpation-report-page.component';

@Component({ selector: 'apx-chart', standalone: true, template: '<div class="apx-double"></div>' })
class ApexChartDouble {
  readonly series = input<unknown>();
  readonly chart = input<unknown>();
  readonly labels = input<unknown>();
  readonly plotOptions = input<unknown>();
  readonly yaxis = input<unknown>();
  readonly grid = input<unknown>();
  readonly stroke = input<unknown>();
  readonly tooltip = input<unknown>();
  readonly responsive = input<unknown>();
  readonly xaxis = input<unknown>();
  readonly dataLabels = input<unknown>();
  readonly legend = input<unknown>();
  readonly colors = input<unknown>();
  readonly theme = input<unknown>();
}

/** The part of PalpationReportService the page reads, driven by signals the test can set. */
class FakeService {
  readonly status = signal<ReportStatus>('listo');
  readonly reason = signal<ReportErrorReason | null>(null);
  readonly events = signal<readonly PalpationEventRow[]>([]);
  readonly herd = signal<readonly PalpationHerdRow[]>([]);
  readonly tenantId = signal<number | null>(9101);
  readonly role = signal<string | null>('ADMIN');
  readonly unrecognizedCount = computed(() => this.events().filter(e => e.uninterpreted).length + this.herd().filter(h => h.uninterpreted).length);
  readonly load = vi.fn(() => Promise.resolve());
  readonly loadHistory = vi.fn(() => Promise.resolve({ ok: true as const, rows: [] as PalpationEventRow[] }));
}

const TODAY = '2026-11-18';
const events = [
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90 }),
  eventRow({ livestock_id: 'A3', health_log_id: 'e3', event_date: '2023-07-20', result: 'PREÑADA', is_historical_load: true }),
];
const herd = [
  herdRow({ livestock_id: 'A1', rfid_siniiga: '9999000001', category: 'VACA', current_status: 'VACÍA' }),
  herdRow({ livestock_id: 'A2', rfid_siniiga: '9999000002', category: 'VACA', current_status: 'PREÑADA' }),
  herdRow({ livestock_id: 'A3', rfid_siniiga: '9999000003', category: 'VACA', current_status: 'ACTIVO', last_is_historical: true, last_event_date: '2023-07-20' }),
];

/**
 * A stand-in for the address bar: the query parameters of the page and a `navigate` that applies the change the way the router does
 * (`merge`: a value of null removes the parameter), so the page can be tested reading and writing the address without a real router.
 */
function makeAddress(query: string) {
  const state: Record<string, string[]> = {};
  for (const [k, v] of new URLSearchParams(query)) (state[k] ??= []).push(v);
  const navigate = vi.fn((_commands: unknown[], extras: { queryParams: Params }) => {
    for (const [k, v] of Object.entries(extras.queryParams)) {
      if (v === null || v === undefined) delete state[k];
      else state[k] = [String(v)];
    }
    return Promise.resolve(true);
  });
  const route = { snapshot: { get queryParamMap() { return convertToParamMap(state); } } };
  return { navigate, route, state };
}

function setup(
  configure: (s: FakeService) => void = () => undefined,
  query = '',
): { f: ComponentFixture<PalpationReportPageComponent>; fake: FakeService; address: ReturnType<typeof makeAddress> } {
  const fake = new FakeService();
  fake.events.set(events);
  fake.herd.set(herd);
  configure(fake);
  const address = makeAddress(query);
  TestBed.configureTestingModule({
    providers: [
      { provide: PalpationReportService, useValue: fake },
      { provide: PALPATION_TODAY, useValue: () => TODAY },
      { provide: Router, useValue: { navigate: address.navigate } },
      { provide: ActivatedRoute, useValue: address.route },
    ],
  });
  TestBed.overrideComponent(PalpationChartsComponent, { remove: { imports: [NgApexchartsModule] }, add: { imports: [ApexChartDouble] } });
  const f = TestBed.createComponent(PalpationReportPageComponent);
  f.detectChanges();
  return { f, fake, address };
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const text = (f: ComponentFixture<unknown>) => el(f).textContent?.replace(/\s+/g, ' ').trim() ?? '';
const rowsText = (f: ComponentFixture<unknown>) => [...el(f).querySelectorAll('[data-testid="palp-table"] tbody tr')].map(r => r.textContent?.replace(/\s+/g, ' ').trim() ?? '');
function choose(f: ComponentFixture<unknown>, id: string, value: string): void {
  const select = el(f).querySelector<HTMLSelectElement>(`#${id}`)!;
  select.value = value;
  select.dispatchEvent(new Event('change'));
  f.detectChanges();
}

describe('PalpationReportPageComponent', () => {
  describe('states', () => {
    it('shows "sin tenant" and no content', () => {
      const { f } = setup(s => s.status.set('sin-tenant'));
      expect(text(f)).toContain('Selecciona una empresa');
      expect(el(f).querySelector('[data-testid="palp-table"]')).toBeNull();
    });

    it('shows "sin permiso" and no content', () => {
      const { f } = setup(s => s.status.set('sin-permiso'));
      expect(text(f)).toContain('Tu rol en esta empresa no permite ver el reporte de palpaciones');
      expect(el(f).querySelector('app-palpation-kpi-cards')).toBeNull();
    });

    it('shows the loading state', () => {
      expect(text(setup(s => s.status.set('cargando')).f)).toContain('Cargando palpaciones');
    });

    it('shows the empty state', () => {
      expect(text(setup(s => s.status.set('vacio')).f)).toContain('No hay palpaciones registradas');
    });

    it('shows an error with its reason and no figures, and retries', () => {
      const { f, fake } = setup(s => { s.status.set('error'); s.reason.set('empty-body'); });
      expect(text(f)).toContain('El servidor respondió sin datos.');
      expect(el(f).querySelector('app-palpation-kpi-cards')).toBeNull();
      fake.load.mockClear();
      (el(f).querySelector('[role="alert"] button') as HTMLButtonElement).click();
      expect(fake.load).toHaveBeenCalledTimes(1);
    });

    it('shows "sin campaña" when only the historical load exists, and "Ver todo el historial" opens it', () => {
      const { f } = setup(s => s.events.set([events[2]!]));
      expect(text(f)).toContain('Aún no hay palpaciones de una campaña reciente');
      (el(f).querySelector('button.btn-primary') as HTMLButtonElement).click();
      f.detectChanges();
      expect(el(f).querySelector('app-palpation-kpi-cards')).not.toBeNull();
      expect(text(f)).toContain('histórico (carga 2023)');
    });

    it('shows the truncation banner above the content', () => {
      const { f } = setup(s => s.status.set('truncado'));
      expect(text(f)).toContain('Reporte incompleto');
      expect(el(f).querySelector('app-palpation-kpi-cards')).not.toBeNull();
    });

    it('shows the unrecognised-values banner with the count', () => {
      const { f } = setup(s => s.events.set([...events, eventRow({ livestock_id: 'U', health_log_id: 'u', event_date: '2026-11-11', result: null, uninterpreted: true, is_clinical_result: false })]));
      expect(text(f)).toContain('1 registro tiene un resultado o un término que la aplicación no reconoce');
    });
  });

  describe('content', () => {
    it('loads on entry and reloads when the company changes', () => {
      const { f, fake } = setup();
      expect(fake.load).toHaveBeenCalledTimes(1);
      fake.tenantId.set(9102);
      f.detectChanges();
      expect(fake.load).toHaveBeenCalledTimes(2);
    });

    it('defaults to the recent campaign (anchor 10/11/2026 minus 60 days) and keeps the 2023 load out', () => {
      const { f } = setup();
      expect(el(f).querySelector('[data-testid="period-label"]')?.textContent).toContain('campaña reciente (11/09/2026 a 10/11/2026)');
      const rows = rowsText(f);
      expect(rows.length).toBe(2);
      expect(rows.join(' ')).not.toContain('9999000003');
    });

    it('shows the KPIs with their denominators, the charts and the table', () => {
      const { f } = setup();
      expect(el(f).querySelector('[data-testid="kpi-palpated"]')?.textContent?.trim()).toBe('2');
      expect(text(f)).toContain('de 2 con resultado clínico');
      expect(el(f).querySelectorAll('[role="img"]').length).toBe(3);
      expect(el(f).querySelector('[data-testid="palp-table"]')).not.toBeNull();
    });

    it('includes the historical load, with its badge, when the period is "todo el historial"', () => {
      const { f } = setup();
      choose(f, 'palp-period', 'todo');
      const rows = rowsText(f);
      expect(rows.length).toBe(3);
      expect(rows.join(' ')).toContain('histórico (carga 2023)');
      expect(el(f).querySelector('[data-testid="period-label"]')?.textContent).toContain('todo el historial');
    });

    it('applies a custom period from two dates', () => {
      const { f } = setup();
      choose(f, 'palp-period', 'personalizado');
      const from = el(f).querySelector<HTMLInputElement>('#palp-from')!;
      from.value = '2026-11-01';
      from.dispatchEvent(new Event('change'));
      f.detectChanges();
      expect(rowsText(f).length).toBe(1);
    });

    it('filters the table by result', () => {
      const { f } = setup();
      choose(f, 'palp-result', 'PREÑADA');
      const rows = rowsText(f);
      expect(rows.length).toBe(1);
      expect(rows[0]).toContain('9999000002');
    });

    it('filters the table by animal status, with the statuses taken from the data', () => {
      const { f } = setup();
      const options = [...el(f).querySelectorAll<HTMLOptionElement>('#palp-status option')].map(o => o.value);
      expect(options).toEqual(['TODOS', 'PREÑADA', 'VACÍA']);
      choose(f, 'palp-status', 'VACÍA');
      expect(rowsText(f).length).toBe(1);
    });

    it('sorts when a header is pressed, and reverses on a second press', () => {
      const { f } = setup();
      const header = () => el(f).querySelector<HTMLButtonElement>('[data-sort="identifier"]')!;
      header().click();
      f.detectChanges();
      expect(rowsText(f)[0]).toContain('9999000001');
      header().click();
      f.detectChanges();
      expect(rowsText(f)[0]).toContain('9999000002');
    });
  });

  describe('drawer', () => {
    it('opens from a row button as a dialog, closes with Escape and gives the focus back to that button', async () => {
      const { f, fake } = setup();
      const button = el(f).querySelector<HTMLButtonElement>('[data-testid="open-row"]')!;
      button.focus();
      button.click();
      f.detectChanges();
      await f.whenStable();
      f.detectChanges();
      const dialog = el(f).querySelector('[role="dialog"]');
      expect(dialog).not.toBeNull();
      expect(dialog?.getAttribute('aria-modal')).toBe('true');
      expect(fake.loadHistory).toHaveBeenCalled();
      dialog!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
      f.detectChanges();
      expect(el(f).querySelector('[role="dialog"]')).toBeNull();
      expect(document.activeElement).toBe(button);
    });
  });

  describe('campaign comparison tabs', () => {
    const tabButton = (f: ComponentFixture<unknown>, id: string) => el(f).querySelector<HTMLButtonElement>(`[data-tab="${id}"]`)!;
    const open = (f: ComponentFixture<unknown>, id: string) => {
      tabButton(f, id).click();
      f.detectChanges();
    };

    it('starts on "Resumen", unchanged, with three tabs that follow the ARIA tabs pattern', () => {
      const { f } = setup();
      const tabs = [...el(f).querySelectorAll('[role="tab"]')];
      expect(tabs.map(t => t.textContent?.trim())).toEqual(['Resumen', 'Comparar campañas', 'Todas las palpaciones']);
      expect(el(f).querySelector('[role="tablist"]')?.getAttribute('aria-label')).toBeTruthy();
      expect(tabButton(f, 'resumen').getAttribute('aria-selected')).toBe('true');
      expect(tabButton(f, 'comparar').getAttribute('aria-selected')).toBe('false');
      expect(tabButton(f, 'comparar').getAttribute('tabindex')).toBe('-1');
      expect(el(f).querySelector('[role="tabpanel"]')?.getAttribute('aria-labelledby')).toBe('palp-tab-resumen');
      expect(el(f).querySelector('app-palpation-kpi-cards')).not.toBeNull();
      expect(el(f).querySelector('app-palpation-campaign-compare')).toBeNull();
    });

    for (const status of ['sin-tenant', 'sin-permiso', 'cargando', 'error'] as const) {
      it(`shows no tabs and no comparison while the report is "${status}"`, () => {
        const { f } = setup(s => s.status.set(status));
        expect(el(f).querySelector('[role="tablist"]')).toBeNull();
        expect(el(f).querySelector('app-palpation-campaigns-editor')).toBeNull();
        expect(el(f).querySelector('app-palpation-campaign-compare')).toBeNull();
        expect(el(f).querySelector('app-palpation-event-list')).toBeNull();
      });
    }

    it('proposes the campaigns from the dates when the screen opens, and says they are only a proposal', () => {
      const { f } = setup();
      open(f, 'comparar');
      const rows = [...el(f).querySelectorAll('[data-testid="campaign-row"]')];
      // 2023-07-20, 2026-09-20 and 2026-11-10 are more than 7 days apart: three campaigns, the 2023 load included
      expect(rows.length).toBe(3);
      expect((rows[0]?.querySelector('[data-testid="campaign-from"]') as HTMLInputElement).value).toBe('2023-07-20');
      expect((rows[2]?.querySelector('[data-testid="campaign-to"]') as HTMLInputElement).value).toBe('2026-11-10');
      expect(text(f)).toContain('Propuesta automática');
    });

    it('shows the comparison with the neutral note, and the transition table of the two latest campaigns', () => {
      const { f } = setup();
      open(f, 'comparar');
      expect(el(f).querySelector('app-palpation-campaign-compare')).not.toBeNull();
      expect(el(f).querySelector('[data-testid="compare-note"]')?.textContent).toContain('no explica causas');
      expect(el(f).querySelector('[data-testid="transition-table"]')).not.toBeNull();
      expect(el(f).querySelector('[role="tabpanel"]')?.getAttribute('aria-labelledby')).toBe('palp-tab-comparar');
    });

    it('shows the full list of palpations with the campaign column and no technician', () => {
      const { f } = setup();
      open(f, 'todas');
      expect(el(f).querySelector('app-palpation-event-list')).not.toBeNull();
      expect(el(f).querySelectorAll('[data-testid="event-row"]').length).toBe(3);
      expect(text(f)).not.toContain('Técnico');
    });

    it('moves between the tabs with the arrow keys, Home and End', () => {
      const { f } = setup();
      const key = (k: string) => {
        document.activeElement?.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
        f.detectChanges();
      };
      tabButton(f, 'resumen').focus();
      key('ArrowRight');
      expect(tabButton(f, 'comparar').getAttribute('aria-selected')).toBe('true');
      expect(document.activeElement).toBe(tabButton(f, 'comparar'));
      key('End');
      expect(tabButton(f, 'todas').getAttribute('aria-selected')).toBe('true');
      key('ArrowRight');
      expect(tabButton(f, 'resumen').getAttribute('aria-selected')).toBe('true');
      key('ArrowLeft');
      expect(tabButton(f, 'todas').getAttribute('aria-selected')).toBe('true');
      key('Home');
      expect(tabButton(f, 'resumen').getAttribute('aria-selected')).toBe('true');
    });

    it('rejects an overlapping range with a message and hides the comparison and the list until it is fixed', () => {
      const { f } = setup();
      open(f, 'comparar');
      const to = el(f).querySelectorAll<HTMLInputElement>('[data-testid="campaign-to"]')[0]!;
      to.value = '2026-11-10'; // the first campaign now reaches the last one
      to.dispatchEvent(new Event('change', { bubbles: true }));
      f.detectChanges();
      expect(text(f)).toContain('se traslapa');
      expect(el(f).querySelector('app-palpation-campaign-compare')).toBeNull();
      expect(el(f).querySelector('[data-testid="campaigns-invalid"]')?.textContent).toContain('la comparación');
      open(f, 'todas');
      expect(el(f).querySelector('[data-testid="campaigns-invalid"]')?.textContent).toContain('la lista de palpaciones');
    });

    it('keeps the campaigns the user edited when switching tabs, and goes back to a proposal only when asked', () => {
      const { f } = setup();
      open(f, 'comparar');
      const label = el(f).querySelectorAll<HTMLInputElement>('[data-testid="campaign-label"]')[0]!;
      label.value = 'Carga histórica';
      label.dispatchEvent(new Event('change', { bubbles: true }));
      f.detectChanges();
      expect(text(f)).not.toContain('Propuesta automática');
      open(f, 'resumen');
      open(f, 'todas');
      expect(el(f).querySelectorAll<HTMLInputElement>('[data-testid="campaign-label"]')[0]?.value).toBe('Carga histórica');
      (el(f).querySelector('[data-testid="campaign-suggest"]') as HTMLButtonElement).click();
      f.detectChanges();
      expect(el(f).querySelectorAll<HTMLInputElement>('[data-testid="campaign-label"]')[0]?.value).toBe('Campaña 1');
      expect(text(f)).toContain('Propuesta automática');
    });

    it('gives the export of the follow-up lists the status and the company of the report: enabled when ready, disabled when truncated', () => {
      const ready = setup();
      open(ready.f, 'comparar');
      const button = () => el(ready.f).querySelector<HTMLButtonElement>('[data-testid="pairs-export"]')!;
      expect(button().disabled).toBe(false);
      ready.fake.status.set('truncado');
      ready.f.detectChanges();
      expect(button().disabled).toBe(true);
      expect(text(ready.f)).toContain('incompleto');
      ready.fake.status.set('listo');
      ready.fake.tenantId.set(null);
      ready.f.detectChanges();
      expect(el(ready.f).querySelector('[data-testid="pairs-export"]')?.hasAttribute('disabled') ?? true).toBe(true);
    });

    it('does not make a request of its own: the report loads once, and the comparison reads the same rows', () => {
      const { f, fake } = setup();
      open(f, 'comparar');
      open(f, 'todas');
      expect(fake.load).toHaveBeenCalledTimes(1);
      expect(fake.loadHistory).not.toHaveBeenCalled();
    });

    it('forgets the campaigns when the company changes (the service clears its rows first)', () => {
      const { f, fake } = setup();
      open(f, 'comparar');
      expect(el(f).querySelectorAll('[data-testid="campaign-row"]').length).toBe(3);
      fake.events.set([]);
      fake.herd.set([]);
      fake.tenantId.set(9102);
      f.detectChanges();
      fake.status.set('cargando');
      f.detectChanges();
      expect(el(f).querySelector('app-palpation-campaigns-editor')).toBeNull();
      fake.events.set([events[0] as PalpationEventRow]);
      fake.status.set('listo');
      f.detectChanges();
      open(f, 'comparar');
      // a single date gives no proposal: the other company starts with nothing instead of inheriting the old ranges
      expect(el(f).querySelectorAll('[data-testid="campaign-row"]').length).toBe(0);
      expect(text(f)).toContain('No se pudo proponer');
    });

    it('shows a warning above the tabs when the report is truncated, and it stays there on the new tabs', () => {
      const { f } = setup(s => s.status.set('truncado'));
      open(f, 'comparar');
      expect(text(f)).toContain('incompleto');
    });
  });

  describe('deep link to a matrix cell', () => {
    const A = '2026-09-20_2026-09-20';
    const B = '2026-11-10_2026-11-10';
    const VALID = `a=${A}&b=${B}&cell=sin-registro.vacia`;
    const tabButton = (f: ComponentFixture<unknown>, id: string) => el(f).querySelector<HTMLButtonElement>(`[data-tab="${id}"]`)!;
    const cellButton = (f: ComponentFixture<unknown>, from: string, to: string) => el(f).querySelector<HTMLButtonElement>(`[data-cell-button="${from}>${to}"]`)!;
    const campaignRows = (f: ComponentFixture<unknown>) =>
      [...el(f).querySelectorAll('[data-testid="campaign-row"]')].map(r => [
        (r.querySelector('[data-testid="campaign-from"]') as HTMLInputElement).value,
        (r.querySelector('[data-testid="campaign-to"]') as HTMLInputElement).value,
      ]);

    it('opens the comparison with the two campaigns of the link and the cell it names, once the data has arrived', () => {
      const { f } = setup(() => undefined, VALID);
      expect(tabButton(f, 'comparar').getAttribute('aria-selected')).toBe('true');
      expect(campaignRows(f)).toEqual([['2026-09-20', '2026-09-20'], ['2026-11-10', '2026-11-10']]);
      expect(el(f).querySelector('[data-testid="cell-title"]')?.textContent).toContain('Animales: Sin registro en Campaña A y Vacía en Campaña B');
      expect(el(f).querySelector('[data-testid="cell-count"]')?.textContent).toContain('1');
      expect(cellButton(f, 'NO_PALPADA', 'VACÍA').getAttribute('aria-pressed')).toBe('true');
    });

    it('opens the comparison without a cell when the link only names the two campaigns', () => {
      const { f } = setup(() => undefined, `a=${A}&b=${B}`);
      expect(tabButton(f, 'comparar').getAttribute('aria-selected')).toBe('true');
      expect(campaignRows(f).length).toBe(2);
      expect(el(f).querySelector('[data-testid="cell-section"]')).toBeNull();
    });

    it('does not rewrite the address when it already says what the page shows', () => {
      const { address } = setup(() => undefined, VALID);
      expect(address.navigate).not.toHaveBeenCalled();
    });

    it.each([
      ['an impossible date', `a=2026-13-01_2026-13-02&b=${B}&cell=vacia.vacia`],
      ['a missing campaign', `a=${A}&cell=vacia.vacia`],
      ['a repeated parameter', `a=${A}&a=${A}&b=${B}`],
      ['overlapping campaigns', `a=${A}&b=${A}&cell=vacia.vacia`],
      ['an unknown cell', `a=${A}&b=${B}&cell=nada.nada`],
      ['the impossible cell', `a=${A}&b=${B}&cell=sin-registro.sin-registro`],
      ['markup', `a=${encodeURIComponent('<b>')}&b=${B}`],
    ])('falls back to the normal view when the link has %s, and removes the bad parameters from the address', (_name, query) => {
      const { f, address } = setup(() => undefined, query);
      expect(tabButton(f, 'resumen').getAttribute('aria-selected')).toBe('true');
      expect(el(f).querySelector('[data-testid="cell-section"]')).toBeNull();
      tabButton(f, 'comparar').click();
      f.detectChanges();
      // the campaigns are the automatic proposal, not what the bad link said
      expect(el(f).textContent).toContain('Propuesta automática');
      expect(el(f).querySelectorAll('[data-testid="campaign-row"]').length).toBe(3);
      // the address is cleaned (only our three parameters), so reloading does not repeat the failure
      expect(address.state['a']).toBeUndefined();
      expect(address.state['b']).toBeUndefined();
      expect(address.state['cell']).toBeUndefined();
      const calls = address.navigate.mock.calls as [unknown[], { queryParams: Params }][];
      for (const [, extras] of calls) expect(Object.values(extras.queryParams).every(v => v === null)).toBe(true);
    });

    it('leaves the other parameters of the address alone when it cleans a bad link', () => {
      const { address } = setup(() => undefined, `a=oops&utm_source=mail`);
      expect(address.state['utm_source']).toEqual(['mail']);
      expect(address.state['a']).toBeUndefined();
    });

    it('keeps a valid link in the address while the data is still loading', () => {
      const { address } = setup(s => { s.events.set([]); s.herd.set([]); s.status.set('cargando'); }, VALID);
      expect(address.navigate).not.toHaveBeenCalled();
      expect(address.state['cell']).toEqual(['sin-registro.vacia']);
    });

    it('ignores every other parameter, in particular any company or animal', () => {
      const { f, fake } = setup(() => undefined, `${VALID}&id_company=5&tenant_id=7&livestock_id=abc&token=xyz`);
      expect(el(f).querySelector('[data-testid="cell-count"]')?.textContent).toContain('1');
      expect(fake.tenantId()).toBe(9101); // the data is the active company's, as always
      expect(fake.load).toHaveBeenCalledTimes(1);
      expect(el(f).textContent).not.toContain('abc');
    });

    it('waits for the data: with nothing loaded yet the normal view shows, and the link is applied when the rows arrive', () => {
      const { f, fake } = setup(s => { s.events.set([]); s.herd.set([]); s.status.set('cargando'); }, VALID);
      expect(el(f).querySelector('[data-tab]')).toBeNull();
      fake.events.set(events);
      fake.herd.set(herd);
      fake.status.set('listo');
      f.detectChanges();
      expect(tabButton(f, 'comparar').getAttribute('aria-selected')).toBe('true');
      expect(el(f).querySelector('[data-testid="cell-count"]')?.textContent).toContain('1');
    });

    it('drops the link when the company changes before the data arrives: it is never applied to another company', () => {
      const { f, fake, address } = setup(s => { s.events.set([]); s.herd.set([]); s.status.set('cargando'); }, VALID);
      fake.tenantId.set(9102);
      f.detectChanges();
      fake.events.set(events);
      fake.herd.set(herd);
      fake.status.set('listo');
      f.detectChanges();
      expect(tabButton(f, 'resumen').getAttribute('aria-selected')).toBe('true');
      expect(el(f).querySelector('[data-testid="cell-section"]')).toBeNull();
      expect(address.state['cell']).toBeUndefined(); // the address was cleaned
    });

    it('writes only the two date ranges and the cell id to the address when a cell is opened, replacing the entry, and nothing else', () => {
      const { f, address } = setup();
      tabButton(f, 'comparar').click();
      f.detectChanges();
      expect(address.navigate).not.toHaveBeenCalled(); // no cell yet: nothing to write
      cellButton(f, 'NO_PALPADA', 'VACÍA')?.click();
      f.detectChanges();
      const rest = el(f).querySelectorAll('[data-cell-button]');
      expect(rest.length).toBeGreaterThan(0);
      const [commands, extras] = address.navigate.mock.calls.at(-1) as [unknown[], { queryParams: Params; queryParamsHandling: string; replaceUrl: boolean }];
      expect(commands).toEqual([]);
      expect(extras.queryParamsHandling).toBe('merge');
      expect(extras.replaceUrl).toBe(true);
      expect(Object.keys(extras.queryParams).sort()).toEqual(['a', 'b', 'cell']);
      for (const v of Object.values(extras.queryParams)) expect(String(v)).toMatch(/^[0-9a-z._-]+$/);
      expect(JSON.stringify(extras.queryParams)).not.toMatch(/A1|A2|A3|9999|9101|company|tenant/i);
    });

    it('follows the cell: a new cell rewrites the address, and closing it clears the three parameters', () => {
      const { f, address } = setup();
      tabButton(f, 'comparar').click();
      f.detectChanges();
      el(f).querySelector<HTMLButtonElement>('[data-cell-button]')!.click();
      f.detectChanges();
      expect(address.state['cell']?.length).toBe(1);
      el(f).querySelector<HTMLButtonElement>('[data-testid="cell-close"]')!.click();
      f.detectChanges();
      expect(address.state['a']).toBeUndefined();
      expect(address.state['b']).toBeUndefined();
      expect(address.state['cell']).toBeUndefined();
    });

    it('clears the parameters when the user leaves the comparison tab, and writes them again when the cell is shown again', () => {
      const { f, address } = setup(() => undefined, VALID);
      expect(address.state['cell']).toEqual(['sin-registro.vacia']);
      tabButton(f, 'resumen').click();
      f.detectChanges();
      expect(address.state['cell']).toBeUndefined();
      tabButton(f, 'comparar').click();
      f.detectChanges();
      expect(address.state['cell']).toEqual(['sin-registro.vacia']);
    });

    it('closes the cell and clears the address when the company changes (the data of the other company starts clean)', () => {
      const { f, fake, address } = setup(() => undefined, VALID);
      expect(el(f).querySelector('[data-testid="cell-section"]')).not.toBeNull();
      fake.events.set([]);
      fake.herd.set([]);
      fake.tenantId.set(9102);
      f.detectChanges();
      expect(el(f).querySelector('[data-testid="cell-section"]')).toBeNull();
      expect(address.state['cell']).toBeUndefined();
    });

    it('keeps the company isolation as today: the page makes the same single load and the link adds no request', () => {
      const { fake } = setup(() => undefined, VALID);
      expect(fake.load).toHaveBeenCalledTimes(1);
      expect(fake.loadHistory).not.toHaveBeenCalled();
    });
  });
});
