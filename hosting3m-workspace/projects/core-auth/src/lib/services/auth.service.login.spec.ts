import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { AuthService } from './auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

describe('AuthService.login (HTTP 200 with error: true, #1037)', () => {
  const config = {
    apiUrl_crud: 'https://n8n.example.com/webhook/crud/v6/CRUD',
    apiUrl_token: 'https://n8n.example.com/webhook/v3/genera-token',
    apiUrl_ai: 'https://n8n.example.com/webhook/ai',
    system_id: 'test_app'
  };
  let service: AuthService;
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AUTH_ENV_CONFIG, useValue: config }
      ]
    });
    service = TestBed.inject(AuthService);
    http = TestBed.inject(HttpTestingController);
  });

  it('maps HTTP 200 with error:true to an error and stores no token', () => {
    let error: any;
    let emitted = false;
    service.login({ user: 'a', pass: 'b' }).subscribe({ next: () => (emitted = true), error: e => (error = e) });
    http.expectOne(config.apiUrl_token).flush({ error: true, message: 'Credenciales inválidas' });

    expect(emitted).toBe(false);
    expect(error).toBeTruthy();
    expect(error.message).toBe('Credenciales inválidas');
    expect(localStorage.getItem('authToken')).toBeNull();
    expect(service.isAuthenticated()).toBe(false);
  });

  it('uses a fallback message when error:true carries no message', () => {
    let error: any;
    service.login({ user: 'a', pass: 'b' }).subscribe({ error: e => (error = e) });
    http.expectOne(config.apiUrl_token).flush({ error: true });
    expect(error.message).toBe('El servidor rechazó la solicitud.');
  });

  it('still passes a select_company response through unchanged', () => {
    let res: any;
    service.login({ user: 'a', pass: 'b' }).subscribe(r => (res = r));
    http.expectOne(config.apiUrl_token).flush({ data: { status: 'select_company', companies: [{ id_company: 1 }] } });
    expect(res.status).toBe('select_company');
  });

  it('does not treat error:false as an error', () => {
    let res: any;
    let error: any;
    service.login({ user: 'a', pass: 'b' }).subscribe({ next: r => (res = r), error: e => (error = e) });
    http.expectOne(config.apiUrl_token).flush({ error: false, data: { status: 'select_company', companies: [] } });
    expect(error).toBeUndefined();
    expect(res.status).toBe('select_company');
  });
});
