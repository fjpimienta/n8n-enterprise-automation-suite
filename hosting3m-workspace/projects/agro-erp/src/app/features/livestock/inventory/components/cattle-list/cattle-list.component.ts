import { Component, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';
import { TenantService } from 'core-auth';
import { CattleDataService } from '@core/services/cattle-data.service';

type SortableColumn = 'rfid_siniiga' | 'tenant_name' | 'category' | 'business_model' | 'current_weight_kg' | 'current_status';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule, FormsModule, CattleDetailModalComponent],
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

  // Derivado del signal global — evita una segunda fuente de verdad desincronizada
  public totalHeads = computed(() => this.cattleList().length);

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

    const source = this.cattleList();
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