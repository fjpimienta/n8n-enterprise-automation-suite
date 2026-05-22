import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router'; // <-- Agregamos Router
import { AuthService } from '@core/services/auth.service';
import { ThemeService } from '@core/services/theme.service'; // <-- Agregamos ThemeService

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './header.component.html'
})
export class HeaderComponent {
  public authService = inject(AuthService);
  public themeService = inject(ThemeService); // <-- Inyectado
  private router = inject(Router);            // <-- Inyectado

  // MOCK: Simulamos el servicio de layout móvil
  public layoutService = {
    toggleMobileMenu: () => {
      document.body.classList.toggle('offcanvas-active');
    }
  };

  // 🛠️ Función para destruir la sesión
  public logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }
}