import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { TenantService } from 'core-auth';
import { livestockRouteRedirect } from '@shared/utils/business-domain.util';

/**
 * Livestock screens (ganadería, cumplimiento, livestock catalogs, official UPPs) are not for palm companies:
 * a palm company is sent to the palm dashboard. Livestock and unknown domains pass, as before.
 *
 * UX only: the real isolation is id_company in the gateway. Mirror of palmDomainGuard.
 */
export const livestockDomainGuard: CanActivateFn = () => {
  const redirect = livestockRouteRedirect(inject(TenantService).activeTenant());
  return redirect ? inject(Router).parseUrl(redirect) : true;
};
