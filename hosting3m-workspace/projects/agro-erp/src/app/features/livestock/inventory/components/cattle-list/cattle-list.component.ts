import { Component, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';
import { MetadataDetailModalComponent } from '@shared/components/metadata-detail-modal/metadata-detail-modal.component';
import { hasDisplayableMetadata } from '@shared/utils/metadata-view.util';
import { TenantService } from 'core-auth';
import { CattleDataService } from '@core/services/cattle-data.service';
import { HERD_STATUS_FILTER_OPTIONS, HerdStatusFilter, filterByHerdStatus } from '@shared/utils/herd-status.util';
import { SPECIES_FILTER_ALL, deriveAvailableSpecies, filterBySpecies } from '@shared/utils/species.util';

type SortableColumn = 'rfid_siniiga' | 'lot_name' | 'category' | 'business_model' | 'current_weight_kg' | 'current_status';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule, FormsModule, CattleDetailModalComponent, MetadataDetailModalComponent],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent implements OnInit {
  // 1. Inyectamos el servicio de datos globales que ya tiene el effect integrado
  private cattleDataService = inject(CattleDataService);

  // 2. Exponemos los signals globales directamente hacia el HTML (.html)
  public cattleList = this.cattleDataService.cattleList;
  public isLoading = this.cattleDataService.isLoading;
  public tenantService = inject(TenantService);

  // Filtro de estado de vida (venta/mortandad). Default: solo hato vivo.
  // Criterio compartido con main-dashboard vía @shared/utils/herd-status.util.
  public readonly herdStatusOptions = HERD_STATUS_FILTER_OPTIONS;
  public herdStatusFilter = signal<HerdStatusFilter>('ACTIVOS');

  private statusFilteredList = computed(() =>
    filterByHerdStatus(this.cattleList(), this.herdStatusFilter())
  );

  // Filtro "Filtrar Especie": mismas especies dinámicas que el dashboard, vía @shared/utils/species.util.
  // Se compone SOBRE el conjunto ya filtrado por estado de vida, no lo reemplaza.
  public speciesFilter = signal<string>(SPECIES_FILTER_ALL);
  public readonly speciesFilterAll = SPECIES_FILTER_ALL;
  public availableSpecies = computed(() => deriveAvailableSpecies(this.cattleList()));

  private speciesFilteredList = computed(() =>
    filterBySpecies(this.statusFilteredList(), this.speciesFilter())
  );

  // "Total de Cabezas" refleja el alcance de los filtros activos (estado de vida + especie),
  // no el conteo bruto de filas.
  public totalHeads = computed(() => this.speciesFilteredList().length);

  // Búsqueda por arete y orden de columnas (evita que el orden "salte" tras cada guardado,
  // ya que la vista vw_cattle_kpi no garantiza un orden estable entre lecturas)
  public searchQuery = signal<string>('');
  public sortColumn = signal<SortableColumn>('rfid_siniiga');
  public sortDirection = signal<'asc' | 'desc'>('asc');
  private readonly numericColumns: SortableColumn[] = ['current_weight_kg'];

  public filteredCattleList = computed(() => {
    const q = this.searchQuery().trim().toLowerCase();
    const column = this.sortColumn();
    const direction = this.sortDirection();

    const source = this.speciesFilteredList();
    const filtered = !q ? source : source.filter(animal =>
      animal.rfid_siniiga?.toLowerCase().includes(q) ||
      animal.numero_fuego?.toLowerCase().includes(q) ||
      animal.electronic_rfid?.toLowerCase().includes(q)
    );

    return [...filtered].sort((a, b) => {
      const valueA = a[column];
      const valueB = b[column];

      const comparison = this.numericColumns.includes(column)
        ? Number(valueA ?? 0) - Number(valueB ?? 0)
        : String(valueA ?? '').localeCompare(String(valueB ?? ''), 'es', { sensitivity: 'base' });

      return direction === 'asc' ? comparison : -comparison;
    });
  });

  // Modal de detalle de metadata (JSONB variable por animal — sin shape fijo)
  public metadataAnimal = signal<any | null>(null);

  public animalHasMetadata(animal: any): boolean {
    return hasDisplayableMetadata(animal?.metadata);
  }

  public openMetadata(animal: any) {
    this.metadataAnimal.set(animal);
  }

  public closeMetadata() {
    this.metadataAnimal.set(null);
  }

  // Variables para el Modal
  public isModalOpen = false;
  public modalAction: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS' | 'SALIDA' = 'ALTA';
  public selectedRfid = '';
  public selectedId = '';
  public selectedAnimal: any = null;

  async ngOnInit() {
    // Delega en el servicio compartido (misma fuente que main-dashboard, adg-alerts, etc.)
    // en vez de hacer un fetch propio: evita dos escrituras concurrentes al mismo signal
    // global y garantiza que todas las vistas muestren siempre el mismo dato.
    await this.cattleDataService.loadCattleData();
  }

  public toggleSort(column: SortableColumn) {
    if (this.sortColumn() === column) {
      this.sortDirection.update(dir => dir === 'asc' ? 'desc' : 'asc');
    } else {
      this.sortColumn.set(column);
      this.sortDirection.set('asc');
    }
  }

  public openModal(action: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS' | 'SALIDA', rfid: string = '', id: string = '', animal: any = null) {
    this.modalAction = action;
    this.selectedRfid = rfid;
    this.selectedId = id;
    this.selectedAnimal = animal;
    this.isModalOpen = true;
  }

  // Cuando el modal se cierra, verificamos si guardó algo para recargar la tabla
  public onModalClose(saved: boolean) {
    this.isModalOpen = false;
    if (saved) {
      this.cattleDataService.loadCattleData();
    }
  }
}