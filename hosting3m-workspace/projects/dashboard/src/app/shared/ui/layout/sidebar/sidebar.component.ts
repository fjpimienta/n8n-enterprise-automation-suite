import { Component, inject, output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '@core/services/auth.service';
import { ThemeService } from '@core/services/theme.service';

interface NavItem {
    label: string;
    route: string;
    icon: string; // Nombre del icono de Tabler/Lucide
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

    menu: NavSection[] = [
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
                { label: 'Caja y Gastos', route: '/dashboard/finanzas', icon: 'wallet' }
            ]
        }
    ];

    handleLinkClick() {
        this.linkClicked.emit();
    }

    onLogout() {
        this.authService.logout();
        this.router.navigate(['/login']);
        this.handleLinkClick();
    }
}