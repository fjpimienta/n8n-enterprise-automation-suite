import { Injectable, signal, computed } from '@angular/core';

export interface TenantContext {
  id_company: number;
  company_name: string;
  role: string;
  industry: string;
}

@Injectable({ providedIn: 'root' })
export class TenantService {
  private readonly _availableTenants = signal<TenantContext[]>(this.loadAvailableFromStorage());
  private readonly _activeTenant = signal<TenantContext | null>(this.loadActiveFromStorage());

  public readonly availableTenants = computed(() => {
    if (this._availableTenants().length === 0) this.hydrate();
    return this._availableTenants();
  });

  public readonly activeTenant = this._activeTenant.asReadonly();
  public readonly activeTenantId = computed(() => this._activeTenant()?.id_company || null);

  // En tenant.service.ts
  public debugState(): void {
    console.group('🔍 [TenantService Audit]');
    console.log('Available Tenants Count:', this._availableTenants().length);
    console.log('Current Available:', this._availableTenants());
    console.log('Active Tenant:', this._activeTenant());
    console.groupEnd();
  }

  constructor() {
    this.hydrate();
  }

  public hydrate(): void {
    const cached = localStorage.getItem('user_tenants');
    const active = localStorage.getItem('active_tenant_context');
    console.log('✅ [TenantService] Estableciendo cached:', cached);
    console.log('✅ [TenantService] Estableciendo active:', active);
    console.log('this._availableTenants():', this._availableTenants());
    console.log('this._availableTenants().length:', this._availableTenants().length);

    if (cached && this._availableTenants().length === 0) {
      try {
        this._availableTenants.set(JSON.parse(cached));
      } catch (e) { console.error('Error parseando tenants', e); }
    }
    if (active && !this._activeTenant()) {
      try { this._activeTenant.set(JSON.parse(active)); } catch (e) { console.error('Error parseando active', e); }
    }
  }

  public setAvailableTenants(tenants: TenantContext[]): void {
    console.log('🚀 [TenantService] SETEANDO NUEVOS TENANTS:', tenants);
    this._availableTenants.set(tenants);
    localStorage.setItem('user_tenants', JSON.stringify(tenants));
  }

  public setActiveTenant(tenant: TenantContext): void {
    console.log('🚀 [TenantService] SETEANDO TENANT:', tenant);
    this._activeTenant.set(tenant);
    localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
  }

  public clearContext(): void {
    this._activeTenant.set(null);
    this._availableTenants.set([]);
    localStorage.removeItem('active_tenant_context');
    localStorage.removeItem('user_tenants');
  }

  private loadActiveFromStorage(): TenantContext | null {
    const cached = localStorage.getItem('active_tenant_context');
    try { return cached ? JSON.parse(cached) : null; } catch { return null; }
  }

  private loadAvailableFromStorage(): TenantContext[] {
    const cached = localStorage.getItem('user_tenants');
    try { return cached ? JSON.parse(cached) : []; } catch { return []; }
  }
}