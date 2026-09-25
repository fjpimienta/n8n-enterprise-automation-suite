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

type SortColumn = 'rfidSiniiga' | 'numeroFuego' | 'eventType' | 'eventDate';
type SortDirection = 'asc' | 'desc';
type GroupByMode = 'NONE' | 'ANIMAL' | 'EVENT_TYPE';

/** Bloque de filas ya agrupadas para el render por grupos (Animal / Tipo de Evento). */
interface EventLogGroup {
  key: string;
  entries: EventLogEntry[];
}

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

  // Hato completo del tenant activo (vía CattleDataService), deliberadamente SIN los filtros
  // de UI de Inventario (tab CRIA/ENGORDA, especie, lote, herdStatusFilter) — un animal fuera
  // de esos filtros (ej. VACÍA con el toggle 'ACTIVOS' + otro tab seleccionado) no debe perder
  // su historial de eventos. Ver `entries` más abajo para la capa real de aislamiento multi-tenant.
  public cattleData = input<Livestock[]>([]);

  public readonly eventTypeLabel = EVENT_TYPE_LABEL;

  public isLoading = signal<boolean>(false);
  public loadError = signal<string | null>(null);
  private rawRows = signal<CattleEventLogRow[]>([]);

  public eventTypeFilter = signal<'TODOS' | CattleEventType>('TODOS');
  public searchQuery = signal<string>('');

  // 📅 Filtro de rango de fechas (inputs type="date", combinados con AND — mismo patrón que
  // matchesType/matchesQuery). Comparación por instante real, no por substring de fecha, para
  // no depender del formato exacto (con/sin hora) que devuelva `event_date` desde el gateway.
  public dateFrom = signal<string>('');
  public dateTo = signal<string>('');

  // ↕️ Orden por columna. Default: fecha de evento, descendente (más reciente primero) —
  // mismo criterio que `entries` ya aplicaba antes de esta feature.
  public sortColumn = signal<SortColumn>('eventDate');
  public sortDirection = signal<SortDirection>('desc');

  // 🗂️ Agrupación opcional del render — puramente visual, no cambia qué filas existen
  // ni el conteo que usa el Paginator (ver `groupedPageEntries`).
  public groupBy = signal<GroupByMode>('NONE');

  public pagination = new Paginator(() => this.sortedEntries().length);

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
    // Límite inclusivo: "hasta" cubre el día completo (23:59:59.999), no solo su medianoche.
    const fromMs = this.dateFrom() ? new Date(`${this.dateFrom()}T00:00:00`).getTime() : null;
    const toMs = this.dateTo() ? new Date(`${this.dateTo()}T23:59:59.999`).getTime() : null;

    return this.entries().filter(entry => {
      const matchesType = type === 'TODOS' || entry.eventType === type;
      const matchesQuery = !query ||
        entry.rfidSiniiga.toLowerCase().includes(query) ||
        entry.numeroFuego.toLowerCase().includes(query);
      const entryMs = new Date(entry.eventDate).getTime();
      const matchesDateFrom = fromMs === null || entryMs >= fromMs;
      const matchesDateTo = toMs === null || entryMs <= toMs;
      return matchesType && matchesQuery && matchesDateFrom && matchesDateTo;
    });
  });

  /** Orden por columna, aplicado sobre `filteredEntries` y antes de la paginación. */
  public sortedEntries = computed<EventLogEntry[]>(() => {
    const column = this.sortColumn();
    const direction = this.sortDirection();
    const factor = direction === 'asc' ? 1 : -1;

    return [...this.filteredEntries()].sort((a, b) => {
      switch (column) {
        case 'rfidSiniiga':
          return factor * a.rfidSiniiga.localeCompare(b.rfidSiniiga);
        case 'numeroFuego':
          return factor * a.numeroFuego.localeCompare(b.numeroFuego);
        case 'eventType':
          return factor * this.eventTypeLabel[a.eventType].localeCompare(this.eventTypeLabel[b.eventType]);
        case 'eventDate':
        default:
          return factor * (new Date(a.eventDate).getTime() - new Date(b.eventDate).getTime());
      }
    });
  });

  public paginatedEntries = computed<EventLogEntry[]>(() => {
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.sortedEntries().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  /**
   * Agrupación puramente visual de la página actual — no altera qué filas existen ni el
   * total que usa el Paginator (basado en `sortedEntries`, no en los grupos). Con `groupBy()
   * === 'NONE'` queda vacío y la plantilla renderiza el `<tbody>` plano de siempre.
   */
  public groupedPageEntries = computed<EventLogGroup[]>(() => {
    const mode = this.groupBy();
    if (mode === 'NONE') return [];

    const groups = new Map<string, EventLogEntry[]>();
    for (const entry of this.paginatedEntries()) {
      const key = mode === 'ANIMAL'
        ? `${entry.rfidSiniiga} / ${entry.numeroFuego}`
        : this.eventTypeLabel[entry.eventType];
      const bucket = groups.get(key);
      if (bucket) {
        bucket.push(entry);
      } else {
        groups.set(key, [entry]);
      }
    }

    return Array.from(groups.entries()).map(([key, groupEntries]) => ({ key, entries: groupEntries }));
  });

  public setEventTypeFilter(value: string): void {
    this.eventTypeFilter.set(value as 'TODOS' | CattleEventType);
    this.pagination.reset();
  }

  public setSearch(query: string): void {
    this.searchQuery.set(query);
    this.pagination.reset();
  }

  public setDateFrom(value: string): void {
    this.dateFrom.set(value);
    this.pagination.reset();
  }

  public setDateTo(value: string): void {
    this.dateTo.set(value);
    this.pagination.reset();
  }

  public setGroupBy(value: string): void {
    this.groupBy.set(value as GroupByMode);
  }

  public setSort(column: SortColumn): void {
    if (this.sortColumn() === column) {
      this.sortDirection.update(dir => (dir === 'asc' ? 'desc' : 'asc'));
    } else {
      this.sortColumn.set(column);
      this.sortDirection.set('desc');
    }
  }

  /** Exportación client-side sobre `sortedEntries` (todas las filas filtradas, no solo la página actual). */
  public exportCsv(): void {
    const header = ['Arete SINIIGA', 'Nº Fuego', 'Tipo de Evento', 'Fecha', 'Detalle'];
    const rows = this.sortedEntries().map(entry => [
      entry.rfidSiniiga,
      entry.numeroFuego,
      this.eventTypeLabel[entry.eventType],
      entry.eventDate,
      this.describeEntry(entry)
    ]);

    const csv = [header, ...rows]
      .map(row => row.map(cell => `"${String(cell ?? '').replace(/"/g, '""')}"`).join(','))
      .join('\n');

    const blob = new Blob([`﻿${csv}`], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `cattle-event-log-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  private describeEntry(entry: EventLogEntry): string {
    switch (entry.eventType) {
      case 'PESO':
        return entry.weightKg !== null ? `${entry.weightKg.toFixed(2)} kg` : '';
      case 'SALUD':
        return [entry.healthEventType, entry.description].filter(Boolean).join(' — ');
      case 'PARTO':
      case 'NACIMIENTO':
        return [
          entry.calfSex === 'MACHO' ? 'Macho' : 'Hembra',
          entry.calfWeightKg !== null ? `${entry.calfWeightKg.toFixed(2)} kg al nacer` : null
        ].filter(Boolean).join(', ');
      default:
        return '';
    }
  }
}
