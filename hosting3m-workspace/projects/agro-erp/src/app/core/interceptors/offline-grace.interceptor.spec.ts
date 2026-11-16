import { TestBed } from '@angular/core/testing';
import { HttpClient, HttpErrorResponse, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { AUTH_ENV_CONFIG, AuthService } from 'core-auth';
import { offlineGraceGuard } from './offline-grace.interceptor';

const CRUD = 'https://api.example.test/crud/v6';
const TOKEN_URL = 'https://api.example.test/token';

describe('offlineGraceGuard', () => {
  let state: () => string;
  let http: HttpClient;
  let ctrl: HttpTestingController;
  let downstream: string[];

  beforeEach(() => {
    state = () => 'valid';
    downstream = [];
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { getSessionState: () => state() } },
        { provide: AUTH_ENV_CONFIG, useValue: { apiUrl_crud: CRUD, apiUrl_token: TOKEN_URL, apiUrl_ai: '', apiUrl_upload: '' } },
        provideHttpClient(withInterceptors([
          offlineGraceGuard,
          (req, next) => { downstream.push(req.url); return next(req); }
        ])),
        provideHttpClientTesting()
      ]
    });
    http = TestBed.inject(HttpClient);
    ctrl = TestBed.inject(HttpTestingController);
  });

  afterEach(() => ctrl.verify());

  function error(url: string, body: unknown = {}): Promise<HttpErrorResponse> {
    return new Promise((resolve, reject) =>
      http.post(url, body).subscribe({ next: () => reject(new Error('should fail')), error: e => resolve(e) }));
  }

  it('grace blocks API calls with status 0 and never calls next', async () => {
    state = () => 'grace';
    const e = await error(`${CRUD}/vw_cattle_kpi`);
    expect(e.status).toBe(0);
    expect(e.statusText).toBe('OfflineGrace');
    expect(downstream).toEqual([]);
    ctrl.expectNone(`${CRUD}/vw_cattle_kpi`);
  });

  it('grace lets the exempt login route through', () => {
    state = () => 'grace';
    http.post(TOKEN_URL, {}).subscribe();
    ctrl.expectOne(TOKEN_URL).flush({});
    expect(downstream).toEqual([TOKEN_URL]);
  });

  it('grace lets the public companys getall through', () => {
    state = () => 'grace';
    http.post(`${CRUD}/companys`, { operation: 'getall', table_name: 'companys' }).subscribe();
    ctrl.expectOne(`${CRUD}/companys`).flush({});
  });

  for (const s of ['valid', 'expired']) {
    it(`${s} passes through untouched`, () => {
      state = () => s;
      http.post(`${CRUD}/vw_cattle_kpi`, {}).subscribe();
      ctrl.expectOne(`${CRUD}/vw_cattle_kpi`).flush({});
      expect(downstream).toEqual([`${CRUD}/vw_cattle_kpi`]);
    });
  }

  it('non-API origins are untouched in grace', () => {
    state = () => 'grace';
    http.get('https://cdn.example.test/x.css').subscribe();
    ctrl.expectOne('https://cdn.example.test/x.css').flush('');
  });

  it('a throwing getSessionState passes through', () => {
    state = () => { throw new Error('boom'); };
    http.post(`${CRUD}/vw_cattle_kpi`, {}).subscribe();
    ctrl.expectOne(`${CRUD}/vw_cattle_kpi`).flush({});
  });
});
