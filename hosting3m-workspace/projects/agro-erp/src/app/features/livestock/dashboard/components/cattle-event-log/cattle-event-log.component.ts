import { Component, input, inject, signal, computed, effect, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { Livestock } from '../../../models/livestock.model';
import { CattleEventLogRow, CattleEventType } from '../../../models/cattle-event-log.model';
import { Paginator } from '../../utils/paginator';

/** Fila normalizada para el timeline — numéricos ya parseados (nunca comparados como texto,
 *  Contrato Meta-CRUD) y los tres identificadores de auditoría resueltos a texto legible. */
interface EventLogEntry {
  id: string;
  livestockId: string;
  rfidSiniiga: string;
  numeroFuego: string;
  eventType: CattleEventType;
  eventDate: string;
  weightKg: number | null;
  healthEventType: string | null;
  description: string | null;
  calfSex: string | null;
  calfWeightKg: number | null;
}

const EVENT_TYPE_LABEL: Record<CattleEventType, string> = {
  PESO: 'Registro de Peso',
  SALUD: 'Evento Sanitario',
  PARTO: 'Parto (madre)',
  NACIMIENTO: 'Nacimiento (cría)'
};

@Component({
  selector: 'app-cattle-event-log',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './cattle-event-log.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class CattleEventLogComponent {
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);

  // Hato ya filtrado por tenant + módulo (CRIA/ENGORDA) + especie + lote — mismo input que
  // ReproductiveDashboardComponent/EngordaDashboardComponent reciben de MainDashboardComponent.
  public cattleData = input<Livestock[]>([]);

  public readonly eventTypeLabel = EVENT_TYPE_LABEL;

  public isLoading = signal<boolean>(false);
  public loadError = signal<string | null>(null);
  private rawRows = signal<CattleEventLogRow[]>([]);

  public eventTypeFilter = signal<'TODOS' | CattleEventType>('TODOS');
  public searchQuery = signal<string>('');

  public pagination = new Paginator(() => this.filteredEntries().length);

  constructor() {
    // Recarga ante cambio de rancho activo — mismo patrón reactivo que MainDashboardComponent.
    // Fail-closed: sin tenant activo no se dispara ninguna consulta (ver loadEventLog más abajo
    // para el caso en que el tenant se pierde a mitad de una carga ya en curso).
    effect(() => {
      if (this.tenantService.activeTenantId()) {
        this.loadEventLog();
      } else {
        this.loadError.set('No hay un rancho activo — no se puede mostrar la bitácora de eventos.');
      }
    }, { allowSignalWrites: true });
  }

  public async loadEventLog(): Promise<void> {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const rows = await this.cattleApi.getCattleEventLog();
      this.rawRows.set(rows);
    } catch (error: any) {
      // MetaCRUD Silent Error Shield: el servicio deja propagar tanto los errores HTTP como
      // el `error:true` que el gateway responde con status 200 — nunca se asume éxito.
      console.error('[Agro-ERP] Error al cargar la bitácora de eventos:', error);
      this.loadError.set(error?.message || 'No se pudo cargar la bitácora de eventos.');
      this.rawRows.set([]);
    } finally {
      this.isLoading.set(false);
    }
  }

  /**
   * Segunda capa de aislamiento multi-tenant, además del filtro que ya aplica el gateway
   * sobre `tenant_id` en vw_cattle_event_log (migración 060): solo se conservan filas cuyo
   * `livestock_id` está presente en `cattleData()`, el hato ya verificado del tenant activo
   * vía vw_cattle_kpi. Cualquier fila que el gateway devolviera de otro tenant por error
   * queda descartada aquí sin excepción — fail-closed, nunca mostrada.
   */
  public entries = computed<EventLogEntry[]>(() => {
    const validIds = new Set(this.cattleData().map(a => a.id));

    return this.rawRows()
      .filter(row => validIds.has(row.livestock_id))
      .map(row => ({
        id: row.id,
        livestockId: row.livestock_id,
        rfidSiniiga: row.rfid_siniiga || 'Sin arete',
        numeroFuego: row.numero_fuego || 'S/N',
        eventType: row.event_type,
        eventDate: row.event_date,
        weightKg: row.weight_kg != null ? Number(row.weight_kg) : null,
        healthEventType: row.health_event_type ?? null,
        description: row.description ?? null,
        calfSex: row.calf_sex ?? null,
        calfWeightKg: row.calf_weight_kg != null ? Number(row.calf_weight_kg) : null
      }))
      .sort((a, b) => new Date(b.eventDate).getTime() - new Date(a.eventDate).getTime());
  });

  public filteredEntries = computed<EventLogEntry[]>(() => {
    const type = this.eventTypeFilter();
    const query = this.searchQuery().trim().toLowerCase();

    return this.entries().filter(entry => {
      const matchesType = type === 'TODOS' || entry.eventType === type;
      const matchesQuery = !query ||
        entry.rfidSiniiga.toLowerCase().includes(query) ||
        entry.numeroFuego.toLowerCase().includes(query);
      return matchesType && matchesQuery;
    });
  });

  public paginatedEntries = computed<EventLogEntry[]>(() => {
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.filteredEntries().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  public setEventTypeFilter(value: string): void {
    this.eventTypeFilter.set(value as 'TODOS' | CattleEventType);
    this.pagination.reset();
  }

  public setSearch(query: string): void {
    this.searchQuery.set(query);
    this.pagination.reset();
  }
}
