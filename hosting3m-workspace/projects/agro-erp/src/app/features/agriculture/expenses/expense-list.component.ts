import { ChangeDetectionStrategy, Component, computed, effect, inject, input, output, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CategoryChipsComponent } from '@shared/expenses-ui/category-chips.component';
import { DetailPanelComponent } from '@shared/expenses-ui/detail-panel.component';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import { AgriExpense, ExpenseCategory } from '@core/models/agri-expense.model';
import { exportRowsToCsv } from '@shared/utils/csv-export.util';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import { expenseCsvColumns, formatMoney, periodLabel, truncToPeriod, validateBalanceRange, validateVoidReason } from '../utils/expense.util';
import { filterExpenses } from '../utils/expense-view.util';

/**
 * Recorded expenses (ADMIN / OWNER), voided ones included and flagged. No totals here: they come from the
 * balance (sp_agri_expense_balance). Voiding asks for a mandatory reason and a confirmation and goes
 * through sp_agri_void_expense; an expense is never edited nor deleted.
 */
@Component({
  selector: 'app-expense-list',
  standalone: true,
  imports: [FormsModule, CategoryChipsComponent, DetailPanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './expense-list.component.html',
})
export class ExpenseListComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  categories = input<ExpenseCategory[]>([]);
  refreshToken = input<number>(0);
  onVoided = output<void>();

  readonly money = formatMoney;

  dateFrom = signal('');
  dateTo = signal('');
  plantationId = signal('');
  lotId = signal('');
  /** Client-side filters over the loaded page only. */
  categoryId = signal('');
  search = signal('');
  showVoided = signal(true);
  selectedId = signal<string | null>(null);
  lots = signal<Lot[]>([]);

  expenses = signal<AgriExpense[]>([]);
  visible = computed(() => filterExpenses(this.expenses(), { search: this.search(), categoryId: this.categoryId(), showVoided: this.showVoided() }));
  selected = computed(() => this.expenses().find(e => e.id === this.selectedId()) ?? null);
  categoryOptions = computed(() => this.categories().map(c => ({ value: c.id, label: c.name + (c.isActive ? '' : ' (inactiva)') })));
  voidedCount = computed(() => this.expenses().filter(e => e.isVoid).length);
  isLoading = signal(false);
  loaded = signal(false);
  loadError = signal<string | null>(null);
  filterError = signal<string | null>(null);
  actionSuccess = signal<string | null>(null);
  possiblyTruncated = signal(false);
  private seq = 0;
  private lotSeq = 0;

  toVoid = signal<AgriExpense | null>(null);
  voidReason = signal('');
  voidError = signal<string | null>(null);
  isVoiding = signal(false);

  constructor() {
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      untracked(() => {
        this.seq++;
        this.resetFilters();
        this.expenses.set([]);
        this.loaded.set(false);
        this.toVoid.set(null);
        this.selectedId.set(null);
        if (tenantId) void this.load();
      });
    });
    effect(() => {
      this.refreshToken();
      untracked(() => { if (this.loaded()) void this.load(); });
    });
  }

  resetFilters() {
    const today = todayCdmx();
    this.dateFrom.set(truncToPeriod(today, 'MONTH'));
    this.dateTo.set(today);
    this.plantationId.set('');
    this.lotId.set('');
    this.categoryId.set('');
    this.search.set('');
    this.lots.set([]);
    this.filterError.set(null);
  }

  day(date: string) { return periodLabel('DAY', date, date); }

  select(expense: AgriExpense) {
    this.selectedId.set(this.selectedId() === expense.id ? null : expense.id);
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

  async load() {
    const error = validateBalanceRange(this.dateFrom(), this.dateTo(), 'MONTH');
    if (error) {
      this.filterError.set(error);
      return;
    }
    this.filterError.set(null);
    const seq = ++this.seq;
    // Fail closed: without an active company nothing is requested.
    if (!this.tenantService.activeTenantId()) {
      this.expenses.set([]);
      this.loadError.set('No hay una empresa activa.');
      return;
    }
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const { items, possiblyTruncated } = await this.api.getExpenses({
        dateFrom: this.dateFrom(), dateTo: this.dateTo(), plantationId: this.plantationId() || null,
        lotId: this.plantationId() ? this.lotId() || null : null, categoryId: null,
      });
      if (seq !== this.seq) return;
      this.expenses.set(items);
      this.possiblyTruncated.set(possiblyTruncated);
      this.loaded.set(true);
    } catch (error: any) {
      if (seq !== this.seq) return;
      // Silent Error Shield: an error is never shown as an empty list.
      console.error('[Agro-ERP] Error al cargar los gastos:', error);
      this.expenses.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar los gastos.');
    } finally {
      if (seq === this.seq) this.isLoading.set(false);
    }
  }

  place(e: AgriExpense): string {
    if (!e.plantationId) return 'General (sin plantación)';
    return `${e.plantationCode ?? ''}${e.lotCode ? ' · ' + e.lotCode : ''}`;
  }

  exportCsv() {
    if (!this.visible().length) return;
    exportRowsToCsv(this.visible(), expenseCsvColumns(), `gastos_${this.dateFrom()}_${this.dateTo()}.csv`);
  }

  // Void -----------------------------------------------------------------------------------------------

  requestVoid(expense: AgriExpense) {
    if (expense.isVoid) return;
    this.actionSuccess.set(null);
    this.voidReason.set('');
    this.voidError.set(null);
    this.toVoid.set(expense);
  }

  cancelVoid() {
    if (!this.isVoiding()) this.toVoid.set(null);
  }

  async confirmVoid() {
    const expense = this.toVoid();
    if (!expense) return;
    const error = validateVoidReason(this.voidReason());
    if (error) {
      this.voidError.set(error);
      return;
    }
    this.isVoiding.set(true);
    this.voidError.set(null);
    try {
      await this.api.voidExpense(expense.id, this.voidReason());
      this.toVoid.set(null);
      this.actionSuccess.set(`Gasto del ${expense.expenseDate} por ${formatMoney(expense.amount)} anulado.`);
      this.onVoided.emit();
    } catch (error: any) {
      // Shown inside the dialog, in Spanish (procedure message), never only in the console.
      console.error('[Agro-ERP] Error al anular el gasto:', error);
      this.voidError.set(error?.message || 'No se pudo anular el gasto.');
    } finally {
      this.isVoiding.set(false);
    }
  }
}
