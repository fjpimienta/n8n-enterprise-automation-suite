import { CommonModule } from '@angular/common';
import { Component, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { BreedCatalog } from '@core/models/breed-catalog.model';

@Component({
  selector: 'app-breed-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './breed-form-modal.component.html',
})
export class BreedFormModalComponent {
  isOpen = input.required<boolean>();
  selectedBreed = input<BreedCatalog | null>(null);
  isReadonly = input<boolean>(false);
  breedData = model.required<Partial<BreedCatalog>>();

  onClose = output<void>();
  onSave = output<void>();

  updateField(key: string, value: any) {
    this.breedData.update(current => ({ ...current, [key]: value }));
  }
}
