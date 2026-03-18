import { Component, EventEmitter, Output, inject, input, OnDestroy, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule, AbstractControl, ValidationErrors } from '@angular/forms';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { HotelService } from '@features/dashboard/services/hotel.service';

/**
 * Validador personalizado para asegurar que la descripción no sea solo espacios en blanco
 */
function descriptionValidator(control: AbstractControl): ValidationErrors | null {
  const value = control.value;
  if (!value || typeof value !== 'string') {
    return { required: true };
  }
  if (value.trim().length === 0) {
    return { required: true };
  }
  if (value.trim().length < 10) {
    return { minlength: { requiredLength: 10, actualLength: value.trim().length } };
  }
  return null;
}

@Component({
  selector: 'app-maintenance-ticket-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './maintenance-ticket-modal.component.html',
  styleUrl: './maintenance-ticket-modal.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MaintenanceTicketModalComponent implements OnDestroy {
  private maintenanceService = inject(MaintenanceService);
  private hotelService = inject(HotelService);
  private fb = inject(FormBuilder);
  private cdr = inject(ChangeDetectorRef);

  // Inputs: Recibimos la habitación y (opcionalmente) el ID de inspección si viene de un rondín
  room = input.required<any>();
  inspectionId = input<number | null>(null);

  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<any>();

  isLoading = false;

  // Formulario Reactivo con validaciones robustas
  ticketForm: FormGroup = this.fb.group({
    issue_type: ['PLOMERIA', [Validators.required]],
    priority: ['NORMAL', [Validators.required]],
    description: ['', [Validators.required, descriptionValidator]]
  });

  // Getters para acceso fácil a los controles del formulario
  get issueTypeControl() {
    return this.ticketForm.get('issue_type')!;
  }

  get priorityControl() {
    return this.ticketForm.get('priority')!;
  }

  get descriptionControl() {
    return this.ticketForm.get('description')!;
  }

  /**
   * Maneja el cierre del modal y limpia el formulario
   */
  closeModal() {
    this.resetForm();
    this.onClose.emit();
  }

  /**
   * Resetea el formulario a su estado inicial
   */
  private resetForm() {
    this.ticketForm.reset({
      issue_type: 'PLOMERIA',
      priority: 'NORMAL',
      description: ''
    });
    this.ticketForm.markAsUntouched();
    this.ticketForm.markAsPristine();
    this.isLoading = false;
  }

  /**
   * Valida y guarda el ticket de mantenimiento
   */
  async saveTicket() {
    // Marcar todos los campos como touched para mostrar errores
    if (this.ticketForm.invalid) {
      this.ticketForm.markAllAsTouched();
      this.cdr.markForCheck();
      return;
    }

    // Validación adicional con trim para asegurar que no sea solo espacios
    const descriptionValue = this.descriptionControl.value?.trim();
    if (!descriptionValue || descriptionValue.length < 10) {
      this.descriptionControl.setErrors({
        required: true,
        minlength: { requiredLength: 10, actualLength: descriptionValue?.length || 0 }
      });
      this.descriptionControl.markAsTouched();
      this.cdr.markForCheck();
      return;
    }

    this.isLoading = true;
    this.cdr.markForCheck();

    try {
      const formValue = this.ticketForm.value;
      const newTicket = {
        issue_type: formValue.issue_type,
        priority: formValue.priority,
        description: descriptionValue, // Usar valor con trim
        room_id: this.room().id,
        inspection_id: this.inspectionId() || null
      };

      // 1. Crear el Ticket en la base de datos
      await this.maintenanceService.createTicket(newTicket);

      // 2. ⚡ AUTOMATIZACIÓN INTELIGENTE (Mantenimiento Diferido)
      if (this.room().status === 'occupied') {
        // Si está ocupada, NO cambiamos el estado para no romper el flujo de Check-out
        alert('✅ Ticket creado.\n\nComo la habitación está ocupada, pasará a Mantenimiento automáticamente en cuanto el huésped haga Check-out.');
      } else {
        // Si está disponible o sucia (vacía), la bloqueamos de inmediato
        await this.hotelService.updateRoomMaintenance(this.room().id);
        alert('✅ Ticket creado y habitación puesta en Mantenimiento.');
      }

      this.onSave.emit(newTicket);
      this.resetForm();
      this.onClose.emit();

    } catch (error) {
      console.error('Error al crear ticket:', error);
      alert('Error al procesar la solicitud. Por favor, intente nuevamente.');
    } finally {
      this.isLoading = false;
      this.cdr.markForCheck();
    }
  }

  /**
   * Limpieza de recursos al destruir el componente
   */
  ngOnDestroy(): void {
    this.resetForm();
  }
}