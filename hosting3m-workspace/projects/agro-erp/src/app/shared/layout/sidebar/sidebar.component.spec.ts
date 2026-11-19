import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG, TenantContext } from 'core-auth';
import { describe, expect, it } from 'vitest';
import { SidebarComponent } from './sidebar.component';

const API = 'https://api.example.test';

function render(role: string, kind: 'LIVESTOCK' | 'AGRICULTURE' = 'LIVESTOCK'): ComponentFixture<SidebarComponent> {
  const tenant: TenantContext = {
    id_company: 9101,
    company_name: 'Empresa sintética',
    role,
    industry: kind === 'LIVESTOCK' ? 'Ganadería de Precisión' : 'Agricultura de Precisión',
    business_type: kind,
  };
  localStorage.clear();
  localStorage.setItem('user_tenants', JSON.stringify([tenant]));
  localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
  TestBed.resetTestingModule();
  TestBed.configureTestingModule({
    imports: [SidebarComponent],
    providers: [
      provideRouter([]),
      provideHttpClient(),
      provideHttpClientTesting(),
      { provide: AUTH_ENV_CONFIG, useValue: { apiUrl_crud: `${API}/crud/v6`, apiUrl_token: `${API}/token`, apiUrl_upload: '', system_id: 'agro_erp' } },
    ],
  });
  const f = TestBed.createComponent(SidebarComponent);
  f.detectChanges();
  return f;
}

const link = (f: ComponentFixture<unknown>) => (f.nativeElement as HTMLElement).querySelector('a[href="/ganaderia/palpaciones"]');

describe('SidebarComponent: "Palpaciones" entry', () => {
  it('is shown to ADMIN and EDITOR of a livestock company, with its Spanish label', () => {
    for (const role of ['ADMIN', 'EDITOR']) {
      const f = render(role);
      expect(link(f)).not.toBeNull();
      expect(link(f)?.textContent).toContain('Palpaciones');
    }
  });

  it('is hidden from CUSTOMER and OWNER (the gateway models accept only the roles of PALPATION_ALLOWED_ROLES)', () => {
    for (const role of ['CUSTOMER', 'OWNER']) {
      expect(link(render(role))).toBeNull();
    }
  });

  it('is hidden from a palm company, whatever the role', () => {
    expect(link(render('ADMIN', 'AGRICULTURE'))).toBeNull();
  });

  it('keeps the other livestock entries', () => {
    const f = render('ADMIN');
    expect((f.nativeElement as HTMLElement).textContent).toContain('Censo Biológico');
  });
});
