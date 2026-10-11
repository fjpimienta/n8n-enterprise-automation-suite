import { Component, EventEmitter, Input, Output, computed, signal } from '@angular/core';
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
  /** When true, the confirm button stays disabled until the trimmed notes are non-empty. */
  @Input() notesRequired = false;
  /** While true (request in flight) both buttons are disabled. */
  @Input() busy = false;
  /** Backend error shown inside the modal; the typed notes are kept so the user can retry. */
  @Input() errorMessage: string | null = null;

  @Output() confirm = new EventEmitter<{ notas?: string }>();
  @Output() cancel = new EventEmitter<void>();

  public notas = signal<string>('');
  public hasNotes = computed(() => this.notas().trim() !== '');

  public onConfirm(): void {
    if (this.busy || (this.notesRequired && !this.hasNotes())) return;
    const notas = this.notas().trim();
    // The notes are NOT cleared here: on a backend error the modal stays open for a retry.
    // The parent closes (destroys) the modal on success.
    this.confirm.emit(notas ? { notas } : {});
  }

  public onCancel(): void {
    if (this.busy) return;
    this.notas.set('');
    this.cancel.emit();
  }
}
