import { ChangeDetectionStrategy, Component, computed, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  LotInput,
  PLANTING_PATTERN_OPTIONS,
  PlantationTenure,
  TENURE_OPTIONS,
  Variety,
  WATER_REGIME_OPTIONS,
} from '@core/models/agri.model';

/** Create / edit form of a palm lot. Tenure '' = "Igual que la plantación" (stored as NULL). */
@Component({
  selector: 'app-agri-lot-form-modal',
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
            <h5 class="modal-title"><i class="ti ti-layout-grid me-2"></i>{{ isEdit() ? 'Editar lote' : 'Nuevo lote' }} · {{ plantationName() }}</h5>
            <button type="button" class="btn-close btn-close-white" [disabled]="isSubmitting()" (click)="onClose.emit()"></button>
          </div>
          <div class="modal-body p-4">
            @if (errorMessage()) {
            <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2"></i>{{ errorMessage() }}</div>
            }
            <div class="row">
              <div class="col-12 col-md-3 mb-3">
                <label class="form-label fw-bold">Clave <span class="text-danger">*</span></label>
                <input type="text" class="form-control" maxlength="40" [disabled]="isSubmitting()"
                  [ngModel]="data().code" (ngModelChange)="set('code', $event)" placeholder="Ej. L-01">
              </div>
              <div class="col-12 col-md-6 mb-3">
                <label class="form-label fw-bold">Nombre</label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().name" (ngModelChange)="set('name', $event)" placeholder="Opcional">
              </div>
              <div class="col-12 col-md-3 mb-3">
                <label class="form-label fw-bold">Superficie (ha) <span class="text-danger">*</span></label>
                <input type="text" inputmode="decimal" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().areaHa" (ngModelChange)="set('areaHa', $event)">
              </div>
            </div>
            <div class="row">
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Fecha de siembra</label>
                <input type="date" class="form-control" [max]="today()" [disabled]="isSubmitting()"
                  [ngModel]="data().plantingDate" (ngModelChange)="set('plantingDate', $event)">
                <label class="form-check mt-2 mb-0">
                  <input type="checkbox" class="form-check-input" [disabled]="isSubmitting()"
                    [ngModel]="data().plantingDateIsApprox" (ngModelChange)="set('plantingDateIsApprox', $event)">
                  <span class="form-check-label">Fecha aproximada</span>
                </label>
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Variedad</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().varietyId" (ngModelChange)="set('varietyId', $event)">
                  <option value="">Sin especificar</option>
                  @for (v of varieties(); track v.id) { <option [value]="v.id">{{ v.name }}</option> }
                </select>
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Proveedor de semilla</label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().seedSupplier" (ngModelChange)="set('seedSupplier', $event)">
              </div>
            </div>
            <div class="row">
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Patrón de siembra</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().plantingPattern" (ngModelChange)="set('plantingPattern', $event)">
                  <option value="">—</option>
                  @for (o of patternOptions; track o.value) { <option [value]="o.value">{{ o.label }}</option> }
                </select>
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Espaciamiento (m)</label>
                <input type="text" inputmode="decimal" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().spacingM" (ngModelChange)="set('spacingM', $event)">
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Densidad de diseño (plantas/ha)</label>
                <input type="text" inputmode="numeric" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().designDensityPlantsHa" (ngModelChange)="set('designDensityPlantsHa', $event)" placeholder="Ej. 143">
              </div>
              <div class="col-6 col-md-3 mb-3">
                <label class="form-label">Régimen hídrico</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().waterRegime" (ngModelChange)="set('waterRegime', $event)">
                  <option value="">—</option>
                  @for (o of waterOptions; track o.value) { <option [value]="o.value">{{ o.label }}</option> }
                </select>
              </div>
            </div>
            <div class="row">
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label">Tipo de suelo</label>
                <input type="text" class="form-control" maxlength="100" [disabled]="isSubmitting()"
                  [ngModel]="data().soilType" (ngModelChange)="set('soilType', $event)">
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Tenencia del lote</label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().tenure" (ngModelChange)="setTenure($event)">
                  <option value="">Igual que la plantación ({{ plantationTenureLabel() }})</option>
                  @for (o of tenureOptions; track o.value) { <option [value]="o.value">{{ o.label }}</option> }
                </select>
              </div>
              @if (data().tenure === 'RENTADA') {
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Arrendador del lote <span class="text-danger">*</span></label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().lessorName" (ngModelChange)="set('lessorName', $event)">
              </div>
              }
            </div>
            <div class="mb-1">
              <label class="form-label">Notas</label>
              <textarea class="form-control" rows="2" [disabled]="isSubmitting()"
                [ngModel]="data().notes" (ngModelChange)="set('notes', $event)"></textarea>
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn" [disabled]="isSubmitting()" (click)="onClose.emit()">Cancelar</button>
            <button class="btn btn-primary" [disabled]="isSubmitting()" (click)="onSave.emit()">
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
export class AgriLotFormModalComponent {
  isOpen = input.required<boolean>();
  editingId = input<string | null>(null);
  plantationName = input<string>('');
  plantationTenure = input<PlantationTenure | null>(null);
  varieties = input<Variety[]>([]);
  today = input<string>('');
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);
  data = model.required<LotInput>();

  onClose = output<void>();
  onSave = output<void>();

  readonly tenureOptions = TENURE_OPTIONS;
  readonly patternOptions = PLANTING_PATTERN_OPTIONS;
  readonly waterOptions = WATER_REGIME_OPTIONS;
  isEdit = computed(() => !!this.editingId());
  plantationTenureLabel = computed(() =>
    TENURE_OPTIONS.find(o => o.value === this.plantationTenure())?.label ?? '—');

  set<K extends keyof LotInput>(key: K, value: LotInput[K]) {
    this.data.update(current => ({ ...current, [key]: value }));
  }

  /** Only a lot with its own RENTADA tenure keeps a lessor (agri_lots_lessor_only_if_rented_check). */
  setTenure(tenure: PlantationTenure | '') {
    this.data.update(current => ({ ...current, tenure, lessorName: tenure === 'RENTADA' ? current.lessorName : '' }));
  }
}
