import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';
import { AuthService } from 'core-auth';
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
}