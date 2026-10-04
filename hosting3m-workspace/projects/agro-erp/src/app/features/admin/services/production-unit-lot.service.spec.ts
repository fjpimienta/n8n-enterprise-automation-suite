import { TestBed } from '@angular/core/testing';
import { HttpClient } from '@angular/common/http';
import { signal } from '@angular/core';
import { of } from 'rxjs';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import {
  DuplicateLotNameError,
  ProductionUnitLotService,
  TenantContextError,
} from './production-unit-lot.service';

const UPP = 'upp-1';

/** Minimal fake of the Meta-CRUD gateway: answers per (model, operation) and records every call. */
class FakeGateway {
  calls: Array<{ model: string; body: any }> = [];
  responses: Record<string, any> = {};

  post(url: string, body: any) {
    const model = url.split('/').pop()!;
    this.calls.push({ model, body });
    const res = this.responses[`${model}:${body.operation}`] ?? { error: false, data: [{}] };
    return of(res);
  }

  callsFor(model: string, operation: string) {
    return this.calls.filter(c => c.model === model && c.body.operation === operation);
  }
}

describe('ProductionUnitLotService', () => {
  let service: ProductionUnitLotService;
  let gateway: FakeGateway;
  let activeTenantId: ReturnType<typeof signal<number | null>>;
  let livestock: any[];

  const lotRow = (overrides: Record<string, unknown> = {}) => ({
    id: 'lot-1',
    id_company: 3,
    production_unit_id: UPP,
    lot_name: 'Potrero 1',
    tenure_type: 'RENTADA',
    lessor_name: 'Eladio',
    location_notes: null,
    is_active: true,
    notes: null,
    created_at: '2026-10-01',
    ...overrides,
  });

  beforeEach(() => {
    gateway = new FakeGateway();
    activeTenantId = signal<number | null>(3);
    livestock = [];

    TestBed.configureTestingModule({
      providers: [
        { provide: HttpClient, useValue: gateway },
        { provide: TenantService, useValue: { activeTenantId } },
        { provide: CattleApiService, useValue: { getAllLivestock: async () => livestock } },
      ],
    });
    service = TestBed.inject(ProductionUnitLotService);
  });

  it('refuses to call the gateway without an active tenant', async () => {
    activeTenantId.set(null);
    await expect(service.getLots(UPP)).rejects.toBeInstanceOf(TenantContextError);
    expect(gateway.calls.length).toBe(0);
  });

  it('drops rows of other tenants and phantom rows', async () => {
    gateway.responses['production_unit_lots:getall'] = {
      error: false,
      data: [lotRow(), lotRow({ id: 'lot-x', id_company: 6 }), {}],
    };
    const lots = await service.getLots(UPP);
    expect(lots.map(l => l.id)).toEqual(['lot-1']);
  });

  it('counts live head per lot by UPP + case-insensitive name, ignoring terminal statuses and other tenants', async () => {
    gateway.responses['production_unit_lots:getall'] = { error: false, data: [lotRow()] };
    livestock = [
      { tenant_id: 3, production_unit_id: UPP, lot_name: 'potrero 1', current_status: 'ACTIVO' },
      { tenant_id: 3, production_unit_id: UPP, lot_name: 'Potrero 1', current_status: 'PREÑADA' },
      { tenant_id: 3, production_unit_id: UPP, lot_name: 'Potrero 1', current_status: 'VENDIDO' },
      { tenant_id: 6, production_unit_id: UPP, lot_name: 'Potrero 1', current_status: 'ACTIVO' },
      { tenant_id: 3, production_unit_id: 'upp-2', lot_name: 'Potrero 1', current_status: 'ACTIVO' },
    ];
    const [lot] = await service.getLots(UPP);
    expect(lot.assignedLivestockCount).toBe(2);
  });

  it('reports the count as ambiguous when two lots of the UPP share a name', async () => {
    gateway.responses['production_unit_lots:getall'] = {
      error: false,
      data: [lotRow(), lotRow({ id: 'lot-2', lot_name: 'POTRERO 1', is_active: false })],
    };
    const lots = await service.getLots(UPP);
    expect(lots.every(l => l.assignedLivestockCount === null)).toBe(true);
  });

  it('rejects creating a lot in a UPP owned by another tenant', async () => {
    gateway.responses['production_units:getone'] = { error: false, data: [{ id: UPP, id_company: 6, is_active: true }] };
    await expect(service.createLot({ productionUnitId: UPP, lotName: 'X', tenureType: 'PROPIO' }))
      .rejects.toBeInstanceOf(TenantContextError);
    expect(gateway.callsFor('production_unit_lots', 'insert').length).toBe(0);
  });

  it('creates with the session tenant and a null lessor for non-rented tenure', async () => {
    gateway.responses['production_units:getone'] = { error: false, data: [{ id: UPP, id_company: 3, is_active: true }] };
    await service.createLot({ productionUnitId: UPP, lotName: '  Corral  ', tenureType: 'PROPIO', lessorName: 'ignored' });
    const [insert] = gateway.callsFor('production_unit_lots', 'insert');
    expect(insert.body.fields).toEqual(expect.objectContaining({
      id_company: 3, production_unit_id: UPP, lot_name: 'Corral', tenure_type: 'PROPIO', lessor_name: null, is_active: true,
    }));
  });

  it('never updates a lot that the tenant-scoped getone does not confirm', async () => {
    gateway.responses['production_unit_lots:getone'] = { error: false, data: {} };
    await expect(service.deactivateLot('lot-x')).rejects.toBeInstanceOf(TenantContextError);
    expect(gateway.callsFor('production_unit_lots', 'update').length).toBe(0);
  });

  it('soft-deletes via is_active = false (never a DELETE)', async () => {
    gateway.responses['production_unit_lots:getone'] = { error: false, data: [lotRow()] };
    await service.deactivateLot('lot-1');
    const [update] = gateway.callsFor('production_unit_lots', 'update');
    expect(update.body).toEqual(expect.objectContaining({ id: 'lot-1', fields: { is_active: false } }));
    expect(gateway.calls.some(c => c.body.operation === 'delete')).toBe(false);
  });

  it('clears lessor_name when tenure changes away from RENTADA', async () => {
    gateway.responses['production_unit_lots:getone'] = { error: false, data: [lotRow()] };
    await service.updateLot('lot-1', { tenureType: 'PROPIO' });
    const [update] = gateway.callsFor('production_unit_lots', 'update');
    expect(update.body.fields).toEqual({ tenure_type: 'PROPIO', lessor_name: null });
  });

  it('maps the unique-index violation (HTTP 200 + error:true) to DuplicateLotNameError', async () => {
    gateway.responses['production_unit_lots:getone'] = { error: false, data: [lotRow({ is_active: false })] };
    gateway.responses['production_unit_lots:update'] = {
      error: true,
      message: 'duplicate key value violates unique constraint "uq_lot_name_per_unit"',
    };
    await expect(service.reactivateLot('lot-1')).rejects.toBeInstanceOf(DuplicateLotNameError);
  });
});
