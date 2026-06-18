import { Component, inject, signal, computed } from '@angular/core'; // 🚀 FIX: Agregar computed
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';
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
  public tenantService = inject(TenantService);
  private router = inject(Router);

  public userRole = signal<string | null>(null);

  isMobileMenuOpen = this.layoutService.mobileMenuOpen;
  isCollapsed = this.layoutService.sidebarCollapsed;

  // 🚀 FIX: Programación defensiva para inferir el tipo de negocio
  public isLivestock = computed(() => {
    const t = this.tenantService.activeTenant();
    return t?.business_type === 'LIVESTOCK' || t?.industry?.toLowerCase().includes('ganader');
  });

  public isAgriculture = computed(() => {
    const t = this.tenantService.activeTenant();
    return t?.business_type === 'AGRICULTURE' || t?.industry?.toLowerCase().includes('agricultura');
  });

  ngOnInit() {
    const currentRole = localStorage.getItem('role') || 'EDITOR';
    this.userRole.set(currentRole);
  }

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

  getInitials(name?: string): string {
    if (!name) return 'H3M';
    return name.split(' ').map(n => n[0]).join('').substring(0, 3).toUpperCase();
  }
}