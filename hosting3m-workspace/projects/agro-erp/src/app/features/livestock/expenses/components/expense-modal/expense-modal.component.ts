import { Component, inject, signal, computed, output, Input, OnChanges, SimpleChanges, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { FormsModule } from '@angular/forms';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';

@Component({
  selector: 'app-expense-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule],
  templateUrl: './expense-modal.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ExpenseModalComponent implements OnChanges {
  private fb = inject(FormBuilder);
  private cattleApi = inject(CattleApiService);
  private cattleData = inject(CattleDataService);

  /** Animal pre-seleccionado desde contexto externo (ej. modal de COSTOS) */
  @Input() preSelectedAnimal: any = null;

  public onClose = output<void>();
  public onSaveSuccess = output<void>();

  public isSubmitting = signal(false);
  public loadingHealthLogs = signal(false);

  // Estado del buscador de animal
  public searchQuery = signal('');
  public selectedAnimal = signal<any>(null);
  public showDropdown = signal(false);
  public healthLogs = signal<any[]>([]);
  public selectedHealthEventId = signal<string | null>(null);

  // Animales filtrados por lo que escribe el usuario
  public filteredAnimals = computed(() => {
    const query = this.searchQuery().toLowerCase().trim();
    if (!query || query.length < 2) return [];
    return this.cattleData.cattleList()
      .filter(a =>
        a.rfid_siniiga?.toLowerCase().includes(query) ||
        a.numero_fuego?.toLowerCase().includes(query)
      )
      .slice(0, 8);
  });

  public expenseForm = this.fb.group({
    expense_date: [new Date().toISOString().split('T')[0], Validators.required],
    category:     ['', Validators.required],
    amount:       [null as number | null, [Validators.required, Validators.min(0.01)]],
    quantity:     [null as number | null],
    unit_measure: ['KG'],
    description:  ['']
  });

  ngOnChanges(changes: SimpleChanges) {
    if (changes['preSelectedAnimal'] && this.preSelectedAnimal) {
      this.selectedAnimal.set(this.preSelectedAnimal);
      this.loadHealthLogs(this.preSelectedAnimal.id);
    }
  }

  get isAnimalLocked(): boolean {
    return this.preSelectedAnimal !== null;
  }

  onSearchInput(value: string) {
    this.searchQuery.set(value);
    this.showDropdown.set(value.length >= 2);
    if (!value) this.clearAnimal();
  }

  selectAnimal(animal: any) {
    this.selectedAnimal.set(animal);
    this.searchQuery.set(animal.rfid_siniiga);
    this.showDropdown.set(false);
    this.selectedHealthEventId.set(null);
    this.healthLogs.set([]);
    this.loadHealthLogs(animal.id);
  }

  clearAnimal() {
    this.selectedAnimal.set(null);
    this.searchQuery.set('');
    this.healthLogs.set([]);
    this.selectedHealthEventId.set(null);
    this.showDropdown.set(false);
  }

  private async loadHealthLogs(livestockId: string) {
    this.loadingHealthLogs.set(true);
    try {
      const logs = await this.cattleApi.getHealthLogsByAnimal(livestockId);
      this.healthLogs.set(logs);
    } finally {
      this.loadingHealthLogs.set(false);
    }
  }

  async submit() {
    if (this.expenseForm.invalid) {
      this.expenseForm.markAllAsTouched();
      return;
    }

    this.isSubmitting.set(true);
    try {
      const animal = this.selectedAnimal();
      await this.cattleApi.createExpense({
        ...this.expenseForm.value,
        livestock_id:    animal ? animal.id : null,
        health_event_id: this.selectedHealthEventId() || null
      });

      this.onSaveSuccess.emit();
      this.resetForm();
    } catch (error) {
      console.error('Error en el pipeline de guardado:', error);
    } finally {
      this.isSubmitting.set(false);
    }
  }

  private resetForm() {
    this.expenseForm.reset({
      expense_date: new Date().toISOString().split('T')[0],
      unit_measure: 'KG'
    });
    if (!this.isAnimalLocked) this.clearAnimal();
    this.selectedHealthEventId.set(null);
    this.healthLogs.set([]);
  }
}
