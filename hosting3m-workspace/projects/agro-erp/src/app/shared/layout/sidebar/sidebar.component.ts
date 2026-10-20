import { Component, inject, signal, computed } from '@angular/core'; // 🚀 FIX: Agregar computed
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';
import { AuthService, TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { menuVisibility } from '@shared/utils/menu-visibility.util';

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

  // Menu by business domain and active-company role (single rule: @shared/utils/menu-visibility.util).
  private menu = computed(() => menuVisibility(this.tenantService.activeTenant()));
  public isLivestock = computed(() => this.menu().livestockIntelligence);
  public isAgriculture = computed(() => this.menu().palmIntelligence);
  public canAdministerPalm = computed(() => this.menu().palmAdministration);
  public showPalmExpenses = computed(() => this.menu().palmExpenses);
  public isAdmin = computed(() => this.menu().sharedConfig);
  public showLivestockConfig = computed(() => this.menu().livestockConfig);
  public personalLabel = computed(() => this.menu().personalLabel);
  public showIntelligenceSection = computed(() => this.menu().intelligenceSection);
  public showConfigSection = computed(() => this.menu().configSection);

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