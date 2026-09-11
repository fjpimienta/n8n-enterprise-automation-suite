import { Component, EventEmitter, Input, Output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

/**
 * Modal de confirmación genérico (Tabler UI) para acciones irreversibles. No contiene
 * lógica de negocio — reutilizable por cualquier pantalla que necesite confirmar una
 * acción antes de ejecutarla, con una nota opcional capturada en el mismo paso.
 */
@Component({
  selector: 'app-confirm-action-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './confirm-action-modal.component.html',
})
export class ConfirmActionModalComponent {
  @Input() title = 'Confirmar acción';
  @Input() message = '¿Estás seguro de realizar esta acción?';
  @Input() confirmLabel = 'Confirmar';
  @Input() cancelLabel = 'Cancelar';
  @Input() variant: 'danger' | 'warning' | 'primary' = 'primary';
  /** Si se define, muestra un textarea opcional de notas con esta etiqueta. */
  @Input() notesLabel?: string;

  @Output() confirm = new EventEmitter<{ notas?: string }>();
  @Output() cancel = new EventEmitter<void>();

  public notas = signal<string>('');

  public onConfirm(): void {
    const notas = this.notas().trim();
    this.confirm.emit(notas ? { notas } : {});
    this.notas.set('');
  }

  public onCancel(): void {
    this.notas.set('');
    this.cancel.emit();
  }
}
