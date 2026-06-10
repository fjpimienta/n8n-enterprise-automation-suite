import { Component, inject, OnInit, signal, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TenantService } from 'core-auth';

@Component({
  selector: 'app-tenant-selector',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './tenant-selector.component.html'
})
export class TenantSelectorComponent implements OnInit {
  public tenantService = inject(TenantService);

  ngOnInit() {
    if (this.tenantService.availableTenants().length === 0) {
      console.warn('⚠️ [TenantSelector] Estado vacío detectado. Sincronizando con persistencia...');
    }
  }

  // 🛡️ Procesa el cambio de contexto de rancho
  onSelect(tenantId: any) {
    const id = Number(tenantId);
    const tenant = this.tenantService.availableTenants().find(t => t.id_company === id);

    if (tenant) {
      this.tenantService.setActiveTenant(tenant);
      // Al mutar el Signal global, los componentes que lo escuchan se actualizarán en cascada.
    }
  }
}