import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { TenantService, TenantContext } from '../services/tenant.service';

@Component({
  selector: 'lib-tenant-selector',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './tenant-selector.component.html',
  styleUrl: './tenant-selector.component.css',
})
export class TenantSelectorComponent {
  public tenantService = inject(TenantService);
  private router = inject(Router);

  selectTenant(event: Event, tenant: TenantContext) {
    event.preventDefault();

    // Inyectamos el tenant en el Signal global
    this.tenantService.setActiveTenant(tenant);

    // Redirigimos a la aplicación principal. 
    // Al ser un Monorepo, la app que consuma esta librería manejará esta ruta.
    this.router.navigate(['/dashboard']);
  }

  getIconForIndustry(industry: string): string {
    const ind = industry?.toLowerCase() || '';
    if (ind.includes('hotel')) return 'M3 21l18 0 M4 21v-15a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v15 M9 21v-8a3 3 0 0 1 6 0v8 M8 7h.01 M12 7h.01 M16 7h.01 M8 11h.01 M12 11h.01 M16 11h.01';
    if (ind.includes('ganad')) return 'M3 4.513v15a4 4 0 0 0 4 4h10a4 4 0 0 0 4 -4v-15l-9 -4.513z M12 12m-3 0a3 3 0 1 0 6 0a3 3 0 1 0 -6 0';
    if (ind.includes('hielo')) return 'M8 16a4 4 0 0 1 8 0 M10 16v-8h4v8 M12 8l0 -4 M12 4l-2 2 M12 4l2 2';
    return 'M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0'; // Default
  }
}