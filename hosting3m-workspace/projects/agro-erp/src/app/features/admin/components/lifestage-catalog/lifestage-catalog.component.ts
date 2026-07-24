import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { LifestageCatalog } from '@core/models/lifestage-catalog.model';
import { LifestageFormModalComponent } from '../lifestage-form-modal/lifestage-form-modal.component';

@Component({
  selector: 'app-lifestage-catalog',
  standalone: true,
  imports: [CommonModule, FormsModule, LifestageFormModalComponent],
  templateUrl: './lifestage-catalog.component.html',
})
export class LifestageCatalogComponent {
  public adminService = inject(AdminService);

  lifestages = this.adminService.lifestages;
  loadingLifestages = this.adminService.loadingLifestages;

  searchQuery = signal<string>('');

  filteredLifestages = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.lifestages().filter(l =>
      !q ||
      l.categoria_origen?.toLowerCase().includes(q) ||
      l.categoria_destino?.toLowerCase().includes(q) ||
      l.especie?.toLowerCase().includes(q)
    );
  });

  isModalOpen = signal<boolean>(false);
  isLoadingDetail = signal<boolean>(false);
  isReadOnlyMode = signal<boolean>(false);
  selectedLifestage = signal<LifestageCatalog | null>(null);
  currentLifestageData = signal<Partial<LifestageCatalog>>({});

  constructor() {
    this.adminService.loadLifestages();
  }

  openModal(lifestage: LifestageCatalog | null = null) {
    this.isReadOnlyMode.set(false);
    if (lifestage) {
      this.selectedLifestage.set(lifestage);
      this.currentLifestageData.set({ ...lifestage });
    } else {
      this.selectedLifestage.set(null);
      this.currentLifestageData.set(this.getEmptyLifestage());
    }
    this.isModalOpen.set(true);
  }

  closeModal() {
    this.isModalOpen.set(false);
    this.selectedLifestage.set(null);
  }

  async saveLifestage() {
    const data = this.currentLifestageData();
    const operation: 'insert' | 'update' = this.selectedLifestage() ? 'update' : 'insert';

    if (!data.especie || !data.categoria_origen || !data.categoria_destino || !data.edad_min_meses) {
      alert('⚠️ Especie, Categoría Origen, Categoría Destino y Edad Mínima son obligatorios.');
      return;
    }

    if (data.categoria_origen === data.categoria_destino) {
      alert('⚠️ La Categoría Origen y Destino no pueden ser la misma.');
      return;
    }

    try {
      await lastValueFrom(
        this.adminService.saveLifestage(data, operation, this.selectedLifestage()?.id)
      );
      alert(operation === 'insert' ? '✅ Transición registrada correctamente' : '✅ Transición actualizada correctamente');
      this.closeModal();
      this.adminService.loadLifestages();
    } catch (error) {
      console.error('[Agro-ERP] Error al guardar la transición:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
    }
  }

  async deleteLifestage(lifestage: LifestageCatalog) {
    const label = `${lifestage.categoria_origen} → ${lifestage.categoria_destino}`;
    if (!confirm(`⚠️ ¿Eliminar la transición "${label}" del catálogo? Esta acción no puede deshacerse.`)) return;

    try {
      await lastValueFrom(this.adminService.deleteLifestage(lifestage.id!));
      this.adminService.loadLifestages();
    } catch (error) {
      console.error('[Agro-ERP] Error al eliminar la transición:', error);
      alert('❌ No se pudo eliminar el registro.');
    }
  }

  private getEmptyLifestage(): Partial<LifestageCatalog> {
    return {
      especie: 'BOVINO',
      categoria_origen: '',
      categoria_destino: '',
      edad_min_meses: undefined,
      requiere_validacion_peso: true,
      notas: '',
    };
  }
}
