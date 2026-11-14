import { inject } from '@angular/core';
import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { throwError } from 'rxjs';
import { TenantService } from '../services/tenant.service';
import { AUTH_ENV_CONFIG } from '../auth.config';
import { isAllowedOrigin, isExemptRoute } from '../allowed-origin';

export const tenantInterceptor: HttpInterceptorFn = (req, next) => {
  const tenantService = inject(TenantService);
  const envConfig = inject(AUTH_ENV_CONFIG);
  const activeTenantId = tenantService.activeTenantId();
  const hasValidActiveTenant = typeof activeTenantId === 'number' && Number.isInteger(activeTenantId) && activeTenantId > 0;
  const isApiRequest = isAllowedOrigin(req.url, envConfig);
  const isExempt = isExemptRoute(req.url, envConfig);

  if (isApiRequest && !isExempt && !hasValidActiveTenant) {
    return throwError(() => new HttpErrorResponse({
      status: 403,
      statusText: 'No active tenant',
      url: req.url
    }));
  }

  if (hasValidActiveTenant && isApiRequest && !isExempt) {
    const clonedRequest = req.clone({
      setHeaders: {
        'X-Tenant-ID': String(activeTenantId),
        'x-tenant-id': String(activeTenantId)
      }
    });
    return next(clonedRequest);
  }

  return next(req);
};