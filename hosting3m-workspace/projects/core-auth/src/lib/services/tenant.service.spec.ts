import { TestBed } from '@angular/core/testing';

import { TenantService, TenantContext } from './tenant.service';

describe('TenantService', () => {
  let service: TenantService;

  const adminCompanyA: TenantContext = {
    id_company: 1, company_name: 'Company A', role: 'ADMIN', industry: 'Ganadería', business_type: 'LIVESTOCK'
  };
  const editorCompanyB: TenantContext = {
    id_company: 2, company_name: 'Company B', role: 'EDITOR', industry: 'Ganadería', business_type: 'LIVESTOCK'
  };
  const adminCompanyC: TenantContext = {
    id_company: 3, company_name: 'Company C', role: 'ADMIN', industry: 'Ganadería', business_type: 'LIVESTOCK'
  };

  // Mismo predicado, verbatim, que MainDashboardComponent.isAdminForActiveTenant y
  // CattleListComponent.isAdminForActiveTenant — probado aquí contra el TenantService real
  // (sin mocks) para verificar el mecanismo compartido, no una reimplementación paralela.
  const isAdmin = () => (service.activeTenant()?.role || '').toUpperCase() === 'ADMIN';

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({});
    service = TestBed.inject(TenantService);
  });

  afterEach(() => {
    localStorage.clear();
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('reports the role of the currently active tenant, not the first one ever set', () => {
    service.setActiveTenant(editorCompanyB);
    expect(isAdmin()).toBe(false);

    service.setActiveTenant(adminCompanyA);
    expect(isAdmin()).toBe(true);
  });

  it('updates live across a multi-company Context Switcher sequence (ADMIN -> EDITOR -> ADMIN), same service instance, no re-login', () => {
    // Simulates TenantSelectorComponent.onSelect(): only ever calls setActiveTenant() with an
    // entry already cached in availableTenants() — never re-authenticates, never touches the JWT.
    service.setActiveTenant(adminCompanyA);
    expect(isAdmin()).toBe(true); // Company A, ADMIN

    service.setActiveTenant(editorCompanyB);
    expect(isAdmin()).toBe(false); // switched to Company B, EDITOR

    service.setActiveTenant(adminCompanyC);
    expect(isAdmin()).toBe(true); // switched to Company C, ADMIN
  });

  it('persists the active tenant role change to localStorage on every switch', () => {
    service.setActiveTenant(adminCompanyA);
    expect(JSON.parse(localStorage.getItem('active_tenant_context')!).role).toBe('ADMIN');

    service.setActiveTenant(editorCompanyB);
    expect(JSON.parse(localStorage.getItem('active_tenant_context')!).role).toBe('EDITOR');
  });

  it('clearContext wipes both the active tenant and the available tenants list (logout fail-closed)', () => {
    service.setAvailableTenants([adminCompanyA, editorCompanyB]);
    service.setActiveTenant(adminCompanyA);

    service.clearContext();

    expect(service.activeTenant()).toBeNull();
    expect(service.availableTenants()).toEqual([]);
    expect(localStorage.getItem('user_tenants')).toBeNull();
    expect(localStorage.getItem('active_tenant_context')).toBeNull();
  });
});
