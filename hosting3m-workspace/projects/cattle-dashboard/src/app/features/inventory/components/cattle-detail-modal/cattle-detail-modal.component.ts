import { Component, inject, Input, Output, EventEmitter, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { CattleApiService } from '@core/services/cattle-api.service';

@Component({
  selector: 'app-cattle-detail-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './cattle-detail-modal.component.html',
  styleUrls: ['./cattle-detail-modal.component.scss']
})
export class CattleDetailModalComponent implements OnInit {
  private fb = inject(FormBuilder);
  private cattleApi = inject(CattleApiService); // Inyectamos el nuevo servicio

  @Input() actionType: 'ALTA' | 'SALUD' | 'PESO' = 'ALTA';
  @Input() selectedRfid: string = '';
  @Input() livestockId: string = ''; // Necesitaremos el UUID interno (id) para relacionar salud y peso
  @Output() close = new EventEmitter<boolean>(); // Emitimos true si se guardó con éxito

  public isSaving = signal<boolean>(false); // Control de carga
  private today = new Date().toISOString().split('T')[0];

  public altaForm: FormGroup = this.fb.group({
    rfid_siniiga: ['', [Validators.required, Validators.minLength(4)]],
    electronic_rfid: ['', [Validators.minLength(15)]],
    business_model: ['CRIA', Validators.required],
    category: ['VACA', Validators.required],
    current_status: ['ACTIVO', Validators.required], // Agregado por tu estructura DB
    current_weight_kg: ['', [Validators.required, Validators.min(1)]],
    birth_date: [this.today, Validators.required]
  });

  public saludForm: FormGroup = this.fb.group({
    livestock_id: [''], // El UUID foráneo
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required], // Solo visual
    event_type: ['VACUNACION', Validators.required],
    event_date: [this.today, Validators.required],
    description: [''],
    medicines_json: [{}] // Agregado por tu estructura DB
  });

  public pesoForm: FormGroup = this.fb.group({
    livestock_id: [''], // El UUID foráneo
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required], // Solo visual
    weight_kg: ['', [Validators.required, Validators.min(1)]],
    log_date: [this.today, Validators.required]
  });

  ngOnInit() {
    if (this.selectedRfid) {
      this.saludForm.patchValue({
        rfid_siniiga: this.selectedRfid,
        livestock_id: this.livestockId
      });
      this.pesoForm.patchValue({
        rfid_siniiga: this.selectedRfid,
        livestock_id: this.livestockId
      });
    }
  }

  public async submitForm() {
    // 1. Validar el formulario activo
    if (this.actionType === 'ALTA' && this.altaForm.invalid) return alert('Completa los campos obligatorios./ALTA');
    if (this.actionType === 'SALUD' && this.saludForm.invalid) return alert('Completa los campos obligatorios./SALUD');
    if (this.actionType === 'PESO' && this.pesoForm.invalid) return alert('Completa los campos obligatorios./PESO');

    this.isSaving.set(true);

    try {
      // 2. Enviar a PostgreSQL vía Meta-CRUD
      if (this.actionType === 'ALTA') {
        const payload = this.altaForm.value;
        await this.cattleApi.createLivestock(payload);
      }
      else if (this.actionType === 'SALUD') {
        const payload = this.saludForm.getRawValue(); // getRawValue para incluir campos disabled
        await this.cattleApi.createHealthLog({
          livestock_id: payload.livestock_id,
          event_type: payload.event_type,
          event_date: payload.event_date,
          description: payload.description,
          medicines_json: {} // Aquí podrías mandar un objeto JSON si capturas medicinas
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

      alert('✅ Registro guardado exitosamente en el Ledger.');
      this.closeModal(true); // Emitimos true para que la tabla se recargue

    } catch (error: any) {
      console.error('Error al guardar en PostgreSQL:', error);
      alert(`❌ Ocurrió un error al guardar: ${error.message || 'Error de conexión'}`);
    } finally {
      this.isSaving.set(false);
    }
  }

  public closeModal(saved: boolean = false) {
    this.close.emit(saved);
  }
}