import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TenantService } from 'core-auth';

/** Tenant roles allowed to write lots — mirrors `crud_models.allowed_roles_insert/update` ('ADMIN,OWNER'). */
const LOT_WRITE_ROLES = new Set(['ADMIN', 'OWNER']);

export function canManageLots(role: string | null | undefined): boolean {
  return LOT_WRITE_ROLES.has((role ?? '').toUpperCase());
}

/**
 * Fail-closed guard for routes carrying `:tenantId`. The tenant interceptor always sends
 * the ACTIVE tenant as `x-tenant-id`, so a URL pointing at any other tenant would silently
 * show the active tenant's data under the wrong heading. Such URLs are rejected (never
 * switched implicitly) and the user is sent back to the tenant list.
 */
export const activeTenantRouteGuard: CanActivateFn = route => {
  const tenantService = inject(TenantService);
  const router = inject(Router);

  const activeId = Number(tenantService.activeTenantId());
  const routeId = Number(route.paramMap.get('tenantId'));

  if (Number.isInteger(activeId) && activeId > 0 && routeId === activeId) {
    return true;
  }

  console.warn('[Agro-ERP] Bloqueado: la ruta apunta a una empresa distinta de la activa.', { routeId, activeId });
  return router.createUrlTree(['/admin/tenants']);
};
