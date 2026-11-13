import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TenantService } from 'core-auth';
import { environment } from '@env/environment';
import { AgriApiService, AgriTenantContextError } from './agri-api.service';

const TENANT = 10;
const OTHER = 11;

/** A row of the browser view, as the gateway sends it (numerics as strings, the date as a timestamp at 06:00Z). */
const saleRow = (o: Record<string, unknown> = {}) => ({
  id: 's1', id_company: TENANT, folio: 'S1', sale_date: '2026-11-12T06:00:00.000Z', buyer_name: 'COMPRADOR SINTETICO',
  quantity: '1250.500', unit_code: 'KGM', unit_price: '8.123456', total_amount: '10158.49', payment_method: 'PUE',
  ticket_ref: 'T1', ticket_warning: false, plantation_id: 'p1', plantation_code: 'P1', plantation_name: 'Norte',
  lot_id: null, lot_code: null, lot_name: null, status: 'ACTIVE', void_reason: null, voided_at: null, is_test: false,
  created_at: '2026-11-12T18:30:00.000Z', ...o,
});

function setup(tenant: string | null = String(TENANT)) {
  TestBed.configureTestingModule({
    providers: [provideHttpClient(), provideHttpClientTesting(), { provide: TenantService, useValue: { activeTenantId: () => tenant } }],
  });
  return { service: TestBed.inject(AgriApiService), http: TestBed.inject(HttpTestingController) };
}

describe('AgriApiService.getSales', () => {
  afterEach(() => TestBed.inject(HttpTestingController).verify());
  const query = { dateFrom: '2026-11-01', dateTo: '2026-11-30', plantationId: null, lotId: null, status: 'ALL' as const };

  it('posts a getall on agri_sales with the company, the date range, limit 2000 and sort_by sale_date', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    const req = http.expectOne(`${environment.apiUrl_crud}/agri_sales`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({
      operation: 'getall', limit: 2000, sort_by: 'sale_date',
      filters: { id_company: TENANT, sale_date: { _gte: '2026-11-01', _lte: '2026-11-30' } },
    });
    req.flush({ error: false, data: [saleRow()] });
    const { items, possiblyTruncated } = await pending;
    expect(possiblyTruncated).toBe(false);
    expect(items).toHaveLength(1);
  });

  it('adds only the filters that were chosen (plantation, lot, status)', async () => {
    const { service, http } = setup();
    const pending = service.getSales({ ...query, plantationId: 'p1', lotId: 'l1', status: 'VOID' });
    await Promise.resolve();
    const req = http.expectOne(`${environment.apiUrl_crud}/agri_sales`);
    expect(req.request.body.filters).toEqual({
      id_company: TENANT, sale_date: { _gte: '2026-11-01', _lte: '2026-11-30' }, plantation_id: 'p1', lot_id: 'l1', status: 'VOID',
    });
    req.flush({ error: false, data: [] });
    await pending;
  });

  it('maps numerics from strings, keeps only the first 10 characters of the date and leaves real instants alone', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: false, data: [
      saleRow({ status: 'VOID', void_reason: 'Duplicada', voided_at: '2026-11-13T01:00:00.000Z', is_test: true, ticket_warning: 't' }),
    ] });
    const sale = (await pending).items[0];
    expect(sale).toMatchObject({
      id: 's1', idCompany: TENANT, saleDate: '2026-11-12', quantityKg: 1250.5, unitPrice: 8.123456, totalAmount: 10158.49,
      status: 'VOID', voidReason: 'Duplicada', voidedAt: '2026-11-13T01:00:00.000Z', isTest: true, ticketWarning: true,
      createdAt: '2026-11-12T18:30:00.000Z', plantationCode: 'P1', lotId: null,
    });
    expect(typeof sale.totalAmount).toBe('number');
  });

  it('a date-only value at 00:00Z gives the same day', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: false, data: [saleRow({ sale_date: '2026-11-12T00:00:00.000Z' })] });
    expect((await pending).items[0].saleDate).toBe('2026-11-12');
  });

  it('strips the phantom row of an empty result', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: false, data: [{}] });
    expect((await pending).items).toEqual([]);
  });

  it('drops rows of another company', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: false, data: [
      saleRow({ id: 'mine' }), saleRow({ id: 'foreign', id_company: OTHER }), saleRow({ id: 'nocompany', id_company: null }),
    ] });
    expect((await pending).items.map(s => s.id)).toEqual(['mine']);
  });

  it('sorts newest first and warns when the page may be cut (exactly 2000 rows)', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    const rows = Array.from({ length: 2000 }, (_, i) => saleRow({ id: `s${i}`, sale_date: i === 7 ? '2026-11-20T06:00:00.000Z' : '2026-11-02T06:00:00.000Z' }));
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: false, data: rows });
    const result = await pending;
    expect(result.possiblyTruncated).toBe(true);
    expect(result.items[0].id).toBe('s7');
  });

  it('an error:true answer is thrown (never an empty list)', async () => {
    const { service, http } = setup();
    const pending = service.getSales(query);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sales`).flush({ error: true, message: 'Sin permiso para esta operación.' });
    await expect(pending).rejects.toThrow('Sin permiso para esta operación.');
  });

  it('fails closed without an active company: no request', async () => {
    const { service, http } = setup(null);
    await expect(service.getSales(query)).rejects.toBeInstanceOf(AgriTenantContextError);
    http.expectNone(`${environment.apiUrl_crud}/agri_sales`);
  });
});

describe('AgriApiService.getSalesBalance', () => {
  afterEach(() => TestBed.inject(HttpTestingController).verify());
  const answer = { success: true, grain: 'MONTH', date_from: '2026-11-01', date_to: '2026-11-30', total_amount: '500.25', sale_count: 2, total_quantity_kg: '60', by_period: [], by_plantation: [] };

  it('calls agri_sale_balance with call_sp, ids as null instead of "" and no company or e-mail in the payload', async () => {
    const { service, http } = setup();
    const pending = service.getSalesBalance({ dateFrom: '2026-11-01', dateTo: '2026-11-30', grain: 'MONTH', plantationId: '', lotId: '' });
    await Promise.resolve();
    const req = http.expectOne(`${environment.apiUrl_crud}/agri_sale_balance`);
    expect(req.request.body).toEqual({
      operation: 'call_sp',
      fields: { date_from: '2026-11-01', date_to: '2026-11-30', grain: 'MONTH', plantation_id: null, lot_id: null },
    });
    expect(JSON.stringify(req.request.body)).not.toMatch(/id_company|tenant|actor_email/);
    req.flush({ error: false, data: answer });
    expect(await pending).toMatchObject({ totalAmount: 500.25, saleCount: 2, totalQuantityKg: 60 });
  });

  it('sends the chosen plantation and lot', async () => {
    const { service, http } = setup();
    const pending = service.getSalesBalance({ dateFrom: '2026-11-01', dateTo: '2026-11-30', grain: 'DAY', plantationId: 'p1', lotId: 'l1' });
    await Promise.resolve();
    const req = http.expectOne(`${environment.apiUrl_crud}/agri_sale_balance`);
    expect(req.request.body.fields).toMatchObject({ grain: 'DAY', plantation_id: 'p1', lot_id: 'l1' });
    req.flush({ error: false, data: answer });
    await pending;
  });

  it('is a success only with success:true (otherwise not confirmed) and surfaces error:true', async () => {
    const { service, http } = setup();
    const q = { dateFrom: '2026-11-01', dateTo: '2026-11-30', grain: 'MONTH' as const, plantationId: null, lotId: null };
    const first = service.getSalesBalance(q);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sale_balance`).flush({ error: false, data: { total_amount: '1' } });
    await expect(first).rejects.toThrow('no confirmó');
    const second = service.getSalesBalance(q);
    await Promise.resolve();
    http.expectOne(`${environment.apiUrl_crud}/agri_sale_balance`).flush({ error: true, message: 'Solo un administrador de la empresa puede consultar el balance de ventas.' });
    await expect(second).rejects.toThrow('administrador');
  });

  it('fails closed without an active company: no request', async () => {
    const { service, http } = setup(null);
    await expect(service.getSalesBalance({ dateFrom: '', dateTo: '', grain: 'MONTH', plantationId: null, lotId: null })).rejects.toBeInstanceOf(AgriTenantContextError);
    http.expectNone(`${environment.apiUrl_crud}/agri_sale_balance`);
  });
});
