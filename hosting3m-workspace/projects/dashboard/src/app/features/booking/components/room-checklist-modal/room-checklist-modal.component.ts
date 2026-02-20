import { Component, EventEmitter, Output, inject, input, DestroyRef, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

@Component({
  selector: 'app-room-checklist-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './room-checklist-modal.component.html'
})
export class RoomChecklistModalComponent implements OnInit {
  private hotelService = inject(HotelService);
  private destroyRef = inject(DestroyRef);

  room = input.required<any>();
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<any>();

  isLoading = true;
  existingInspectionId: number | null = null;

  checklist = {
    general: {
      limpieza_pisos: false,
      cama_tendida: false,
      botes_basura: false,
      aroma_agradable: false,
      techos_esquinas: false,
      ruido_exterior: false
    },
    bano: {
      limpieza_wc: false,
      toallas_completas: false,
      amenidades_jabones: false,
      agua_caliente: false,
      sin_fugas: false,
      presion_agua: false,
      drenaje_fluido: false
    },
    equipamiento: {
      control_tv_baterias: false,
      tv_enciende: false,
      ac_funcional: false,
      ac_silencioso: false,
      luces_funcionan: false,
      internet_velocidad: false
    },
    seguridad: {
      llaves_tarjeta: false,
      puerta_cierra: false,
      caja_fuerte: false,
      barandales_firmes: false,
      pisos_antideslizantes: false
    },
    observaciones: ''
  };

  ngOnInit() {
    this.isLoading = true;
    this.hotelService.getTodayChecklist(this.room().id).pipe(
      takeUntilDestroyed(this.destroyRef)
    ).subscribe({
      next: (data) => {
        if (data && data.checklist_data) {
          this.existingInspectionId = data.id;
          const dbData = data.checklist_data;
          this.checklist = {
            general: { ...this.checklist.general, ...(dbData.general || {}) },
            bano: { ...this.checklist.bano, ...(dbData.bano || {}) },
            equipamiento: { ...this.checklist.equipamiento, ...(dbData.equipamiento || {}) },
            seguridad: { ...this.checklist.seguridad, ...(dbData.seguridad || {}) },
            observaciones: data.observaciones || dbData.observaciones || ''
          };
        } else {
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
    const obs = this.existingInspectionId
      ? this.hotelService.updateChecklist(
          this.existingInspectionId,
          this.checklist,
          this.checklist.observaciones
        )
      : this.hotelService.saveChecklist(
          this.room().id,
          this.checklist,
          this.checklist.observaciones
        );
    obs.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (res) => this.handleSuccess(res, this.existingInspectionId ? 'actualizado' : 'registrado'),
      error: (err) => this.handleError(err)
    });
  }

  private handleSuccess(res: any, accion: string) {
    this.isLoading = false;
    this.hotelService.invalidateChecklistCache(this.room().id);
    this.onSave.emit({ ...res, messageInternal: `Rondín ${accion} correctamente` });
  }

  private handleError(err: any) {
    console.error('Error al guardar:', err);
    this.isLoading = false;
    alert('❌ Ocurrió un error al guardar la inspección.');
  }

  markAll(status: boolean) {
    const keys = ['general', 'bano', 'equipamiento', 'seguridad'];
    keys.forEach(group => {
      const section = this.checklist[group as keyof typeof this.checklist];
      if (section && typeof section === 'object') {
        for (const item in section as Record<string, boolean>) {
          (section as Record<string, boolean>)[item] = status;
        }
      }
    });
  }
}
