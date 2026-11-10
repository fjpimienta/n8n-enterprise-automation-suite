import { ChangeDetectionStrategy, Component, computed, effect, input, output, signal, untracked } from '@angular/core';
import type { SaleIncome } from '@core/models/sale.model';
import { KpiCardComponent, KpiTone } from '@shared/expenses-ui/kpi-card.component';
import { PeriodChipsComponent } from '@shared/expenses-ui/period-chips.component';
import { ShareBarListComponent, ShareItem } from '@shared/expenses-ui/share-bar-list.component';
import { TrendBarsComponent } from '@shared/expenses-ui/trend-bars.component';
import { buildTrendBars } from '@shared/expenses-ui/expenses-period.util';
import { formatDelta, formatMoney, formatPercent, sharePercent } from '@shared/expenses-ui/expenses-ui.util';
import { todayCdmx } from '../../../../agriculture/utils/agri.util';
import type { Expense } from '../../../models/expense.model';
import type { Livestock } from '../../../models/livestock.model';
import {
  LIVESTOCK_PERIOD_PRESETS, LivestockPeriodPreset, REFERENCE_PRICE_PER_KG, comparisonLabel, filterByRange, herdValue, netBalance, perHead,
  periodView, spendByType, spendDelta, spendTrend, sumAmount, uppBalance,
} from '../../livestock-expense.util';
import { accumulatedResult, mortalityLoss, periodResult, recentSales, resultTone, resultWord, signedMoney } from '../../livestock-result.util';
import { unweightedHeads } from '@shared/utils/herd-status.util';
import { formatCalendarDate } from '@shared/utils/authorization-deadline.util';

/**
 * Financial summary of the Livestock dashboard (ADMIN only). Pure view: the dashboard owns the data and passes the
 * already filtered lists; nothing is fetched here. The period only affects spend, per head, type and trend;
 * the balance by UPP is accumulated over all dates.
 */
@Component({
  selector: 'app-livestock-expense-summary',
  standalone: true,
  imports: [PeriodChipsComponent, KpiCardComponent, ShareBarListComponent, TrendBarsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './livestock-expense-summary.component.html',
})
export class LivestockExpenseSummaryComponent {
  /** Amounts are rendered only when true; otherwise the component renders nothing. */
  canViewAmounts = input<boolean>(false);
  cattle = input<readonly Livestock[]>([]);
  expenses = input<readonly Expense[]>([]);
  pricePerKg = input<number>(REFERENCE_PRICE_PER_KG);
  /** Changes when the company / module / species / lot changes: local state goes back to its defaults. */
  resetKey = input<unknown>(null);
  loading = input<boolean>(false);
  /** Sale incomes already scoped by the dashboard (company and module / species / lot). */
  incomes = input<readonly SaleIncome[]>([]);
  incomesLoaded = input<boolean>(false);
  incomesError = input<string | null>(null);
  /** Dead animals (BAJA_MORTANDAD) in the current filter. */
  mortalityCattle = input<readonly Livestock[]>([]);
  /** Whole herd, to resolve the tag of a sold animal. */
  lookup = input<readonly Livestock[]>([]);
  openSales = output<void>();

  readonly presets = LIVESTOCK_PERIOD_PRESETS;
  readonly money = formatMoney;
  readonly formatPercent = formatPercent;

  preset = signal<LivestockPeriodPreset>('MONTH');
  today = signal(todayCdmx());

  constructor() {
    effect(() => {
      this.resetKey();
      untracked(() => { this.preset.set('MONTH'); this.today.set(todayCdmx()); });
    });
  }

  setPreset(value: string) { this.preset.set(value as LivestockPeriodPreset); this.today.set(todayCdmx()); }

  private view = computed(() => periodView(this.preset(), this.today()));
  private periodExpenses = computed(() => {
    if (!this.canViewAmounts()) return [];
    const { range } = this.view();
    return filterByRange(this.expenses(), range.from, range.to);
  });
  /** Nothing to show yet: first load without data. */
  isEmptyLoading = computed(() => this.loading() && !this.cattle().length && !this.expenses().length);

  comparison = computed(() => {
    if (!this.canViewAmounts()) return null;
    const preset = this.preset();
    const view = this.view();
    const r = spendDelta(this.expenses(), preset, this.today());
    return { ...r, label: comparisonLabel(preset, view.inProgress) };
  });
  periodTotal = computed(() => sumAmount(this.periodExpenses()));
  deltaText = computed(() => formatDelta(this.comparison()?.delta ?? null));
  deltaTone = computed<KpiTone>(() => {
    const d = this.comparison()?.delta ?? null;
    return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down';
  });
  deltaHint = computed(() => (this.deltaText() ? this.comparison()!.label : 'Sin gasto en el periodo de comparación'));

  heads = computed(() => this.cattle().length);
  value = computed(() => (this.canViewAmounts() ? herdValue(this.cattle(), this.pricePerKg()) : 0));
  /** Animals in the valued scope without a usable weight: they add $0 to the herd value. */
  unweighted = computed(() => unweightedHeads(this.cattle()));
  priceHint = computed(() => {
    const base = `Precio de referencia ${formatMoney(this.pricePerKg())}/kg`;
    const n = this.unweighted().withoutWeight;
    if (n <= 0) return base;
    return `${base} · ${n === 1 ? '1 animal sin peso no suma' : `${n} animales sin peso no suman`} al valor`;
  });
  rows = computed(() => (this.canViewAmounts() ? uppBalance(this.cattle(), this.expenses(), this.pricePerKg()) : []));
  net = computed(() => netBalance(this.rows()));
  perHeadValue = computed(() => perHead(this.periodTotal(), this.heads()));
  uppRows = computed(() => this.rows().filter(r => r.kind !== 'none'));
  noUpp = computed(() => this.rows().find(r => r.kind === 'none') ?? null);
  noUppPct = computed(() => sharePercent(this.noUpp()?.heads ?? 0, this.heads()));

  typeItems = computed<ShareItem[]>(() => spendByType(this.periodExpenses()).filter(r => r.amount > 0)
    .map(r => ({ key: r.key, label: r.label, amount: r.amount, amountText: formatMoney(r.amount) })));
  bars = computed(() => {
    if (!this.canViewAmounts()) return [];
    const { range, grain } = this.view();
    return buildTrendBars(spendTrend(this.expenses(), range, grain), grain, this.today(), formatMoney);
  });
  trendTitle = computed(() => (this.view().grain === 'DAY' ? 'Gasto por día' : 'Gasto por mes'));
  // Resultado del periodo ----------------------------------------------------------------------------
  readonly signedMoney = signedMoney;
  readonly shortDate = formatCalendarDate;
  /** The incomes block is shown only once they loaded; an error before that is an explicit error, never "$0". */
  incomesReady = computed(() => this.incomesLoaded());
  result = computed(() => (this.canViewAmounts() && this.incomesLoaded() ? periodResult(this.incomes(), this.expenses(), this.preset(), this.today()) : null));
  resultTone = computed<KpiTone>(() => resultTone(this.result()?.result ?? 0));
  /** Without a percentage (sign change, no base) the hint says what the result is compared with instead. */
  resultHint = computed(() => resultWord(this.result()?.result ?? 0) + (this.resultDeltaText() ? '' : ` · ${this.comparison()?.label ?? ''}`));
  incomeDeltaText = computed(() => formatDelta(this.result()?.incomeDelta ?? null));
  resultDeltaText = computed(() => formatDelta(this.result()?.resultDelta ?? null));
  incomeTone = computed<KpiTone>(() => { const d = this.result()?.incomeDelta ?? null; return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down'; });
  resultDeltaTone = computed<KpiTone>(() => { const d = this.result()?.resultDelta ?? null; return d === null || Math.round(d * 10) === 0 ? 'flat' : d > 0 ? 'up' : 'down'; });
  mortality = computed(() => mortalityLoss(this.mortalityCattle(), this.pricePerKg()));
  accumulated = computed(() => (this.incomesLoaded() ? accumulatedResult(this.incomes(), this.expenses()) : null));
  sales = computed(() => recentSales(this.incomes(), this.view().range, this.lookup(), 5));
  salesCount = computed(() => this.result()?.soldHeads ?? 0);

  meterWidth(pct: number | null): number { return pct === null ? 0 : Math.min(100, Math.max(0, pct)); }
}
