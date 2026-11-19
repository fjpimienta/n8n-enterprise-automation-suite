import { ChangeDetectionStrategy, Component, InjectionToken, computed, effect, inject, signal, untracked } from '@angular/core';
import { PalpationReportService } from '../../services/palpation-report.service';
import { campaignEventRows } from '../../utils/palpation-campaign-compare';
import { Campaign, CampaignError, sortCampaigns, suggestCampaigns, validateCampaigns } from '../../utils/palpation-campaigns';
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
import { PalpationCampaignCompareComponent } from '../palpation-campaign-compare/palpation-campaign-compare.component';
import { PalpationCampaignsEditorComponent } from '../palpation-campaigns-editor/palpation-campaigns-editor.component';
import { PalpationChartsComponent } from '../palpation-charts/palpation-charts.component';
import { PalpationEventListComponent } from '../palpation-event-list/palpation-event-list.component';
import { PalpationKpiCardsComponent } from '../palpation-kpi-cards/palpation-kpi-cards.component';
import { PalpationStateComponent, PalpationStateKind } from '../palpation-state/palpation-state.component';
import { PalpationTableComponent, RowOpenEvent } from '../palpation-table/palpation-table.component';

/** Today's calendar date. A token so tests can fix it; the default reads the browser's local date. */
export const PALPATION_TODAY = new InjectionToken<() => string>('PALPATION_TODAY', {
  providedIn: 'root',
  factory: () => () => todayLocal(),
});

export type PeriodMode = 'campana' | 'todo' | 'personalizado';

export type PalpationTab = 'resumen' | 'comparar' | 'todas';

const TABS: readonly { readonly id: PalpationTab; readonly label: string }[] = [
  { id: 'resumen', label: 'Resumen' },
  { id: 'comparar', label: 'Comparar campañas' },
  { id: 'todas', label: 'Todas las palpaciones' },
];

/**
 * Palpation report (read-only). Container: it reads the fail-closed service, decides which state to show, builds the period, the KPIs and
 * the rows with pure functions, and hands them to presentational components. Every figure is computed for display from the rows the
 * gateway returned and is never stored (CLAUDE.md, Zero-Compute Client). OnPush and signals.
 */
@Component({
  selector: 'app-palpation-report-page',
  standalone: true,
  imports: [
    PalpationStateComponent,
    PalpationKpiCardsComponent,
    PalpationChartsComponent,
    PalpationTableComponent,
    PalpationAnimalDrawerComponent,
    PalpationCampaignsEditorComponent,
    PalpationCampaignCompareComponent,
    PalpationEventListComponent,
  ],
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

  protected readonly tabs = TABS;
  protected readonly tab = signal<PalpationTab>('resumen');

  /**
   * The campaigns of the comparison: user-defined date ranges kept in memory only (nothing is stored, per the Zero-Compute rule). They start as an
   * automatic PROPOSAL when the data arrives, until the user edits them; a company change or a logout clears them with the data.
   */
  protected readonly campaigns = signal<readonly Campaign[]>([]);
  private readonly userEdited = signal(false);
  private lastTenant: number | null = null;

  protected readonly campaignsAreProposal = computed(() => !this.userEdited() && this.campaigns().length > 0);
  protected readonly campaignErrors = computed<readonly CampaignError[]>(() => validateCampaigns(this.campaigns()));
  /** The campaigns, oldest first, or null while they have a validation error (the comparison and the list then explain why they are not shown). */
  protected readonly validCampaigns = computed<readonly Campaign[] | null>(() => (this.campaignErrors().length === 0 ? sortCampaigns(this.campaigns()) : null));
  protected readonly campaignEvents = computed(() => {
    const valid = this.validCampaigns();
    return valid === null ? [] : campaignEventRows(this.service.events(), this.service.herd(), valid);
  });

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

    // Proposes the campaigns once per load, never over the user's own edits; a company change or a cleared dataset starts from scratch.
    effect(() => {
      const events = this.service.events();
      const tenant = this.service.tenantId();
      untracked(() => {
        if (tenant !== this.lastTenant || events.length === 0) {
          this.lastTenant = tenant;
          this.userEdited.set(false);
          this.campaigns.set([]);
        }
        if (events.length > 0 && !this.userEdited()) this.campaigns.set(suggestCampaigns(events));
      });
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

  protected onCampaignsChange(list: Campaign[]): void {
    this.userEdited.set(true);
    this.campaigns.set(list);
  }

  /** The user asked for a new automatic proposal: it replaces their ranges only because they asked. */
  protected resuggest(): void {
    this.userEdited.set(false);
    this.campaigns.set(suggestCampaigns(this.service.events()));
  }

  /** Arrow keys, Home and End move between the tabs (roving tabindex), as in the WAI-ARIA tabs pattern. */
  protected onTabKey(event: KeyboardEvent): void {
    const ids = TABS.map(t => t.id);
    const i = ids.indexOf(this.tab());
    let next: number;
    switch (event.key) {
      case 'ArrowRight': next = (i + 1) % ids.length; break;
      case 'ArrowLeft': next = (i - 1 + ids.length) % ids.length; break;
      case 'Home': next = 0; break;
      case 'End': next = ids.length - 1; break;
      default: return;
    }
    event.preventDefault();
    const id = ids[next] as PalpationTab;
    this.tab.set(id);
    document.getElementById(`palp-tab-${id}`)?.focus();
  }

  protected reload(): void {
    void this.service.load();
  }
}
