import { inject } from '@angular/core';
import { HttpInterceptorFn } from '@angular/common/http';
import { TenantService } from '../services/tenant.service'; // 🎯 Ruta relativa corregida
import { AUTH_ENV_CONFIG } from '../auth.config';
import { isAllowedOrigin } from '../allowed-origin';

export const tenantInterceptor: HttpInterceptorFn = (req, next) => {
  const tenantService = inject(TenantService);
  const envConfig = inject(AUTH_ENV_CONFIG);
  const activeTenantId = tenantService.activeTenantId(); // Lectura reactiva del Signal

  // Header only goes to allowed origins (#1037); a missing tenant is still not blocked client-side.
  if (activeTenantId !== undefined && activeTenantId !== null && isAllowedOrigin(req.url, envConfig)) {
    const clonedRequest = req.clone({
      setHeaders: {
        'X-Tenant-ID': String(activeTenantId),
        'x-tenant-id': String(activeTenantId) // Doble canal de compatibilidad para NodeJS/n8n
      }
    });
    return next(clonedRequest);
  }

  return next(req);
};