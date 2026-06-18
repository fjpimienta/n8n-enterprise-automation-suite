import { Component, inject, signal, output, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { CattleApiService } from '@core/services/cattle-api.service';

@Component({
  selector: 'app-expense-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './expense-modal.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ExpenseModalComponent {
  private fb = inject(FormBuilder);
  private cattleApi = inject(CattleApiService);

  // 🚀 Comunicadores con el componente Padre (Main Dashboard)
  public onClose = output<void>();
  public onSaveSuccess = output<void>();

  public isSubmitting = signal(false);

  // 🚀 Formulario Reactivo Estricto
  public expenseForm = this.fb.group({
    expense_date: [new Date().toISOString().split('T')[0], Validators.required],
    category: ['', Validators.required],
    amount: [null, [Validators.required, Validators.min(0.01)]],
    quantity: [null],
    unit_measure: ['KG'],
    description: ['']
  });

  async submit() {
    if (this.expenseForm.invalid) {
      this.expenseForm.markAllAsTouched();
      return;
    }

    this.isSubmitting.set(true);
    try {
      // Pasamos los valores puros. El servicio se encarga del tenant_id
      await this.cattleApi.createExpense(this.expenseForm.value);

      // Emitimos señal de éxito y limpiamos
      this.onSaveSuccess.emit();
      this.expenseForm.reset();
    } catch (error) {
      console.error('Error en el pipeline de guardado:', error);
    } finally {
      this.isSubmitting.set(false);
    }
  }
}