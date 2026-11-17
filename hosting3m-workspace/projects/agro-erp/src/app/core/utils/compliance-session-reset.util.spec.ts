import { HttpRequest, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Injectable, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { AUTH_ENV_CONFIG, AuthService, TenantService, tenantInterceptor } from 'core-auth';
import { Subject } from 'rxjs';
import { environment } from '@env/environment';
import { ComplianceService } from '@features/compliance/services/compliance.service';
import { wireComplianceSessionReset } from './compliance-session-reset.util';

const UPP_URL = `${environment.apiUrl_crud}/upp_compliance_status`;
const PSG_URL = `${environment.apiUrl_crud}/psg_compliance_status`;

const ok = (data: unknown[]) => ({ error: false, operation: 'getall', message: '', data });
const uppRow = (ranch_name: string) => ({
  production_unit_id: `upp-${ranch_name}`,
  ranch_name,
  update_status: 'EXPIRED',
  days_since_update: 400
});

/** Matches a request to `url` that the tenant interceptor stamped with tenant `id`. */
const forTenant = (url: string, id: number) => (req: HttpRequest<unknown>) =>
  req.url === url && req.headers.get('X-Tenant-ID') === String(id);

/** Mirrors the real order in TenantService.setActiveTenant(): the signal is set before the emission. */
@Injectable()
class FakeTenantService {
  readonly activeTenantId = signal<number | null>(null);
  readonly activeTenantChanges$ = new Subject<number | null>();

  setActiveTenant(id: number): void {
    this.activeTenantId.set(id);
    this.activeTenantChanges$.next(id);
  }

  clearContext(): void {
    this.activeTenantId.set(null);
    this.activeTenantChanges$.next(null);
  }
}

@Injectable()
class FakeAuthService {
  readonly sessionEvents$ = new Subject<{ type: string }>();
}

describe('wireComplianceSessionReset (#1109)', () => {
  let tenant: FakeTenantService;
  let auth: FakeAuthService;
  let compliance: ComplianceService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        // The real tenant interceptor runs, so the X-Tenant-ID header asserted below is the one the server gets.
        provideHttpClient(withInterceptors([tenantInterceptor])),
        provideHttpClientTesting(),
        { provide: TenantService, useClass: FakeTenantService },
        { provide: AuthService, useClass: FakeAuthService },
        {
          provide: AUTH_ENV_CONFIG,
          useValue: {
            apiUrl_crud: environment.apiUrl_crud,
            apiUrl_token: environment.apiUrl_token,
            apiUrl_ai: environment.apiUrl_ai,
            apiUrl_upload: environment.apiUrl_upload
          }
        }
      ]
    });
    tenant = TestBed.inject(TenantService) as unknown as FakeTenantService;
    auth = TestBed.inject(AuthService) as unknown as FakeAuthService;
    compliance = TestBed.inject(ComplianceService);
    httpMock = TestBed.inject(HttpTestingController);
    TestBed.runInInjectionContext(() => wireComplianceSessionReset());
  });

  afterEach(() => httpMock.verify());

  it('clears all compliance state on logout and does not reload', () => {
    tenant.setActiveTenant(1);
    httpMock.expectOne(forTenant(UPP_URL, 1)).flush(ok([uppRow('A')]));
    httpMock.expectOne(forTenant(PSG_URL, 1)).flush(ok([]));
    expect(compliance.uppList().length).toBe(1);

    auth.sessionEvents$.next({ type: 'logout' });

    expect(compliance.uppList()).toEqual([]);
    expect(compliance.uppState()).toBe('idle');
    httpMock.expectNone(UPP_URL);
    httpMock.expectNone(PSG_URL);
  });

  it('does not reset on login events', () => {
    tenant.setActiveTenant(1);
    httpMock.expectOne(forTenant(UPP_URL, 1)).flush(ok([uppRow('A')]));
    httpMock.expectOne(forTenant(PSG_URL, 1)).flush(ok([]));

    auth.sessionEvents$.next({ type: 'login' });

    expect(compliance.uppList().length).toBe(1);
  });

  it('clears synchronously on a tenant change and reloads both sources for the new tenant', () => {
    tenant.setActiveTenant(1);
    httpMock.expectOne(forTenant(UPP_URL, 1)).flush(ok([uppRow('A')]));
    httpMock.expectOne(forTenant(PSG_URL, 1)).flush(ok([]));

    tenant.setActiveTenant(2);

    // Nothing from A is visible after the switch, before B's responses arrive.
    expect(compliance.uppList()).toEqual([]);
    expect(compliance.uppState()).toBe('loading');
    expect(compliance.psgState()).toBe('loading');
    const upp = httpMock.expectOne(forTenant(UPP_URL, 2));
    const psg = httpMock.expectOne(forTenant(PSG_URL, 2));
    upp.flush(ok([uppRow('B')]));
    psg.flush(ok([]));
    expect(compliance.uppList().map(row => row.ranch_name)).toEqual(['B']);
  });

  it('a request started under A carries A, and its late response is discarded after the switch to B', () => {
    tenant.setActiveTenant(1);
    const upA = httpMock.expectOne(forTenant(UPP_URL, 1));
    const psgA = httpMock.expectOne(forTenant(PSG_URL, 1));

    tenant.setActiveTenant(2);
    const upB = httpMock.expectOne(forTenant(UPP_URL, 2));
    httpMock.expectOne(forTenant(PSG_URL, 2)).flush(ok([]));

    upA.flush(ok([uppRow('A')]));
    expect(compliance.uppList()).toEqual([]);

    upB.flush(ok([uppRow('B')]));
    expect(compliance.uppList().map(row => row.ranch_name)).toEqual(['B']);

    psgA.flush(ok([{ psg_license_id: 'psg-A', validity_status: 'EXPIRED' }]));
    expect(compliance.psgList()).toEqual([]);
  });

  it('A to B to A quickly: each request carries its own tenant, and only the last A response applies', () => {
    tenant.setActiveTenant(1);
    tenant.setActiveTenant(2);
    tenant.setActiveTenant(1);

    const pending = httpMock.match(UPP_URL);
    expect(pending.map(req => req.request.headers.get('X-Tenant-ID'))).toEqual(['1', '2', '1']);

    pending[0].flush(ok([uppRow('A-viejo')]));
    pending[1].flush(ok([uppRow('B')]));
    expect(compliance.uppList()).toEqual([]);

    pending[2].flush(ok([uppRow('A-actual')]));
    expect(compliance.uppList().map(row => row.ranch_name)).toEqual(['A-actual']);

    httpMock.match(PSG_URL).forEach(req => req.flush(ok([])));
  });

  it('a null tenant emission resets the state and does not reload', () => {
    tenant.setActiveTenant(1);
    httpMock.expectOne(forTenant(UPP_URL, 1)).flush(ok([uppRow('A')]));
    httpMock.expectOne(forTenant(PSG_URL, 1)).flush(ok([]));
    expect(compliance.uppList().length).toBe(1);

    tenant.clearContext();

    expect(compliance.uppList()).toEqual([]);
    expect(compliance.uppState()).toBe('idle');
    httpMock.expectNone(UPP_URL);
    httpMock.expectNone(PSG_URL);
  });
});
