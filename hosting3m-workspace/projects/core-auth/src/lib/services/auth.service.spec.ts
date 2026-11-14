import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { AuthService } from './auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config';

describe('Auth', () => {
  let service: AuthService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: AUTH_ENV_CONFIG,
          useValue: {
            apiUrl_crud: 'https://n8n.example.com/webhook/crud/v6/CRUD',
            apiUrl_token: 'https://n8n.example.com/webhook/v3/genera-token',
            apiUrl_ai: 'https://n8n.example.com/webhook/ai',
            system_id: 'test_app'
          }
        }
      ]
    });
    service = TestBed.inject(AuthService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
