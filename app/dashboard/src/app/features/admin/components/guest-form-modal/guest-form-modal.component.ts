import { CommonModule } from '@angular/common';
import { Component, input, model, output } from '@angular/core';
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
  selectedGuest = input<any>(null); // El usuario original para saber si es edición
  guestData = model.required<any>(); // Usamos 'model' para sincronización bidireccional simple

  onClose = output<void>();
  onSave = output<void>();
}
