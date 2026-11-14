import { TestBed } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { tenantInterceptor } from './tenant.interceptor';
import { TenantService } from '../services/tenant.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

describe('tenantInterceptor', () => {
  const config = {
    apiUrl_crud: 'https://n8n.example.com/webhook/abc/crud/v6',
    apiUrl_token: 'https://n8n.example.com/webhook/v3/genera-token',
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

  function tenantHeadersFor(url: string): [string | null, string | null] {
    http.post(url, {}).subscribe({ error: () => undefined });
    const req = ctrl.expectOne(url);
    const headers: [string | null, string | null] = [
      req.request.headers.get('X-Tenant-ID'),
      req.request.headers.get('x-tenant-id')
    ];
    req.flush({});
    return headers;
  }

  it('sends X-Tenant-ID to each configured origin', () => {
    expect(tenantHeadersFor(config.apiUrl_crud + '/x')).toEqual(['7', '7']);
    expect(tenantHeadersFor(config.apiUrl_ai)).toEqual(['7', '7']);
    expect(tenantHeadersFor(config.apiUrl_upload + '/x')).toEqual(['7', '7']);
  });

  it('does not send the tenant header to look-alike, other-port or other-scheme hosts', () => {
    expect(tenantHeadersFor('https://n8n.example.com.evil.example/x')).toEqual([null, null]);
    expect(tenantHeadersFor('https://n8n.example.com:8443/x')).toEqual([null, null]);
    expect(tenantHeadersFor('http://n8n.example.com/x')).toEqual([null, null]);
  });

  it('does not send the tenant header to a foreign origin', () => {
    expect(tenantHeadersFor('https://cdn.other.example/x')).toEqual([null, null]);
  });

  it('does not send the tenant header on relative or unparseable URLs', () => {
    expect(tenantHeadersFor('/api/x')).toEqual([null, null]);
    expect(tenantHeadersFor('not a url')).toEqual([null, null]);
  });

  it('rejects protected requests when there is no active tenant', () => {
    tenantId = null;
    let result: unknown;

    http.post(config.apiUrl_crud + '/x', {}).subscribe({
      next: () => fail('Expected a rejected request'),
      error: (error) => { result = error; }
    });

    expect(result).toEqual(jasmine.objectContaining({ status: 403, statusText: 'No active tenant' }));
  });

  it('allows the public company directory without a tenant', () => {
    tenantId = null;
    expect(tenantHeadersFor(config.apiUrl_crud + '/companys/getall')).toEqual([null, null]);
  });
});
