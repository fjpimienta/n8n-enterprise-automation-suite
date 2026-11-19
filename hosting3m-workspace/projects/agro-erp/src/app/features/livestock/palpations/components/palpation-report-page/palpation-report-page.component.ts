import { ChangeDetectionStrategy, Component, InjectionToken, computed, effect, inject, signal, untracked } from '@angular/core';
import { PalpationReportService } from '../../services/palpation-report.service';
import { isCalendarDate, todayLocal } from '../../utils/palpation-dates';
import { Period, campaignStart, defaultPeriod, periodKpis } from '../../utils/palpation-metrics';
import {
  RowFilterResult,
  SortDir,
  SortKey,
  STATE_LABEL,
  buildTableRows,
  distinctStatuses,
  filterRows,
  formatDate,
  sortRows,
} from '../../utils/palpation-view';
import { PalpationAnimalDrawerComponent } from '../palpation-animal-drawer/palpation-animal-drawer.component';
import { PalpationChartsComponent } from '../palpation-charts/palpation-charts.component';
import { PalpationKpiCardsComponent } from '../palpation-kpi-cards/palpation-kpi-cards.component';
import { PalpationStateComponent, PalpationStateKind } from '../palpation-state/palpation-state.component';
import { PalpationTableComponent, RowOpenEvent } from '../palpation-table/palpation-table.component';

/** Today's calendar date. A token so tests can fix it; the default reads the browser's local date. */
export const PALPATION_TODAY = new InjectionToken<() => string>('PALPATION_TODAY', {
  providedIn: 'root',
  factory: () => () => todayLocal(),
});

export type PeriodMode = 'campana' | 'todo' | 'personalizado';

/**
 * Palpation report (read-only). Container: it reads the fail-closed service, decides which state to show, builds the period, the KPIs and
 * the rows with pure functions, and hands them to presentational components. Every figure is computed for display from the rows the
 * gateway returned and is never stored (CLAUDE.md, Zero-Compute Client). OnPush and signals.
 */
@Component({
  selector: 'app-palpation-report-page',
  standalone: true,
  imports: [PalpationStateComponent, PalpationKpiCardsComponent, PalpationChartsComponent, PalpationTableComponent, PalpationAnimalDrawerComponent],
  templateUrl: './palpation-report-page.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationReportPageComponent {
  protected readonly service = inject(PalpationReportService);
  private readonly today = inject(PALPATION_TODAY);

  protected readonly mode = signal<PeriodMode>('campana');
  protected readonly customFrom = signal('');
  protected readonly customTo = signal('');
  protected readonly resultFilter = signal<RowFilterResult>('TODOS');
  protected readonly statusFilter = signal('TODOS');
  protected readonly sortKey = signal<SortKey>('lastDate');
  protected readonly sortDir = signal<SortDir>('desc');
  protected readonly selected = signal<RowOpenEvent | null>(null);

  protected readonly resultOptions: readonly { value: RowFilterResult; label: string }[] = [
    { value: 'TODOS', label: 'Todos los resultados' },
    { value: 'PREÑADA', label: STATE_LABEL['PREÑADA'] },
    { value: 'VACÍA', label: STATE_LABEL['VACÍA'] },
    { value: 'TERMINO_RANCHO', label: STATE_LABEL.TERMINO_RANCHO },
    { value: 'SIN_RESULTADO', label: STATE_LABEL.SIN_RESULTADO },
    { value: 'SIN_INTERPRETAR', label: STATE_LABEL.SIN_INTERPRETAR },
  ];

  protected readonly campaign = computed(() => campaignStart(this.service.events(), this.today()));

  /** The period in use, or null when "campaña reciente" is chosen and the company has no campaign yet. */
  protected readonly period = computed<Period | null>(() => {
    switch (this.mode()) {
      case 'todo':
        return { from: null, to: null };
      case 'personalizado': {
        const from = this.customFrom();
        const to = this.customTo();
        return { from: isCalendarDate(from) ? from : null, to: isCalendarDate(to) ? to : null };
      }
      default:
        return defaultPeriod(this.service.events(), this.today());
    }
  });

  /** Which non-content state to show, or null when the content is shown. */
  protected readonly stateKind = computed<PalpationStateKind | null>(() => {
    switch (this.service.status()) {
      case 'sin-tenant': return 'sin-tenant';
      case 'sin-permiso': return 'sin-permiso';
      case 'cargando': return 'cargando';
      case 'error': return 'error';
      case 'vacio': return 'vacio';
      default: return this.period() === null ? 'sin-campana' : null;
    }
  });

  protected readonly periodLabel = computed(() => {
    const p = this.period();
    if (this.mode() === 'todo') return 'todo el historial';
    if (this.mode() === 'personalizado') return 'el periodo elegido';
    return p && p.from && p.to ? `campaña reciente (${formatDate(p.from)} a ${formatDate(p.to)})` : 'campaña reciente';
  });

  protected readonly kpis = computed(() => {
    const p = this.period();
    return p === null ? null : periodKpis(this.service.events(), p);
  });

  private readonly allRows = computed(() => {
    const p = this.period();
    return p === null ? [] : buildTableRows(this.service.events(), this.service.herd(), p);
  });

  protected readonly statusOptions = computed(() => distinctStatuses(this.allRows()));

  protected readonly rows = computed(() =>
    sortRows(filterRows(this.allRows(), { result: this.resultFilter(), status: this.statusFilter() }), this.sortKey(), this.sortDir()),
  );

  constructor() {
    // Loads on entry and again when the active company or its role changes. The service resets itself on a tenant change.
    effect(() => {
      this.service.tenantId();
      this.service.role();
      untracked(() => void this.service.load());
    });
  }

  protected setMode(event: Event): void {
    this.mode.set((event.target as HTMLSelectElement).value as PeriodMode);
  }

  protected setResult(event: Event): void {
    this.resultFilter.set((event.target as HTMLSelectElement).value as RowFilterResult);
  }

  protected setStatus(event: Event): void {
    this.statusFilter.set((event.target as HTMLSelectElement).value);
  }

  protected setCustom(which: 'from' | 'to', event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    (which === 'from' ? this.customFrom : this.customTo).set(value);
  }

  protected onSort(key: SortKey): void {
    if (this.sortKey() === key) {
      this.sortDir.set(this.sortDir() === 'asc' ? 'desc' : 'asc');
    } else {
      this.sortKey.set(key);
      this.sortDir.set(key === 'lastDate' ? 'desc' : 'asc');
    }
  }

  protected reload(): void {
    void this.service.load();
  }
}
