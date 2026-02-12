import { Component, EventEmitter, inject, Input, Output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ExpenseService } from '../../services/expense.service';
import { AuthService } from '@core/services/auth.service';

@Component({
  selector: 'app-expense-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './expense-form-modal.component.html'
})
export class ExpenseFormModalComponent {
  private expenseService = inject(ExpenseService);
  private authService = inject(AuthService);

  @Input() isOpen = false;
  @Input() roomId: number | null = null; // Opcional: Si viene desde el detalle de hab.
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<void>();

  isSaving = signal(false);

  // Modelo del formulario
  expenseData = {
    description: '',
    amount: 0,
    category: 'Insumos',
    payment_method: 'Efectivo',
    expense_date: new Date().toISOString().split('T')[0], // Formato YYYY-MM-DD
    room_id: null as number | null,
    expense_type: 'OPEX',
    project_phase: 'OPERACION'
  };

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
        room_id: this.roomId,
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
      expense_type: 'OPEX',
      project_phase: 'OPERACION'
    };
  }
}