import { ChangeDetectionStrategy, Component, computed, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { PlantationInput, PlantationTenure, TENURE_OPTIONS } from '@core/models/agri.model';

/** Create / edit form of a plantation. Never sees ids, id_company or is_default. */
@Component({
  selector: 'app-plantation-form-modal',
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
            <h5 class="modal-title"><i class="ti ti-plant-2 me-2"></i>{{ isEdit() ? 'Editar plantación' : 'Nueva plantación' }}</h5>
            <button type="button" class="btn-close btn-close-white" [disabled]="isSubmitting()" (click)="onClose.emit()"></button>
          </div>
          <div class="modal-body p-4">
            @if (errorMessage()) {
            <div class="alert alert-danger" role="alert"><i class="ti ti-alert-triangle me-2"></i>{{ errorMessage() }}</div>
            }
            <div class="row">
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Clave <span class="text-danger">*</span></label>
                <input type="text" class="form-control" maxlength="40" [disabled]="isSubmitting()"
                  [ngModel]="data().code" (ngModelChange)="set('code', $event)" placeholder="Ej. PLM-01">
                <small class="form-hint">Única en la empresa entre plantaciones activas.</small>
              </div>
              <div class="col-12 col-md-8 mb-3">
                <label class="form-label fw-bold">Nombre <span class="text-danger">*</span></label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().name" (ngModelChange)="set('name', $event)" placeholder="Ej. Plantación El Edén">
              </div>
            </div>
            <div class="row">
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Superficie total (ha) <span class="text-danger">*</span></label>
                <input type="text" inputmode="decimal" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().totalAreaHa" (ngModelChange)="set('totalAreaHa', $event)" placeholder="Ej. 120.5">
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Tenencia <span class="text-danger">*</span></label>
                <select class="form-select" [disabled]="isSubmitting()" [ngModel]="data().tenure" (ngModelChange)="setTenure($event)">
                  @for (o of tenureOptions; track o.value) { <option [value]="o.value">{{ o.label }}</option> }
                </select>
              </div>
              @if (data().tenure === 'RENTADA') {
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label fw-bold">Arrendador <span class="text-danger">*</span></label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().lessorName" (ngModelChange)="set('lessorName', $event)">
              </div>
              }
            </div>
            <hr class="my-3">
            <h6 class="text-muted text-uppercase fw-bold mb-3">Ubicación</h6>
            <div class="row">
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label">Estado</label>
                <input type="text" class="form-control" maxlength="100" [disabled]="isSubmitting()"
                  [ngModel]="data().state" (ngModelChange)="set('state', $event)">
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label">Municipio</label>
                <input type="text" class="form-control" maxlength="100" [disabled]="isSubmitting()"
                  [ngModel]="data().municipality" (ngModelChange)="set('municipality', $event)">
              </div>
              <div class="col-12 col-md-4 mb-3">
                <label class="form-label">Localidad</label>
                <input type="text" class="form-control" maxlength="150" [disabled]="isSubmitting()"
                  [ngModel]="data().locality" (ngModelChange)="set('locality', $event)">
              </div>
            </div>
            <div class="row">
              <div class="col-6 mb-3">
                <label class="form-label">Latitud</label>
                <input type="text" inputmode="decimal" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().latitude" (ngModelChange)="set('latitude', $event)" placeholder="Ej. 17.5094">
              </div>
              <div class="col-6 mb-3">
                <label class="form-label">Longitud</label>
                <input type="text" inputmode="decimal" class="form-control" [disabled]="isSubmitting()"
                  [ngModel]="data().longitude" (ngModelChange)="set('longitude', $event)" placeholder="Ej. -91.9821">
              </div>
              <div class="col-12"><small class="form-hint">Captura latitud y longitud juntas, o deja ambas vacías.</small></div>
            </div>
            <div class="mb-1 mt-3">
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
export class PlantationFormModalComponent {
  isOpen = input.required<boolean>();
  editingId = input<string | null>(null);
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);
  data = model.required<PlantationInput>();

  onClose = output<void>();
  onSave = output<void>();

  readonly tenureOptions = TENURE_OPTIONS;
  isEdit = computed(() => !!this.editingId());

  set<K extends keyof PlantationInput>(key: K, value: PlantationInput[K]) {
    this.data.update(current => ({ ...current, [key]: value }));
  }

  /** Leaving RENTADA clears the lessor (agri_plantations_lessor_only_if_rented_check). */
  setTenure(tenure: PlantationTenure) {
    this.data.update(current => ({ ...current, tenure, lessorName: tenure === 'RENTADA' ? current.lessorName : '' }));
  }
}
