import { Component, inject, computed } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NgClass } from '@angular/common';
import { TenantService } from 'core-auth';

import { SidebarComponent } from '../sidebar/sidebar.component';
import { HeaderComponent } from '../header/header.component';

import { AiChatComponent } from 'ui-chat';

// 🚀 IMPORTANTE: Importa el componente visual del chat desde tu librería (Ajusta el nombre si es diferente)

@Component({
  selector: 'app-main-layout',
  standalone: true,
  // 🚀 Agrégalo al arreglo de imports
  imports: [RouterOutlet, NgClass, SidebarComponent, HeaderComponent, AiChatComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss']
})
export class MainLayoutComponent {
  private tenantService = inject(TenantService);

  public currentTenant = this.tenantService.activeTenant;

  // 🚀 FIX: Fallback dinámico para inyección de tema
  public themeClass = computed(() => {
    const tenant = this.currentTenant();
    const isAgri = tenant?.business_type === 'AGRICULTURE' || tenant?.industry?.toLowerCase().includes('agricultura');
    return isAgri ? 'theme-palm' : 'theme-cattle';
  });
}