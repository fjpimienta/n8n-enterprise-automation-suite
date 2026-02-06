import { Component, EventEmitter, Output, inject, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HotelService } from '@features/dashboard/services/hotel.service';

@Component({
  selector: 'app-room-checklist-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './room-checklist-modal.component.html'
})
export class RoomChecklistModalComponent {

  private hotelService = inject(HotelService);

  room = input.required<any>();
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<any>();

  isLoading = true; // Para bloquear mientras carga
  existingInspectionId: number | null = null;


  // Modelo de datos del Checklist
  checklist = {
    general: {
      limpieza_pisos: false,
      cama_tendida: false,
      botes_basura: false,
      aroma_agradable: false,
      techos_esquinas: false
    },
    bano: {
      limpieza_wc: false,
      toallas_completas: false,
      amenidades_jabones: false,
      agua_caliente: false,
      sin_fugas: false,
      flujo_agua: false
    },
    equipamiento: {
      control_tv_baterias: false,
      tv_enciende: false,
      ac_funcional: false,
      luces_funcionan: false
    },
    seguridad: {
      llaves_tarjeta: false,
      puerta_cierra: false,
      caja_fuerte: false
    },
    observaciones: ''
  };

  ngOnInit() {
    this.isLoading = true;

    // Buscamos si ya existe rondín hoy
    this.hotelService.getTodayChecklist(this.room().id).subscribe({
      next: (data) => {
        if (data && data.checklist_data) {
          // 1. Guardamos el ID para poder hacer UPDATE luego
          this.existingInspectionId = data.id;

          const dbData = data.checklist_data;

          // 2. FUSIÓN SEGURA (Aquí estaba tu error):
          this.checklist = {
            general: { ...this.checklist.general, ...(dbData.general || {}) },
            bano: { ...this.checklist.bano, ...(dbData.bano || {}) },
            equipamiento: { ...this.checklist.equipamiento, ...(dbData.equipamiento || {}) },
            seguridad: { ...this.checklist.seguridad, ...(dbData.seguridad || {}) },
            observaciones: data.observaciones || dbData.observaciones || ''
          };

        } else {
          console.log('🆕 Nuevo rondín (Modo Creación)');
          this.existingInspectionId = null;
        }
        this.isLoading = false;
      },
      error: (err) => {
        console.error('Error al cargar:', err);
        this.isLoading = false;
      }
    });
  }

  saveChecklist() {
    this.isLoading = true;

    // LÓGICA DE DECISIÓN: ¿Crear o Actualizar?
    if (this.existingInspectionId) {
      // --- UPDATE ---
      this.hotelService.updateChecklist(
        this.existingInspectionId,
        this.checklist,
        this.checklist.observaciones
      ).subscribe({
        next: (res) => this.handleSuccess(res, 'actualizado'),
        error: (err) => this.handleError(err)
      });
    } else {
      // --- INSERT ---
      this.hotelService.saveChecklist(
        this.room().id,
        this.checklist,
        this.checklist.observaciones
      ).subscribe({
        next: (res) => this.handleSuccess(res, 'registrado'),
        error: (err) => this.handleError(err)
      });
    }
  }

  // Helper para éxito
  private handleSuccess(res: any, accion: string) {
    this.isLoading = false;
    // Enviamos un mensaje interno para que el dashboard sepa qué decir
    this.onSave.emit({ ...res, messageInternal: `Rondín ${accion} correctamente` });
  }

  // Helper para error
  private handleError(err: any) {
    console.error('Error al guardar:', err);
    this.isLoading = false;
    alert('❌ Ocurrió un error al guardar la inspección.');
  }

  // Función auxiliar para marcar todo OK (opcional)
  markAll(status: boolean) {
    const keys = ['general', 'bano', 'equipamiento', 'seguridad'];
    keys.forEach(group => {
      // @ts-ignore
      for (const item in this.checklist[group]) {
        // @ts-ignore
        this.checklist[group][item] = status;
      }
    });
  }
}
