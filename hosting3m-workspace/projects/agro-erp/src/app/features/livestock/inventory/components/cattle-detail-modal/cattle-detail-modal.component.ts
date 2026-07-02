import { Component, inject, Input, Output, EventEmitter, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { CattleApiService } from '@core/services/cattle-api.service';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';

@Component({
  selector: 'app-cattle-detail-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, ExpenseModalComponent],
  templateUrl: './cattle-detail-modal.component.html',
  styleUrls: ['./cattle-detail-modal.component.scss']
})
export class CattleDetailModalComponent implements OnInit {
  private fb = inject(FormBuilder);
  private cattleApi = inject(CattleApiService);

  @Input() actionType: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS' | 'SALIDA' = 'ALTA';
  @Input() selectedRfid: string = '';
  @Input() livestockId: string = '';
  @Input() selectedAnimal: any = null;
  @Output() close = new EventEmitter<boolean>();

  public isSaving = signal<boolean>(false);
  private today = new Date().toISOString().split('T')[0];

  // Estado del sub-módulo COSTOS
  public animalExpenses = signal<any[]>([]);
  public loadingCosts = signal(false);
  public showSubExpenseModal = signal(false);

  public totalCost = computed(() =>
    this.animalExpenses().reduce((sum, e) => sum + Number(e.amount || 0), 0)
  );

  public costPerKg = computed(() => {
    const weight = Number(this.selectedAnimal?.current_weight_kg || 0);
    return weight > 0 ? this.totalCost() / weight : 0;
  });

  // Referencia visual (no autoritativa) de vigencia normativa TB/BR. La validación real la hace el SP.
  public diasDesde(fecha?: string): number | null {
    if (!fecha) return null;
    return Math.floor((Date.now() - new Date(fecha).getTime()) / 86400000);
  }

  // Postgres rechaza '' en columnas date ("invalid input syntax for type date").
  // Los selects/inputs opcionales del form mandan '' cuando quedan vacíos; se normalizan a null.
  private sanitizeDates(payload: any): any {
    return {
      ...payload,
      tb_test_date: payload.tb_test_date || null,
      br_test_date: payload.br_test_date || null
    };
  }

  public altaForm: FormGroup = this.fb.group({
    rfid_siniiga: ['S/N', [Validators.required]], // Por defecto S/N
    numero_fuego: [''], // 🐂 NUEVO: Número interno o de fierro
    electronic_rfid: ['', [Validators.minLength(15)]],
    business_model: ['CRIA', Validators.required],
    category: ['VACA', Validators.required],
    current_status: ['ACTIVO', Validators.required],
    current_weight_kg: ['', [Validators.required, Validators.min(1)]],
    birth_date: [this.today, Validators.required],
    upp_origen: [''],
    tb_test_date: [''],
    br_test_date: ['']
  });

  public saludForm: FormGroup = this.fb.group({
    livestock_id: [''],
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required],
    event_type: ['VACUNACION', Validators.required],
    event_date: [this.today, Validators.required],
    description: [''],
    // 🩺 NUEVOS CAMPOS CLÍNICOS PARA REPRODUCCIÓN (Mapeados del Excel)
    dx_resultado: ['VACIA'], // 'VACIA' o 'PREÑADA'
    dx_dias_gestacion: [0], // Ej. 120 (Si está preñada)
    dx_condicion: ['UNE'], // UNE, UT, etc.
    dx_ovario: ['N/A'] // OI, OD, N/A
  });

  public pesoForm: FormGroup = this.fb.group({
    livestock_id: [''],
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required],
    weight_kg: ['', [Validators.required, Validators.min(1)]],
    log_date: [this.today, Validators.required]
  });

  public editForm: FormGroup = this.fb.group({
    rfid_siniiga: ['', Validators.required],
    numero_fuego: [''],
    electronic_rfid: ['', [Validators.minLength(15)]],
    business_model: ['CRIA', Validators.required],
    category: ['VACA', Validators.required],
    current_status: ['ACTIVO', Validators.required],
    current_weight_kg: ['', [Validators.required, Validators.min(1)]],
    birth_date: ['', Validators.required],
    upp_origen: [''],
    tb_test_date: [''],
    br_test_date: ['']
  });

  ngOnInit() {
    if (this.selectedRfid) {
      this.saludForm.patchValue({ rfid_siniiga: this.selectedRfid, livestock_id: this.livestockId });
      this.pesoForm.patchValue({ rfid_siniiga: this.selectedRfid, livestock_id: this.livestockId });
    }
    if (this.actionType === 'COSTOS' && this.livestockId) {
      this.loadAnimalCosts();
    }
    if (this.selectedAnimal && this.actionType === 'EDITAR') {
      this.editForm.patchValue({
        rfid_siniiga: this.selectedAnimal.rfid_siniiga,
        numero_fuego: this.selectedAnimal.numero_fuego ?? '',
        electronic_rfid: this.selectedAnimal.electronic_rfid ?? '',
        business_model: this.selectedAnimal.business_model,
        category: this.selectedAnimal.category,
        current_status: this.selectedAnimal.current_status,
        current_weight_kg: this.selectedAnimal.current_weight_kg,
        birth_date: this.selectedAnimal.birth_date?.split('T')[0] ?? '',
        upp_origen: this.selectedAnimal.upp_origen ?? '',
        tb_test_date: this.selectedAnimal.tb_test_date?.split('T')[0] ?? '',
        br_test_date: this.selectedAnimal.br_test_date?.split('T')[0] ?? ''
      });
    }
  }

  public async submitForm() {
    if (this.actionType === 'ALTA' && this.altaForm.invalid) return alert('Completa los campos obligatorios./ALTA');
    if (this.actionType === 'SALUD' && this.saludForm.invalid) return alert('Completa los campos obligatorios./SALUD');
    if (this.actionType === 'PESO' && this.pesoForm.invalid) return alert('Completa los campos obligatorios./PESO');
    if (this.actionType === 'EDITAR' && this.editForm.invalid) return alert('Completa los campos obligatorios./EDITAR');

    this.isSaving.set(true);

    try {
      // 2. Enviar a PostgreSQL vía Meta-CRUD
      if (this.actionType === 'ALTA') {
        const payload = this.sanitizeDates(this.altaForm.value);
        await this.cattleApi.createLivestock(payload);
      }
      else if (this.actionType === 'SALUD') {
        const payload = this.saludForm.getRawValue();

        // Empaquetamos la metadata clínica basándonos en el Excel
        const clinicalMetadata = payload.event_type === 'PALPACION' ? {
          resultado: payload.dx_resultado,
          dias_gestacion: payload.dx_resultado === 'PREÑADA' ? payload.dx_dias_gestacion : 0,
          condicion_utero: payload.dx_condicion,
          ovario_afectado: payload.dx_ovario
        } : {};

        await this.cattleApi.createHealthLog({
          livestock_id: payload.livestock_id,
          event_type: payload.event_type,
          event_date: payload.event_date,
          description: payload.description,
          medicines_json: clinicalMetadata // Magia pura: El JSON se guarda en PostgreSQL
        });
      }
      else if (this.actionType === 'PESO') {
        const payload = this.pesoForm.getRawValue();
        await this.cattleApi.createWeightLog({
          livestock_id: payload.livestock_id,
          weight_kg: payload.weight_kg,
          log_date: payload.log_date,
          source_device: 'CAPTURA_MANUAL'
        });
      }
      else if (this.actionType === 'EDITAR') {
        await this.cattleApi.updateLivestock(this.livestockId, this.sanitizeDates(this.editForm.value));
      }
      else if (this.actionType === 'SALIDA') {
        const electronicRfid = this.selectedAnimal?.electronic_rfid;
        if (!electronicRfid) throw new Error('Este animal no tiene RFID electrónico (bolo ruminal) registrado.');

        const resultado = await this.cattleApi.procesarSalidaGanado(electronicRfid);
        if (!resultado.success) {
          alert(`⚠️ Salida rechazada por normativa: ${resultado.motivo}`);
          this.closeModal(false); // No hubo cambios en BD, no hace falta recargar
          return;
        }
      }

      alert('✅ Registro guardado exitosamente en el Ledger.');
      this.closeModal(true); // Emitimos true para que la tabla se recargue

    } catch (error: any) {
      console.error('Error al guardar en PostgreSQL:', error);
      alert(`❌ Ocurrió un error al guardar: ${error.message || 'Error de conexión'}`);
    } finally {
      this.isSaving.set(false);
    }
  }

  public async loadAnimalCosts() {
    this.loadingCosts.set(true);
    try {
      const expenses = await this.cattleApi.getExpensesByAnimal(this.livestockId);
      this.animalExpenses.set(expenses);
    } finally {
      this.loadingCosts.set(false);
    }
  }

  public closeModal(saved: boolean = false) {
    this.close.emit(saved);
  }
}