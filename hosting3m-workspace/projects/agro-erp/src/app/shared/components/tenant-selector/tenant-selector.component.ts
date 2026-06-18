import { Component, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router'; // 🚀 IMPORTANTE: Agregar Router
import { TenantService } from 'core-auth';

@Component({
  selector: 'app-tenant-selector',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './tenant-selector.component.html'
})
export class TenantSelectorComponent implements OnInit {
  public tenantService = inject(TenantService);
  private router = inject(Router); // 🚀 Inyectar el Router

  ngOnInit() {
    if (this.tenantService.availableTenants().length === 0) {
      console.warn('⚠️ [TenantSelector] Estado vacío detectado. Sincronizando con persistencia...');
    }
  }

  // 🛡️ Procesa el cambio de contexto de rancho y redirige
  onSelect(tenantId: any) {
    const id = Number(tenantId);
    const tenant = this.tenantService.availableTenants().find(t => t.id_company === id);

    if (tenant) {
      this.tenantService.setActiveTenant(tenant);

      // 🚀 FIX: Enrutamiento defensivo basado en la industria
      const isAgri = tenant.business_type === 'AGRICULTURE' || tenant.industry?.toLowerCase().includes('agricultura');
      const targetRoute = isAgri ? '/agricultura/dashboard' : '/ganaderia/dashboard';

      this.router.navigate([targetRoute]);
    }
  }
}