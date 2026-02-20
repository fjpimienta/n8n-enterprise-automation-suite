import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.isAuthenticated()) {
    return true;
  }

  router.navigate(['/login']);
  return false;
};

/**
 * Role guard con lookup O(1) vía Set.
 * Uso: canActivate: [authGuard, roleGuard(['ADMIN', 'EDITOR'])]
 */
export function roleGuard(allowedRoles: readonly string[]): CanActivateFn {
  const allowed = new Set(allowedRoles.map(r => r.toUpperCase()));

  return (route, state) => {
    const authService = inject(AuthService);
    const router = inject(Router);

    if (!authService.isAuthenticated()) {
      router.navigate(['/login']);
      return false;
    }

    const userRole = authService.currentUser()?.role?.toUpperCase();
    if (userRole && allowed.has(userRole)) {
      return true;
    }

    router.navigate(['/unauthorized']);
    return false;
  };
}
