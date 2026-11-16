import { TestBed } from '@angular/core/testing';
import { HttpClient, HttpErrorResponse, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router, provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG, AuthEnvironmentConfig, AuthService } from 'core-auth';
import { graceAuthInterceptor } from './grace-auth.interceptor';

/**
 * Production configuration (no `offlineGraceMs`): `graceAuthInterceptor` must be a pure pass-through to
 * core-auth's `authInterceptor` for `'valid'` and `'expired'` sessions (#1087 phase 1b-iii-b audit).
 */
const NOW_MS = Date.UTC(2026, 10, 15, 12, 0, 0);
const NOW_S = NOW_MS / 1000;
const API = 'https://api.example.test/crud/v6';

const config: AuthEnvironmentConfig = {
  apiUrl_crud: API,
  apiUrl_token: 'https://api.example.test/token',
  apiUrl_ai: 'https://api.example.test/ai',
  apiUrl_upload: '',
  system_id: 'agro_erp',
};

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function tokenWithExp(exp: number): string {
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ user: 'ana', name: 'Ana', role: 'ADMIN', id_company: 7, exp })}.sig`;
}

describe('graceAuthInterceptor without offlineGraceMs (production)', () => {
  let http: HttpClient;
  let ctrl: HttpTestingController;
  let logout: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.useFakeTimers({ now: NOW_MS, toFake: ['Date'] });
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    localStorage.clear();
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
    logout = vi.spyOn(TestBed.inject(AuthService), 'logout');
    TestBed.inject(Router);
  });

  afterEach(() => {
    ctrl.verify();
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it("'valid': the API request carries the Bearer token exactly as core-auth's authInterceptor does", () => {
    const token = tokenWithExp(NOW_S + 3600);
    localStorage.setItem('authToken', token);
    http.post(`${API}/hotel_rooms`, { entity: 'hotel_rooms' }).subscribe();
    const req = ctrl.expectOne(`${API}/hotel_rooms`);
    expect(req.request.headers.get('Authorization')).toBe(`Bearer ${token}`);
    expect(logout).not.toHaveBeenCalled();
    req.flush({});
  });

  it("'valid': a 401 response is passed through unchanged, with no logout", () => {
    localStorage.setItem('authToken', tokenWithExp(NOW_S + 3600));
    let error: unknown = null;
    http.post(`${API}/x`, {}).subscribe({ error: (e: unknown) => { error = e; } });
    ctrl.expectOne(`${API}/x`).flush('nope', { status: 401, statusText: 'Unauthorized' });
    expect(error).toBeInstanceOf(HttpErrorResponse);
    expect((error as HttpErrorResponse).status).toBe(401);
    expect(logout).not.toHaveBeenCalled();
  });

  it("'expired': core-auth's behavior is kept: the token is not sent, logout runs and the call fails with 401", () => {
    localStorage.setItem('authToken', tokenWithExp(NOW_S - 60));
    let error: HttpErrorResponse | null = null;
    http.post(`${API}/hotel_rooms`, {}).subscribe({ error: (e: HttpErrorResponse) => { error = e; } });
    ctrl.expectNone(`${API}/hotel_rooms`);
    expect(logout).toHaveBeenCalledTimes(1);
    expect(error).toEqual(expect.objectContaining({ status: 401, statusText: 'No auth token' }));
  });
});
