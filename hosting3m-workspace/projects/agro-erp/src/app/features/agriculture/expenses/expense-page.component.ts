import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import { ExpenseCategory, ExpenseInput, ExpenseUnit } from '@core/models/agri-expense.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { UNCONFIRMED_MESSAGE, todayCdmx } from '../utils/agri.util';
import { ExpenseTab, canReadExpenses, emptyExpenseInput, expenseTabsFor, validateExpenseInput } from '../utils/expense.util';
import { ExpenseBalanceComponent } from './expense-balance.component';
import { ExpenseCategoryListComponent } from './expense-category-list.component';
import { ExpenseFormModalComponent } from './expense-form-modal.component';
import { ExpenseListComponent } from './expense-list.component';

const TAB_LABELS: Record<ExpenseTab, string> = { BALANCE: 'Balance', GASTOS: 'Gastos registrados', CATEGORIAS: 'Categorías' };

/**
 * "Gastos" of the active palm company (migration 081).
 * - Capture (ADMIN / OWNER / EDITOR) through sp_agri_record_expense. After saving, the EDITOR only sees
 *   "Gasto registrado": never an amount nor a list.
 * - Balance, list with voiding, CSV and category catalog: ADMIN / OWNER only, by the role of the ACTIVE
 *   company (re-checked live: a role or company change leaves an amount tab at once). The gateway answers
 *   403 to anyone else regardless.
 */
@Component({
  selector: 'app-expense-page',
  standalone: true,
  imports: [ExpenseFormModalComponent, ExpenseBalanceComponent, ExpenseListComponent, ExpenseCategoryListComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './expense-page.component.html',
})
export class ExpensePageComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  private role = computed(() => this.tenantService.activeTenant()?.role);
  canRead = computed(() => canReadExpenses(this.role()));
  tabs = computed(() => expenseTabsFor(this.role()));
  activeTab = signal<ExpenseTab>('BALANCE');
  /** Bumped after a capture / void so the open tab reloads. */
  refreshToken = signal(0);
  readonly tabLabels = TAB_LABELS;

  categories = signal<ExpenseCategory[]>([]);
  activeCategories = computed(() => this.categories().filter(c => c.isActive));
  units = signal<ExpenseUnit[]>([]);
  catalogError = signal<string | null>(null);
  catalogsLoading = signal(false);
  private catalogSeq = 0;

  isModalOpen = signal(false);
  /** "Today" in America/Mexico_City, taken when the capture opens (the screen may stay open past midnight). */
  today = signal(todayCdmx());
  formData = signal<ExpenseInput>(emptyExpenseInput('', todayCdmx()));
  formLots = signal<Lot[]>([]);
  formLotsLoading = signal(false);
  isSubmitting = signal(false);
  formError = signal<string | null>(null);
  successMessage = signal<string | null>(null);
  private lotSeq = 0;

  constructor() {
    // A company change clears everything at once (fail-closed) and reloads the catalogs of the new one.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      untracked(() => {
        this.catalogSeq++;
        this.categories.set([]);
        this.units.set([]);
        this.isModalOpen.set(false);
        this.successMessage.set(null);
        this.formError.set(null);
        if (tenantId) void this.loadCatalogs();
      });
    });
    // The role of the active company can change without reloading: leave an amount tab at once.
    effect(() => {
      const tabs = this.tabs();
      if (tabs.length && !tabs.includes(this.activeTab())) this.activeTab.set(tabs[0]);
    });
  }

  async loadCatalogs() {
    const seq = ++this.catalogSeq;
    this.catalogsLoading.set(true);
    this.catalogError.set(null);
    try {
      const [categories, units] = await Promise.all([this.api.getExpenseCategories(), this.api.getExpenseUnits()]);
      if (seq !== this.catalogSeq) return; // company switched meanwhile
      this.categories.set(categories.items);
      this.units.set(units);
      if (!categories.items.some(c => c.isActive)) {
        this.catalogError.set(this.canRead()
          ? 'No hay categorías de gasto activas. Agrégalas en la pestaña Categorías.'
          : 'No hay categorías de gasto activas. Pide a un administrador que las registre.');
      }
    } catch (error: any) {
      if (seq !== this.catalogSeq) return;
      console.error('[Agro-ERP] Error al cargar los catálogos de gastos:', error);
      this.catalogError.set(error?.message || 'No se pudieron cargar las categorías y unidades.');
    } finally {
      if (seq === this.catalogSeq) this.catalogsLoading.set(false);
    }
  }

  /** Called by the category tab after a change, so the capture uses the current catalog. */
  onCategoriesChanged() {
    void this.loadCatalogs();
  }

  // Capture ------------------------------------------------------------------------------------------

  openCapture() {
    const plantationId = this.context.activePlantationId() ?? '';
    this.today.set(todayCdmx());
    this.formData.set(emptyExpenseInput(plantationId, this.today()));
    this.formError.set(null);
    this.successMessage.set(null);
    this.isModalOpen.set(true);
    void this.loadFormLots(plantationId);
  }

  closeCapture() {
    if (!this.isSubmitting()) this.isModalOpen.set(false);
  }

  async loadFormLots(plantationId: string) {
    const seq = ++this.lotSeq;
    this.formLots.set([]);
    if (!plantationId) return;
    this.formLotsLoading.set(true);
    try {
      const { items } = await this.api.getLots(plantationId);
      if (seq !== this.lotSeq) return;
      this.formLots.set(items.filter(l => l.isActive).sort((a, b) => a.code.localeCompare(b.code, 'es', { numeric: true })));
    } catch (error: any) {
      if (seq !== this.lotSeq) return;
      console.error('[Agro-ERP] Error al cargar los lotes para el gasto:', error);
      this.formError.set(error?.message || 'No se pudieron cargar los lotes de la plantación.');
    } finally {
      if (seq === this.lotSeq) this.formLotsLoading.set(false);
    }
  }

  async saveCapture() {
    const data = this.formData();
    const today = todayCdmx();
    const validation = validateExpenseInput(data, today);
    if (validation) {
      this.formError.set(validation);
      return;
    }
    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      await this.api.recordExpense(data);
      this.isModalOpen.set(false);
      // Never an amount in the confirmation: the EDITOR does not read amounts.
      this.successMessage.set('Gasto registrado.');
      this.refreshToken.update(n => n + 1);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al registrar el gasto:', error);
      const message = error?.message || 'No se pudo registrar el gasto.';
      // Without a confirmed answer the expense may exist: the EDITOR cannot check the list, so say who can.
      this.formError.set(message === UNCONFIRMED_MESSAGE && !this.canRead()
        ? 'El servidor no confirmó el registro. Antes de capturarlo otra vez, pide a un administrador que revise si quedó guardado.'
        : message);
    } finally {
      this.isSubmitting.set(false);
    }
  }
}
