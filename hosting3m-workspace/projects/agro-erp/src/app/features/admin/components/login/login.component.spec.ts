import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG } from 'core-auth';

import { LoginComponent } from './login.component';

// --- PARCHE MANUAL PARA VITEST/JSDOM ---
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: any) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});
// ---------------------------------------

describe('LoginComponent', () => {
  let component: LoginComponent;
  let fixture: ComponentFixture<LoginComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [LoginComponent],
      providers: [
        provideHttpClient(),
        provideRouter([]),
        {
          provide: AUTH_ENV_CONFIG,
          useValue: {
            apiUrl_crud: 'https://example.invalid',
            apiUrl_token: 'https://example.invalid',
            apiUrl_ai: 'https://example.invalid',
            apiUrl_upload: 'https://example.invalid',
            system_id: 'agro-erp'
          }
        }
      ]
    })
    .compileComponents();

    fixture = TestBed.createComponent(LoginComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
