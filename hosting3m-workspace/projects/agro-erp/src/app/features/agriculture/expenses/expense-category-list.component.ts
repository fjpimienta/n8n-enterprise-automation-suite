import { ChangeDetectionStrategy, Component, computed, effect, inject, output, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TenantService } from 'core-auth';
import { CategoryInput, ExpenseCategory } from '@core/models/agri-expense.model';
import { AgriApiService } from '../services/agri-api.service';
import { categoryCodeFromName, reactivationConflict, validateCategoryInput } from '../utils/expense.util';

/**
 * Expense category catalog of the active company (ADMIN / OWNER). The code is chosen on creation and never
 * changes (P0082): to "rename" a code, deactivate the category and create another. Nothing is deleted.
 */
@Component({
  selector: 'app-expense-category-list',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
      <div class="text-muted small">{{ activeCount() }} activas / {{ categories().length }} totales · las inactivas no aparecen al capturar</div>
      <button class="btn btn-primary" (click)="openModal()"><i class="ti ti-square-rounded-plus me-2"></i>Nueva categoría</button>
    </div>

    @if (loadError()) {
    <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2"></i>{{ loadError() }}</div>
    }
    @if (actionError()) {
    <div class="alert alert-warning alert-dismissible" role="alert">
      <i class="ti ti-alert-circle me-2"></i>{{ actionError() }}
      <button type="button" class="btn-close" (click)="actionError.set(null)"></button>
    </div>
    }
    @if (actionSuccess()) {
    <div class="alert alert-success alert-dismissible" role="alert">
      <i class="ti ti-check me-2"></i>{{ actionSuccess() }}
      <button type="button" class="btn-close" (click)="actionSuccess.set(null)"></button>
    </div>
    }

    <div class="card shadow-sm border-0">
      <div class="table-responsive">
        <table class="table table-vcenter card-table table-sm">
          <thead><tr><th class="w-1">Orden</th><th>Nombre</th><th>Clave</th><th>Estado</th><th class="w-1"></th></tr></thead>
          <tbody>
            @for (c of categories(); track c.id) {
            <tr [class.text-muted]="!c.isActive">
              <td>{{ c.sortOrder }}</td>
              <td class="fw-medium">{{ c.name }}</td>
              <td><code>{{ c.code }}</code></td>
              <td>@if (c.isActive) { <span class="badge bg-green-lt">Activa</span> } @else { <span class="badge bg-secondary-lt">Inactiva</span> }</td>
              <td>
                <div class="btn-list flex-nowrap">
                  <button class="btn btn-icon btn-outline-secondary btn-sm" title="Editar" [disabled]="busyId() === c.id" (click)="openModal(c)"><i class="ti ti-edit"></i></button>
                  @if (c.isActive) {
                  <button class="btn btn-icon btn-outline-danger btn-sm" title="Desactivar" [disabled]="busyId() === c.id" (click)="setActive(c, false)">
                    @if (busyId() === c.id) { <span class="spinner-border spinner-border-sm" role="status"></span> } @else { <i class="ti ti-archive"></i> }
                  </button>
                  } @else {
                  <button class="btn btn-icon btn-outline-success btn-sm" title="Reactivar" [disabled]="busyId() === c.id" (click)="setActive(c, true)">
                    @if (busyId() === c.id) { <span class="spinner-border spinner-border-sm" role="status"></span> } @else { <i class="ti ti-refresh"></i> }
                  </button>
                  }
                </div>
              </td>
            </tr>
            } @empty {
            <tr><td colspan="5" class="text-center text-muted py-5">
              @if (isLoading()) { <span class="spinner-border spinner-border-sm me-2" role="status"></span>Cargando categorías… }
              @else { Esta empresa no tiene categorías de gasto. Se crean solas con la primera plantación, o agrégalas aquí. }
            </td></tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    @if (isModalOpen()) {
    <div class="modal-backdrop fade show"></div>
    <div class="modal modal-blur fade show d-block" tabindex="-1">
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content shadow-lg border-0">
          <div class="modal-header bg-dark text-white">
            <h5 class="modal-title"><i class="ti ti-tags me-2"></i>{{ editingId() ? 'Editar categoría' : 'Nueva categoría' }}</h5>
            <button type="button" class="btn-close btn-close-white" [disabled]="isSubmitting()" (click)="closeModal()"></button>
          </div>
          <div class="modal-body p-4">
            @if (formError()) {
            <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2"></i>{{ formError() }}</div>
            }
            <div class="mb-3">
              <label class="form-label fw-bold">Nombre <span class="text-danger">*</span></label>
              <input type="text" class="form-control" maxlength="120" [disabled]="isSubmitting()"
                [ngModel]="form().name" (ngModelChange)="setName($event)" placeholder="Ej. Fertilizantes">
            </div>
            <div class="row">
              <div class="col-8 mb-3">
                <label class="form-label fw-bold">Clave @if (!editingId()) { <span class="text-danger">*</span> }</label>
                <input type="text" class="form-control text-uppercase" maxlength="40" [disabled]="isSubmitting() || !!editingId()"
                  [ngModel]="form().code" (ngModelChange)="setCode($event)">
                <div class="small text-muted mt-1">
                  @if (editingId()) { La clave no se puede cambiar. } @else { Mayúsculas, números y guion bajo; no se podrá cambiar después. }
                </div>
              </div>
              <div class="col-4 mb-3">
                <label class="form-label">Orden</label>
                <input type="text" inputmode="numeric" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="form().sortOrder" (ngModelChange)="patch('sortOrder', $event)" placeholder="100">
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn" [disabled]="isSubmitting()" (click)="closeModal()">Cancelar</button>
            <button class="btn btn-primary" [disabled]="isSubmitting()" (click)="save()">
              @if (isSubmitting()) { <span class="spinner-border spinner-border-sm me-2" role="status"></span>Guardando… }
              @else { <i class="ti ti-device-floppy me-2"></i>Guardar }
            </button>
          </div>
        </div>
      </div>
    </div>
    }
  `,
})
export class ExpenseCategoryListComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);

  /** The page reloads the capture catalog after any change here. */
  onChanged = output<void>();

  categories = signal<ExpenseCategory[]>([]);
  activeCount = computed(() => this.categories().filter(c => c.isActive).length);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  actionSuccess = signal<string | null>(null);
  busyId = signal<string | null>(null);
  private seq = 0;

  isModalOpen = signal(false);
  editingId = signal<string | null>(null);
  form = signal<CategoryInput>({ code: '', name: '', sortOrder: '' });
  /** On creation the code follows the name until the user types a code of their own. */
  private codeTouched = false;
  isSubmitting = signal(false);
  formError = signal<string | null>(null);

  constructor() {
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      untracked(() => {
        this.seq++;
        this.categories.set([]);
        this.isModalOpen.set(false);
        if (tenantId) void this.load();
      });
    });
  }

  async load() {
    const seq = ++this.seq;
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const { items } = await this.api.getExpenseCategories();
      if (seq === this.seq) this.categories.set(items);
    } catch (error: any) {
      if (seq !== this.seq) return;
      console.error('[Agro-ERP] Error al cargar las categorías de gasto:', error);
      this.categories.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar las categorías.');
    } finally {
      if (seq === this.seq) this.isLoading.set(false);
    }
  }

  openModal(category: ExpenseCategory | null = null) {
    this.editingId.set(category?.id ?? null);
    this.form.set(category
      ? { code: category.code, name: category.name, sortOrder: String(category.sortOrder) }
      : { code: '', name: '', sortOrder: '' });
    this.codeTouched = !!category;
    this.formError.set(null);
    this.actionSuccess.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (!this.isSubmitting()) this.isModalOpen.set(false);
  }

  patch<K extends keyof CategoryInput>(key: K, value: CategoryInput[K]) {
    this.form.update(current => ({ ...current, [key]: value }));
  }

  setName(name: string) {
    this.form.update(current => ({ ...current, name, code: this.codeTouched ? current.code : categoryCodeFromName(name) }));
  }

  setCode(code: string) {
    this.codeTouched = true;
    this.patch('code', code.toUpperCase());
  }

  async save() {
    const id = this.editingId();
    const error = validateCategoryInput(this.form(), this.categories(), id);
    if (error) {
      this.formError.set(error);
      return;
    }
    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      if (id) await this.api.updateExpenseCategory(id, this.form());
      else await this.api.createExpenseCategory(this.form());
      this.isModalOpen.set(false);
      this.actionSuccess.set(id ? 'Categoría actualizada.' : 'Categoría registrada.');
      await this.load();
      this.onChanged.emit();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al guardar la categoría:', error);
      this.formError.set(error?.message || 'No se pudo guardar la categoría.');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  async setActive(category: ExpenseCategory, isActive: boolean) {
    this.actionError.set(null);
    this.actionSuccess.set(null);
    if (isActive) {
      const conflict = reactivationConflict(category, this.categories());
      if (conflict) {
        this.actionError.set(conflict);
        return;
      }
    }
    this.busyId.set(category.id);
    try {
      await this.api.setExpenseCategoryActive(category.id, isActive);
      this.actionSuccess.set(isActive ? `La categoría ${category.name} se reactivó.` : `La categoría ${category.name} quedó inactiva; sus gastos se conservan.`);
      await this.load();
      this.onChanged.emit();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cambiar el estado de la categoría:', error);
      this.actionError.set(error?.message || 'No se pudo cambiar el estado de la categoría.');
    } finally {
      this.busyId.set(null);
    }
  }
}
