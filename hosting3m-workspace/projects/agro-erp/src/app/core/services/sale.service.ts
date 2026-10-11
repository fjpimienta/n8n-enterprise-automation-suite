import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '@env/environment';
import { TenantService } from 'core-auth';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { isPhantomRow, stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import {
  SaleIncome,
  SaleMode,
  SaleReferencePrice,
  SaleReferencePriceInput,
  PaymentMethod
} from '@core/models/sale.model';
import { parseOptionalNumber } from '@shared/utils/sale-income.util';

/** Raised when the active tenant context is missing or does not own the requested record. */
export class SaleTenantContextError extends Error {}

/**
 * Data layer for sale income (migration 071): `cattle_sale_income` (read-only ledger) and
 * `cattle_sale_reference_prices` (CRUD). Both models are ADMIN-only in `crud_models`.
 *
 * Multi-tenant isolation is fail-closed: no call without an active tenant, every returned row is
 * re-checked against it and dropped if it does not match, and a reference price is re-read with
 * a tenant-scoped `getone` before any update.
 */
@Injectable({ providedIn: 'root' })
export class SaleService {
  private http = inject(HttpClient);
  private tenantService = inject(TenantService);
  private apiUrl_crud = environment.apiUrl_crud;

  public async getReferencePrices(): Promise<SaleReferencePrice[]> {
    const tenantId = this.requireTenant();
    const res = await this.post<any>('cattle_sale_reference_prices', {
      entity: 'cattle_sale_reference_prices',
      table_name: 'cattle_sale_reference_prices',
      operation: 'getall',
      filters: { tenant_id: tenantId },
      sort_by: 'valid_from'
    });

    return stripPhantomRows(res.data, 'id')
      .filter(row => Number(row.tenant_id) === tenantId)
      .map(row => this.mapReferencePrice(row));
  }

  public async createReferencePrice(input: SaleReferencePriceInput): Promise<void> {
    const tenantId = this.requireTenant();
    await this.post<any>('cattle_sale_reference_prices', {
      entity: 'cattle_sale_reference_prices',
      table_name: 'cattle_sale_reference_prices',
      operation: 'insert',
      fields: { tenant_id: tenantId, ...this.referenceFields(input), is_active: true }
    });
  }

  public async updateReferencePrice(id: string, input: SaleReferencePriceInput): Promise<void> {
    const current = await this.getOwnedReferencePrice(id);
    await this.post<any>('cattle_sale_reference_prices', {
      entity: 'cattle_sale_reference_prices',
      table_name: 'cattle_sale_reference_prices',
      operation: 'update',
      id: current.id,
      fields: this.referenceFields(input)
    });
  }

  /** Soft-delete: income already recorded never depends on a reference price. */
  public async setReferencePriceActive(id: string, isActive: boolean): Promise<void> {
    const current = await this.getOwnedReferencePrice(id);
    await this.post<any>('cattle_sale_reference_prices', {
      entity: 'cattle_sale_reference_prices',
      table_name: 'cattle_sale_reference_prices',
      operation: 'update',
      id: current.id,
      fields: { is_active: isActive }
    });
  }

  public async getSaleIncome(): Promise<SaleIncome[]> {
    const tenantId = this.requireTenant();
    const res = await this.post<any>('cattle_sale_income', {
      entity: 'cattle_sale_income',
      table_name: 'cattle_sale_income',
      operation: 'getall',
      filters: { tenant_id: tenantId },
      sort_by: 'sale_date'
    });

    return stripPhantomRows(res.data, 'id')
      .filter(row => Number(row.tenant_id) === tenantId)
      .map(row => this.mapIncome(row));
  }

  /** Tenant-scoped `getone`: the only accepted proof that a reference price belongs to the active tenant. */
  private async getOwnedReferencePrice(id: string): Promise<SaleReferencePrice> {
    const tenantId = this.requireTenant();
    const res = await this.post<any>('cattle_sale_reference_prices', {
      entity: 'cattle_sale_reference_prices',
      table_name: 'cattle_sale_reference_prices',
      operation: 'getone',
      filters: { id }
    });

    const raw = res.data[0];
    if (isPhantomRow(raw, 'id') || Number(raw.tenant_id) !== tenantId) {
      throw new SaleTenantContextError('El precio de referencia no existe o no pertenece a la empresa activa.');
    }
    return this.mapReferencePrice(raw);
  }

  private referenceFields(input: SaleReferencePriceInput): Record<string, unknown> {
    return {
      category: input.category.trim().toUpperCase(),
      sale_mode: input.saleMode,
      reference_amount: input.referenceAmount,
      reference_price_per_kg: input.referencePricePerKg,
      valid_from: input.validFrom,
      valid_to: input.validTo || null,
      notes: (input.notes ?? '').trim() || null
    };
  }

  private mapReferencePrice(row: any): SaleReferencePrice {
    return {
      id: String(row.id),
      tenantId: Number(row.tenant_id),
      category: String(row.category ?? ''),
      saleMode: row.sale_mode as SaleMode,
      referenceAmount: parseOptionalNumber(row.reference_amount),
      referencePricePerKg: parseOptionalNumber(row.reference_price_per_kg),
      validFrom: String(row.valid_from ?? '').slice(0, 10),
      validTo: row.valid_to ? String(row.valid_to).slice(0, 10) : null,
      isActive: this.parseBoolean(row.is_active),
      notes: row.notes ?? null,
      createdAt: row.created_at ?? null
    };
  }

  private mapIncome(row: any): SaleIncome {
    return {
      id: String(row.id),
      tenantId: Number(row.tenant_id),
      livestockId: String(row.livestock_id ?? ''),
      pendingAuthorizationId: row.pending_authorization_id ?? null,
      saleDate: String(row.sale_date ?? '').slice(0, 10),
      saleMode: row.sale_mode as SaleMode,
      amount: parseOptionalNumber(row.amount) ?? 0,
      weightKg: parseOptionalNumber(row.weight_kg),
      pricePerKg: parseOptionalNumber(row.price_per_kg),
      buyerName: String(row.buyer_name ?? ''),
      paymentMethod: row.payment_method as PaymentMethod,
      invoiced: this.parseBoolean(row.invoiced),
      invoiceFolio: row.invoice_folio ?? null,
      banked: this.parseBoolean(row.banked),
      guiaTransito: row.guia_transito ?? null
    };
  }

  /** Posts to the gateway and surfaces `error: true` (HTTP 200) as a thrown error, message as-is. */
  private async post<T>(model: string, payload: object): Promise<ApiResponse<T>> {
    const res = await firstValueFrom(this.http.post<ApiResponse<T>>(`${this.apiUrl_crud}/${model}`, payload));
    if (!res || res.error) {
      throw new Error(res?.message || 'El servidor reportó un error al procesar la solicitud.');
    }
    return { ...res, data: Array.isArray(res.data) ? res.data : (res.data ? [res.data as T] : []) };
  }

  private requireTenant(): number {
    const tenantId = Number(this.tenantService.activeTenantId());
    if (!Number.isInteger(tenantId) || tenantId <= 0) {
      throw new SaleTenantContextError('No hay una empresa activa en la sesión.');
    }
    return tenantId;
  }

  private parseBoolean(value: unknown): boolean {
    return value === true || value === 'true' || value === 't' || value === 1;
  }
}
