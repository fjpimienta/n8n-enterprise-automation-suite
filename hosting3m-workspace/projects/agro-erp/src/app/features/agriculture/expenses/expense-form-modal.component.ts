import { ChangeDetectionStrategy, Component, computed, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Lot, Plantation } from '@core/models/agri.model';
import { ExpenseCategory, ExpenseInput, ExpenseUnit } from '@core/models/agri-expense.model';
import { formatAmountInput, formatMoney, parseAmountText } from '../utils/expense.util';

/**
 * Capture form of a palm expense (ADMIN / OWNER / EDITOR). Plantation defaults to the active one ('' =
 * general expense of the company); the lot list belongs to the chosen plantation and is loaded by the
 * parent (plantationChange). The amount is typed freely ("10,000.50"), shown formatted, and sent without
 * commas by buildExpenseFields.
 */
@Component({
  selector: 'app-expense-form-modal',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (isOpen()) {
    <div class="modal-backdrop fade show"></div>
    <div class="modal modal-blur fade show d-block" tabindex="-1">
      <div class="modal-dialog modal-dialog-centered modal-lg">
        <div class="modal-content shadow-lg border-0">
          <div class="modal-header bg-dark text-white">
            <h5 class="modal-title"><i class="ti ti-receipt me-2"></i>Registrar gasto</h5>
            <button type="button" class="btn-close btn-close-white" [disabled]="isSubmitting()" (click)="onClose.emit()"></button>
          </div>
          <div class="modal-body p-4">
            @if (errorMessage()) {
            <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2"></i>{{ errorMessage() }}</div>
            }
            @if (catalogError()) {
            <div class="alert alert-warning" role="alert"><i class="ti ti-alert-circle me-2"></i>{{ catalogError() }}</div>
            }
            <div class="row">
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold">Plantación</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().plantationId" (ngModelChange)="setPlantation($event)">
                  @for (p of plantations(); track p.id) { <option [value]="p.id">{{ p.code }} · {{ p.name }}</option> }
                  <option value="">Gasto general de la empresa (sin plantación)</option>
                </select>
              </div>
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold">Lote</label>
                <select class="form-select" [disabled]="isSubmitting() || !data().plantationId || lotsLoading()"
                  [ngModel]="data().lotId" (ngModelChange)="set('lotId', $event)">
                  <option value="">{{ lotsLoading() ? 'Cargando lotes…' : 'Toda la plantación (sin lote)' }}</option>
                  @for (l of lots(); track l.id) { <option [value]="l.id">{{ l.code }}{{ l.name ? ' · ' + l.name : '' }}</option> }
                </select>
              </div>
            </div>
            <div class="row">
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold">Categoría <span class="text-danger">*</span></label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().categoryId" (ngModelChange)="set('categoryId', $event)">
                  <option value="" disabled>Elige una categoría…</option>
                  @for (c of categories(); track c.id) { <option [value]="c.id">{{ c.name }}</option> }
                </select>
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label fw-bold">Fecha <span class="text-danger">*</span></label>
                <input type="date" class="form-control" [max]="today()" [disabled]="isSubmitting()"
                  [ngModel]="data().expenseDate" (ngModelChange)="set('expenseDate', $event)">
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label fw-bold">Monto (MXN) <span class="text-danger">*</span></label>
                <input type="text" inputmode="decimal" class="form-control text-end" placeholder="0.00" [disabled]="isSubmitting()"
                  [class.is-invalid]="amountInvalid()" [ngModel]="data().amount" (ngModelChange)="set('amount', $event)" (blur)="formatAmount()">
                <div class="small mt-1" [class.text-muted]="!amountInvalid()" [class.text-danger]="amountInvalid()">{{ amountPreview() }}</div>
              </div>
            </div>
            <div class="row">
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Cantidad</label>
                <input type="text" inputmode="decimal" class="form-control" placeholder="Opcional" [disabled]="isSubmitting()"
                  [ngModel]="data().quantity" (ngModelChange)="set('quantity', $event)">
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Unidad</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().unitCode" (ngModelChange)="set('unitCode', $event)">
                  <option value="">—</option>
                  @for (u of units(); track u.code) { <option [value]="u.code">{{ u.name }}</option> }
                </select>
              </div>
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label">Proveedor</label>
                <input type="text" class="form-control" maxlength="150" placeholder="Opcional" [disabled]="isSubmitting()"
                  [ngModel]="data().supplierName" (ngModelChange)="set('supplierName', $event)">
              </div>
            </div>
            <div class="mb-3">
              <label class="form-label">Descripción</label>
              <textarea class="form-control" rows="2" placeholder="Ej. 20 bultos de fertilizante 17-17-17" [disabled]="isSubmitting()"
                [ngModel]="data().description" (ngModelChange)="set('description', $event)"></textarea>
            </div>
            <div class="row align-items-end">
              <div class="col-12 col-md-4 mb-2">
                <label class="form-check mb-0">
                  <input type="checkbox" class="form-check-input" [disabled]="isSubmitting()"
                    [ngModel]="data().isInvoiced" (ngModelChange)="setInvoiced($event)">
                  <span class="form-check-label">Tiene factura</span>
                </label>
              </div>
              @if (data().isInvoiced) {
              <div class="col-12 col-md-8 mb-2">
                <label class="form-label">Folio de la factura</label>
                <input type="text" class="form-control" maxlength="60" placeholder="Opcional" [disabled]="isSubmitting()"
                  [ngModel]="data().invoiceFolio" (ngModelChange)="set('invoiceFolio', $event)">
              </div>
              }
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn" [disabled]="isSubmitting()" (click)="onClose.emit()">Cancelar</button>
            <button class="btn btn-primary" [disabled]="isSubmitting() || categories().length === 0" (click)="onSave.emit()">
              @if (isSubmitting()) { <span class="spinner-border spinner-border-sm me-2" role="status"></span>Guardando… }
              @else { <i class="ti ti-device-floppy me-2"></i>Registrar gasto }
            </button>
          </div>
        </div>
      </div>
    </div>
    }
  `,
})
export class ExpenseFormModalComponent {
  isOpen = input.required<boolean>();
  plantations = input<Plantation[]>([]);
  lots = input<Lot[]>([]);
  lotsLoading = input<boolean>(false);
  categories = input<ExpenseCategory[]>([]);
  units = input<ExpenseUnit[]>([]);
  today = input<string>('');
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);
  catalogError = input<string | null>(null);
  data = model.required<ExpenseInput>();

  onClose = output<void>();
  onSave = output<void>();
  plantationChange = output<string>();

  private parsedAmount = computed(() => parseAmountText(this.data().amount, 2));
  amountInvalid = computed(() => Number.isNaN(this.parsedAmount()));
  amountPreview = computed(() => {
    const amount = this.parsedAmount();
    if (amount === null) return 'Ej. 10,000.50';
    return Number.isNaN(amount) ? 'Monto no válido: usa números, coma para miles y punto para centavos.' : formatMoney(amount);
  });

  set<K extends keyof ExpenseInput>(key: K, value: ExpenseInput[K]) {
    this.data.update(current => ({ ...current, [key]: value }));
  }

  /** Changing the plantation clears the lot (a lot always belongs to its plantation). */
  setPlantation(plantationId: string) {
    this.data.update(current => ({ ...current, plantationId, lotId: '' }));
    this.plantationChange.emit(plantationId);
  }

  setInvoiced(isInvoiced: boolean) {
    this.data.update(current => ({ ...current, isInvoiced, invoiceFolio: isInvoiced ? current.invoiceFolio : '' }));
  }

  formatAmount() {
    const amount = this.parsedAmount();
    if (amount !== null && !Number.isNaN(amount)) this.set('amount', formatAmountInput(amount));
  }
}
