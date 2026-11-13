import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { LotSummary, PlantationSummary, STAGE_OPTIONS } from '@core/models/agri.model';
import { ExpenseBalance } from '@core/models/agri-expense.model';
import { SaleBalance } from '@core/models/agri-sale.model';
import { KpiCardComponent, KpiTone } from '@shared/expenses-ui/kpi-card.component';
import { PeriodChipsComponent } from '@shared/expenses-ui/period-chips.component';
import { ShareBarListComponent, ShareItem } from '@shared/expenses-ui/share-bar-list.component';
import { TrendBarsComponent } from '@shared/expenses-ui/trend-bars.component';
import { averagePerDay, buildTrendBars, elapsedDays } from '@shared/expenses-ui/expenses-period.util';
import { deltaPercent, formatDelta, formatPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
import { AgriApiService } from '../../../services/agri-api.service';
import { PlantationContextService } from '../../../services/plantation-context.service';
import { canAdministerPalm, todayCdmx } from '../../../utils/agri.util';
import { formatMoney, periodLabel } from '../../../utils/expense.util';
import {
  OVERVIEW_PRESETS, OVERVIEW_SCOPES, OverviewPlan, OverviewPreset, OverviewScope, categoryGroups, plantationGroups, planOverview,
} from '../../../utils/expense-overview.util';
import { densityComparison, lotsByStage, plantTotals } from '../../../utils/palm-dashboard.util';
import { balanceAvailability, buildIncomeExpense, formatSignedMoney } from '../../../utils/income-expense.util';
import { canManageSales } from '../../../utils/sale.util';

/**
 * Palm dashboard (read-only) for the ACTIVE plantation, from vw_agri_plantation_summary and
 * vw_agri_lot_summary. The only financial block is the expense overview, for ADMIN / OWNER only, from
 * sp_agri_expense_balance (totals computed by the database; here only ratios of what it returns are derived).
 * Each part of the overview (current period, previous period, company total) loads and fails on its own.
 * ADMIN only, on top of that: an income-vs-expense block (sales from sp_agri_sales_balance, expenses from the balance above)
 * for the same period and scope. Each figure has its own loading and error state; the balance (income minus expense, in
 * integer cents) exists only when both are present and both answers match the requested range.
 */
@Component({
  selector: 'app-palm-dashboard',
  standalone: true,
  imports: [DecimalPipe, RouterLink, KpiCardComponent, PeriodChipsComponent, ShareBarListComponent, TrendBarsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './palm-dashboard.component.html',
  styleUrls: ['./palm-dashboard.component.scss'],
})
export class PalmDashboardComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  canAdminister = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));
  /** Income-vs-expense block: ADMIN of the ACTIVE company only (sales are ADMIN-only; OWNER keeps just the expense block). */
  canSeeBalance = computed(() => canManageSales(this.tenantService.activeTenant()?.role));
  plantation = this.context.activePlantation;

  summary = signal<PlantationSummary | null>(null);
  lots = signal<LotSummary[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  possiblyTruncated = signal(false);

  activeLots = computed(() => this.lots().filter(l => l.isActive));
  stages = computed(() => lotsByStage(this.lots()));
  totals = computed(() => plantTotals(this.lots()));
  density = computed(() => densityComparison(this.lots()));
  maxStageLots = computed(() => Math.max(1, ...this.stages().map(s => s.lots)));

  readonly money = formatMoney;
  readonly presets = OVERVIEW_PRESETS;
  readonly scopes = OVERVIEW_SCOPES;

  preset = signal<OverviewPreset>('MONTH');
  scope = signal<OverviewScope>('COMPANY');
  today = signal(todayCdmx());
  plan = signal<OverviewPlan | null>(null);

  balance = signal<ExpenseBalance | null>(null);
  loading = signal(false);
  error = signal<string | null>(null);
  previous = signal<ExpenseBalance | null>(null);
  /** Company-wide balance of the same period: only the denominator of "Parte de la empresa" (plantation scope). */
  companyBalance = signal<ExpenseBalance | null>(null);
  salesBalance = signal<SaleBalance | null>(null);
  salesLoading = signal(false);
  salesError = signal<string | null>(null);
  private seq = 0;

  rangeLabel = computed(() => {
    const p = this.plan();
    return p ? `${periodLabel('DAY', p.range.from, p.range.from)} al ${periodLabel('DAY', p.range.to, p.range.to)}` : '';
  });
  scopeLabel = computed(() => (this.scope() === 'PLANTATION'
    ? `Plantación ${this.plantation()?.code ?? ''}${this.plantation()?.name ? ' · ' + this.plantation()!.name : ''}`.trim() : 'Toda la empresa'));
  /** Plantation scope without an active plantation: nothing is requested. */
  noPlantation = computed(() => this.scope() === 'PLANTATION' && !this.context.activePlantationId());

  avgPerDay = computed(() => {
    const b = this.balance();
    const p = this.plan();
    return b && p ? averagePerDay(b.totalAmount, elapsedDays(p.range, this.today())) : null;
  });
  delta = computed(() => {
    const b = this.balance();
    const prev = this.previous();
    return b && prev ? deltaPercent(b.totalAmount, prev.totalAmount) : null;
  });
  deltaText = computed(() => formatDelta(this.delta()));
  deltaTone = computed<KpiTone>(() => {
    const d = this.delta();
    return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down';
  });
  deltaHint = computed(() => {
    const c = this.plan()?.comparison;
    if (!c) return 'Sin anulados';
    if (c.kind === 'in-progress') return 'Periodo en curso';
    return this.deltaText() ? c.label : 'Sin anulados';
  });
  /** 4th KPI: general expenses (company) or the share of the company total (plantation). */
  fourthLabel = computed(() => (this.scope() === 'PLANTATION' ? 'Parte de la empresa' : 'Generales (sin plantación)'));
  fourthValue = computed(() => {
    const b = this.balance();
    if (!b) return '—';
    if (this.scope() === 'COMPANY') return formatMoney(b.generalAmount);
    const company = this.companyBalance();
    return company && company.totalAmount > 0 ? formatPercent(sharePercent(b.totalAmount, company.totalAmount)) : '—';
  });
  fourthHint = computed(() => (this.scope() === 'COMPANY' ? 'Sin plantación asignada'
    : this.companyBalance() ? 'Del gasto total de la empresa' : 'Total de la empresa no disponible'));

  // Income vs. expense (ADMIN only). Everything below is derived from the two answers; nothing is added up in the client.
  /** The range both procedures were asked for. */
  requested = computed(() => {
    const p = this.plan();
    return p ? { dateFrom: p.query.dateFrom, dateTo: p.query.dateTo } : null;
  });
  incomeExpense = computed(() => buildIncomeExpense(this.salesBalance(), this.balance(), this.requested()));
  availability = computed(() => balanceAvailability({
    scopeReady: !this.noPlantation(), salesLoading: this.salesLoading(), expenseLoading: this.loading(),
    salesError: this.salesError(), expenseError: this.error(), sales: this.salesBalance(), expense: this.balance(), requested: this.requested(),
  }));
  incomeText = computed(() => {
    const s = this.salesBalance();
    return s ? formatMoney(s.totalAmount) : this.salesLoading() ? 'Calculando…' : 'No disponible';
  });
  incomeHint = computed(() => {
    const s = this.salesBalance();
    return this.salesError() ?? (s ? `${s.saleCount} ${s.saleCount === 1 ? 'venta vigente' : 'ventas vigentes'}` : '');
  });
  expenseText = computed(() => {
    const b = this.balance();
    return b ? formatMoney(b.totalAmount) : this.loading() ? 'Calculando…' : 'No disponible';
  });
  expenseHint = computed(() => {
    const b = this.balance();
    return this.error() ?? (b ? `${b.expenseCount} ${b.expenseCount === 1 ? 'gasto vigente' : 'gastos vigentes'}` : '');
  });
  balanceText = computed(() => {
    const status = this.availability().status;
    const net = this.incomeExpense();
    if ((status === 'ready' || status === 'empty') && net) return formatSignedMoney(net.net);
    return status === 'loading' ? 'Calculando…' : 'No disponible';
  });
  balanceHint = computed(() => this.availability().reason ?? 'Ventas menos gastos');
  /** Text next to the arrow of the balance card (never colour alone); empty when there is nothing to say. */
  balanceBadge = computed(() => {
    const net = this.availability().status === 'ready' ? this.incomeExpense() : null;
    return net?.direction === 'up' ? 'A favor' : net?.direction === 'down' ? 'En contra' : '';
  });
  balanceTone = computed<KpiTone>(() => (this.availability().status === 'ready' ? this.incomeExpense()?.direction ?? 'flat' : 'flat'));

  bars = computed(() => {
    const b = this.balance();
    return b ? buildTrendBars(b.byPeriod, b.grain, this.today(), formatMoney) : [];
  });
  trendTitle = computed(() => (this.balance()?.grain === 'DAY' || (!this.balance() && this.preset() === 'MONTH') ? 'Gasto por día' : 'Gasto por mes'));
  categoryItems = computed<ShareItem[]>(() => categoryGroups(this.balance()).map(r => ({ key: r.key, label: r.label, amount: r.amount, amountText: formatMoney(r.amount) })));
  plantationItems = computed<ShareItem[]>(() => plantationGroups(this.balance()).map(r => ({ key: r.key, label: r.label, amount: r.amount, amountText: formatMoney(r.amount) })));

  constructor() {
    effect(() => {
      const plantationId = this.context.activePlantationId();
      untracked(() => {
        this.summary.set(null);
        this.lots.set([]);
        if (plantationId) void this.load(plantationId);
      });
    });
    // Expense overview: ADMIN / OWNER only. A company or role change clears everything and goes back to the defaults.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      this.canAdminister();
      this.canSeeBalance();
      untracked(() => {
        this.seq++;
        this.clearOverview();
        this.preset.set('MONTH');
        this.scope.set('COMPANY');
        void tenantId;
      });
    });
    // (Re)load when the company, the role, the period, the scope or (plantation scope) the plantation changes.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      const canSee = this.canAdminister();
      this.canSeeBalance(); // a role change between ADMIN and OWNER reloads too
      const preset = this.preset();
      const scope = this.scope();
      const plantationId = scope === 'PLANTATION' ? this.context.activePlantationId() : null;
      untracked(() => {
        this.seq++;
        this.clearOverview();
        // Fail closed: no company, no permission, or no plantation for the plantation scope -> no request at all.
        if (tenantId && canSee) void this.loadOverview(preset, scope, plantationId);
      });
    });
  }

  private clearOverview() {
    this.balance.set(null);
    this.previous.set(null);
    this.companyBalance.set(null);
    this.plan.set(null);
    this.error.set(null);
    this.loading.set(false);
    this.salesBalance.set(null);
    this.salesError.set(null);
    this.salesLoading.set(false);
  }

  setPreset(value: string) { this.preset.set(value as OverviewPreset); }
  setScope(value: string) { this.scope.set(value as OverviewScope); }

  stageLabel(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.label ?? value; }
  stageBadge(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.badge ?? 'bg-secondary-lt'; }

  /**
   * Current period first (it is the one that may show an error); the previous period and the company total only decorate
   * it: their failure hides that figure and never blocks anything. A stale answer (newer request, company switch) is dropped.
   */
  async loadOverview(preset: OverviewPreset, scope: OverviewScope, plantationId: string | null) {
    const seq = this.seq;
    this.today.set(todayCdmx());
    const plan = planOverview(preset, scope, plantationId, this.today());
    this.plan.set(plan);
    if (!plan) return; // plantation scope without an active plantation
    const live = () => seq === this.seq;
    this.loading.set(true);

    // Income of the same range and scope (lot always null). ADMIN only: any other role makes no sales request at all.
    if (this.canSeeBalance()) {
      this.salesLoading.set(true);
      this.api.getSalesBalance({
        dateFrom: plan.query.dateFrom, dateTo: plan.query.dateTo, grain: plan.query.grain, plantationId: plan.query.plantationId, lotId: null,
      }).then(b => { if (live()) this.salesBalance.set(b); })
        .catch((error: any) => {
          if (!live()) return;
          console.error('[Agro-ERP] Error al cargar las ventas del periodo:', error);
          this.salesError.set(error?.message || 'No se pudieron cargar las ventas.');
        })
        .finally(() => { if (live()) this.salesLoading.set(false); });
    }

    if (plan.previous) {
      this.api.getExpenseBalance(plan.previous).then(p => { if (live()) this.previous.set(p); })
        .catch(error => console.error('[Agro-ERP] No se pudo cargar el periodo anterior:', error));
    }
    if (plan.company) {
      this.api.getExpenseBalance(plan.company).then(c => { if (live()) this.companyBalance.set(c); })
        .catch(error => console.error('[Agro-ERP] No se pudo cargar el total de la empresa:', error));
    }
    try {
      const balance = await this.api.getExpenseBalance(plan.query);
      if (live()) this.balance.set(balance);
    } catch (error: any) {
      if (!live()) return;
      // Its own error: the rest of the dashboard stays usable, and an error is never shown as $0.
      console.error('[Agro-ERP] Error al cargar el gasto:', error);
      this.error.set(error?.message || 'No se pudo cargar el gasto.');
    } finally {
      if (live()) this.loading.set(false);
    }
  }

  async load(plantationId: string) {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const [summaries, lots] = await Promise.all([this.api.getPlantationSummaries(), this.api.getLotSummaries(plantationId)]);
      if (this.context.activePlantationId() !== plantationId) return; // plantation switched meanwhile
      this.summary.set(summaries.items.find(s => s.id === plantationId) ?? null);
      this.lots.set(lots.items);
      this.possiblyTruncated.set(summaries.possiblyTruncated || lots.possiblyTruncated);
    } catch (error: any) {
      // Silent Error Shield: an error is shown as an error, never as "0 lots".
      console.error('[Agro-ERP] Error al cargar el tablero de palma:', error);
      this.loadError.set(error?.message || 'No se pudo cargar el tablero de la plantación.');
    } finally {
      this.isLoading.set(false);
    }
  }
}
