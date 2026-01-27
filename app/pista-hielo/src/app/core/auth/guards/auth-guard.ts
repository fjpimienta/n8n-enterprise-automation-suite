import { CanActivateFn, Router } from '@angular/router';
import { inject, PLATFORM_ID } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { AuthService } from '@core/auth/auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);
  const platformId = inject(PLATFORM_ID);

  // 1. Si estamos en el servidor, permitimos pasar (el cliente validará después)
  // Esto evita el parpadeo o redirección prematura en SSR
  if (!isPlatformBrowser(platformId)) {
    return true;
  }

  // 2. Validación en el cliente (Navegador)
  if (authService.isAuthenticated()) {
    return true;
  }

  // Si no está logueado, mandar al login
  return router.createUrlTree(['/login']);
};