import { Injectable, inject, signal, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, of } from 'rxjs';
import { environment } from '@env/environment';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import {
  UppComplianceStatus,
  PsgComplianceStatus,
  LivestockCensusSnapshot
} from '../models/agro-registry.model';
import { UppComplianceStatusView, ProductionUnitView } from '../models/compliance-view.model';

const STATUS_WEIGHT: Record<string, number> = {
  EXPIRED: 0,
  WARNING: 1,
  UNKNOWN: 2,
  OK: 3
};

@Injectable({ providedIn: 'root' })
export class ComplianceService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;

  public uppList = signal<UppComplianceStatusView[]>([]);
  public psgList = signal<PsgComplianceStatus[]>([]);
  public loadingUpp = signal<boolean>(false);
  public loadingPsg = signal<boolean>(false);
  public error = signal<string | null>(null);

  public uppDetail = signal<ProductionUnitView | null>(null);
  public uppDetailCensus = signal<LivestockCensusSnapshot | null>(null);
  public loadingDetail = signal<boolean>(false);

  /** Guards against redundant getall calls when list and alert card share this service. */
  private uppLoaded = signal<boolean>(false);
  private psgLoaded = signal<boolean>(false);

  public expiredUppCount = computed(() =>
    this.uppList().filter(u => u.update_status === 'EXPIRED').length
  );

  public warningUppCount = computed(() =>
    this.uppList().filter(u => u.update_status === 'WARNING').length
  );

  public expiredPsgCount = computed(() =>
    this.psgList().filter(p => p.validity_status === 'EXPIRED').length
  );

  /** Idempotent: no-ops if the list is already loaded, unless force is passed. */
  public loadUppStatus(force = false): void {
    if (this.uppLoaded() && !force) return;

    this.loadingUpp.set(true);
    this.error.set(null);

    const payload = {
      entity: 'upp_compliance_status',
      table_name: 'vw_upp_compliance_status',
      operation: 'getall',
      filters: {}
    };

    this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/upp_compliance_status`, payload)
      .pipe(
        catchError(() => {
          this.error.set('No se pudo conectar con el servicio de cumplimiento normativo.');
          return of<ApiResponse<any>>({ error: true, operation: 'getall', message: '', data: [] });
        })
      )
      .subscribe(res => {
        if (res.error) {
          this.error.set(res.message || 'El servidor reportó un error al consultar el estado de cumplimiento de las UPP.');
          this.uppList.set([]);
        } else {
          const rows = Array.isArray(res.data) ? res.data : [];
          this.uppList.set(rows.map(row => this.mapUppRow(row)).sort(this.byCriticality));
          this.uppLoaded.set(true);
        }
        this.loadingUpp.set(false);
      });
  }

  /** Idempotent: no-ops if the list is already loaded, unless force is passed. */
  public loadPsgStatus(force = false): void {
    if (this.psgLoaded() && !force) return;

    this.loadingPsg.set(true);
    this.error.set(null);

    const payload = {
      entity: 'psg_compliance_status',
      table_name: 'vw_psg_compliance_status',
      operation: 'getall',
      filters: {}
    };

    this.http.post<ApiResponse<PsgComplianceStatus>>(`${this.apiUrl_crud}/psg_compliance_status`, payload)
      .pipe(
        catchError(() => {
          this.error.set('No se pudo conectar con el servicio de vigencia de licencias PSG.');
          return of<ApiResponse<PsgComplianceStatus>>({ error: true, operation: 'getall', message: '', data: [] });
        })
      )
      .subscribe(res => {
        if (res.error) {
          this.error.set(res.message || 'El servidor reportó un error al consultar la vigencia de las licencias PSG.');
          this.psgList.set([]);
        } else {
          this.psgList.set(Array.isArray(res.data) ? res.data : []);
          this.psgLoaded.set(true);
        }
        this.loadingPsg.set(false);
      });
  }

  public getUppDetail(id: string): void {
    this.loadingDetail.set(true);
    this.error.set(null);
    this.uppDetail.set(null);
    this.uppDetailCensus.set(null);

    const payload = {
      entity: 'production_units',
      table_name: 'production_units',
      operation: 'getone',
      filters: { id }
    };

    this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/production_units`, payload)
      .pipe(
        catchError(() => {
          this.error.set('No se pudo cargar el detalle de la unidad de producción.');
          return of<ApiResponse<any>>({ error: true, operation: 'getone', message: '', data: [] });
        })
      )
      .subscribe(res => {
        if (res.error) {
          this.error.set(res.message || 'El servidor reportó un error al consultar la unidad de producción.');
          this.loadingDetail.set(false);
          return;
        }

        const raw = Array.isArray(res.data) ? res.data[0] : res.data;
        if (!raw) {
          this.loadingDetail.set(false);
          return;
        }

        this.uppDetail.set(this.mapProductionUnit(raw));
        this.loadLatestCensus(id);
      });
  }

  private loadLatestCensus(productionUnitId: string): void {
    const payload = {
      entity: 'livestock_census_snapshots',
      table_name: 'livestock_census_snapshots',
      operation: 'getall',
      filters: { production_unit_id: productionUnitId }
    };

    this.http.post<ApiResponse<LivestockCensusSnapshot>>(`${this.apiUrl_crud}/livestock_census_snapshots`, payload)
      .pipe(
        catchError(() => of<ApiResponse<LivestockCensusSnapshot>>({ error: true, operation: 'getall', message: '', data: [] }))
      )
      .subscribe(res => {
        const rows = !res.error && Array.isArray(res.data) ? res.data : [];
        const latest = rows.reduce<LivestockCensusSnapshot | null>((mostRecent, row) => {
          if (!mostRecent) return row;
          return new Date(row.snapshot_date) > new Date(mostRecent.snapshot_date) ? row : mostRecent;
        }, null);

        this.uppDetailCensus.set(latest);
        this.loadingDetail.set(false);
      });
  }

  /** Most critical first: EXPIRED > WARNING > UNKNOWN > OK, then longest-stale within a status. */
  private byCriticality = (a: UppComplianceStatusView, b: UppComplianceStatusView): number => {
    const weightDiff = (STATUS_WEIGHT[a.update_status] ?? 99) - (STATUS_WEIGHT[b.update_status] ?? 99);
    if (weightDiff !== 0) return weightDiff;

    if (a.days_since_update == null && b.days_since_update == null) return 0;
    if (a.days_since_update == null) return 1;
    if (b.days_since_update == null) return -1;
    return b.days_since_update - a.days_since_update;
  };

  private mapUppRow(row: any): UppComplianceStatusView {
    const grazingSurfaceHa = this.parseNullableNumber(row.grazing_surface_ha);
    return {
      ...row,
      total_surface_ha: this.parseNullableNumber(row.total_surface_ha),
      grazing_surface_ha: grazingSurfaceHa,
      hasGrazingSurface: (grazingSurfaceHa ?? 0) > 0,
      last_declared_head: this.parseNullableNumber(row.last_declared_head),
      active_head_in_system: this.parseNumber(row.active_head_in_system),
      days_since_update: this.parseNullableNumber(row.days_since_update)
    };
  }

  private mapProductionUnit(row: any): ProductionUnitView {
    const grazingSurfaceHa = this.parseNullableNumber(row.grazing_surface_ha);
    return {
      ...row,
      total_surface_ha: this.parseNullableNumber(row.total_surface_ha),
      grazing_surface_ha: grazingSurfaceHa,
      hasGrazingSurface: (grazingSurfaceHa ?? 0) > 0,
      latitude: this.parseNullableNumber(row.latitude),
      longitude: this.parseNullableNumber(row.longitude)
    };
  }

  private parseNumber(value: unknown): number {
    const parsed = typeof value === 'number' ? value : parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseNullableNumber(value: unknown): number | null {
    if (value === null || value === undefined) return null;
    const parsed = typeof value === 'number' ? value : parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : null;
  }
}
