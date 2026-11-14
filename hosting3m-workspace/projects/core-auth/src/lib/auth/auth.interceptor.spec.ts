import { TestBed } from '@angular/core/testing';
import { HttpClient, HttpErrorResponse, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router } from '@angular/router';

import { authInterceptor } from './auth.interceptor';
import { AuthService } from '../services/auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

/** Body sent by the dashboard and agro-erp services for the public `companys getall` read. */
const COMPANYS_GETALL_BODY = {
  entity: 'companys',
  table_name: 'companys',
  operation: 'getall',
  action: 'list',
  filters: {}
};

describe('authInterceptor', () => {
  const config = {
    apiUrl_crud: 'https://n8n.example.com/webhook/abc/crud/v6',
    apiUrl_token: 'https://n8n.example.com/webhook/v3/genera-token',
    apiUrl_ai: 'https://ai.example.com',
    apiUrl_upload: 'https://files.example.com:3001/upload',
    system_id: 'test'
  };
  let token: string | null;
  let http: HttpClient;
  let ctrl: HttpTestingController;

  beforeEach(() => {
    token = 'jwt-token';
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: AUTH_ENV_CONFIG, useValue: config },
        { provide: AuthService, useValue: { getStoredToken: () => token, logout: () => undefined } },
        { provide: Router, useValue: { navigate: () => undefined } }
      ]
    });
    http = TestBed.inject(HttpClient);
    ctrl = TestBed.inject(HttpTestingController);
  });

  /** Sends a POST and flushes it if it reaches the backend. Returns the Authorization header seen by the backend, or null. */
  function authHeaderFor(url: string, body: unknown = {}): string | null {
    http.post(url, body).subscribe({ error: () => undefined });
    const req = ctrl.expectOne(url);
    const header = req.request.headers.get('Authorization');
    req.flush({});
    return header;
  }

  /**
   * Sends a request and returns the error raised by the interceptor, or null when the request
   * reached the backend (in which case it is flushed so the call completes).
   */
  function rejectionFor(url: string, body: unknown = {}, method: 'post' | 'get' = 'post'): HttpErrorResponse | null {
    const state: { error: HttpErrorResponse | null } = { error: null };
    const request = method === 'post' ? http.post(url, body) : http.get(url);
    request.subscribe({ error: (err: HttpErrorResponse) => { state.error = err; } });
    ctrl.match(url).forEach((req) => req.flush({}));
    return state.error;
  }

  describe('with a JWT', () => {
    it('sends the JWT to each configured origin', () => {
      expect(authHeaderFor(config.apiUrl_crud + '/hotel_rooms')).toBe('Bearer jwt-token');
      expect(authHeaderFor(config.apiUrl_ai)).toBe('Bearer jwt-token');
      expect(authHeaderFor(config.apiUrl_upload + '/x')).toBe('Bearer jwt-token');
      expect(authHeaderFor(config.apiUrl_token + '/other')).toBe('Bearer jwt-token');
    });

    it('keeps the JWT on companys operations other than getall', () => {
      const url = config.apiUrl_crud + '/companys';
      expect(authHeaderFor(url, { ...COMPANYS_GETALL_BODY, operation: 'getone' })).toBe('Bearer jwt-token');
    });
  });

  describe('origin matching', () => {
    it('does not send the JWT to a look-alike host sharing the allowed host as prefix', () => {
      expect(authHeaderFor('https://n8n.example.com.evil.example/webhook/abc/crud/v6/x')).toBeNull();
    });

    it('does not send the JWT to a prefix look-alike of a base URL without path', () => {
      expect(authHeaderFor('https://ai.example.com.evil.example/x')).toBeNull();
    });

    it('does not send the JWT to the same host on another port or scheme', () => {
      expect(authHeaderFor('https://n8n.example.com:8443/webhook/abc/crud/v6/x')).toBeNull();
      expect(authHeaderFor('http://n8n.example.com/webhook/abc/crud/v6/x')).toBeNull();
    });

    it('does not send the JWT to a userinfo-spoofed URL', () => {
      expect(authHeaderFor('https://n8n.example.com@evil.example/x')).toBeNull();
    });

    it('does not send the JWT to a foreign origin', () => {
      expect(authHeaderFor('https://cdn.other.example/lib.js')).toBeNull();
    });

    it('does not send the JWT on relative or unparseable URLs', () => {
      expect(authHeaderFor('/api/x')).toBeNull();
      expect(authHeaderFor('not a url')).toBeNull();
    });
  });

  describe('without a JWT', () => {
    beforeEach(() => {
      token = null;
    });

    it('rejects protected requests with 401', () => {
      expect(rejectionFor(config.apiUrl_crud + '/x', {})).toEqual(
        expect.objectContaining({ status: 401, statusText: 'No auth token' })
      );
    });

    it('rejects protected CRUD requests on the origin shared with apiUrl_token', () => {
      const error = rejectionFor(config.apiUrl_crud + '/hotel_rooms', { entity: 'hotel_rooms', operation: 'getall' });
      expect(error?.status).toBe(401);
    });

    it('rejects other paths on the apiUrl_token origin', () => {
      expect(rejectionFor(config.apiUrl_token + '/other', {})?.status).toBe(401);
      expect(rejectionFor('https://n8n.example.com/webhook/v3/other', {})?.status).toBe(401);
    });

    it('rejects a GET to the token endpoint, which is exempt only as a POST', () => {
      expect(rejectionFor(config.apiUrl_token, undefined, 'get')?.status).toBe(401);
    });

    it('allows the token endpoint (login) without a JWT and attaches no Authorization header', () => {
      expect(rejectionFor(config.apiUrl_token, { user: 'u', pass: 'p' })).toBeNull();
      expect(authHeaderFor(config.apiUrl_token, { user: 'u', pass: 'p' })).toBeNull();
    });

    it('allows the public companys getall read without a JWT', () => {
      expect(authHeaderFor(config.apiUrl_crud + '/companys', COMPANYS_GETALL_BODY)).toBeNull();
    });

    it('rejects companys operations other than getall, even with the companys identifiers', () => {
      const url = config.apiUrl_crud + '/companys';
      for (const operation of ['getone', 'insert', 'update', 'delete']) {
        expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, operation })?.status).toBe(401);
      }
    });

    it('rejects a companys request whose entity or table_name is another table', () => {
      const url = config.apiUrl_crud + '/companys';
      expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, entity: 'users' })?.status).toBe(401);
      expect(rejectionFor(url, { ...COMPANYS_GETALL_BODY, table_name: 'users' })?.status).toBe(401);
    });

    it('rejects companys getall without identifying companys fields', () => {
      const url = config.apiUrl_crud + '/companys';
      expect(rejectionFor(url, { operation: 'getall' })?.status).toBe(401);
      expect(rejectionFor(url, undefined)?.status).toBe(401);
    });

    it('rejects a companys getall on a path that is not the companys collection endpoint', () => {
      expect(rejectionFor(config.apiUrl_crud + '/companys/getall', COMPANYS_GETALL_BODY)?.status).toBe(401);
      expect(rejectionFor(config.apiUrl_crud + '/companys_archive', COMPANYS_GETALL_BODY)?.status).toBe(401);
      expect(rejectionFor(config.apiUrl_crud + '/x/companys', COMPANYS_GETALL_BODY)?.status).toBe(401);
    });
  });
});
