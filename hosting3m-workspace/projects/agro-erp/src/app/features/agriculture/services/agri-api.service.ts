import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '@env/environment';
import { TenantService } from 'core-auth';
import { isPhantomRow, stripPhantomRows } from '@core/utils/gateway-empty-row.util';
import {
  AgriRow,
  CensusHistoryEntry,
  CensusReason,
  HistoryReason,
  Lot,
  LotInput,
  LotSummary,
  Plantation,
  PlantationInput,
  PlantationSummary,
  PlantationTenure,
  ProductiveStage,
  Variety,
} from '@core/models/agri.model';
import {
  AgriExpense,
  CategoryInput,
  ExpenseBalance,
  ExpenseBalanceQuery,
  ExpenseCategory,
  ExpenseGrain,
  ExpenseInput,
  ExpenseSummaryRow,
  ExpenseUnit,
} from '@core/models/agri-expense.model';
import { buildCategoryFields, buildExpenseFields, parseExpenseBalance } from '../utils/expense.util';
import {
  UNCONFIRMED_MESSAGE,
  buildLotFields,
  buildPlantationFields,
  friendlyGatewayError,
  interpretSpResponse,
  isPossiblyTruncated,
  toBool,
  toInt,
  toNumber,
} from '../utils/agri.util';

/** Raised when there is no active company, or a record does not belong to it. */
export class AgriTenantContextError extends Error {}

export interface ListResult<T> {
  items: T[];
  /** The listing came back with exactly 1500 / 2000 rows: it may be cut by the gateway. */
  possiblyTruncated: boolean;
}

type Row = Record<string, any>;

/**
 * Data layer of the palm module (migration 080), fail-closed on every step:
 *   - no call without an active company; the tenant interceptor sends it as x-tenant-id and the gateway
 *     injects / filters id_company;
 *   - every row returned is re-checked against the active company and dropped if it does not match;
 *   - before any update the record is re-read with a tenant-scoped getone (the route / UI id is never
 *     trusted);
 *   - HTTP 200 with error:true is an error (MetaCRUD Silent Error Shield); empty collections arrive as
 *     data:[{}] and are stripped; numerics arrive as strings and are parsed;
 *   - call_sp responses count as success only with error:false and data.success:true.
 * Nothing is physically deleted: deactivate / reactivate through is_active.
 */
@Injectable({ providedIn: 'root' })
export class AgriApiService {
  private http = inject(HttpClient);
  private tenantService = inject(TenantService);
  private apiUrl = environment.apiUrl_crud;

  // ------------------------------------------------------------------------------------------------
  // Varieties (global catalog)
  // ------------------------------------------------------------------------------------------------

  async getVarieties(): Promise<Variety[]> {
    this.requireTenant();
    const res = await this.post('agri_variety_catalog', { operation: 'getall', filters: { is_active: true } });
    return stripPhantomRows(this.rows(res), 'id')
      .map(r => ({ id: r['id'], code: r['variety_code'] ?? '', name: r['variety_name'] ?? '', isActive: toBool(r['is_active']) }))
      .filter(v => v.isActive)
      .sort((a, b) => a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }));
  }

  // ------------------------------------------------------------------------------------------------
  // Plantations
  // ------------------------------------------------------------------------------------------------

  async getPlantations(): Promise<ListResult<Plantation>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_plantations', { operation: 'getall', filters: { id_company: tenant } });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant).map(r => this.mapPlantation(r))
      .sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async getPlantationSummaries(): Promise<ListResult<PlantationSummary>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_plantation_summary', { operation: 'getall', filters: { id_company: tenant } });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant).map(r => this.mapPlantationSummary(r));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  /** Tenant-scoped read of one plantation; the only accepted proof that an id belongs to the company. */
  async getPlantation(id: string): Promise<Plantation> {
    const raw = await this.getOwned('agri_plantations', id, 'La plantación no existe o no pertenece a la empresa activa.');
    return this.mapPlantation(raw);
  }

  async createPlantation(input: PlantationInput): Promise<Plantation> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_plantations', {
      operation: 'insert',
      fields: { ...buildPlantationFields(input), id_company: tenant, is_active: true },
    });
    const created = this.rows(res)[0];
    if (isPhantomRow(created, 'id')) throw new Error(UNCONFIRMED_MESSAGE);
    return this.mapPlantation(created);
  }

  async updatePlantation(id: string, input: PlantationInput): Promise<void> {
    const current = await this.getPlantation(id);
    await this.post('agri_plantations', { operation: 'update', id: current.id, fields: buildPlantationFields(input) });
  }

  async setPlantationActive(id: string, isActive: boolean): Promise<void> {
    const current = await this.getPlantation(id);
    await this.post('agri_plantations', { operation: 'update', id: current.id, fields: { is_active: isActive } });
  }

  async setDefaultPlantation(id: string): Promise<{ changed: boolean }> {
    const current = await this.getPlantation(id);
    const data = await this.callSp('agri_set_default_plantation', { plantation_id: current.id });
    return { changed: data['changed'] === true };
  }

  // ------------------------------------------------------------------------------------------------
  // Lots
  // ------------------------------------------------------------------------------------------------

  async getLots(plantationId: string): Promise<ListResult<Lot>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_lots', { operation: 'getall', filters: { id_company: tenant, plantation_id: plantationId } });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant && r['plantation_id'] === plantationId)
      .map(r => this.mapLot(r));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async getLotSummaries(plantationId: string): Promise<ListResult<LotSummary>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_lot_summary', { operation: 'getall', filters: { id_company: tenant, plantation_id: plantationId } });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant && r['plantation_id'] === plantationId)
      .map(r => this.mapLotSummary(r))
      .sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.code.localeCompare(b.code, 'es', { numeric: true, sensitivity: 'base' }));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async getLot(id: string): Promise<Lot> {
    const raw = await this.getOwned('agri_lots', id, 'El lote no existe o no pertenece a la empresa activa.');
    return this.mapLot(raw);
  }

  async getLotSummary(id: string): Promise<LotSummary> {
    const raw = await this.getOwned('agri_lot_summary', id, 'El lote no existe o no pertenece a la empresa activa.');
    return this.mapLotSummary(raw);
  }

  async createLot(plantationId: string, input: LotInput): Promise<void> {
    const tenant = this.requireTenant();
    // Re-validates the plantation against the session company; never trusts the id from the UI.
    const plantation = await this.getPlantation(plantationId);
    if (!plantation.isActive) throw new AgriTenantContextError('No se pueden registrar lotes en una plantación inactiva.');
    await this.post('agri_lots', {
      operation: 'insert',
      fields: { ...buildLotFields(input), id_company: tenant, plantation_id: plantation.id, is_active: true },
    });
  }

  async updateLot(id: string, input: LotInput): Promise<void> {
    const current = await this.getLot(id);
    await this.post('agri_lots', { operation: 'update', id: current.id, fields: buildLotFields(input) });
  }

  async setLotActive(id: string, isActive: boolean): Promise<void> {
    const current = await this.getLot(id);
    await this.post('agri_lots', { operation: 'update', id: current.id, fields: { is_active: isActive } });
  }

  // ------------------------------------------------------------------------------------------------
  // Rows, census and history
  // ------------------------------------------------------------------------------------------------

  async getRows(lotId: string): Promise<ListResult<AgriRow>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_rows', {
      operation: 'getall', filters: { id_company: tenant, lot_id: lotId }, limit: 2000, sort_by: 'row_number',
    });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant && r['lot_id'] === lotId)
      .map(r => this.mapRow(r))
      .sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.rowNumber - b.rowNumber);
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async getRow(id: string): Promise<AgriRow> {
    const raw = await this.getOwned('agri_rows', id, 'La fila no existe o no pertenece a la empresa activa.');
    return this.mapRow(raw);
  }

  async setRowActive(id: string, isActive: boolean): Promise<void> {
    const current = await this.getRow(id);
    await this.post('agri_rows', { operation: 'update', id: current.id, fields: { is_active: isActive } });
  }

  /** Single row = fromRow === toRow. Rows are never inserted through the generic CRUD. */
  async createRows(lotId: string, fromRow: number, toRow: number, positionsPerRow: number): Promise<number> {
    const lot = await this.getLot(lotId);
    const data = await this.callSp('agri_bulk_create_rows', {
      lot_id: lot.id, from_row: fromRow, to_row: toRow, positions_per_row: positionsPerRow,
    });
    return toInt(data['created']);
  }

  async recordCensus(rowId: string, census: {
    alivePlants: number; reason: CensusReason; censusDate: string | null; notes: string | null; plantingPositions: number | null;
  }): Promise<{ changed: boolean }> {
    const row = await this.getRow(rowId);
    // The actor email is never sent: the gateway takes it from the verified JWT.
    const data = await this.callSp('agri_record_row_census', {
      row_id: row.id,
      alive_plants: census.alivePlants,
      reason: census.reason,
      census_date: census.censusDate,
      notes: census.notes,
      planting_positions: census.plantingPositions,
    });
    return { changed: data['changed'] === true };
  }

  async getRowHistory(rowId: string): Promise<ListResult<CensusHistoryEntry>> {
    const tenant = this.requireTenant();
    const row = await this.getRow(rowId);
    const res = await this.post('agri_row_census_history', {
      operation: 'getall', filters: { id_company: tenant, row_id: row.id }, sort_by: 'changed_at',
    });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant && r['row_id'] === row.id)
      .map(r => this.mapHistory(r))
      .sort((a, b) => b.changedAt.localeCompare(a.changedAt));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  // ------------------------------------------------------------------------------------------------
  // Expenses (migration 081). Amounts: ADMIN / OWNER only (the gateway answers 403 to anyone else).
  // ------------------------------------------------------------------------------------------------

  /** Global, read-only unit catalog (active units only). */
  async getExpenseUnits(): Promise<ExpenseUnit[]> {
    this.requireTenant();
    const res = await this.post('agri_unit_catalog', { operation: 'getall', filters: { is_active: true } });
    return stripPhantomRows(this.rows(res), 'unit_code')
      .filter(r => toBool(r['is_active']))
      .map(r => ({ code: r['unit_code'], name: r['unit_name'] ?? r['unit_code'], sortOrder: toInt(r['sort_order'], 100) }))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }));
  }

  /** Expense categories of the active company (EDITOR reads them to capture). */
  async getExpenseCategories(): Promise<ListResult<ExpenseCategory>> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_expense_categories', { operation: 'getall', filters: { id_company: tenant } });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant).map(r => this.mapCategory(r))
      .sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.sortOrder - b.sortOrder
        || a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async createExpenseCategory(input: CategoryInput): Promise<void> {
    const tenant = this.requireTenant();
    const res = await this.post('agri_expense_categories', {
      operation: 'insert', fields: { ...buildCategoryFields(input, true), id_company: tenant },
    });
    if (isPhantomRow(this.rows(res)[0], 'id')) throw new Error(UNCONFIRMED_MESSAGE);
  }

  /** Name and order only: the code is immutable (P0082). */
  async updateExpenseCategory(id: string, input: CategoryInput): Promise<void> {
    const current = await this.getOwned('agri_expense_categories', id, 'La categoría no existe o no pertenece a la empresa activa.');
    await this.post('agri_expense_categories', { operation: 'update', id: current['id'], fields: buildCategoryFields(input, false) });
  }

  async setExpenseCategoryActive(id: string, isActive: boolean): Promise<void> {
    const current = await this.getOwned('agri_expense_categories', id, 'La categoría no existe o no pertenece a la empresa activa.');
    await this.post('agri_expense_categories', { operation: 'update', id: current['id'], fields: { is_active: isActive } });
  }

  /**
   * Records an expense through sp_agri_record_expense. Plantation and lot are re-validated against the
   * session company first (the ids from the form are never trusted). The answer carries no amount.
   */
  async recordExpense(input: ExpenseInput): Promise<{ expenseId: string }> {
    const fields = buildExpenseFields(input);
    if (fields['plantation_id']) {
      const plantation = await this.getPlantation(String(fields['plantation_id']));
      if (!plantation.isActive) throw new AgriTenantContextError('La plantación está inactiva: no se le pueden registrar gastos.');
    }
    if (fields['lot_id']) {
      const lot = await this.getLot(String(fields['lot_id']));
      if (lot.plantationId !== fields['plantation_id']) throw new AgriTenantContextError('El lote no pertenece a la plantación seleccionada.');
    }
    const data = await this.callSp('agri_record_expense', fields);
    return { expenseId: String(data['expense_id'] ?? '') };
  }

  /** Expense list (ADMIN / OWNER) between two dates, optionally filtered; voided rows included and flagged. */
  async getExpenses(query: { dateFrom: string; dateTo: string; plantationId: string | null; lotId: string | null; categoryId: string | null }):
    Promise<ListResult<AgriExpense>> {
    const tenant = this.requireTenant();
    const filters: Record<string, unknown> = { id_company: tenant, expense_date: { _gte: query.dateFrom, _lte: query.dateTo } };
    if (query.plantationId) filters['plantation_id'] = query.plantationId;
    if (query.lotId) filters['lot_id'] = query.lotId;
    if (query.categoryId) filters['category_id'] = query.categoryId;
    const res = await this.post('agri_expenses', { operation: 'getall', filters, limit: 2000, sort_by: 'expense_date' });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant).map(r => this.mapExpense(r))
      .sort((a, b) => b.expenseDate.localeCompare(a.expenseDate) || b.createdAt.localeCompare(a.createdAt));
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  async voidExpense(id: string, reason: string): Promise<void> {
    const current = await this.getOwned('agri_expenses', id, 'El gasto no existe o no pertenece a la empresa activa.');
    await this.callSp('agri_void_expense', { expense_id: current['id'], reason: reason.trim() });
  }

  /** Totals of any filter combination, computed by sp_agri_expense_balance (ADMIN / OWNER). */
  async getExpenseBalance(query: Partial<ExpenseBalanceQuery> = {}): Promise<ExpenseBalance> {
    const data = await this.callSp('agri_expense_balance', {
      date_from: query.dateFrom ?? null, date_to: query.dateTo ?? null, grain: query.grain ?? null,
      plantation_id: query.plantationId ?? null, lot_id: query.lotId ?? null, category_id: query.categoryId ?? null,
    });
    return parseExpenseBalance(data);
  }

  /** Detail rows of vw_agri_expense_summary for whole periods between dateFrom (a period start) and dateTo. */
  async getExpenseSummary(query: ExpenseBalanceQuery): Promise<ListResult<ExpenseSummaryRow>> {
    const tenant = this.requireTenant();
    const filters: Record<string, unknown> = {
      id_company: tenant, grain: query.grain, period_start: { _gte: query.dateFrom, _lte: query.dateTo },
    };
    if (query.plantationId) filters['plantation_id'] = query.plantationId;
    if (query.lotId) filters['lot_id'] = query.lotId;
    if (query.categoryId) filters['category_id'] = query.categoryId;
    const res = await this.post('agri_expense_summary', { operation: 'getall', filters, limit: 2000, sort_by: 'period_start' });
    const raw = stripPhantomRows(this.rows(res), 'id');
    const items = raw.filter(r => toInt(r['id_company']) === tenant && r['grain'] === query.grain).map(r => this.mapSummary(r))
      .sort((a, b) => a.periodStart.localeCompare(b.periodStart) || b.totalAmount - a.totalAmount);
    return { items, possiblyTruncated: isPossiblyTruncated(raw.length) };
  }

  // ------------------------------------------------------------------------------------------------
  // Plumbing
  // ------------------------------------------------------------------------------------------------

  private requireTenant(): number {
    const tenant = Number(this.tenantService.activeTenantId());
    if (!Number.isInteger(tenant) || tenant <= 0) {
      throw new AgriTenantContextError('No hay una empresa activa en la sesión.');
    }
    return tenant;
  }

  private async getOwned(model: string, id: string, notFound: string): Promise<Row> {
    const tenant = this.requireTenant();
    if (!id) throw new AgriTenantContextError(notFound);
    const res = await this.post(model, { operation: 'getone', filters: { id } });
    const raw = this.rows(res)[0];
    if (isPhantomRow(raw, 'id') || toInt(raw['id_company']) !== tenant || raw['id'] !== id) {
      throw new AgriTenantContextError(notFound);
    }
    return raw;
  }

  /** Posts to the gateway and surfaces error:true (HTTP 200) or an empty body as a thrown error. */
  private async post(model: string, payload: object): Promise<any> {
    const res: any = await firstValueFrom(this.http.post(`${this.apiUrl}/${model}`, payload));
    if (!res || typeof res !== 'object') throw new Error(UNCONFIRMED_MESSAGE);
    if (res.error) throw new Error(friendlyGatewayError(String(res.message ?? '')));
    return res;
  }

  private async callSp(model: string, fields: Record<string, unknown>): Promise<Record<string, unknown>> {
    this.requireTenant();
    const res = await firstValueFrom(this.http.post(`${this.apiUrl}/${model}`, { operation: 'call_sp', fields }));
    const outcome = interpretSpResponse(res);
    if (!outcome.ok) throw new Error(outcome.message);
    return outcome.data;
  }

  private rows(res: any): Row[] {
    const data = res?.data;
    if (Array.isArray(data)) return data;
    return data && typeof data === 'object' ? [data] : [];
  }

  private mapPlantation(r: Row): Plantation {
    return {
      id: r['id'], idCompany: toInt(r['id_company']),
      code: r['plantation_code'] ?? '', name: r['plantation_name'] ?? '',
      state: r['state'] ?? null, municipality: r['municipality'] ?? null, locality: r['locality'] ?? null,
      latitude: toNumber(r['latitude']), longitude: toNumber(r['longitude']),
      totalAreaHa: toNumber(r['total_area_ha']) ?? 0,
      tenure: r['tenure'] as PlantationTenure, lessorName: r['lessor_name'] ?? null,
      isDefault: toBool(r['is_default']), isActive: toBool(r['is_active']),
      notes: r['notes'] ?? null, createdAt: r['created_at'] ?? '',
    };
  }

  private mapPlantationSummary(r: Row): PlantationSummary {
    return {
      id: r['id'], idCompany: toInt(r['id_company']), code: r['plantation_code'] ?? '', name: r['plantation_name'] ?? '',
      isActive: toBool(r['is_active']), isDefault: toBool(r['is_default']),
      totalAreaHa: toNumber(r['total_area_ha']) ?? 0, activeLots: toInt(r['active_lots']),
      plantedAreaHa: toNumber(r['planted_area_ha']) ?? 0, hasAreaInconsistency: toBool(r['has_area_inconsistency']),
      activeRows: toInt(r['active_rows']), plantingPositions: toInt(r['planting_positions']),
      alivePlants: toInt(r['alive_plants']), missingPlants: toInt(r['missing_plants']),
    };
  }

  private mapLot(r: Row): Lot {
    return {
      id: r['id'], idCompany: toInt(r['id_company']), plantationId: r['plantation_id'],
      code: r['lot_code'] ?? '', name: r['lot_name'] ?? null, areaHa: toNumber(r['area_ha']) ?? 0,
      plantingDate: r['planting_date'] ? String(r['planting_date']).slice(0, 10) : null,
      plantingDateIsApprox: toBool(r['planting_date_is_approx']),
      varietyId: r['variety_id'] ?? null, seedSupplier: r['seed_supplier'] ?? null,
      plantingPattern: r['planting_pattern'] ?? null, spacingM: toNumber(r['spacing_m']),
      designDensityPlantsHa: toNumber(r['design_density_plants_ha']),
      waterRegime: r['water_regime'] ?? null, soilType: r['soil_type'] ?? null,
      tenure: r['tenure'] ?? null, lessorName: r['lessor_name'] ?? null,
      isActive: toBool(r['is_active']), notes: r['notes'] ?? null,
    };
  }

  private mapLotSummary(r: Row): LotSummary {
    return {
      id: r['id'], idCompany: toInt(r['id_company']), plantationId: r['plantation_id'],
      code: r['lot_code'] ?? '', name: r['lot_name'] ?? null, isActive: toBool(r['is_active']),
      areaHa: toNumber(r['area_ha']) ?? 0,
      plantingDate: r['planting_date'] ? String(r['planting_date']).slice(0, 10) : null,
      plantingDateIsApprox: toBool(r['planting_date_is_approx']),
      varietyName: r['variety_name'] ?? null,
      effectiveTenure: r['effective_tenure'] ?? null, effectiveLessorName: r['effective_lessor_name'] ?? null,
      ageYears: toNumber(r['age_years']), productiveStage: (r['productive_stage'] ?? 'SIN_FECHA') as ProductiveStage,
      activeRows: toInt(r['active_rows']), plantingPositions: toInt(r['planting_positions']),
      alivePlants: toInt(r['alive_plants']), missingPlants: toInt(r['missing_plants']),
      realDensityPlantsHa: toNumber(r['real_density_plants_ha']),
      designDensityPlantsHa: toNumber(r['design_density_plants_ha']),
      densityPctOfDesign: toNumber(r['density_pct_of_design']),
      lastCensusDate: r['last_census_date'] ? String(r['last_census_date']).slice(0, 10) : null,
    };
  }

  private mapRow(r: Row): AgriRow {
    return {
      id: r['id'], idCompany: toInt(r['id_company']), lotId: r['lot_id'],
      rowNumber: toInt(r['row_number']), plantingPositions: toInt(r['planting_positions']),
      alivePlants: toInt(r['alive_plants']),
      lastCensusDate: r['last_census_date'] ? String(r['last_census_date']).slice(0, 10) : null,
      isActive: toBool(r['is_active']), notes: r['notes'] ?? null,
    };
  }

  private mapCategory(r: Row): ExpenseCategory {
    return {
      id: r['id'], idCompany: toInt(r['id_company']), code: r['category_code'] ?? '', name: r['category_name'] ?? '',
      sortOrder: toInt(r['sort_order'], 100), isActive: toBool(r['is_active']),
    };
  }

  private mapExpense(r: Row): AgriExpense {
    const date = (v: unknown) => (v ? String(v).slice(0, 10) : '');
    return {
      id: r['id'], idCompany: toInt(r['id_company']),
      plantationId: r['plantation_id'] ?? null, plantationCode: r['plantation_code'] ?? null, plantationName: r['plantation_name'] ?? null,
      lotId: r['lot_id'] ?? null, lotCode: r['lot_code'] ?? null, lotName: r['lot_name'] ?? null,
      categoryId: r['category_id'], categoryCode: r['category_code'] ?? '', categoryName: r['category_name'] ?? '',
      expenseDate: date(r['expense_date']), amount: toNumber(r['amount']) ?? 0, quantity: toNumber(r['quantity']),
      unitCode: r['unit_code'] ?? null, unitName: r['unit_name'] ?? null,
      supplierName: r['supplier_name'] ?? null, description: r['description'] ?? null,
      isInvoiced: toBool(r['is_invoiced']), invoiceFolio: r['invoice_folio'] ?? null,
      reportedByEmail: r['reported_by_email'] ?? '', isVoid: toBool(r['is_void']), voidReason: r['void_reason'] ?? null,
      voidedByEmail: r['voided_by_email'] ?? null, voidedAt: r['voided_at'] ?? null, createdAt: r['created_at'] ?? '',
    };
  }

  private mapSummary(r: Row): ExpenseSummaryRow {
    const date = (v: unknown) => (v ? String(v).slice(0, 10) : '');
    return {
      id: r['id'], idCompany: toInt(r['id_company']), grain: r['grain'] as ExpenseGrain,
      periodStart: date(r['period_start']), periodEnd: date(r['period_end']),
      plantationId: r['plantation_id'] ?? null, plantationCode: r['plantation_code'] ?? null, plantationName: r['plantation_name'] ?? null,
      lotId: r['lot_id'] ?? null, lotCode: r['lot_code'] ?? null, lotName: r['lot_name'] ?? null,
      categoryId: r['category_id'], categoryCode: r['category_code'] ?? '', categoryName: r['category_name'] ?? '',
      totalAmount: toNumber(r['total_amount']) ?? 0, expenseCount: toInt(r['expense_count']),
    };
  }

  private mapHistory(r: Row): CensusHistoryEntry {
    return {
      id: r['id'], rowId: r['row_id'],
      previousPositions: toNumber(r['previous_positions']), newPositions: toInt(r['new_positions']),
      previousAlive: toNumber(r['previous_alive']), newAlive: toInt(r['new_alive']),
      reason: r['reason'] as HistoryReason, changedBy: r['changed_by'] ?? null, notes: r['notes'] ?? null,
      changedAt: r['changed_at'] ?? '',
    };
  }
}
