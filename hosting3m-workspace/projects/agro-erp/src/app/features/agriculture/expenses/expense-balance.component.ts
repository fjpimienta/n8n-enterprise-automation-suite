import { ChangeDetectionStrategy, Component, computed, effect, inject, input, output, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import {
  ExpenseBalance,
  ExpenseBalanceQuery,
  ExpenseCategory,
  ExpenseGrain,
  ExpenseSummaryRow,
} from '@core/models/agri-expense.model';
import { exportRowsToCsv } from '@shared/utils/csv-export.util';
import { KpiCardComponent, KpiTone } from '@shared/expenses-ui/kpi-card.component';
import { PeriodChipsComponent } from '@shared/expenses-ui/period-chips.component';
import { ShareBarListComponent, ShareItem } from '@shared/expenses-ui/share-bar-list.component';
import { TrendBarsComponent } from '@shared/expenses-ui/trend-bars.component';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import {
  formatMoney,
  periodLabel,
  snapRangeToGrain,
  summaryCsvColumns,
  validateBalanceRange,
} from '../utils/expense.util';
import {
  DateRange,
  PERIOD_PRESETS,
  PeriodPreset,
  averagePerDay,
  buildTrendBars,
  deltaPercent,
  elapsedDays,
  formatDelta,
  formatPercent,
  grainForSpan,
  previousRange,
  rangeForPreset,
  sharePercent,
} from '../utils/expense-view.util';

/**
 * Expense summary (ADMIN / OWNER). Every total comes from sp_agri_expense_balance (current and previous
 * period) and vw_agri_expense_summary (detail); nothing is added up in the browser. Each block loads and
 * fails on its own: the previous period, the invoiced share and the detail never block the main figures.
 */
@Component({
  selector: 'app-expense-balance',
  standalone: true,
  imports: [FormsModule, KpiCardComponent, PeriodChipsComponent, ShareBarListComponent, TrendBarsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './expense-balance.component.html',
})
export class ExpenseBalanceComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  /** Kept for the page binding contract; the summary no longer filters by category. */
  categories = input<ExpenseCategory[]>([]);
  refreshToken = input<number>(0);
  openMovements = output<void>();

  readonly money = formatMoney;
  readonly presets = PERIOD_PRESETS;

  preset = signal<PeriodPreset>('MONTH');
  customFrom = signal('');
  customTo = signal('');
  plantationId = signal('');
  lotId = signal('');
  lots = signal<Lot[]>([]);

  applied = signal<ExpenseBalanceQuery | null>(null);
  appliedPreset = signal<PeriodPreset>('MONTH');
  today = signal(todayCdmx());

  balance = signal<ExpenseBalance | null>(null);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  filterError = signal<string | null>(null);

  previous = signal<ExpenseBalance | null>(null);
  invoicedPct = signal<number | null>(null);

  summary = signal<ExpenseSummaryRow[]>([]);
  summaryLoading = signal(false);
  summaryError = signal<string | null>(null);
  possiblyTruncated = signal(false);

  private seq = 0;
  private lotSeq = 0;

  appliedLabel = computed(() => {
    const q = this.applied();
    return q ? `${periodLabel('DAY', q.dateFrom, q.dateFrom)} al ${periodLabel('DAY', q.dateTo, q.dateTo)}` : '';
  });

  // Derived view state (ratios of values already returned by the database) -----------------------------
  avgPerDay = computed(() => {
    const b = this.balance();
    const q = this.applied();
    return b && q ? averagePerDay(b.totalAmount, elapsedDays({ from: q.dateFrom, to: q.dateTo }, this.today())) : null;
  });
  deltaText = computed(() => {
    const b = this.balance();
    const p = this.previous();
    return b && p ? formatDelta(deltaPercent(b.totalAmount, p.totalAmount)) : '';
  });
  deltaTone = computed<KpiTone>(() => {
    const b = this.balance();
    const p = this.previous();
    if (!b || !p) return 'flat';
    const d = deltaPercent(b.totalAmount, p.totalAmount);
    return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down';
  });
  invoicedText = computed(() => formatPercent(this.invoicedPct()));
  bars = computed(() => {
    const b = this.balance();
    return b ? buildTrendBars(b.byPeriod, b.grain, this.today(), formatMoney) : [];
  });
  categoryItems = computed<ShareItem[]>(() => [...(this.balance()?.byCategory ?? [])]
    .filter(c => c.totalAmount > 0).sort((a, b) => b.totalAmount - a.totalAmount)
    .map(c => ({ key: c.categoryId, label: c.categoryName, amount: c.totalAmount, amountText: formatMoney(c.totalAmount) })));
  plantationItems = computed<ShareItem[]>(() => [...(this.balance()?.byPlantation ?? [])]
    .filter(p => p.totalAmount > 0).sort((a, b) => b.totalAmount - a.totalAmount)
    .map(p => ({
      key: p.plantationId ?? 'general',
      label: p.plantationId ? `${p.plantationCode} · ${p.plantationName}` : 'General (sin plantación)',
      amount: p.totalAmount, amountText: formatMoney(p.totalAmount),
    })));
  topLots = computed(() => {
    const b = this.balance();
    if (!b) return [];
    return [...b.byLot].filter(l => l.totalAmount > 0).sort((x, y) => y.totalAmount - x.totalAmount).slice(0, 5)
      .map(l => ({ ...l, pctText: formatPercent(sharePercent(l.totalAmount, b.totalAmount)) }));
  });

  constructor() {
    // Company change: back to the defaults of the new company, nothing of the previous one stays on screen.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      untracked(() => {
        this.seq++;
        this.resetFilters();
        this.clearData();
        this.applied.set(null);
        if (tenantId) this.apply();
      });
    });
    // A capture or a void elsewhere on the screen: reload the applied query (not on the first run: the
    // company effect above already loaded it).
    let lastToken: number | null = null;
    effect(() => {
      const token = this.refreshToken();
      untracked(() => {
        const changed = lastToken !== null && token !== lastToken;
        lastToken = token;
        const q = this.applied();
        if (changed && q) void this.load(q, this.appliedPreset());
      });
    });
  }

  label(grain: ExpenseGrain, start: string, end: string) { return periodLabel(grain, start, end); }

  private clearData() {
    this.balance.set(null);
    this.previous.set(null);
    this.invoicedPct.set(null);
    this.summary.set([]);
    this.summaryError.set(null);
    this.loadError.set(null);
    this.possiblyTruncated.set(false);
  }

  resetFilters() {
    this.today.set(todayCdmx());
    this.preset.set('MONTH');
    const r = rangeForPreset('MONTH', this.today());
    this.customFrom.set(r.from);
    this.customTo.set(r.to);
    this.plantationId.set('');
    this.lotId.set('');
    this.lots.set([]);
    this.filterError.set(null);
  }

  /** Picking a preset applies it at once; "Personalizado" only reveals the date inputs. */
  setPreset(value: string) {
    const preset = value as PeriodPreset;
    this.preset.set(preset);
    if (preset !== 'CUSTOM') {
      const r = rangeForPreset(preset, todayCdmx());
      this.customFrom.set(r.from);
      this.customTo.set(r.to);
      this.apply();
    }
  }

  async setPlantation(plantationId: string) {
    this.plantationId.set(plantationId);
    this.lotId.set('');
    const seq = ++this.lotSeq;
    this.lots.set([]);
    if (plantationId) {
      try {
        const { items } = await this.api.getLots(plantationId);
        if (seq === this.lotSeq) this.lots.set(items.sort((a, b) => a.code.localeCompare(b.code, 'es', { numeric: true })));
      } catch (error: any) {
        if (seq !== this.lotSeq) return;
        console.error('[Agro-ERP] Error al cargar los lotes del filtro:', error);
        this.filterError.set(error?.message || 'No se pudieron cargar los lotes de la plantación.');
        return;
      }
    }
    if (this.applied()) this.apply();
  }

  setLot(lotId: string) {
    this.lotId.set(lotId);
    this.apply();
  }

  /** Range and grain of the chosen period, snapped to whole periods so the totals and the detail agree. */
  private currentRange(): { range: DateRange; grain: ExpenseGrain } {
    this.today.set(todayCdmx());
    const preset = this.preset();
    if (preset === 'CUSTOM') {
      const grain = grainForSpan(this.customFrom(), this.customTo());
      const snapped = snapRangeToGrain(this.customFrom(), this.customTo(), grain);
      return { range: snapped, grain };
    }
    const r = rangeForPreset(preset, this.today());
    return { range: { from: r.from, to: r.to }, grain: r.grain };
  }

  apply() {
    const { range, grain } = this.currentRange();
    const error = validateBalanceRange(range.from, range.to, grain);
    if (error) {
      this.filterError.set(error);
      return;
    }
    this.filterError.set(null);
    if (this.preset() === 'CUSTOM') {
      // The inputs show the whole periods actually used.
      this.customFrom.set(range.from);
      this.customTo.set(range.to);
    }
    const query: ExpenseBalanceQuery = {
      dateFrom: range.from, dateTo: range.to, grain,
      plantationId: this.plantationId() || null, lotId: this.plantationId() ? this.lotId() || null : null,
      categoryId: null,
    };
    this.applied.set(query);
    this.appliedPreset.set(this.preset());
    void this.load(query, this.preset());
  }

  async load(query: ExpenseBalanceQuery, preset: PeriodPreset) {
    const seq = ++this.seq;
    // Fail closed: without an active company nothing is requested.
    if (!this.tenantService.activeTenantId()) {
      this.clearData();
      this.loadError.set('No hay una empresa activa.');
      return;
    }
    this.isLoading.set(true);
    this.loadError.set(null);
    this.summaryLoading.set(true);
    this.summaryError.set(null);
    this.previous.set(null);
    this.invoicedPct.set(null);
    const live = () => seq === this.seq; // a newer query or a company change won

    // Main figures. Failing here is shown as an error, never as "$0" (Silent Error Shield).
    this.api.getExpenseBalance(query).then(balance => {
      if (live()) this.balance.set(balance);
    }).catch((error: any) => {
      if (!live()) return;
      console.error('[Agro-ERP] Error al cargar el balance de gastos:', error);
      this.balance.set(null);
      this.loadError.set(error?.message || 'No se pudo cargar el balance de gastos.');
    }).finally(() => { if (live()) this.isLoading.set(false); });

    // Previous equivalent period: only decorates the total card.
    const prev = snapRangeToGrain(...this.prevArgs(preset, query));
    this.api.getExpenseBalance({ ...query, dateFrom: prev.from, dateTo: prev.to }).then(p => {
      if (live()) this.previous.set(p);
    }).catch((error: any) => {
      console.error('[Agro-ERP] No se pudo cargar el periodo anterior:', error);
    });

    // Invoiced share: counts over the complete list of the range; hidden when the page may be cut.
    this.api.getExpenses({ dateFrom: query.dateFrom, dateTo: query.dateTo, plantationId: query.plantationId, lotId: query.lotId, categoryId: null })
      .then(({ items, possiblyTruncated }) => {
        if (!live() || possiblyTruncated) return;
        const valid = items.filter(e => !e.isVoid);
        this.invoicedPct.set(valid.length ? sharePercent(valid.filter(e => e.isInvoiced).length, valid.length) : null);
      }).catch((error: any) => {
        console.error('[Agro-ERP] No se pudo calcular el porcentaje facturado:', error);
      });

    // Detail table (collapsed by default).
    this.api.getExpenseSummary(query).then(summary => {
      if (!live()) return;
      this.summary.set(summary.items);
      this.possiblyTruncated.set(summary.possiblyTruncated);
    }).catch((error: any) => {
      if (!live()) return;
      console.error('[Agro-ERP] Error al cargar el detalle de gastos:', error);
      this.summary.set([]);
      this.summaryError.set(error?.message || 'No se pudo cargar el detalle.');
    }).finally(() => { if (live()) this.summaryLoading.set(false); });
  }

  private prevArgs(preset: PeriodPreset, q: ExpenseBalanceQuery): [string, string, ExpenseGrain] {
    const p = previousRange(preset, { from: q.dateFrom, to: q.dateTo });
    return [p.from, p.to, q.grain];
  }

  exportCsv() {
    const q = this.applied();
    if (!q || !this.summary().length) return;
    exportRowsToCsv(this.summary(), summaryCsvColumns(), `balance_gastos_${q.grain.toLowerCase()}_${q.dateFrom}_${q.dateTo}.csv`);
  }
}
