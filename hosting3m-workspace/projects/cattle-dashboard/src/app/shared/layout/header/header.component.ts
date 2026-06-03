import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { AuthService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { LayoutService } from '@shared/services/layout.service'; // 🚀 IMPORTANTE: Servicio Real

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './header.component.html'
})
export class HeaderComponent {
  public authService = inject(AuthService);
  public themeService = inject(ThemeService);
  public layoutService = inject(LayoutService); // 🚀 Inyectado correctamente
  private router = inject(Router);

  // 🚀 Disparador real usando Signals
  public toggleMenu() {
    this.layoutService.mobileMenuOpen.update(val => !val);
  }

  public logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}