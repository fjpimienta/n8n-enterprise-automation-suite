import { Component, inject, output, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '@core/services/auth.service';
import { ThemeService } from '@core/services/theme.service';

interface NavItem {
  label: string;
  route: string;
  icon: string;
  /** Si se define, solo usuarios con este rol ven el ítem */
  requiredRole?: string;
}

interface NavSection {
  title: string;
  items: NavItem[];
}

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  templateUrl: './sidebar.component.html',
  styleUrls: ['./sidebar.component.scss']
})
export class SidebarComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  public themeService = inject(ThemeService);
  toggleMenu = output<void>();
  closeMenu = output<void>();
  linkClicked = output<void>();

  private readonly menu: NavSection[] = [
    {
      title: 'OPERACIONES',
      items: [
        { label: 'Dashboard', route: '/dashboard', icon: 'layout-dashboard' },
        { label: 'Mantenimiento', route: '/dashboard/mantenimiento', icon: 'tool' },
        { label: 'Reservas', route: '/dashboard/reservas', icon: 'calendar' }
      ]
    },
    {
      title: 'ADMINISTRACIÓN',
      items: [
        { label: 'Huéspedes', route: '/dashboard/huespedes', icon: 'users' },
        { label: 'Personal', route: '/dashboard/personal', icon: 'user-check' },
        { label: 'Inventario', route: '/dashboard/inventario', icon: 'box' }
      ]
    },
    {
      title: 'FINANZAS',
      items: [
        { label: 'Caja y Gastos', route: '/dashboard/finanzas', icon: 'wallet', requiredRole: 'ADMIN' }
      ]
    }
  ];

  /** Menú filtrado por RBAC; se re-evalúa cuando currentUser cambia (sin memory leaks) */
  readonly visibleMenu = computed(() => {
    return this.menu
      .map(section => ({
        ...section,
        items: section.items.filter(item => {
          if (!item.requiredRole) return true;
          return this.authService.hasRole(item.requiredRole);
        })
      }))
      .filter(section => section.items.length > 0);
  });

  handleLinkClick() {
    this.linkClicked.emit();
  }

  onLogout() {
    this.authService.logout();
    this.router.navigate(['/login']);
    this.handleLinkClick();
  }
}
