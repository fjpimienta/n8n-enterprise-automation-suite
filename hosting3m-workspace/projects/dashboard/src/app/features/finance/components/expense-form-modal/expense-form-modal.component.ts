import { Component, EventEmitter, inject, Input, Output, signal, OnChanges, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ExpenseService } from '../../services/expense.service';
import { BookingService } from '@features/booking/services/booking.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { AuthService } from 'core-auth';

@Component({
  selector: 'app-expense-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './expense-form-modal.component.html'
})
export class ExpenseFormModalComponent implements OnChanges {
  private expenseService = inject(ExpenseService);
  private authService = inject(AuthService);
  public bookingService = inject(BookingService);
  private maintenanceService = inject(MaintenanceService);

  @Input() isOpen = false;
  @Input() roomId: number | null = null; // Opcional: Si viene desde el detalle de hab.
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<void>();

  isSaving = signal(false);
  roomTickets = signal<any[]>([]);
  loadingTickets = signal(false);

  // Modelo del formulario
  expenseData = {
    description: '',
    amount: 0,
    category: 'Insumos',
    payment_method: 'Efectivo',
    expense_date: new Date().toISOString().split('T')[0], // Formato YYYY-MM-DD
    room_id: null as number | null,
    maintenance_ticket_id: null as number | null,
    expense_type: 'OPEX',
    project_phase: 'OPERACION'
  };

  /** True cuando la habitación viene fija desde el contexto (ej. Room Detail Modal) */
  get isRoomLocked(): boolean {
    return this.roomId !== null;
  }

  get effectiveRoomId(): number | null {
    return this.roomId ?? this.expenseData.room_id;
  }

  ngOnChanges(changes: SimpleChanges) {
    if (changes['isOpen'] && this.isOpen) {
      this.resetForm();
      if (this.roomId) {
        this.expenseData.room_id = this.roomId;
        this.loadTicketsForRoom(this.roomId);
      }
    }
  }

  async onRoomSelected(value: number | null) {
    this.expenseData.room_id = value;
    this.expenseData.maintenance_ticket_id = null;
    this.roomTickets.set([]);
    if (value) await this.loadTicketsForRoom(value);
  }

  private async loadTicketsForRoom(roomId: number) {
    this.loadingTickets.set(true);
    try {
      const tickets = await this.maintenanceService.getTickets({ room_id: roomId });
      this.roomTickets.set(tickets);
    } catch (error) {
      this.roomTickets.set([]);
    } finally {
      this.loadingTickets.set(false);
    }
  }

  projectPhases = [
    { value: 'OPERACION', label: '🏨 Operación Normal' },
    { value: 'FASE_0', label: '⚡ Fase 0: Infraestructura' },
    { value: 'FASE_1', label: '🧱 Fase 1: Planta Baja' },
    { value: 'FASE_2', label: '🚧 Fase 2: Primer Piso Ala Norte' },
    { value: 'FASE_3', label: '🏗️ Fase 3: Primer Piso Ala Sur' },
    { value: 'FASE_4', label: '🧱 Fase 4: Segundo Piso' }
  ];

  categories = ['Insumos', 'Mantenimiento', 'Limpieza', 'Servicios', 'Nómina', 'Marketing', 'Caja Chica'];
  paymentMethods = ['Efectivo', 'Transferencia', 'Tarjeta Corp'];

  async submit() {
    if (!this.expenseData.description || !this.expenseData.amount) {
      alert('Por favor completa concepto y monto.');
      return;
    }

    this.isSaving.set(true);
    try {
      const user = this.authService.currentUser();

      await this.expenseService.createExpense({
        ...this.expenseData,
        amount: Number(this.expenseData.amount), // Asegurar número
        category: this.expenseData.category as any,
        payment_method: this.expenseData.payment_method as any,
        room_id: this.effectiveRoomId,
        maintenance_ticket_id: this.expenseData.maintenance_ticket_id,
        registered_by: user?.id || 0, // ID del usuario actual
        // Aquí podrías agregar shift_id si tienes el control de turnos
      });

      alert('✅ Gasto registrado correctamente');
      this.onSave.emit();
      this.close();
      this.resetForm();
    } catch (error) {
      alert('Error al registrar el gasto');
    } finally {
      this.isSaving.set(false);
    }
  }

  close() {
    this.onClose.emit();
  }

  resetForm() {
    this.expenseData = {
      description: '',
      amount: 0,
      category: 'Insumos',
      payment_method: 'Efectivo',
      expense_date: new Date().toISOString().split('T')[0], // Formato YYYY-MM-DD
      room_id: null as number | null,
      maintenance_ticket_id: null as number | null,
      expense_type: 'OPEX',
      project_phase: 'OPERACION'
    };
    this.roomTickets.set([]);
  }
}