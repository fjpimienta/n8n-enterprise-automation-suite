import { CommonModule } from '@angular/common';
import { Component, computed, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { LOT_TENURE_OPTIONS, LotTenureType, ProductionUnitLot } from '@core/models/production-unit-lot.model';

/** Editable state of the lot form. Kept separate from `ProductionUnitLot` so the modal never sees ids or tenant data. */
export interface LotFormState {
  lotName: string;
  tenureType: LotTenureType;
  lessorName: string;
  locationNotes: string;
  notes: string;
}

@Component({
  selector: 'app-lot-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './lot-form-modal.component.html',
})
export class LotFormModalComponent {
  isOpen = input.required<boolean>();
  selectedLot = input<ProductionUnitLot | null>(null);
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);
  lotData = model.required<LotFormState>();

  onClose = output<void>();
  onSave = output<void>();

  readonly tenureOptions = LOT_TENURE_OPTIONS;

  /** `lessor_name` is only valid for rented parcels (`production_unit_lots_lessor_only_if_rented_check`). */
  isLessorEnabled = computed(() => this.lotData().tenureType === 'RENTADA');

  updateField<K extends keyof LotFormState>(key: K, value: LotFormState[K]) {
    this.lotData.update(current => ({ ...current, [key]: value }));
  }

  updateTenure(tenureType: LotTenureType) {
    this.lotData.update(current => ({
      ...current,
      tenureType,
      lessorName: tenureType === 'RENTADA' ? current.lessorName : ''
    }));
  }
}
