import { CommonModule } from '@angular/common';
import { Component, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-upp-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './upp-form-modal.component.html',
})
export class UppFormModalComponent {
  isOpen = input.required<boolean>();
  selectedUpp = input<any>(null);
  isReadonly = input<boolean>(false);
  uppData = model.required<any>();

  onClose = output<void>();
  onSave = output<void>();

  updateField(key: string, value: any) {
    this.uppData.update(current => ({ ...current, [key]: value }));
  }

  updateMetadataField(key: string, value: any) {
    this.uppData.update(current => ({
      ...current,
      metadata: { ...current.metadata, [key]: value },
    }));
  }
}
