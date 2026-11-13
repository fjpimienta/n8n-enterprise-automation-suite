import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TenantService } from 'core-auth';
import { PALM_DASHBOARD_ROUTE, isPalmDomain, palmRouteRedirect } from '@shared/utils/business-domain.util';
import { canAdministerPalm } from '../utils/agri.util';
import { canCaptureExpense } from '../utils/expense.util';
import { canManageSales } from '../utils/sale.util';

/**
 * Palm screens exist only for palm companies. A livestock (or unknown) company is sent to its own
 * dashboard — never shown palm screens under another company's heading.
 */
export const palmDomainGuard: CanActivateFn = () => {
  const redirect = palmRouteRedirect(inject(TenantService).activeTenant());
  return redirect ? inject(Router).parseUrl(redirect) : true;
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

/**
 * "Gastos": ADMIN / OWNER / EDITOR of the ACTIVE palm company (CUSTOMER is read-only and never captures).
 * The amounts (balance, list, catalog) are gated again inside the screen and by the gateway.
 */
export const palmExpenseGuard: CanActivateFn = () => {
  const tenant = inject(TenantService).activeTenant();
  if (isPalmDomain(tenant) && canCaptureExpense(tenant?.role)) return true;
  return inject(Router).parseUrl(PALM_DASHBOARD_ROUTE);
};

/**
 * "Ventas": ADMIN of the ACTIVE palm company only (read, summary and void are ADMIN-only in the gateway). Uses
 * tenantService.activeTenant()?.role, never the JWT role. OWNER, EDITOR and CUSTOMER go back to the palm dashboard.
 */
export const palmSalesGuard: CanActivateFn = () => {
  const tenant = inject(TenantService).activeTenant();
  if (isPalmDomain(tenant) && canManageSales(tenant?.role)) return true;
  return inject(Router).parseUrl(PALM_DASHBOARD_ROUTE);
};
