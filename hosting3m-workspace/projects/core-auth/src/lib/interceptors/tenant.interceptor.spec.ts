import { TestBed } from '@angular/core/testing';
import { HttpClient, HttpErrorResponse, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { tenantInterceptor } from './tenant.interceptor';
import { TenantService } from '../services/tenant.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

/** Body sent by the dashboard and agro-erp services for the public `companys getall` read. */
const COMPANYS_GETALL_BODY = {
  entity: 'companys',
  table_name: 'companys',
  operation: 'getall',
  action: 'list',
  filters: {}
};

describe('tenantInterceptor', () => {
  const config = {
    apiUrl_crud: 'https://n8n-gateway/webhook/abc/crud/v6',
    apiUrl_token: 'https://n8n-gateway/webhook/v3/genera-token',
    apiUrl_ai: 'https://ai.example.com',
    apiUrl_upload: 'https://files.example.com:3001/upload',
    system_id: 'test'
  };
  let tenantId: number | null;
  let http: HttpClient;
  let ctrl: HttpTestingController;

  beforeEach(() => {
    tenantId = 7;
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([tenantInterceptor])),
        provideHttpClientTesting(),
        { provide: AUTH_ENV_CONFIG, useValue: config },
        { provide: TenantService, useValue: { activeTenantId: () => tenantId } }
      ]
    });
    http = TestBed.inject(HttpClient);
    ctrl = TestBed.inject(HttpTestingController);
  });

  /** Sends a POST and returns the tenant headers seen by the backend, or [null, null] when none. */
  function tenantHeadersFor(url: string, body: unknown = {}): [string | null, string | null] {
    http.post(url, body).subscribe({ error: () => undefined });
    const req = ctrl.expectOne(url);
    const headers: [string | null, string | null] = [
      req.request.headers.get('X-Tenant-ID'),
      req.request.headers.get('x-tenant-id')
    ];
    req.flush({});
    return headers;
  }

  /**
   * Sends a POST and returns the error raised by the interceptor, or null when the request
   * reached the backend (in which case it is flushed so the call completes).
   */
  function rejectionFor(url: string, body: unknown = {}): HttpErrorResponse | null {
    const state: { error: HttpErrorResponse | null } = { error: null };
    http.post(url, body).subscribe({ error: (err: HttpErrorResponse) => { state.error = err; } });
    ctrl.match(url).forEach((req) => req.flush({}));
    return state.error;
  }

  describe('with an active tenant', () => {
    it('sends X-Tenant-ID to each configured origin', () => {
      expect(tenantHeadersFor(config.apiUrl_crud + '/x')).toEqual(['7', '7']);
      expect(tenantHeadersFor(config.apiUrl_ai)).toEqual(['7', '7']);
      expect(tenantHeadersFor(config.apiUrl_upload + '/x')).toEqual(['7', '7']);
    });

    it('keeps the tenant header on companys operations other than getall', () => {
      expect(tenantHeadersFor(config.apiUrl_crud + '/companys', { ...COMPANYS_GETALL_BODY, operation: 'update' }))
        .toEqual(['7', '7']);
    });

    it('does not send the tenant header to look-alike, other-port or other-scheme hosts', () => {
      expect(tenantHeadersFor('https://n8n-gateway.evil.example/x')).toEqual([null, null]);
      expect(tenantHeadersFor('https://n8n-gateway:8443/x')).toEqual([null, null]);
      expect(tenantHeadersFor('http://n8n-gateway/x')).toEqual([null, null]);
    });

    it('does not send the tenant header to a foreign origin', () => {
      expect(tenantHeadersFor('https://cdn.other.example/x')).toEqual([null, null]);
    });

    it('does not send the tenant header on relative or unparseable URLs', () => {
      expect(tenantHeadersFor('/api/x')).toEqual([null, null]);
      expect(tenantHeadersFor('not a url')).toEqual([null, null]);
    });

    it('passes the token endpoint through without a tenant header', () => {
      expect(tenantHeadersFor(config.apiUrl_token, { user: 'u', pass: 'p' })).toEqual([null, null]);
    });
  });

  describe('without a valid active tenant', () => {
    it('rejects protected requests with 403 when there is no tenant', () => {
      tenantId = null;
      expect(rejectionFor(config.apiUrl_crud + '/x')).toEqual(
        expect.objectContaining({ status: 403, statusText: 'No active tenant' })
      );
    });

    it('rejects zero, negative, fractional and NaN tenant ids', () => {
      for (const invalid of [0, -1, 1.5, Number.NaN]) {
        tenantId = invalid;
        expect(rejectionFor(config.apiUrl_crud + '/x')?.status).toBe(403);
      }
    });

    it('rejects protected CRUD requests on the origin shared with apiUrl_token', () => {
      tenantId = null;
      expect(rejectionFor(config.apiUrl_crud + '/hotel_rooms', { entity: 'hotel_rooms' })?.status).toBe(403);
    });

    it('rejects other paths on the apiUrl_token origin', () => {
      tenantId = null;
      expect(rejectionFor('https://n8n-gateway/webhook/v3/other')?.status).toBe(403);
    });

    it('allows the public companys getall without a tenant and sends no tenant header', () => {
      tenantId = null;
      expect(tenantHeadersFor(config.apiUrl_crud + '/companys', COMPANYS_GETALL_BODY)).toEqual([null, null]);
    });

    it('rejects companys operations other than getall with 403', () => {
      tenantId = null;
      const url = config.apiUrl_crud + '/companys';
      for (const operation of ['getone', 'insert', 'update', 'delete']) {
        expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, operation })?.status).toBe(403);
      }
    });

    it('rejects a companys getall whose entity or table_name is another table', () => {
      tenantId = null;
      const url = config.apiUrl_crud + '/companys';
      expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, entity: 'users' })?.status).toBe(403);
      expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, table_name: 'users' })?.status).toBe(403);
    });

    it('rejects a companys getall on a path that is not the companys collection endpoint', () => {
      tenantId = null;
      expect(rejectionFor(config.apiUrl_crud + '/companys/getall', COMPANYS_GETALL_BODY)?.status).toBe(403);
    });
  });
});
