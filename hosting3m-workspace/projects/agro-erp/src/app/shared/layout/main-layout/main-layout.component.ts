import { Component, inject, computed } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NgClass } from '@angular/common';
import { TenantService } from 'core-auth';

// 🚀 FIX: Importamos tus componentes. (Verifica que la ruta relativa sea correcta según tus carpetas)
import { SidebarComponent } from '../sidebar/sidebar.component';
import { HeaderComponent } from '../header/header.component';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  // 🚀 FIX: Inyectamos los componentes y removemos RouterLink/RouterLinkActive que ya no se usan aquí
  imports: [RouterOutlet, NgClass, SidebarComponent, HeaderComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss']
})
export class MainLayoutComponent {
  private tenantService = inject(TenantService);

  public currentTenant = this.tenantService.activeTenant;

  // Signal computada para determinar el color/estilo según el negocio activo
  public themeClass = computed(() => {
    const tenant = this.currentTenant();
    return tenant?.business_type === 'AGRICULTURE' ? 'theme-palm' : 'theme-cattle';
  });
}