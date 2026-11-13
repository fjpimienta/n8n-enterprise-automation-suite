import { TestBed } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router } from '@angular/router';

import { authInterceptor } from './auth.interceptor';
import { AuthService } from '../services/auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

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

  function authHeaderFor(url: string): string | null {
    http.post(url, {}).subscribe({ error: () => undefined });
    const req = ctrl.expectOne(url);
    const header = req.request.headers.get('Authorization');
    req.flush({});
    return header;
  }

  it('sends the JWT to each configured origin', () => {
    expect(authHeaderFor(config.apiUrl_crud + '/hotel_rooms')).toBe('Bearer jwt-token');
    expect(authHeaderFor(config.apiUrl_ai)).toBe('Bearer jwt-token');
    expect(authHeaderFor(config.apiUrl_upload + '/x')).toBe('Bearer jwt-token');
    expect(authHeaderFor(config.apiUrl_token)).toBe('Bearer jwt-token');
  });

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

  it('sends no Authorization header when there is no token', () => {
    token = null;
    expect(authHeaderFor(config.apiUrl_crud + '/x')).toBeNull();
  });
});
