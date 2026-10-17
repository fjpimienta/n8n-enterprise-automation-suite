import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TenantService } from 'core-auth';
import { PALM_DASHBOARD_ROUTE, dashboardRouteFor, isPalmDomain } from '@shared/utils/business-domain.util';
import { canAdministerPalm } from '../utils/agri.util';

/**
 * Palm screens exist only for palm companies. A livestock (or unknown) company is sent to its own
 * dashboard — never shown palm screens under another company's heading.
 */
export const palmDomainGuard: CanActivateFn = () => {
  const tenant = inject(TenantService).activeTenant();
  if (isPalmDomain(tenant)) return true;
  return inject(Router).parseUrl(dashboardRouteFor(tenant));
};

/**
 * Palm administration (plantations, lots, rows): ADMIN / OWNER of the ACTIVE company. Uses
 * tenantService.activeTenant()?.role, not the role frozen in the JWT (core-auth roleGuard reads the JWT
 * and does not know OWNER; it is intentionally not modified).
 */
export const palmAdminGuard: CanActivateFn = () => {
  const tenant = inject(TenantService).activeTenant();
  if (isPalmDomain(tenant) && canAdministerPalm(tenant?.role)) return true;
  return inject(Router).parseUrl(PALM_DASHBOARD_ROUTE);
};
