import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
// 🚀 FIX: Importamos TenantService
import { AuthService, TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { LayoutService } from '@shared/services/layout.service';
import { TenantSelectorComponent } from '@shared/components/tenant-selector/tenant-selector.component';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule, RouterModule, TenantSelectorComponent],
  templateUrl: './header.component.html'
})
export class HeaderComponent {
  public authService = inject(AuthService);
  // 🚀 FIX: Inyectamos el servicio
  public tenantService = inject(TenantService);
  public themeService = inject(ThemeService);
  public layoutService = inject(LayoutService);
  private router = inject(Router);

  public toggleMenu() {
    this.layoutService.mobileMenuOpen.update(val => !val);
  }

  public logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}