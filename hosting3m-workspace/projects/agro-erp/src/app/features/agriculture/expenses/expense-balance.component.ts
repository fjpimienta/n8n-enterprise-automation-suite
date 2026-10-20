import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import {
  ExpenseBalance,
  ExpenseBalanceQuery,
  ExpenseCategory,
  ExpenseGrain,
  ExpenseSummaryRow,
  GRAIN_OPTIONS,
} from '@core/models/agri-expense.model';
import { exportRowsToCsv } from '@shared/utils/csv-export.util';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import {
  formatMoney,
  periodLabel,
  snapRangeToGrain,
  summaryCsvColumns,
  truncToPeriod,
  validateBalanceRange,
} from '../utils/expense.util';

/**
 * Expense balance (ADMIN / OWNER). Totals by period, category, plantation and lot come from
 * sp_agri_expense_balance; the detail table and the CSV from vw_agri_expense_summary. Nothing is added up in
 * the browser. The range is widened to whole periods so both sources always agree.
 */
@Component({
  selector: 'app-expense-balance',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './expense-balance.component.html',
})
export class ExpenseBalanceComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  categories = input<ExpenseCategory[]>([]);
  refreshToken = input<number>(0);

  readonly grainOptions = GRAIN_OPTIONS;
  readonly money = formatMoney;

  grain = signal<ExpenseGrain>('MONTH');
  dateFrom = signal('');
  dateTo = signal('');
  plantationId = signal('');
  lotId = signal('');
  categoryId = signal('');
  lots = signal<Lot[]>([]);

  applied = signal<ExpenseBalanceQuery | null>(null);
  balance = signal<ExpenseBalance | null>(null);
  summary = signal<ExpenseSummaryRow[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  filterError = signal<string | null>(null);
  possiblyTruncated = signal(false);
  private seq = 0;
  private lotSeq = 0;

  appliedLabel = computed(() => {
    const q = this.applied();
    return q ? `${periodLabel('DAY', q.dateFrom, q.dateFrom)} al ${periodLabel('DAY', q.dateTo, q.dateTo)}` : '';
  });
  maxPeriodTotal = computed(() => Math.max(0, ...(this.balance()?.byPeriod ?? []).map(p => p.totalAmount)));

  constructor() {
    // Company change: back to the defaults of the new company, nothing of the previous one stays on screen.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      untracked(() => {
        this.seq++;
        this.resetFilters();
        this.balance.set(null);
        this.summary.set([]);
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
        if (changed && q) void this.load(q);
      });
    });
  }

  label(grain: ExpenseGrain, start: string, end: string) { return periodLabel(grain, start, end); }

  resetFilters() {
    const today = todayCdmx();
    this.grain.set('MONTH');
    this.dateFrom.set(truncToPeriod(today, 'YEAR'));
    this.dateTo.set(today);
    this.plantationId.set('');
    this.lotId.set('');
    this.categoryId.set('');
    this.lots.set([]);
    this.filterError.set(null);
  }

  async setPlantation(plantationId: string) {
    this.plantationId.set(plantationId);
    this.lotId.set('');
    const seq = ++this.lotSeq;
    this.lots.set([]);
    if (!plantationId) return;
    try {
      const { items } = await this.api.getLots(plantationId);
      if (seq === this.lotSeq) this.lots.set(items.sort((a, b) => a.code.localeCompare(b.code, 'es', { numeric: true })));
    } catch (error: any) {
      if (seq !== this.lotSeq) return;
      console.error('[Agro-ERP] Error al cargar los lotes del filtro:', error);
      this.filterError.set(error?.message || 'No se pudieron cargar los lotes de la plantación.');
    }
  }

  apply() {
    const grain = this.grain();
    const snapped = snapRangeToGrain(this.dateFrom(), this.dateTo(), grain);
    const error = validateBalanceRange(snapped.from, snapped.to, grain);
    if (error) {
      this.filterError.set(error);
      return;
    }
    this.filterError.set(null);
    // The inputs show the whole periods actually used.
    this.dateFrom.set(snapped.from);
    this.dateTo.set(snapped.to);
    const query: ExpenseBalanceQuery = {
      dateFrom: snapped.from, dateTo: snapped.to, grain,
      plantationId: this.plantationId() || null, lotId: this.plantationId() ? this.lotId() || null : null,
      categoryId: this.categoryId() || null,
    };
    this.applied.set(query);
    void this.load(query);
  }

  async load(query: ExpenseBalanceQuery) {
    const seq = ++this.seq;
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const [balance, summary] = await Promise.all([this.api.getExpenseBalance(query), this.api.getExpenseSummary(query)]);
      if (seq !== this.seq) return; // a newer query or a company change won
      this.balance.set(balance);
      this.summary.set(summary.items);
      this.possiblyTruncated.set(summary.possiblyTruncated);
    } catch (error: any) {
      if (seq !== this.seq) return;
      // Silent Error Shield: an error is never shown as "$0".
      console.error('[Agro-ERP] Error al cargar el balance de gastos:', error);
      this.balance.set(null);
      this.summary.set([]);
      this.loadError.set(error?.message || 'No se pudo cargar el balance de gastos.');
    } finally {
      if (seq === this.seq) this.isLoading.set(false);
    }
  }

  exportCsv() {
    const q = this.applied();
    if (!q || !this.summary().length) return;
    exportRowsToCsv(this.summary(), summaryCsvColumns(), `balance_gastos_${q.grain.toLowerCase()}_${q.dateFrom}_${q.dateTo}.csv`);
  }
}
