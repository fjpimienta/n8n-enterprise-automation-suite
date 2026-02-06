import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService } from '@core/auth/auth.service';
import { ThemeService } from '@core/services/theme.service';

// 1. SOLO IMPORTAS EL MÓDULO (Ya no necesitas los iconos individuales aquí)
import { LucideAngularModule } from 'lucide-angular';
import { LayoutService } from '@shared/services/layout.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  // 2. IMPORTS SIMPLE
  imports: [
    CommonModule,
    RouterModule,
    LucideAngularModule
  ],
  // 3. ¡BORRAMOS EL ARRAY PROVIDERS! Ya no es necesario.
  templateUrl: './sidebar.component.html',
  styleUrls: ['./sidebar.component.css']
})
export class SidebarComponent {
  public authService = inject(AuthService);
  public themeService = inject(ThemeService);
  public layoutService = inject(LayoutService);

  isMobileMenuOpen = this.layoutService.mobileMenuOpen;
  isCollapsed = this.layoutService.sidebarCollapsed;

  closeMenu() {
    this.layoutService.mobileMenuOpen.set(false);
  }

  toggleCollapse() {
    this.layoutService.toggleSidebar();
  }

  logout() {
    this.authService.logout();
  }
}