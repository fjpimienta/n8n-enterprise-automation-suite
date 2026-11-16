import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { AUTH_ENV_CONFIG, TenantContext } from 'core-auth';
import { AdminService } from './admin.service';

const NOW_MS = Date.UTC(2026, 10, 15, 12, 0, 0);
const NOW_S = NOW_MS / 1000;
const tenant: TenantContext = {
  id_company: 7, company_name: 'Acme', role: 'ADMIN', industry: 'Ganadería', business_type: 'LIVESTOCK',
};

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
const tokenWithExp = (exp: number) =>
  `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ user: 'ana', role: 'ADMIN', id_company: 7, exp })}.sig`;

describe('AdminService.loadCompanies in grace', () => {
  let ctrl: HttpTestingController;
  let service: AdminService;

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] });
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    localStorage.clear();
    localStorage.setItem('user_tenants', JSON.stringify([tenant]));
    localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: AUTH_ENV_CONFIG,
          useValue: {
            apiUrl_crud: 'https://api.example.test/crud/v6', apiUrl_token: 'https://api.example.test/token',
            apiUrl_ai: '', system_id: 'agro_erp', offlineGraceMs: 16 * 3600 * 1000,
          },
        },
      ],
    });
    ctrl = TestBed.inject(HttpTestingController);
    service = TestBed.inject(AdminService);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it('does not fire the exempt companys request while the token is expired inside grace', () => {
    localStorage.setItem('authToken', tokenWithExp(NOW_S - 60));
    service.loadCompanies();
    expect(ctrl.match(() => true)).toHaveLength(0);
  });

  it('still fires it with a valid session (unchanged behavior)', () => {
    localStorage.setItem('authToken', tokenWithExp(NOW_S + 3600));
    service.loadCompanies();
    const reqs = ctrl.match(() => true);
    expect(reqs).toHaveLength(1);
    reqs[0].flush({ data: [] });
  });
});
