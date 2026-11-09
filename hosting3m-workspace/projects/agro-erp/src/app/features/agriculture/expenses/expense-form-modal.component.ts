import { ChangeDetectionStrategy, Component, computed, effect, input, model, output, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Lot, Plantation } from '@core/models/agri.model';
import { ExpenseCategory, ExpenseInput, ExpenseUnit } from '@core/models/agri-expense.model';
import { CategoryChipsComponent } from '@shared/expenses-ui/category-chips.component';
import { formatAmountInput, formatMoney, parseAmountText } from '../utils/expense.util';
import { addDays, dateShortcutOf, isCaptureReady } from '../utils/expense-view.util';

/**
 * Capture form of a palm expense (ADMIN / OWNER / EDITOR). Plantation defaults to the active one ('' =
 * general expense of the company); the lot list belongs to the chosen plantation and is loaded by the
 * parent (plantationChange). The amount is typed freely ("10,000.50"), shown formatted, and sent without
 * commas by buildExpenseFields.
 */
@Component({
  selector: 'app-expense-form-modal',
  standalone: true,
  imports: [FormsModule, CategoryChipsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  styles: `
    .amount { font-size: 2rem; font-weight: 700; text-align: right; min-height: 64px; font-variant-numeric: tabular-nums; }
    .touch { min-height: 44px; }
    .seg { display: flex; flex-wrap: wrap; gap: .4rem; }
    .seg button { min-height: 44px; padding: 0 1rem; border-radius: 999px; border: 1px solid #c9d1dc; background: #fff; color: #1a2234; }
    .seg button[aria-pressed='true'] { background: #1f6b3f; border-color: #1f6b3f; color: #fff; font-weight: 600; }
    .seg button:focus-visible, summary:focus-visible { outline: 3px solid #14532d; outline-offset: 2px; }
    summary { cursor: pointer; min-height: 44px; display: flex; align-items: center; color: #14532d; font-weight: 600; }
    .btn-save { background: #1f6b3f; border-color: #1f6b3f; color: #fff; min-height: 48px; font-weight: 600; font-variant-numeric: tabular-nums; }
    .btn-save:disabled { opacity: .55; }
    .btn-save:focus-visible { outline: 3px solid #14532d; outline-offset: 2px; }
  `,
  template: `
    @if (isOpen()) {
    <div class="modal-backdrop fade show"></div>
    <div class="modal modal-blur fade show d-block" tabindex="-1" role="dialog" aria-modal="true" aria-labelledby="exp-form-title">
      <div class="modal-dialog modal-dialog-centered modal-dialog-scrollable modal-lg modal-fullscreen-sm-down">
        <div class="modal-content shadow-lg border-0">
          <div class="modal-header">
            <h5 class="modal-title" id="exp-form-title"><i class="ti ti-receipt me-2" aria-hidden="true"></i>Registrar gasto</h5>
            <button type="button" class="btn-close touch" aria-label="Cerrar" [disabled]="isSubmitting()" (click)="onClose.emit()"></button>
          </div>
          <div class="modal-body p-3 p-md-4">
            <div aria-live="assertive">
              @if (errorMessage()) {
              <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2" aria-hidden="true"></i>{{ errorMessage() }}</div>
              }
              @if (catalogError()) {
              <div class="alert alert-warning" role="alert"><i class="ti ti-alert-circle me-2" aria-hidden="true"></i>{{ catalogError() }}</div>
              }
            </div>

            <div class="mb-4">
              <label class="form-label fw-bold" for="exp-form-amount">Monto (MXN) <span class="text-danger" aria-hidden="true">*</span></label>
              <input id="exp-form-amount" type="text" inputmode="decimal" class="form-control amount" placeholder="0.00" autocomplete="off"
                [disabled]="isSubmitting()" [class.is-invalid]="amountInvalid()" [attr.aria-invalid]="amountInvalid()" aria-describedby="exp-form-amount-hint"
                [ngModel]="data().amount" (ngModelChange)="set('amount', $event)" (blur)="formatAmount()">
              <div id="exp-form-amount-hint" class="small mt-1" [class.text-muted]="!amountInvalid()" [class.text-danger]="amountInvalid()">{{ amountPreview() }}</div>
            </div>

            <div class="mb-4">
              <span class="form-label fw-bold d-block" id="exp-form-cat-label">Categoría <span class="text-danger" aria-hidden="true">*</span></span>
              <exp-category-chips [options]="categoryOptions()" [value]="data().categoryId" [large]="true" [disabled]="isSubmitting()"
                ariaLabel="Categoría del gasto" (valueChange)="set('categoryId', $event)"></exp-category-chips>
            </div>

            <div class="row">
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold" for="exp-form-plantation">Plantación</label>
                <select id="exp-form-plantation" class="form-select touch" [disabled]="isSubmitting()" [ngModel]="data().plantationId" (ngModelChange)="setPlantation($event)">
                  @for (p of plantations(); track p.id) { <option [value]="p.id">{{ p.code }} · {{ p.name }}</option> }
                  <option value="">Gasto general de la empresa (sin plantación)</option>
                </select>
              </div>
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold" for="exp-form-lot">Lote</label>
                <select id="exp-form-lot" class="form-select touch" [disabled]="isSubmitting() || !data().plantationId || lotsLoading()"
                  [ngModel]="data().lotId" (ngModelChange)="set('lotId', $event)">
                  <option value="">{{ lotsLoading() ? 'Cargando lotes…' : 'Toda la plantación (sin lote)' }}</option>
                  @for (l of lots(); track l.id) { <option [value]="l.id">{{ l.code }}{{ l.name ? ' · ' + l.name : '' }}</option> }
                </select>
              </div>
            </div>

            <div class="mb-3">
              <span class="form-label fw-bold d-block">Fecha <span class="text-danger" aria-hidden="true">*</span></span>
              <div class="seg" role="group" aria-label="Fecha del gasto">
                <button type="button" [attr.aria-pressed]="shortcut() === 'TODAY'" [disabled]="isSubmitting()" (click)="pickToday()">Hoy</button>
                <button type="button" [attr.aria-pressed]="shortcut() === 'YESTERDAY'" [disabled]="isSubmitting()" (click)="pickYesterday()">Ayer</button>
                <button type="button" [attr.aria-pressed]="shortcut() === 'OTHER'" [disabled]="isSubmitting()" (click)="forceOther.set(true)">Otra fecha</button>
              </div>
              @if (shortcut() === 'OTHER') {
              <label class="visually-hidden" for="exp-form-date">Fecha del gasto</label>
              <input id="exp-form-date" type="date" class="form-control touch mt-2" style="max-width: 220px;" [max]="today()" [disabled]="isSubmitting()"
                [ngModel]="data().expenseDate" (ngModelChange)="set('expenseDate', $event)">
              }
            </div>

            <details class="mt-3">
              <summary>Más detalles (opcional)</summary>
              <div class="row mt-2">
                <div class="col-6 col-md-3 mb-3">
                  <label class="form-label" for="exp-form-qty">Cantidad</label>
                  <input id="exp-form-qty" type="text" inputmode="decimal" class="form-control touch" placeholder="Opcional" [disabled]="isSubmitting()"
                    [ngModel]="data().quantity" (ngModelChange)="set('quantity', $event)">
                </div>
                <div class="col-6 col-md-3 mb-3">
                  <label class="form-label" for="exp-form-unit">Unidad</label>
                  <select id="exp-form-unit" class="form-select touch" [disabled]="isSubmitting()" [ngModel]="data().unitCode" (ngModelChange)="set('unitCode', $event)">
                    <option value="">—</option>
                    @for (u of units(); track u.code) { <option [value]="u.code">{{ u.name }}</option> }
                  </select>
                </div>
                <div class="col-12 col-md-6 mb-3">
                  <label class="form-label" for="exp-form-supplier">Proveedor</label>
                  <input id="exp-form-supplier" type="text" class="form-control touch" maxlength="150" placeholder="Opcional" [disabled]="isSubmitting()"
                    [ngModel]="data().supplierName" (ngModelChange)="set('supplierName', $event)">
                </div>
              </div>
              <div class="mb-3">
                <label class="form-label" for="exp-form-desc">Descripción</label>
                <textarea id="exp-form-desc" class="form-control" rows="2" placeholder="Ej. 20 bultos de fertilizante 17-17-17" [disabled]="isSubmitting()"
                  [ngModel]="data().description" (ngModelChange)="set('description', $event)"></textarea>
              </div>
              <div class="row align-items-end">
                <div class="col-12 col-md-4 mb-2">
                  <label class="form-check mb-0 touch d-flex align-items-center gap-2">
                    <input type="checkbox" class="form-check-input mt-0" [disabled]="isSubmitting()" [ngModel]="data().isInvoiced" (ngModelChange)="setInvoiced($event)">
                    <span class="form-check-label">Tiene factura</span>
                  </label>
                </div>
                @if (data().isInvoiced) {
                <div class="col-12 col-md-8 mb-2">
                  <label class="form-label" for="exp-form-folio">Folio de la factura</label>
                  <input id="exp-form-folio" type="text" class="form-control touch" maxlength="60" placeholder="Opcional" [disabled]="isSubmitting()"
                    [ngModel]="data().invoiceFolio" (ngModelChange)="set('invoiceFolio', $event)">
                </div>
                }
              </div>
            </details>
          </div>
          <div class="modal-footer">
            <button class="btn touch" [disabled]="isSubmitting()" (click)="onClose.emit()">Cancelar</button>
            <button class="btn btn-save" [disabled]="isSubmitting() || !ready()" (click)="onSave.emit()">
              @if (isSubmitting()) { <span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Guardando… }
              @else { <i class="ti ti-device-floppy me-2" aria-hidden="true"></i>{{ saveLabel() }} }
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

  constructor() {
    // Every time the capture opens the date goes back to its shortcut ("Hoy" is the default).
    effect(() => { if (this.isOpen()) untracked(() => this.forceOther.set(false)); });
  }

  /** True once "Otra fecha" is chosen, so the date input stays visible even if it equals today. */
  forceOther = signal(false);
  shortcut = computed(() => (this.forceOther() ? 'OTHER' : dateShortcutOf(this.data().expenseDate, this.today())));
  categoryOptions = computed(() => this.categories().map(c => ({ value: c.id, label: c.name })));
  ready = computed(() => isCaptureReady(this.data()));
  saveLabel = computed(() => {
    const amount = this.parsedAmount();
    return this.ready() && amount !== null ? `Registrar gasto · ${formatMoney(amount)}` : 'Registrar gasto';
  });

  pickToday() { this.forceOther.set(false); this.set('expenseDate', this.today()); }
  pickYesterday() { this.forceOther.set(false); this.set('expenseDate', addDays(this.today(), -1)); }

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
