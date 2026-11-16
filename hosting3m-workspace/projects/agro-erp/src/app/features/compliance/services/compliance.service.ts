import { Injectable, inject, signal, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, catchError, map, of } from 'rxjs';
import { environment } from '@env/environment';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import {
  UppComplianceStatus,
  PsgComplianceStatus,
  LivestockCensusSnapshot
} from '../models/agro-registry.model';
import { UppComplianceStatusView, ProductionUnitView } from '../models/compliance-view.model';
import { isPhantomRow, stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import { isNetworkFailure } from '@shared/utils/network-failure.util';

const STATUS_WEIGHT: Record<string, number> = {
  EXPIRED: 0,
  WARNING: 1,
  UNKNOWN: 2,
  OK: 3
};

const UPP_UNAVAILABLE = 'No se pudo conectar con el servicio de cumplimiento normativo.';
const PSG_UNAVAILABLE = 'No se pudo conectar con el servicio de vigencia de licencias PSG.';
const DETAIL_UNAVAILABLE = 'No se pudo cargar el detalle de la unidad de producción.';

/**
 * `idle` = never requested, `loading` = request in flight, `loaded` = last request succeeded,
 * `failed` = last request failed (transport error, gateway `error:true`, null body or non-array data).
 */
export type ComplianceSourceState = 'idle' | 'loading' | 'loaded' | 'failed';

export interface ComplianceFailure {
  /** `network` = browser offline or no response (status 0); `unavailable` = server or payload problem. */
  reason: 'network' | 'unavailable';
  message: string;
}

type ReadOutcome =
  | { ok: true; rows: any[] }
  | { ok: false; failure: ComplianceFailure };

@Injectable({ providedIn: 'root' })
export class ComplianceService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;

  public uppList = signal<UppComplianceStatusView[]>([]);
  public psgList = signal<PsgComplianceStatus[]>([]);

  /** Per-source state. Each source's failure only affects that source. */
  public uppState = signal<ComplianceSourceState>('idle');
  public psgState = signal<ComplianceSourceState>('idle');
  public uppError = signal<ComplianceFailure | null>(null);
  public psgError = signal<ComplianceFailure | null>(null);
  public loadingUpp = computed(() => this.uppState() === 'loading');
  public loadingPsg = computed(() => this.psgState() === 'loading');

  public uppDetail = signal<ProductionUnitView | null>(null);
  public uppDetailCensus = signal<LivestockCensusSnapshot | null>(null);
  public loadingDetail = signal<boolean>(false);
  /** Detail-screen error. Separate from the list errors so each screen only sees its own. */
  public detailError = signal<string | null>(null);

  /** Latest-wins: a response only applies if no newer request for the same source started. */
  private uppRequestId = 0;
  private psgRequestId = 0;
  private detailRequestId = 0;

  public expiredUppCount = computed(() =>
    this.uppList().filter(u => u.update_status === 'EXPIRED').length
  );

  public warningUppCount = computed(() =>
    this.uppList().filter(u => u.update_status === 'WARNING').length
  );

  public expiredPsgCount = computed(() =>
    this.psgList().filter(p => p.validity_status === 'EXPIRED').length
  );

  /**
   * Loads the UPP status. Skips when already loaded or loading, unless `force` is passed.
   * A failed load clears the list and marks the source `failed`.
   */
  public loadUppStatus(force = false): void {
    const state = this.uppState();
    if (!force && (state === 'loaded' || state === 'loading')) return;

    const requestId = ++this.uppRequestId;
    this.uppState.set('loading');
    this.uppError.set(null);

    this.fetchRows('upp_compliance_status', 'vw_upp_compliance_status', UPP_UNAVAILABLE)
      .subscribe(outcome => {
        if (requestId !== this.uppRequestId) return;
        if (!outcome.ok) {
          this.failUpp(outcome.failure);
          return;
        }
        try {
          const rows = stripPhantomRows(outcome.rows, 'production_unit_id');
          this.uppList.set(rows.map(row => this.mapUppRow(row)).sort(this.byCriticality));
          this.uppState.set('loaded');
        } catch {
          this.failUpp({ reason: 'unavailable', message: UPP_UNAVAILABLE });
        }
      });
  }

  /**
   * Loads the PSG licence status. Skips when already loaded or loading, unless `force` is passed.
   * A failed load clears the list and marks the source `failed`.
   */
  public loadPsgStatus(force = false): void {
    const state = this.psgState();
    if (!force && (state === 'loaded' || state === 'loading')) return;

    const requestId = ++this.psgRequestId;
    this.psgState.set('loading');
    this.psgError.set(null);

    this.fetchRows('psg_compliance_status', 'vw_psg_compliance_status', PSG_UNAVAILABLE)
      .subscribe(outcome => {
        if (requestId !== this.psgRequestId) return;
        if (!outcome.ok) {
          this.failPsg(outcome.failure);
          return;
        }
        try {
          this.psgList.set(stripPhantomRows(outcome.rows, 'psg_license_id'));
          this.psgState.set('loaded');
        } catch {
          this.failPsg({ reason: 'unavailable', message: PSG_UNAVAILABLE });
        }
      });
  }

  /** Reloads only the sources that failed. Used by the card's retry action. */
  public retryFailed(): void {
    if (this.uppState() === 'failed') this.loadUppStatus(true);
    if (this.psgState() === 'failed') this.loadPsgStatus(true);
  }

  public getUppDetail(id: string): void {
    const requestId = ++this.detailRequestId;
    this.loadingDetail.set(true);
    this.detailError.set(null);
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
        catchError(() => of<ApiResponse<any>>({ error: true, operation: 'getone', message: '', data: [] }))
      )
      .subscribe(res => {
        if (requestId !== this.detailRequestId) return;

        if (!res || res.error) {
          this.detailError.set(res?.message || DETAIL_UNAVAILABLE);
          this.loadingDetail.set(false);
          return;
        }

        try {
          const raw = Array.isArray(res.data) ? res.data[0] : res.data;
          if (isPhantomRow(raw, 'id')) {
            this.loadingDetail.set(false);
            return;
          }
          this.uppDetail.set(this.mapProductionUnit(raw));
        } catch {
          this.detailError.set(DETAIL_UNAVAILABLE);
          this.loadingDetail.set(false);
          return;
        }
        this.loadLatestCensus(id, requestId);
      });
  }

  private loadLatestCensus(productionUnitId: string, requestId: number): void {
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
        if (requestId !== this.detailRequestId) return;
        try {
          const rawRows = !res?.error && Array.isArray(res?.data) ? res.data : [];
          const rows = stripPhantomRows(rawRows, 'id');
          const latest = rows.reduce<LivestockCensusSnapshot | null>((mostRecent, row) => {
            if (!mostRecent) return row;
            return new Date(row.snapshot_date) > new Date(mostRecent.snapshot_date) ? row : mostRecent;
          }, null);
          this.uppDetailCensus.set(latest);
        } catch {
          this.uppDetailCensus.set(null);
        }
        this.loadingDetail.set(false);
      });
  }

  /**
   * One gateway `getall`. Any transport error, `error:true`, null body or non-array `data`
   * is a failure. An empty array is a valid, successful empty load.
   */
  private fetchRows(entity: string, tableName: string, unavailable: string): Observable<ReadOutcome> {
    const payload = {
      entity,
      table_name: tableName,
      operation: 'getall',
      filters: {}
    };

    return this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/${entity}`, payload).pipe(
      map((res): ReadOutcome => {
        if (!res) return { ok: false, failure: { reason: 'unavailable', message: unavailable } };
        if (res.error) return { ok: false, failure: { reason: 'unavailable', message: res.message || unavailable } };
        if (!Array.isArray(res.data)) return { ok: false, failure: { reason: 'unavailable', message: unavailable } };
        return { ok: true, rows: res.data };
      }),
      catchError((err): Observable<ReadOutcome> => of({
        ok: false,
        failure: { reason: isNetworkFailure(err) ? 'network' : 'unavailable', message: unavailable }
      }))
    );
  }

  private failUpp(failure: ComplianceFailure): void {
    this.uppList.set([]);
    this.uppError.set(failure);
    this.uppState.set('failed');
  }

  private failPsg(failure: ComplianceFailure): void {
    this.psgList.set([]);
    this.psgError.set(failure);
    this.psgState.set('failed');
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
