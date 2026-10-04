import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '@env/environment';
import { TenantService } from 'core-auth';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { CattleApiService } from '@core/services/cattle-api.service';
import { isPhantomRow, stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import { isActiveHead } from '@shared/utils/herd-status.util';
import {
  CreateProductionUnitLotPayload,
  LotTenureType,
  ProductionUnitLot,
  ProductionUnitSummary,
  UpdateProductionUnitLotPayload,
  lotNameKey,
} from '@core/models/production-unit-lot.model';

/** Raised when the active tenant context is missing or does not own the requested record. */
export class TenantContextError extends Error {}

/** Raised when a lot name collides with another ACTIVE lot of the same UPP (`uq_lot_name_per_unit`). */
export class DuplicateLotNameError extends Error {}

/**
 * Data layer for the lots admin (`production_units` + `production_unit_lots`).
 *
 * Multi-tenant isolation is fail-closed at every step:
 *   - No call is made without an active tenant (`TenantService.activeTenantId`); the
 *     tenant interceptor sends it as `x-tenant-id` and the gateway injects `id_company`.
 *   - Every row the gateway returns is re-checked against the active tenant and dropped
 *     if it does not match — never rendered.
 *   - Before any UPDATE the lot is re-read with a tenant-scoped `getone`. The gateway's
 *     `update` filters only by primary key (it SETs `id_company` from the header instead
 *     of adding it to the WHERE), so a forged id must be rejected here before it reaches it.
 *
 * Lots are never physically deleted: "delete" is `is_active = false`, and the Meta-CRUD
 * model has no DELETE op anyway.
 */
@Injectable({ providedIn: 'root' })
export class ProductionUnitLotService {
  private http = inject(HttpClient);
  private tenantService = inject(TenantService);
  private cattleApi = inject(CattleApiService);
  private apiUrl_crud = environment.apiUrl_crud;

  public async getProductionUnits(): Promise<ProductionUnitSummary[]> {
    const idCompany = this.requireTenant();
    const res = await this.post<any>('production_units', {
      entity: 'production_units',
      table_name: 'production_units',
      operation: 'getall',
      filters: { id_company: idCompany }
    });

    return stripPhantomRows(res.data, 'id')
      .filter(row => Number(row.id_company) === idCompany)
      .map(row => this.mapProductionUnit(row))
      .sort((a, b) => a.ranchName.localeCompare(b.ranchName, 'es', { sensitivity: 'base' }));
  }

  /** Tenant-scoped read of one UPP. Throws `TenantContextError` if it is not the active tenant's. */
  public async getProductionUnit(id: string): Promise<ProductionUnitSummary> {
    const idCompany = this.requireTenant();
    const res = await this.post<any>('production_units', {
      entity: 'production_units',
      table_name: 'production_units',
      operation: 'getone',
      filters: { id }
    });

    const raw = Array.isArray(res.data) ? res.data[0] : res.data;
    if (isPhantomRow(raw, 'id') || Number(raw.id_company) !== idCompany) {
      throw new TenantContextError('La UPP no existe o no pertenece a la empresa activa.');
    }
    return this.mapProductionUnit(raw);
  }

  /** All lots of one UPP (active and inactive), with the live head count per lot. */
  public async getLots(productionUnitId: string): Promise<ProductionUnitLot[]> {
    const idCompany = this.requireTenant();
    const [res, livestock] = await Promise.all([
      this.post<any>('production_unit_lots', {
        entity: 'production_unit_lots',
        table_name: 'production_unit_lots',
        operation: 'getall',
        filters: { id_company: idCompany, production_unit_id: productionUnitId }
      }),
      this.cattleApi.getAllLivestock()
    ]);

    const lots = stripPhantomRows(res.data, 'id')
      .filter(row => Number(row.id_company) === idCompany && row.production_unit_id === productionUnitId)
      .map(row => this.mapLot(row));

    return this.attachLivestockCounts(lots, livestock, idCompany, productionUnitId)
      .sort((a, b) =>
        Number(b.isActive) - Number(a.isActive) ||
        a.lotName.localeCompare(b.lotName, 'es', { sensitivity: 'base' })
      );
  }

  public async createLot(payload: CreateProductionUnitLotPayload): Promise<void> {
    const idCompany = this.requireTenant();
    // Re-validates the UPP against the session tenant; never trusts the id from the route.
    const unit = await this.getProductionUnit(payload.productionUnitId);
    if (!unit.isActive) {
      throw new TenantContextError('No se pueden crear lotes en una UPP inactiva.');
    }

    await this.post<any>('production_unit_lots', {
      entity: 'production_unit_lots',
      table_name: 'production_unit_lots',
      operation: 'insert',
      fields: {
        id_company: idCompany,
        production_unit_id: unit.id,
        lot_name: payload.lotName.trim(),
        tenure_type: payload.tenureType,
        lessor_name: this.lessorFor(payload.tenureType, payload.lessorName),
        location_notes: this.blankToNull(payload.locationNotes),
        notes: this.blankToNull(payload.notes),
        is_active: true
      }
    });
  }

  public async updateLot(id: string, payload: UpdateProductionUnitLotPayload): Promise<void> {
    const current = await this.getOwnedLot(id);

    const fields: Record<string, unknown> = {};
    if (payload.lotName !== undefined) fields['lot_name'] = payload.lotName.trim();
    if (payload.tenureType !== undefined) {
      fields['tenure_type'] = payload.tenureType;
      // Leaving RENTADA must clear the lessor or production_unit_lots_lessor_only_if_rented_check rejects the row.
      fields['lessor_name'] = this.lessorFor(payload.tenureType, payload.lessorName ?? current.lessorName ?? undefined);
    } else if (payload.lessorName !== undefined) {
      fields['lessor_name'] = this.lessorFor(current.tenureType, payload.lessorName);
    }
    if (payload.locationNotes !== undefined) fields['location_notes'] = this.blankToNull(payload.locationNotes);
    if (payload.notes !== undefined) fields['notes'] = this.blankToNull(payload.notes);
    if (payload.isActive !== undefined) fields['is_active'] = payload.isActive;

    await this.post<any>('production_unit_lots', {
      entity: 'production_unit_lots',
      table_name: 'production_unit_lots',
      operation: 'update',
      id: current.id,
      fields
    });
  }

  /** Soft-delete. Assigned animals keep their `lot_id` pointing at the now-inactive lot. */
  public deactivateLot(id: string): Promise<void> {
    return this.updateLot(id, { isActive: false });
  }

  public reactivateLot(id: string): Promise<void> {
    return this.updateLot(id, { isActive: true });
  }

  /** Tenant-scoped `getone`. The only accepted proof that a lot id belongs to the active tenant. */
  private async getOwnedLot(id: string): Promise<ProductionUnitLot> {
    const idCompany = this.requireTenant();
    const res = await this.post<any>('production_unit_lots', {
      entity: 'production_unit_lots',
      table_name: 'production_unit_lots',
      operation: 'getone',
      filters: { id }
    });

    const raw = Array.isArray(res.data) ? res.data[0] : res.data;
    if (isPhantomRow(raw, 'id') || Number(raw.id_company) !== idCompany) {
      throw new TenantContextError('El lote no existe o no pertenece a la empresa activa.');
    }
    return this.mapLot(raw);
  }

  /**
   * `lot_id` is not exposed by `vw_cattle_kpi`, so animals are matched by
   * (`production_unit_id`, `upper(lot_name)`). That is exact while the name is unique
   * within the UPP; when two lots share it (only possible if one is inactive), the
   * animals cannot be attributed and the count is reported as `null`.
   */
  private attachLivestockCounts(
    lots: ProductionUnitLot[],
    livestock: any[],
    idCompany: number,
    productionUnitId: string
  ): ProductionUnitLot[] {
    const lotsPerName = new Map<string, number>();
    for (const lot of lots) {
      const key = lotNameKey(lot.lotName);
      lotsPerName.set(key, (lotsPerName.get(key) ?? 0) + 1);
    }

    const headsPerName = new Map<string, number>();
    for (const animal of Array.isArray(livestock) ? livestock : []) {
      if (Number(animal?.tenant_id) !== idCompany) continue;
      if (animal?.production_unit_id !== productionUnitId) continue;
      if (!isActiveHead(animal)) continue;
      const key = lotNameKey(animal?.lot_name);
      if (!key) continue;
      headsPerName.set(key, (headsPerName.get(key) ?? 0) + 1);
    }

    return lots.map(lot => {
      const key = lotNameKey(lot.lotName);
      const ambiguous = (lotsPerName.get(key) ?? 0) > 1;
      return { ...lot, assignedLivestockCount: ambiguous ? null : (headsPerName.get(key) ?? 0) };
    });
  }

  /** Posts to the gateway and surfaces `error: true` (HTTP 200) as a thrown error. */
  private async post<T>(model: string, payload: object): Promise<ApiResponse<T>> {
    const res = await firstValueFrom(this.http.post<ApiResponse<T>>(`${this.apiUrl_crud}/${model}`, payload));
    if (!res || res.error) {
      const message = res?.message || 'El servidor reportó un error al procesar la solicitud.';
      if (/uq_lot_name_per_unit|duplicate key/i.test(message)) {
        throw new DuplicateLotNameError('Ya existe un lote activo con ese nombre en esta UPP.');
      }
      throw new Error(message);
    }
    return { ...res, data: Array.isArray(res.data) ? res.data : (res.data ? [res.data as T] : []) };
  }

  private requireTenant(): number {
    const idCompany = Number(this.tenantService.activeTenantId());
    if (!Number.isInteger(idCompany) || idCompany <= 0) {
      throw new TenantContextError('No hay una empresa activa en la sesión.');
    }
    return idCompany;
  }

  private lessorFor(tenureType: LotTenureType, lessorName: string | null | undefined): string | null {
    return tenureType === 'RENTADA' ? this.blankToNull(lessorName) : null;
  }

  private blankToNull(value: string | null | undefined): string | null {
    const trimmed = (value ?? '').trim();
    return trimmed || null;
  }

  private parseBoolean(value: unknown): boolean {
    return value === true || value === 'true' || value === 't';
  }

  private mapProductionUnit(row: any): ProductionUnitSummary {
    return {
      id: row.id,
      idCompany: Number(row.id_company),
      uppCode: row.upp_code ?? '',
      ranchName: row.ranch_name ?? '',
      stateName: row.state_name ?? null,
      municipalityName: row.municipality_name ?? null,
      localityName: row.locality_name ?? null,
      isActive: this.parseBoolean(row.is_active),
      registryStatus: row.registry_status ?? null
    };
  }

  private mapLot(row: any): ProductionUnitLot {
    return {
      id: row.id,
      idCompany: Number(row.id_company),
      productionUnitId: row.production_unit_id,
      lotName: row.lot_name ?? '',
      tenureType: row.tenure_type,
      lessorName: row.lessor_name ?? null,
      locationNotes: row.location_notes ?? null,
      isActive: this.parseBoolean(row.is_active),
      notes: row.notes ?? null,
      createdAt: row.created_at ?? ''
    };
  }
}
