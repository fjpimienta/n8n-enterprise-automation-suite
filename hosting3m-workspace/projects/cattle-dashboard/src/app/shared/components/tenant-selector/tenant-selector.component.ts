import { Component, inject, OnInit } from '@angular/core';
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

  // 🛡️ CORRECCIÓN: Ahora acepta directamente el valor numérico/string del select
  onSelect(tenantId: any) {
    const id = Number(tenantId);
    const tenant = this.tenantService.availableTenants().find(t => t.id_company === id);

    if (tenant) {
      this.tenantService.setActiveTenant(tenant);
      // Nota: Al implementar el 'effect' en el dashboard, ya no necesitas hacer window.location.reload()
      // La reactividad de Signals actualizará los datos en tiempo real sin recargar la pantalla.
    }
  }
}