import { CommonModule } from '@angular/common';
import { Component, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ProductionUnitSummary } from '@core/models/production-unit-lot.model';

/** Editable state of the official UPP form. Kept separate so the modal never sees ids or tenant data. */
export interface ProductionUnitFormState {
  ranchName: string;
  uppCode: string;
  stateName: string;
  municipalityName: string;
  localityName: string;
}

@Component({
  selector: 'app-production-unit-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './production-unit-form-modal.component.html',
})
export class ProductionUnitFormModalComponent {
  isOpen = input.required<boolean>();
  selectedUnit = input<ProductionUnitSummary | null>(null);
  isSubmitting = input<boolean>(false);
  errorMessage = input<string | null>(null);
  unitData = model.required<ProductionUnitFormState>();

  onClose = output<void>();
  onSave = output<void>();

  updateField<K extends keyof ProductionUnitFormState>(key: K, value: ProductionUnitFormState[K]) {
    this.unitData.update(current => ({ ...current, [key]: value }));
  }
}
