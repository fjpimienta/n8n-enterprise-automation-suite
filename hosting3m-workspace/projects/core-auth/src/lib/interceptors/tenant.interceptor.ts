import { inject } from '@angular/core';
import { HttpInterceptorFn } from '@angular/common/http';
import { TenantService } from '../services/tenant.service'; // 🎯 Ruta relativa corregida

export const tenantInterceptor: HttpInterceptorFn = (req, next) => {
  const tenantService = inject(TenantService);
  const activeTenantId = tenantService.activeTenantId(); // Lectura reactiva del Signal

  if (activeTenantId !== undefined && activeTenantId !== null) {
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