import { CommonModule } from '@angular/common';
import { Component, input, model, output, effect } from '@angular/core'; // 1. Importar effect
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
    // 2. Creamos un efecto que reacciona cuando el modal se abre o cambian los datos
    effect(() => {
      // Solo ejecutamos si el modal está abierto y hay datos cargados
      if (this.isOpen() && this.guestData()) {
        this.cleanDummyData();
      }
    });
  }

  private cleanDummyData() {
    // Obtenemos una copia del valor actual para no mutar directamente sin control
    const currentData = { ...this.guestData() };
    let hasChanges = false;

    // A. Limpiar Documento ID si es interno (Empieza con INT-)
    if (currentData.doc_id && currentData.doc_id.startsWith('INT-')) {
      currentData.doc_id = ''; // Lo dejamos vacío visualmente
      hasChanges = true;
    }

    // B. Limpiar Email si es ficticio (Empieza con no-email-)
    if (currentData.email && currentData.email.startsWith('no-email-')) {
      currentData.email = ''; // Lo dejamos vacío visualmente
      hasChanges = true;
    }

    // Solo si hubo cambios, actualizamos el modelo (esto actualiza la vista)
    if (hasChanges) {
      this.guestData.set(currentData);
    }
  }
}