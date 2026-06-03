import { Injectable, signal, computed } from '@angular/core';

export interface TenantContext {
  id_company: number;
  company_name: string;
  role: string;
  industry: string;
}

@Injectable({
  providedIn: 'root'
})
export class TenantService {
  private readonly _availableTenants = signal<TenantContext[]>(this.loadAvailableFromStorage());
  private readonly _activeTenant = signal<TenantContext | null>(this.loadActiveFromStorage());

  readonly availableTenants = this._availableTenants.asReadonly();
  readonly activeTenant = this._activeTenant.asReadonly();

  readonly activeTenantId = computed(() => this._activeTenant()?.id_company || null);

  setAvailableTenants(tenants: TenantContext[]): void {
    this._availableTenants.set(tenants);
    localStorage.setItem('user_tenants', JSON.stringify(tenants));
  }

  setActiveTenant(tenant: TenantContext): void {
    this._activeTenant.set(tenant);
    localStorage.setItem('active_tenant_id', String(tenant.id_company));
    localStorage.setItem('active_tenant_context', JSON.stringify(tenant));
  }

  clearContext(): void {
    this._activeTenant.set(null);
    this._availableTenants.set([]);
    localStorage.removeItem('active_tenant_id');
    localStorage.removeItem('active_tenant_context');
    localStorage.removeItem('user_tenants');
  }

  private loadActiveFromStorage(): TenantContext | null {
    const cached = localStorage.getItem('active_tenant_context');
    return cached ? JSON.parse(cached) : null;
  }

  private loadAvailableFromStorage(): TenantContext[] {
    const cached = localStorage.getItem('user_tenants');
    return cached ? JSON.parse(cached) : [];
  }
}