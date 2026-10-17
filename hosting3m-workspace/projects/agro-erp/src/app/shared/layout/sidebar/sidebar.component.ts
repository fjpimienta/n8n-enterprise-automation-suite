import { Component, inject, signal, computed } from '@angular/core'; // 🚀 FIX: Agregar computed
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';
import { AuthService, TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { isLivestockDomain, isPalmDomain } from '@shared/utils/business-domain.util';
import { canAdministerPalm } from '@features/agriculture/utils/agri.util';

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

  // Business domain of the active company (single rule: @shared/utils/business-domain.util)
  public isLivestock = computed(() => isLivestockDomain(this.tenantService.activeTenant()));
  public isAgriculture = computed(() => isPalmDomain(this.tenantService.activeTenant()));
  // Palm administration entries: role of the ACTIVE company (not the JWT role).
  public canAdministerPalm = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));

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