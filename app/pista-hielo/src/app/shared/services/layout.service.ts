import { Injectable, signal } from '@angular/core';
import { Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class LayoutService {
  // Estado Desktop (Mini sidebar)
  sidebarCollapsed = signal<boolean>(false);

  // Estado Móvil (Menú abierto/cerrado)
  mobileMenuOpen = signal<boolean>(false);

  constructor(private router: Router) {
    // Cerrar menú móvil automáticamente al cambiar de ruta
    this.router.events.pipe(
      filter(event => event instanceof NavigationEnd)
    ).subscribe(() => {
      this.mobileMenuOpen.set(false);
    });
  }

  toggleSidebar() {
    this.sidebarCollapsed.update(v => !v);
  }

  toggleMobileMenu() {
    this.mobileMenuOpen.update(v => !v);
  }
}