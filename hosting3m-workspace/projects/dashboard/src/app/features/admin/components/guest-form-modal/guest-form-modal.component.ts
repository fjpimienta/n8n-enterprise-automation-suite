import { CommonModule } from '@angular/common';
import { Component, input, model, output, effect } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-guest-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './guest-form-modal.component.html',
  styleUrl: './guest-form-modal.component.css',
})
export class GuestFormModalComponent {
  isOpen = input.required<boolean>();
  selectedGuest = input<any>(null);
  guestData = model.required<any>();

  onClose = output<void>();
  onSave = output<void>();

  constructor() {
    effect(() => {
      if (this.isOpen() && this.guestData()) {
        this.cleanDummyData();
      }
    });
  }

  private cleanDummyData() {
    const currentData = { ...this.guestData() };
    let hasChanges = false;

    if (currentData.doc_id && currentData.doc_id.startsWith('INT-')) {
      currentData.doc_id = '';
      hasChanges = true;
    }

    if (currentData.email && currentData.email.startsWith('no-email-')) {
      currentData.email = '';
      hasChanges = true;
    }

    if (hasChanges) {
      this.guestData.set(currentData);
    }
  }
}