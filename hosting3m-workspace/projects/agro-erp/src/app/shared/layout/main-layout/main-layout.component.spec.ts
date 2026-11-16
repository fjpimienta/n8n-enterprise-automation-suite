import 'fake-indexeddb/auto';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG, TenantContext } from 'core-auth';
import { AiService, CHAT_CONFIG_TOKEN } from 'ui-chat';
import { offlineGraceGuard } from '@core/interceptors/offline-grace.interceptor';
import { graceAuthInterceptor } from '@core/interceptors/grace-auth.interceptor';
import { tenantInterceptor } from 'core-auth';
import { MainLayoutComponent } from './main-layout.component';

/**
 * Render smoke test for the private area (the bug class behind the NG0203 hotfix): the real layout with
 * its real children, the production interceptor chain and the real session services. Only the network
 * (HTTP testing backend, fake IndexedDB) is stubbed. Configuration mirrors production: NO offlineGraceMs.
 */

const API = 'https://api.example.test';
const tenant: TenantContext = {
  id_company: 7, company_name: 'Acme', role: 'ADMIN', industry: 'Ganadería', business_type: 'LIVESTOCK',
};

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

describe('MainLayoutComponent (render smoke)', () => {
  let fixture: ComponentFixture<MainLayoutComponent>;
  let errors: unknown[][];

  /** Production configuration: no `offlineGraceMs`. The second case turns grace on. */
  function authConfig(extra: { offlineGraceMs?: number } = {}) {
    return { apiUrl_crud: `${API}/crud/v6`, apiUrl_token: `${API}/token`, apiUrl_ai: `${API}/ai`, apiUrl_upload: '', system_id: 'agro_erp', ...extra };
  }

  async function configure(extra: { offlineGraceMs?: number } = {}): Promise<void> {
    localStorage.clear();
    const exp = Math.floor(Date.now() / 1000) + 3600;
    localStorage.setItem('authToken', `${b64url({ alg: 'HS256' })}.${b64url({ user: 'ana', name: 'Ana', role: 'ADMIN', id_company: 7, exp })}.sig`);
    localStorage.setItem('user_tenants', JSON.stringify([tenant]));
    localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
    // jsdom has no matchMedia; the layout reads it for the iOS install prompt (a browser API, not a boundary).
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }));
    errors = [];
    vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => { errors.push(args); });
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    TestBed.resetTestingModule();
    await TestBed.configureTestingModule({
      imports: [MainLayoutComponent],
      providers: [
        provideRouter([{ path: '**', children: [] }]),
        provideHttpClient(withInterceptors([offlineGraceGuard, graceAuthInterceptor, tenantInterceptor])),
        provideHttpClientTesting(),
        { provide: AUTH_ENV_CONFIG, useValue: authConfig(extra) },
        AiService,
        { provide: CHAT_CONFIG_TOKEN, useValue: { apiUrl_ai: `${API}/ai`, logoUrl: '', title: 'Asistente', primaryColor: '#6c9a40' } },
      ],
    }).compileComponents();
  }

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  /** Renders the layout and waits for the prompt's asynchronous IndexedDB check to settle. */
  async function render(): Promise<HTMLElement> {
    expect(() => {
      fixture = TestBed.createComponent(MainLayoutComponent);
      fixture.detectChanges();
    }).not.toThrow();
    await new Promise(resolve => setTimeout(resolve, 0));
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  it('renders the whole private area without throwing (valid session, production config: grace off)', async () => {
    await configure();
    const el = await render();
    expect(el.querySelector('app-sidebar')).not.toBeNull();
    expect(el.querySelector('app-header')).not.toBeNull();
    expect(el.querySelector('app-toast-container')).not.toBeNull();
    expect(el.querySelector('router-outlet')).not.toBeNull();
    // The PIN setup prompt is dormant without offlineGraceMs: not mounted and never visible, even with
    // a valid online session and no PIN record. Give its async check time to (wrongly) appear.
    await new Promise(resolve => setTimeout(resolve, 20));
    fixture.detectChanges();
    expect(el.querySelector('app-pin-setup-prompt')).toBeNull();
    expect(el.querySelector('[aria-label="Crear PIN sin conexión"]')).toBeNull();
    // The chat widget is part of the layout whenever the session is not in grace.
    expect(el.querySelector('lib-ai-chat')).not.toBeNull();
    // No Angular runtime error (NG0xxx) was reported while rendering.
    expect(errors.some(args => /NG0\d+/.test(String(args[0])))).toBe(false);
  });

  it('shows the PIN setup prompt when offlineGraceMs is configured (valid session, no PIN record)', async () => {
    await configure({ offlineGraceMs: 16 * 60 * 60 * 1000 });
    const el = await render();
    expect(el.querySelector('app-pin-setup-prompt')).not.toBeNull();
    // The prompt checks IndexedDB asynchronously, so it appears after a few ticks.
    await vi.waitFor(() => {
      fixture.detectChanges();
      expect(el.querySelector('[aria-label="Crear PIN sin conexión"]')).not.toBeNull();
    });
    expect(errors.some(args => /NG0\d+/.test(String(args[0])))).toBe(false);
  });
});
