import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { BreedCatalog } from '@core/models/breed-catalog.model';
import { BreedFormModalComponent } from '../breed-form-modal/breed-form-modal.component';

@Component({
  selector: 'app-breed-catalog',
  standalone: true,
  imports: [CommonModule, FormsModule, BreedFormModalComponent],
  templateUrl: './breed-catalog.component.html',
})
export class BreedCatalogComponent {
  public adminService = inject(AdminService);

  breeds = this.adminService.breeds;
  loadingBreeds = this.adminService.loadingBreeds;

  searchQuery = signal<string>('');

  filteredBreeds = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.breeds().filter(b =>
      !q ||
      b.raza_grupo?.toLowerCase().includes(q) ||
      b.raza_variante?.toLowerCase().includes(q) ||
      b.especie?.toLowerCase().includes(q)
    );
  });

  isModalOpen = signal<boolean>(false);
  isLoadingDetail = signal<boolean>(false);
  isReadOnlyMode = signal<boolean>(false);
  selectedBreed = signal<BreedCatalog | null>(null);
  currentBreedData = signal<Partial<BreedCatalog>>({});

  constructor() {
    this.adminService.loadBreeds();
  }

  openModal(breed: BreedCatalog | null = null) {
    this.isReadOnlyMode.set(false);
    if (breed) {
      this.selectedBreed.set(breed);
      this.currentBreedData.set({ ...breed });
    } else {
      this.selectedBreed.set(null);
      this.currentBreedData.set(this.getEmptyBreed());
    }
    this.isModalOpen.set(true);
  }

  closeModal() {
    this.isModalOpen.set(false);
    this.selectedBreed.set(null);
  }

  async saveBreed() {
    const data = this.currentBreedData();
    const operation: 'insert' | 'update' = this.selectedBreed() ? 'update' : 'insert';

    if (!data.especie || !data.raza_grupo || !data.peso_adulto_hembra_kg || !data.peso_adulto_macho_kg || !data.dias_gestacion_promedio) {
      alert('⚠️ Especie, Grupo de Raza, Pesos Adultos y Días de Gestación son obligatorios.');
      return;
    }

    try {
      await lastValueFrom(
        this.adminService.saveBreed(data, operation, this.selectedBreed()?.id)
      );
      alert(operation === 'insert' ? '✅ Raza registrada correctamente' : '✅ Raza actualizada correctamente');
      this.closeModal();
      this.adminService.loadBreeds();
    } catch (error) {
      console.error('[Agro-ERP] Error al guardar la raza:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
    }
  }

  async deleteBreed(breed: BreedCatalog) {
    const label = `${breed.raza_grupo}${breed.raza_variante ? ' — ' + breed.raza_variante : ''}`;
    if (!confirm(`⚠️ ¿Eliminar la raza "${label}" del catálogo? Esta acción no puede deshacerse.`)) return;

    try {
      await lastValueFrom(this.adminService.deleteBreed(breed.id!));
      this.adminService.loadBreeds();
    } catch (error) {
      console.error('[Agro-ERP] Error al eliminar la raza:', error);
      alert('❌ No se pudo eliminar el registro.');
    }
  }

  private getEmptyBreed(): Partial<BreedCatalog> {
    return {
      especie: 'BOVINO',
      raza_grupo: '',
      raza_variante: '',
      peso_adulto_hembra_kg: undefined,
      peso_adulto_macho_kg: undefined,
      pct_peso_primer_servicio: 65.00,
      edad_min_pubertad_meses: undefined,
      dias_gestacion_promedio: undefined,
    };
  }
}
