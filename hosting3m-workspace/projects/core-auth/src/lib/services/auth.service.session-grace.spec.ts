import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { AuthService, SessionEvent } from './auth.service';
import { TenantService, TenantContext } from './tenant.service';
import { AUTH_ENV_CONFIG, AuthEnvironmentConfig } from '../auth.config';

const GRACE_MS = 16 * 60 * 60 * 1000;
const NOW_MS = Date.UTC(2026, 10, 15, 12, 0, 0);
const NOW_S = NOW_MS / 1000;

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function makeToken(claims: Record<string, unknown>): string {
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(claims)}.sig`;
}
const tenant = (id: number): TenantContext => ({
  id_company: id, company_name: 'Acme', role: 'ADMIN', industry: 'x', business_type: 'LIVESTOCK'
});
const baseClaims = { user: 'ana', name: 'Ana', role: 'ADMIN', id_company: 7 };

describe('AuthService session grace (additive, opt-in)', () => {
  const baseConfig: AuthEnvironmentConfig = {
    apiUrl_crud: 'https://n8n.example.com/webhook/crud/v6/CRUD',
    apiUrl_token: 'https://n8n.example.com/webhook/v3/genera-token',
    apiUrl_ai: 'https://n8n.example.com/webhook/ai',
    system_id: 'test_app'
  };

  function setup(
    config: AuthEnvironmentConfig,
    token?: string,
    activeId: number | null = 7,
    available: number[] = [7, 8, 9]
  ): AuthService {
    localStorage.clear();
    if (token) localStorage.setItem('authToken', token);
    if (activeId !== null) localStorage.setItem('active_tenant_context', JSON.stringify(tenant(activeId)));
    if (available.length) localStorage.setItem('user_tenants', JSON.stringify(available.map(tenant)));
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting(), { provide: AUTH_ENV_CONFIG, useValue: config }]
    });
    return TestBed.inject(AuthService);
  }
  const tokenExp = (exp: unknown) => makeToken({ ...baseClaims, exp });

  beforeEach(() => vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] }));
  afterEach(() => {
    vi.useRealTimers();
    localStorage.clear();
  });

  describe('with offlineGraceMs configured', () => {
    const cfg = { ...baseConfig, offlineGraceMs: GRACE_MS };

    it('is valid just before and at expiry', () => {
      expect(setup(cfg, tokenExp(NOW_S + 1)).getSessionState()).toBe('valid');
      expect(setup(cfg, tokenExp(NOW_S)).getSessionState()).toBe('valid');
    });

    it('is grace just after expiry', () => {
      expect(setup(cfg, tokenExp(NOW_S - 1)).getSessionState()).toBe('grace');
    });

    it('is grace just before and at the end of the window, expired just after', () => {
      expect(setup(cfg, tokenExp(NOW_S - GRACE_MS / 1000 + 1)).getSessionState()).toBe('grace');
      expect(setup(cfg, tokenExp(NOW_S - GRACE_MS / 1000)).getSessionState()).toBe('grace');
      expect(setup(cfg, tokenExp(NOW_S - GRACE_MS / 1000 - 1)).getSessionState()).toBe('expired');
    });

    it('never calls logout() nor clears storage in the grace path', () => {
      const service = setup(cfg, tokenExp(NOW_S - 60));
      const logout = vi.spyOn(service, 'logout');
      const tenantClear = vi.spyOn(TestBed.inject(TenantService), 'clearContext');
      expect(service.getSessionState()).toBe('grace');
      expect(service.getSessionScope()).toEqual({ user: 'ana', id_company: 7 });
      expect(logout).not.toHaveBeenCalled();
      expect(tenantClear).not.toHaveBeenCalled();
      expect(localStorage.getItem('authToken')).not.toBeNull();
      expect(localStorage.getItem('active_tenant_context')).not.toBeNull();
    });

    it('fails closed to expired on missing, non-numeric or malformed exp', () => {
      expect(setup(cfg, makeToken(baseClaims)).getSessionState()).toBe('expired');
      expect(setup(cfg, tokenExp('soon')).getSessionState()).toBe('expired');
      expect(setup(cfg, tokenExp(null)).getSessionState()).toBe('expired');
      expect(setup(cfg, tokenExp(Number.NaN)).getSessionState()).toBe('expired');
    });

    it('fails closed on missing or malformed token', () => {
      expect(setup(cfg).getSessionState()).toBe('expired');
      expect(setup(cfg, 'not-a-jwt').getSessionState()).toBe('expired');
    });

    it('fails closed when user is missing or the JWT id_company is malformed', () => {
      const exp = NOW_S + 100;
      expect(setup(cfg, makeToken({ ...baseClaims, user: undefined, exp })).getSessionState()).toBe('expired');
      expect(setup(cfg, makeToken({ ...baseClaims, id_company: undefined, exp })).getSessionState()).toBe('expired');
      expect(setup(cfg, makeToken({ ...baseClaims, id_company: 0, exp })).getSessionState()).toBe('expired');
      expect(setup(cfg, makeToken({ ...baseClaims, id_company: '7', exp })).getSessionState()).toBe('expired');
      expect(setup(cfg, makeToken({ ...baseClaims, id_company: 1.5, exp })).getSessionState()).toBe('expired');
    });

    it('fails closed when the active tenant is missing', () => {
      const exp = NOW_S + 100;
      const missing = setup(cfg, tokenExp(exp), null);
      expect(missing.getSessionState()).toBe('expired');
      expect(missing.getSessionScope()).toBeNull();
    });

    it('fails closed when the active tenant is not in availableTenants', () => {
      const s = setup(cfg, tokenExp(NOW_S + 100), 5, [7, 8, 9]);
      expect(s.getSessionState()).toBe('expired');
      expect(s.getSessionScope()).toBeNull();
      const g = setup(cfg, tokenExp(NOW_S - 60), 5, [7, 8, 9]);
      expect(g.getSessionState()).toBe('expired');
      expect(g.getSessionScope()).toBeNull();
    });

    it('fails closed when availableTenants is empty', () => {
      const s = setup(cfg, tokenExp(NOW_S + 100), 7, []);
      expect(s.getSessionState()).toBe('expired');
      expect(s.getSessionScope()).toBeNull();
    });

    it('stays valid after switching to another available tenant and the scope follows it', () => {
      const s = setup(cfg, tokenExp(NOW_S + 100), 7); // JWT company is 7
      expect(s.getSessionScope()).toEqual({ user: 'ana', id_company: 7 });
      TestBed.inject(TenantService).setActiveTenant(tenant(8));
      expect(s.getSessionState()).toBe('valid');
      expect(s.getSessionScope()).toEqual({ user: 'ana', id_company: 8 });
    });

    it('keeps grace after a tenant switch, scoped to the new tenant, and fails closed on an unknown one', () => {
      const s = setup(cfg, tokenExp(NOW_S - 60), 7);
      const tenants = TestBed.inject(TenantService);
      tenants.setActiveTenant(tenant(9));
      expect(s.getSessionState()).toBe('grace');
      expect(s.getSessionScope()).toEqual({ user: 'ana', id_company: 9 });
      tenants.setActiveTenant(tenant(99));
      expect(s.getSessionState()).toBe('expired');
      expect(s.getSessionScope()).toBeNull();
    });
  });

  describe('with offlineGraceMs unset (legacy behavior)', () => {
    it('never reports grace', () => {
      expect(setup(baseConfig, tokenExp(NOW_S - 1)).getSessionState()).toBe('expired');
    });

    it('treats 0, negative, NaN and non-number values as no grace', () => {
      for (const bad of [0, -1, Number.NaN, Infinity, '57600000' as unknown as number]) {
        const s = setup({ ...baseConfig, offlineGraceMs: bad }, tokenExp(NOW_S - 1));
        expect(s.getSessionState()).toBe('expired');
      }
    });

    it('getStoredToken() still logs out and returns null on an expired token', () => {
      const service = setup(baseConfig, tokenExp(NOW_S - 1));
      const logout = vi.spyOn(service, 'logout');
      expect(service.getStoredToken()).toBeNull();
      expect(logout).toHaveBeenCalledTimes(1);
      expect(localStorage.getItem('authToken')).toBeNull();
    });
  });

  describe('existing methods keep their semantics even when grace is configured', () => {
    const cfg = { ...baseConfig, offlineGraceMs: GRACE_MS };

    it('getStoredToken() still logs out an expired token inside the grace window', () => {
      const service = setup(cfg, tokenExp(NOW_S - 60));
      const logout = vi.spyOn(service, 'logout');
      expect(service.getStoredToken()).toBeNull();
      expect(logout).toHaveBeenCalledTimes(1);
      expect(localStorage.getItem('authToken')).toBeNull();
    });

    it('isAuthenticated and currentUser stay false/null for an expired token inside grace', () => {
      const service = setup(cfg, tokenExp(NOW_S - 60));
      expect(service.isAuthenticated()).toBe(false);
      expect(service.currentUser()).toBeNull();
    });
  });

  describe('change streams', () => {
    const cfg = { ...baseConfig, offlineGraceMs: GRACE_MS };

    it('emits login with scope and no token, then logout', () => {
      const service = setup(cfg, undefined, 7);
      const http = TestBed.inject(HttpTestingController);
      const events: SessionEvent[] = [];
      service.sessionEvents$.subscribe(e => events.push(e));

      service.login({ user: 'ana', pass: 'x' }).subscribe();
      const token = tokenExp(NOW_S + 3600);
      http.expectOne(baseConfig.apiUrl_token).flush({ status: 'success', data: { token } });
      service.logout();

      expect(events).toEqual([
        { type: 'login', scope: { user: 'ana', id_company: 7 } },
        { type: 'logout' }
      ]);
      expect(JSON.stringify(events)).not.toContain(token);
    });

    it('emits null scope on login when no available active tenant is set (fail-closed)', () => {
      const service = setup(cfg, undefined, null, []);
      const http = TestBed.inject(HttpTestingController);
      const events: SessionEvent[] = [];
      service.sessionEvents$.subscribe(e => events.push(e));
      service.login({ user: 'ana', pass: 'x' }).subscribe();
      http.expectOne(baseConfig.apiUrl_token).flush({ status: 'success', data: { token: tokenExp(NOW_S + 60) } });
      expect(events).toEqual([{ type: 'login', scope: null }]);
    });

    it('TenantService emits the new id_company on switch and null on clear', () => {
      setup(cfg, undefined, null);
      const tenants = TestBed.inject(TenantService);
      const seen: (number | null)[] = [];
      tenants.activeTenantChanges$.subscribe(v => seen.push(v));
      tenants.setActiveTenant(tenant(7));
      tenants.setActiveTenant(tenant(9));
      tenants.clearContext();
      expect(seen).toEqual([7, 9, null]);
    });
  });
});
