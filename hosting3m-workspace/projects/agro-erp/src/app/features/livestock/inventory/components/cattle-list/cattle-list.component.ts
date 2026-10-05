import { Component, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';
import { MetadataDetailModalComponent } from '@shared/components/metadata-detail-modal/metadata-detail-modal.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { hasDisplayableMetadata } from '@shared/utils/metadata-view.util';
import { withoutFinancialMetadata } from '@shared/utils/financial-metadata.util';
import { TenantService } from 'core-auth';
import { CattleDataService } from '@core/services/cattle-data.service';
import { CattleApiService } from '@core/services/cattle-api.service';
import { HERD_STATUS_FILTER_OPTIONS, HerdStatusFilter, filterByHerdStatus } from '@shared/utils/herd-status.util';
import { SPECIES_FILTER_ALL, deriveAvailableSpecies, filterBySpecies } from '@shared/utils/species.util';
import { LOT_FILTER_ALL, deriveAvailableLots, filterByLot } from '@shared/utils/lot.util';

type SortableColumn = 'rfid_siniiga' | 'lot_name' | 'category' | 'business_model' | 'current_weight_kg' | 'current_status';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule, FormsModule, CattleDetailModalComponent, MetadataDetailModalComponent, TableToolbarComponent, TableFooterComponent],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent implements OnInit {
  // 1. Inyectamos el servicio de datos globales que ya tiene el effect integrado
  private cattleDataService = inject(CattleDataService);
  private cattleApi = inject(CattleApiService);

  // 2. Exponemos los signals globales directamente hacia el HTML (.html)
  public cattleList = this.cattleDataService.cattleList;
  public isLoading = this.cattleDataService.isLoading;
  public tenantService = inject(TenantService);

  // 🔒 COSTOS (gastos por animal) es financiero — ADMIN-only, mismo criterio y misma fuente de
  // rol que main-dashboard.component.ts (`tenantService.activeTenant()?.role`, no `roleGuard`/JWT,
  // que queda congelado a la empresa del login y no refleja un cambio de rancho en vivo).
  public isAdminForActiveTenant = computed(() =>
    (this.tenantService.activeTenant()?.role || '').toUpperCase() === 'ADMIN'
  );

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

  // Filtro "Filtrar Lote": mismos lotes dinámicos que el dashboard, vía @shared/utils/lot.util.
  // Combinable (AND) con especie: se compone SOBRE el conjunto ya filtrado por estado + especie.
  public lotFilter = signal<string>(LOT_FILTER_ALL);
  public readonly lotFilterAll = LOT_FILTER_ALL;
  public availableLots = computed(() => deriveAvailableLots(this.cattleList()));

  private lotFilteredList = computed(() =>
    filterByLot(this.speciesFilteredList(), this.lotFilter())
  );

  // "Total de Cabezas" refleja el alcance de los filtros activos (estado de vida + especie + lote),
  // no el conteo bruto de filas.
  public totalHeads = computed(() => this.lotFilteredList().length);

  // Orden de columnas (evita que el orden "salte" tras cada guardado, ya que la vista
  // vw_cattle_kpi no garantiza un orden estable entre lecturas). La búsqueda ya NO vive aquí —
  // migrada a `cattleTable` (PagedTable), mismo mecanismo normalizado (sin acentos/mayúsculas)
  // que el resto de las tablas estandarizadas, en vez del `.toLowerCase()` que tenía antes.
  public sortColumn = signal<SortableColumn>('rfid_siniiga');
  public sortDirection = signal<'asc' | 'desc'>('asc');
  private readonly numericColumns: SortableColumn[] = ['current_weight_kg'];

  public filteredCattleList = computed(() => {
    const column = this.sortColumn();
    const direction = this.sortDirection();
    const source = this.lotFilteredList();

    return [...source].sort((a, b) => {
      const valueA = a[column];
      const valueB = b[column];

      const comparison = this.numericColumns.includes(column)
        ? Number(valueA ?? 0) - Number(valueB ?? 0)
        : String(valueA ?? '').localeCompare(String(valueB ?? ''), 'es', { sensitivity: 'base' });

      return direction === 'asc' ? comparison : -comparison;
    });
  });

  // 🔑 Cambiar especie/lote/estado o de rancho activo regresa a la página 1 — mismo criterio
  // que main-dashboard.component.ts. El término de búsqueda se combina internamente en
  // PagedTable, no hace falta agregarlo aquí a mano.
  private cattleTableResetKey = computed(() => ({
    species: this.speciesFilter(),
    lot: this.lotFilter(),
    status: this.herdStatusFilter(),
    tenant: this.tenantService.activeTenantId()
  }));

  public cattleTable = new PagedTable(
    () => this.filteredCattleList(),
    () => this.cattleTableResetKey(),
    { search: { fields: row => [row.rfid_siniiga, row.numero_fuego, row.electronic_rfid] } }
  );

  // Lote histórico: capa exclusiva de esta pantalla, NO vive en CattleDataService/cattleList
  // (ese servicio es compartido con main-dashboard/adg-alerts). vw_cattle_lot_history trae el
  // último lote capturado por sp_procesar_salida_ganado en historico_movimientos.lot_origen_anterior,
  // justo antes de que la venta limpie lot_id. Fallback solo cuando lot_name viene vacío y el
  // animal ya no está ACTIVO — nunca se usa como si fuera la ubicación actual.
  private lotHistory = signal<Map<string, string>>(new Map());

  public historicalLotFor(animal: any): string | null {
    if (!animal || animal.lot_name || animal.current_status === 'ACTIVO') return null;
    return this.lotHistory().get(animal.id) ?? null;
  }

  private async loadLotHistory() {
    const rows = await this.cattleApi.getCattleLotHistory();
    const map = new Map<string, string>();
    for (const row of rows) {
      if (row?.livestock_id && row?.lot_origen_anterior) {
        map.set(row.livestock_id, row.lot_origen_anterior);
      }
    }
    this.lotHistory.set(map);
  }

  // Modal de detalle de metadata (JSONB variable por animal — sin shape fijo)
  public metadataAnimal = signal<any | null>(null);

  // 🔒 no-ADMIN nunca ve claves financieras del JSONB (purchase_price, seller_name, etc. —
  // ver financial-metadata.util.ts). Si tras quitarlas no queda nada mostrable, el ícono de
  // "Detalle" se oculta para ese rol, igual que ya pasaba con las claves puramente técnicas.
  public animalHasMetadata(animal: any): boolean {
    return hasDisplayableMetadata(this.getDisplayMetadata(animal));
  }

  public getDisplayMetadata(animal: any): unknown {
    return this.isAdminForActiveTenant() ? animal?.metadata : withoutFinancialMetadata(animal?.metadata);
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
    // El lote histórico, en cambio, es una consulta propia de esta pantalla (ver lotHistory).
    await Promise.all([
      this.cattleDataService.loadCattleData(),
      this.loadLotHistory()
    ]);
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
    // Defensa en profundidad: aunque el botón "Costos" esté oculto en el template, bloquea abrir
    // el modal financiero por consola/binding forzado para un rol no-ADMIN.
    if (action === 'COSTOS' && !this.isAdminForActiveTenant()) return;
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
      this.loadLotHistory();
    }
  }
}