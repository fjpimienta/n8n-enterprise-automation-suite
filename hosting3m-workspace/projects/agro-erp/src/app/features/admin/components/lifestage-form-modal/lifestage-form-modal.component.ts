import { CommonModule } from '@angular/common';
import { Component, input, model, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { LifestageCatalog } from '@core/models/lifestage-catalog.model';

@Component({
  selector: 'app-lifestage-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './lifestage-form-modal.component.html',
})
export class LifestageFormModalComponent {
  isOpen = input.required<boolean>();
  selectedLifestage = input<LifestageCatalog | null>(null);
  isReadonly = input<boolean>(false);
  lifestageData = model.required<Partial<LifestageCatalog>>();

  onClose = output<void>();
  onSave = output<void>();

  readonly categorias = [
    'BECERRA', 'NOVILLONA', 'VACA',
    'BECERRO', 'NOVILLO', 'TORO',
    'BUCERRA', 'BUFALA',
    'BUCERRO', 'BUFALO',
    'BORREGA', 'BORREGO',
  ];

  updateField(key: string, value: any) {
    this.lifestageData.update(current => ({ ...current, [key]: value }));
  }
}
