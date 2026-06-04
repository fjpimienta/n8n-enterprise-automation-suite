import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';
// 🚀 FIX: Importamos TenantService
import { AuthService, TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './sidebar.component.html',
  styleUrls: ['./sidebar.component.scss']
})
export class SidebarComponent {
  public layoutService = inject(LayoutService);
  public authService = inject(AuthService);
  public themeService = inject(ThemeService);
  // 🚀 FIX: Inyectamos el gestor de estado Multi-Tenant
  public tenantService = inject(TenantService);
  private router = inject(Router);

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
    this.router.navigate(['/login']);
  }

  // 🚀 Helper para extraer las iniciales dinámicamente (Ej. "Rancho San José" -> "RSJ")
  getInitials(name?: string): string {
    if (!name) return 'H3M';
    return name.split(' ').map(n => n[0]).join('').substring(0, 3).toUpperCase();
  }
}