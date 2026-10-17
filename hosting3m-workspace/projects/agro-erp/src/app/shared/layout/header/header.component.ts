import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
// 🚀 FIX: Importamos TenantService
import { AuthService, TenantService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { LayoutService } from '@shared/services/layout.service';
import { TenantSelectorComponent } from '@shared/components/tenant-selector/tenant-selector.component';
import { PlantationSelectorComponent } from '@features/agriculture/components/plantation-selector/plantation-selector.component';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule, RouterModule, TenantSelectorComponent, PlantationSelectorComponent],
  templateUrl: './header.component.html',
  styles: [`
    /* Long company names are truncated (full name in the title attribute) instead of pushing the actions. */
    .header-title { min-width: 0; flex: 0 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .header-actions { row-gap: 0.5rem; justify-content: flex-end; }
    @media (max-width: 575.98px) {
      .header-title { max-width: 45vw; font-size: 1rem; }
    }
  `]
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