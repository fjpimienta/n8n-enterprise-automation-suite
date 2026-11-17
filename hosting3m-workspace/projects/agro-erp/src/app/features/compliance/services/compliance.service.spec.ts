import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting, TestRequest } from '@angular/common/http/testing';
import { environment } from '@env/environment';
import { ComplianceService } from './compliance.service';

const UPP_URL = `${environment.apiUrl_crud}/upp_compliance_status`;
const PSG_URL = `${environment.apiUrl_crud}/psg_compliance_status`;
const DETAIL_URL = `${environment.apiUrl_crud}/production_units`;

const uppRow = (overrides: Record<string, unknown> = {}) => ({
  production_unit_id: 'upp-1',
  ranch_name: 'Rancho Uno',
  update_status: 'OK',
  days_since_update: 10,
  total_surface_ha: '12.5',
  grazing_surface_ha: null,
  last_declared_head: '30',
  active_head_in_system: '28',
  ...overrides
});

const psgRow = (overrides: Record<string, unknown> = {}) => ({
  psg_license_id: 'psg-1',
  validity_status: 'OK',
  ...overrides
});

const ok = (data: unknown[]) => ({ error: false, operation: 'getall', message: '', data });
const serverError = { error: true, operation: 'getall', message: 'Fallo del gateway', data: [] };

describe('ComplianceService', () => {
  let service: ComplianceService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()]
    });
    service = TestBed.inject(ComplianceService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  describe('per-source failure', () => {
    it('UPP fails and PSG succeeds: UPP is failed, PSG is loaded, and PSG has no error', () => {
      service.loadUppStatus();
      service.loadPsgStatus();

      httpMock.expectOne(UPP_URL).flush(null, { status: 500, statusText: 'Server Error' });
      httpMock.expectOne(PSG_URL).flush(ok([psgRow()]));

      expect(service.uppState()).toBe('failed');
      expect(service.uppError()?.reason).toBe('unavailable');
      expect(service.uppList()).toEqual([]);
      expect(service.psgState()).toBe('loaded');
      expect(service.psgError()).toBeNull();
      expect(service.psgList().length).toBe(1);
    });

    it('PSG fails after UPP succeeded: the UPP data and state are kept (no cross-clearing)', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(ok([uppRow()]));

      service.loadPsgStatus();
      httpMock.expectOne(PSG_URL).flush(serverError);

      expect(service.uppState()).toBe('loaded');
      expect(service.uppError()).toBeNull();
      expect(service.uppList().length).toBe(1);
      expect(service.psgState()).toBe('failed');
      expect(service.psgError()?.message).toBe('Fallo del gateway');
    });

    it('a successful PSG load does not clear a UPP error from an earlier failure', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(serverError);

      service.loadPsgStatus();
      httpMock.expectOne(PSG_URL).flush(ok([]));

      expect(service.uppState()).toBe('failed');
      expect(service.uppError()).not.toBeNull();
      expect(service.psgState()).toBe('loaded');
    });

    it('reports a network failure (status 0) as reason network', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).error(new ProgressEvent('error'));

      expect(service.uppState()).toBe('failed');
      expect(service.uppError()?.reason).toBe('network');
    });
  });

  describe('gateway and payload failures', () => {
    it('treats HTTP 200 with error:true as failed and keeps the server message', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(serverError);

      expect(service.uppState()).toBe('failed');
      expect(service.uppError()?.message).toBe('Fallo del gateway');
    });

    it('treats a non-array data field on HTTP 200 as failed, not as an empty success', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush({ error: false, operation: 'getall', message: '', data: {} });

      expect(service.uppState()).toBe('failed');
      expect(service.uppError()).not.toBeNull();
    });

    it('treats a null response body as failed and leaves no loading state behind', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(null);

      expect(service.uppState()).toBe('failed');
      expect(service.loadingUpp()).toBe(false);
    });

    it('treats a genuinely empty array as a successful, empty load', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(ok([]));

      expect(service.uppState()).toBe('loaded');
      expect(service.uppError()).toBeNull();
      expect(service.uppList()).toEqual([]);
    });

    it('ignores the gateway phantom row [{}] and still counts as loaded', () => {
      service.loadPsgStatus();
      httpMock.expectOne(PSG_URL).flush(ok([{}]));

      expect(service.psgState()).toBe('loaded');
      expect(service.psgList()).toEqual([]);
    });
  });

  describe('retry', () => {
    it('reloads only the failed source and clears only its error', () => {
      service.loadUppStatus();
      service.loadPsgStatus();
      httpMock.expectOne(UPP_URL).flush(serverError);
      httpMock.expectOne(PSG_URL).flush(ok([]));

      service.retryFailed();
      httpMock.expectNone(PSG_URL);
      httpMock.expectOne(UPP_URL).flush(ok([uppRow()]));

      expect(service.uppState()).toBe('loaded');
      expect(service.uppError()).toBeNull();
      expect(service.uppList().length).toBe(1);
      expect(service.psgState()).toBe('loaded');
    });
  });

  describe('forced reload', () => {
    it('a failed forced reload clears the last good data and is failed (fail-closed)', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(ok([uppRow({ update_status: 'EXPIRED' })]));
      expect(service.uppList().length).toBe(1);

      service.loadUppStatus(true);
      httpMock.expectOne(UPP_URL).flush(null, { status: 503, statusText: 'Unavailable' });

      expect(service.uppState()).toBe('failed');
      expect(service.uppList()).toEqual([]);
      expect(service.expiredUppCount()).toBe(0);
    });

    it('does not re-request a loaded source unless forced', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(ok([]));

      service.loadUppStatus();
      httpMock.expectNone(UPP_URL);
    });

    it('does not start a duplicate request while the same source is still loading', () => {
      service.loadUppStatus();
      service.loadUppStatus();

      httpMock.expectOne(UPP_URL).flush(ok([]));
      expect(service.uppState()).toBe('loaded');
    });
  });

  describe('latest-wins', () => {
    it('ignores an older response that arrives after a newer forced request', () => {
      service.loadUppStatus();
      service.loadUppStatus(true);

      const [older, newer] = httpMock.match(UPP_URL) as TestRequest[];
      newer.flush(serverError);
      older.flush(ok([uppRow()]));

      expect(service.uppState()).toBe('failed');
      expect(service.uppList()).toEqual([]);
    });

    it('applies the newer response when it arrives first', () => {
      service.loadUppStatus();
      service.loadUppStatus(true);

      const [older, newer] = httpMock.match(UPP_URL) as TestRequest[];
      newer.flush(ok([uppRow()]));
      older.flush(serverError);

      expect(service.uppState()).toBe('loaded');
      expect(service.uppList().length).toBe(1);
      expect(service.uppError()).toBeNull();
    });
  });

  describe('detail screen isolation', () => {
    it('a detail failure does not touch the list error, and a list failure does not touch the detail error', () => {
      service.loadUppStatus();
      httpMock.expectOne(UPP_URL).flush(serverError);
      const listError = service.uppError();

      service.getUppDetail('upp-1');
      httpMock.expectOne(DETAIL_URL).flush(null, { status: 500, statusText: 'Server Error' });

      expect(service.uppError()).toBe(listError);
      expect(service.detailError()).not.toBeNull();
      expect(service.loadingDetail()).toBe(false);
    });

    it('a null detail body ends the detail loading state and sets the detail error', () => {
      service.getUppDetail('upp-1');
      httpMock.expectOne(DETAIL_URL).flush(null);

      expect(service.loadingDetail()).toBe(false);
      expect(service.detailError()).not.toBeNull();
    });

    it('a new detail request ignores a stale detail response', () => {
      service.getUppDetail('upp-1');
      service.getUppDetail('upp-2');

      const [older, newer] = httpMock.match(DETAIL_URL) as TestRequest[];
      newer.flush({ error: false, operation: 'getone', message: '', data: [] });
      older.flush(serverError);

      expect(service.detailError()).toBeNull();
      expect(service.loadingDetail()).toBe(false);
    });
  });
});
