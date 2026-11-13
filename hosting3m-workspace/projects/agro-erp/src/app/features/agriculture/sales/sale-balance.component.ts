import { ChangeDetectionStrategy, Component, computed, effect, inject, input, output, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import { SaleBalance, SaleBalanceQuery } from '@core/models/agri-sale.model';
import { KpiCardComponent, KpiTone } from '@shared/expenses-ui/kpi-card.component';
import { PeriodChipsComponent } from '@shared/expenses-ui/period-chips.component';
import { ShareBarListComponent, ShareItem } from '@shared/expenses-ui/share-bar-list.component';
import { TrendBarsComponent } from '@shared/expenses-ui/trend-bars.component';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import { formatMoney, periodLabel, validateBalanceRange } from '../utils/expense.util';
import {
  Comparison,
  DateRange,
  PERIOD_PRESETS,
  PeriodPreset,
  averagePerDay,
  buildTrendBars,
  comparisonFor,
  deltaPercent,
  elapsedDays,
  formatDelta,
  grainForSpan,
  rangeForPreset,
} from '../utils/expense-view.util';
import { averagePricePerKg, canManageSales, formatKg, formatPricePerKg } from '../utils/sale.util';

/**
 * Sales summary (ADMIN only). Every total comes from sp_agri_sales_balance (current and previous period); nothing is
 * added up in the browser, only ratios of values the database returned (average price per kilogram = total / kilograms,
 * variation against the comparable previous period). The previous period only decorates the total card: its failure
 * never blocks the main figures. Voided sales are not counted by the procedure.
 */
@Component({
  selector: 'app-sale-balance',
  standalone: true,
  imports: [FormsModule, KpiCardComponent, PeriodChipsComponent, ShareBarListComponent, TrendBarsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './sale-balance.component.html',
})
export class SaleBalanceComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  refreshToken = input<number>(0);
  openSales = output<void>();

  readonly money = formatMoney;
  readonly kg = formatKg;
  readonly pricePerKg = formatPricePerKg;
  readonly presets = PERIOD_PRESETS;

  /** The role of the ACTIVE company, re-checked live (never the JWT role). */
  allowed = computed(() => canManageSales(this.tenantService.activeTenant()?.role));

  preset = signal<PeriodPreset>('MONTH');
  customFrom = signal('');
  customTo = signal('');
  plantationId = signal('');
  lotId = signal('');
  lots = signal<Lot[]>([]);

  applied = signal<SaleBalanceQuery | null>(null);
  appliedPreset = signal<PeriodPreset>('MONTH');
  today = signal(todayCdmx());

  balance = signal<SaleBalance | null>(null);
  previous = signal<SaleBalance | null>(null);
  /** What the total is compared with (null until loaded). Never a range of a different length. */
  comparison = signal<Comparison | null>(null);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  filterError = signal<string | null>(null);

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
  avgPrice = computed(() => {
    const b = this.balance();
    return b ? averagePricePerKg(b.totalAmount, b.totalQuantityKg) : null;
  });
  delta = computed(() => {
    const b = this.balance();
    const p = this.previous();
    return b && p ? deltaPercent(b.totalAmount, p.totalAmount) : null;
  });
  deltaText = computed(() => formatDelta(this.delta()));
  deltaTone = computed<KpiTone>(() => {
    const d = this.delta();
    return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down';
  });
  deltaHint = computed(() => {
    const c = this.comparison();
    if (!c) return 'Sin comparación';
    if (c.kind === 'in-progress') return 'Periodo en curso';
    return this.deltaText() ? c.label : 'Sin ventas en el periodo anterior';
  });
  bars = computed(() => {
    const b = this.balance();
    return b
      ? buildTrendBars(b.byPeriod.map(p => ({ periodStart: p.periodStart, periodEnd: p.periodEnd, totalAmount: p.totalAmount })), b.grain, this.today(), formatMoney)
      : [];
  });
  trendTitle = computed(() => {
    const grain = this.balance()?.grain;
    return `Ventas por ${grain === 'DAY' ? 'día' : grain === 'WEEK' ? 'semana' : grain === 'YEAR' ? 'año' : 'mes'}`;
  });
  plantationItems = computed<ShareItem[]>(() => [...(this.balance()?.byPlantation ?? [])]
    .filter(p => p.totalAmount > 0).sort((a, b) => b.totalAmount - a.totalAmount)
    .map(p => ({
      key: p.plantationId ?? 'none',
      label: p.plantationId ? `${p.plantationCode ?? ''} · ${p.plantationName ?? ''}` : 'Sin plantación',
      amount: p.totalAmount, amountText: formatMoney(p.totalAmount),
    })));

  constructor() {
    // Company or role change: back to the defaults, nothing of the previous company stays on screen.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      const allowed = this.allowed();
      untracked(() => {
        this.seq++;
        this.resetFilters();
        this.clearData();
        this.applied.set(null);
        if (tenantId && allowed) this.apply();
      });
    });
    // A void elsewhere on the screen: reload the applied query (not on the first run: the effect above already loaded it).
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

  private clearData() {
    this.balance.set(null);
    this.previous.set(null);
    this.comparison.set(null);
    this.loadError.set(null);
    this.isLoading.set(false);
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

  private currentRange(): { range: DateRange; grain: SaleBalanceQuery['grain'] } {
    this.today.set(todayCdmx());
    const preset = this.preset();
    if (preset === 'CUSTOM') return { range: { from: this.customFrom(), to: this.customTo() }, grain: grainForSpan(this.customFrom(), this.customTo()) };
    const r = rangeForPreset(preset, this.today());
    return { range: { from: r.from, to: r.to }, grain: r.grain };
  }

  apply() {
    if (!this.allowed()) return;
    const { range, grain } = this.currentRange();
    const error = validateBalanceRange(range.from, range.to, grain);
    if (error) {
      this.filterError.set(error);
      return;
    }
    this.filterError.set(null);
    const query: SaleBalanceQuery = {
      dateFrom: range.from, dateTo: range.to, grain,
      plantationId: this.plantationId() || null, lotId: this.plantationId() ? this.lotId() || null : null,
    };
    this.applied.set(query);
    this.appliedPreset.set(this.preset());
    void this.load(query, this.preset());
  }

  async load(query: SaleBalanceQuery, preset: PeriodPreset) {
    const seq = ++this.seq;
    // Fail closed: no permission or no active company -> nothing is requested.
    if (!this.allowed()) {
      this.clearData();
      return;
    }
    if (!this.tenantService.activeTenantId()) {
      this.clearData();
      this.loadError.set('No hay una empresa activa.');
      return;
    }
    this.isLoading.set(true);
    this.loadError.set(null);
    this.previous.set(null);
    this.comparison.set(null);
    const live = () => seq === this.seq; // a newer query or a company change won

    // Main figures. Failing here is shown as an error, never as "$0" (Silent Error Shield).
    const main = this.api.getSalesBalance(query);

    // Like-for-like comparison: only decorates the total card. In-progress quarter/year/custom: no request, no variation.
    const comparison = comparisonFor(preset, { from: query.dateFrom, to: query.dateTo }, todayCdmx());
    this.comparison.set(comparison);
    if (comparison.kind === 'range') {
      this.api.getSalesBalance({ ...query, grain: comparison.grain ?? query.grain, dateFrom: comparison.range.from, dateTo: comparison.range.to })
        .then(p => { if (live()) this.previous.set(p); })
        .catch((error: any) => { console.error('[Agro-ERP] No se pudo cargar el periodo anterior de ventas:', error); });
    }

    try {
      const balance = await main;
      if (live()) this.balance.set(balance);
    } catch (error: any) {
      if (!live()) return;
      console.error('[Agro-ERP] Error al cargar el resumen de ventas:', error);
      this.balance.set(null);
      this.loadError.set(error?.message || 'No se pudo cargar el resumen de ventas.');
    } finally {
      if (live()) this.isLoading.set(false);
    }
  }
}
