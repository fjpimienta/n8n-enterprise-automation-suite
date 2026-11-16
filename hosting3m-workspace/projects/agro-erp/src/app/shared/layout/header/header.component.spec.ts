import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA, signal } from '@angular/core';
import { provideRouter } from '@angular/router';
import { AuthService, TenantService } from 'core-auth';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { HeaderComponent } from './header.component';

describe('HeaderComponent', () => {
  let fixture: ComponentFixture<HeaderComponent>;
  let user: ReturnType<typeof signal<{ name: string; role: string } | null>>;
  let state: ReturnType<typeof signal<'valid' | 'grace' | 'expired'>>;
  let scope: ReturnType<typeof signal<{ user: string; id_company: number } | null>>;

  beforeEach(async () => {
    user = signal({ name: 'Ana Pérez', role: 'ADMIN' });
    state = signal<'valid' | 'grace' | 'expired'>('valid');
    scope = signal({ user: 'ana@example.com', id_company: 7 });
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { currentUser: user, logout: vi.fn() } },
        { provide: TenantService, useValue: { activeTenant: signal({ role: 'editor', company_name: 'Acme' }), availableTenants: signal([]), activeTenantId: signal(7) } },
        { provide: OfflineSessionService, useValue: { state, scope } },
      ],
    });
    // Child selectors have their own specs and dependencies; this spec only covers the header identity.
    TestBed.overrideComponent(HeaderComponent, { set: { imports: [], schemas: [CUSTOM_ELEMENTS_SCHEMA] } });
    await TestBed.compileComponents();
    fixture = TestBed.createComponent(HeaderComponent);
    fixture.detectChanges();
  });

  const text = () => (fixture.nativeElement as HTMLElement).textContent ?? '';

  it('valid: shows the JWT identity', () => {
    expect(text()).toContain('Ana Pérez');
    expect(text()).toContain('ADMIN');
  });

  it('grace: shows the scope user and the active company role, never the Administrador / Socio Operativo fallbacks', () => {
    state.set('grace');
    user.set(null);
    fixture.detectChanges();
    expect(text()).toContain('ana@example.com');
    expect(text()).toContain('EDITOR');
    expect(text()).not.toContain('Administrador');
    expect(text()).not.toContain('Socio Operativo');
  });

  it('grace without a scope shows a dash, not an identity', () => {
    state.set('grace');
    scope.set(null);
    user.set(null);
    fixture.detectChanges();
    expect(text()).not.toContain('Administrador');
    expect(text()).not.toContain('Socio Operativo');
  });
});
