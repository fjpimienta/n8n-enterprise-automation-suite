import { TestBed } from '@angular/core/testing';
import { HttpClient, HttpErrorResponse, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router, provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG, AuthEnvironmentConfig, AuthService, TenantContext, TenantService } from 'core-auth';
import { graceAuthInterceptor } from './grace-auth.interceptor';

const GRACE_MS = 16 * 60 * 60 * 1000;
const NOW_MS = Date.UTC(2026, 10, 15, 12, 0, 0);
const NOW_S = NOW_MS / 1000;
const API = 'https://api.example.test/crud/v6';
const TOKEN_URL = 'https://api.example.test/token';
const EXTERNAL = 'https://cdn.example.test/data.json';

const config: AuthEnvironmentConfig = {
  apiUrl_crud: API,
  apiUrl_token: TOKEN_URL,
  apiUrl_ai: 'https://api.example.test/ai',
  apiUrl_upload: '',
  system_id: 'agro_erp',
  offlineGraceMs: GRACE_MS,
};

const tenant: TenantContext = {
  id_company: 7, company_name: 'Acme', role: 'ADMIN', industry: 'Ganadería', business_type: 'LIVESTOCK',
};

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function tokenWithExp(exp: number): string {
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ user: 'ana', name: 'Ana', role: 'ADMIN', id_company: 7, exp })}.sig`;
}

describe('graceAuthInterceptor', () => {
  let http: HttpClient;
  let ctrl: HttpTestingController;
  let auth: AuthService;
  let logout: ReturnType<typeof vi.spyOn>;

  /** Sets the stored token: `'valid'`, `'grace'` (expired inside the window), or `'expired'` (past it). */
  function setSession(kind: 'valid' | 'grace' | 'expired'): void {
    const exp = kind === 'valid' ? NOW_S + 3600
      : kind === 'grace' ? NOW_S - 60
        : NOW_S - GRACE_MS / 1000 - 3600;
    localStorage.setItem('authToken', tokenWithExp(exp));
  }

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] });
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    localStorage.clear();
    localStorage.setItem('user_tenants', JSON.stringify([tenant]));
    localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([{ path: 'login', children: [] }]),
        provideHttpClient(withInterceptors([graceAuthInterceptor])),
        provideHttpClientTesting(),
        { provide: AUTH_ENV_CONFIG, useValue: config },
      ],
    });
    http = TestBed.inject(HttpClient);
    ctrl = TestBed.inject(HttpTestingController);
    auth = TestBed.inject(AuthService);
    TestBed.inject(TenantService);
    TestBed.inject(Router);
    logout = vi.spyOn(auth, 'logout');
  });

  afterEach(() => {
    ctrl.verify();
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  function errorOf(obs: { subscribe: (o: { next: () => void; error: (e: HttpErrorResponse) => void }) => unknown }) {
    return new Promise<HttpErrorResponse>((resolve, reject) => {
      obs.subscribe({ next: () => reject(new Error('should fail')), error: e => resolve(e) });
    });
  }

  describe('valid session', () => {
    it('attaches the Bearer token to API requests, as before', () => {
      setSession('valid');
      http.get(`${API}/vw_cattle_kpi`).subscribe();
      const req = ctrl.expectOne(`${API}/vw_cattle_kpi`);
      expect(req.request.headers.get('Authorization')).toBe(`Bearer ${localStorage.getItem('authToken')}`);
      req.flush({});
    });

    it('keeps a 401 that arrives while still valid: no logout, status unchanged', async () => {
      setSession('valid');
      http.get(`${API}/vw_cattle_kpi`).subscribe({ error: () => undefined });
      const req = ctrl.expectOne(`${API}/vw_cattle_kpi`);
      req.flush({}, { status: 401, statusText: 'Unauthorized' });
      expect(logout).not.toHaveBeenCalled();
    });
  });

  describe('grace session', () => {
    beforeEach(() => setSession('grace'));

    it('lets the exempt login POST through without calling authInterceptor, so it never logs out', () => {
      http.post(TOKEN_URL, { user: 'ana', pass: 'x' }).subscribe();
      const req = ctrl.expectOne(TOKEN_URL);
      expect(req.request.headers.has('Authorization')).toBe(false);
      req.flush({});
      expect(logout).not.toHaveBeenCalled();
      expect(localStorage.getItem('authToken')).not.toBeNull();
    });

    it('never sends the expired token on the exempt public companys getall (manual header stripped)', () => {
      const expired = localStorage.getItem('authToken');
      http.post(`${API}/companys`, { operation: 'getall', table_name: 'companys' }, {
        headers: { Authorization: `Bearer ${expired}` },
      }).subscribe();
      const req = ctrl.expectOne(`${API}/companys`);
      expect(req.request.headers.has('Authorization')).toBe(false);
      req.flush({});
      expect(logout).not.toHaveBeenCalled();
    });

    it('blocks a non-exempt API request with status 0 and never sends it', async () => {
      const err = await errorOf(http.get(`${API}/vw_cattle_kpi`));
      expect(err.status).toBe(0);
      expect(err.statusText).toBe('OfflineGrace');
      ctrl.expectNone(`${API}/vw_cattle_kpi`);
      expect(logout).not.toHaveBeenCalled();
    });

    it('strips any Authorization header from non-API requests and does not log out', () => {
      http.get(EXTERNAL, { headers: { Authorization: 'Bearer stale' } }).subscribe();
      const req = ctrl.expectOne(EXTERNAL);
      expect(req.request.headers.has('Authorization')).toBe(false);
      req.flush({});
      expect(logout).not.toHaveBeenCalled();
    });

    it('in-flight race: a request sent while valid whose 401 arrives in grace becomes status 0 and does not log out', async () => {
      setSession('valid');
      const pending = errorOf(http.get(`${API}/vw_cattle_kpi`));
      const req = ctrl.expectOne(`${API}/vw_cattle_kpi`);
      // The token expires while the request is in flight.
      setSession('grace');
      req.flush({}, { status: 401, statusText: 'Unauthorized' });
      const err = await pending;
      expect(err.status).toBe(0);
      expect(err.statusText).toBe('OfflineGrace');
      expect(logout).not.toHaveBeenCalled();
      expect(localStorage.getItem('authToken')).not.toBeNull();
    });
  });

  describe('expired session (beyond the grace window)', () => {
    it('still logs out on an expired token, unchanged from core-auth', async () => {
      setSession('expired');
      const err = await errorOf(http.get(`${API}/vw_cattle_kpi`));
      expect(err.status).toBe(401);
      expect(logout).toHaveBeenCalled();
    });
  });
});
