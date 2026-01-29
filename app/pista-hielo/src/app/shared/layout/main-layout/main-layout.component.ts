import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from '@core/auth/auth.service';
import { ThemeService } from '@core/services/theme.service'; // <--- Importar

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.css']
})
export class MainLayoutComponent {
  private authService = inject(AuthService);
  private router = inject(Router);

  // Hacemos el servicio público para usarlo directo en el HTML
  public themeService = inject(ThemeService);

  isMobileMenuOpen = signal(false);

  constructor() {
    this.router.events.pipe(
      filter(event => event instanceof NavigationEnd)
    ).subscribe(() => {
      this.isMobileMenuOpen.set(false);
    });
  }

  closeMenu() {
    this.isMobileMenuOpen.set(false);
  }

  toggleMobileMenu() {
    this.isMobileMenuOpen.update(v => !v);
  }

  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}