import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { TenantService } from '../services/tenant.service'; // Ajusta la ruta a tu estructura

export const tenantInterceptor: HttpInterceptorFn = (req, next) => {
  const tenantService = inject(TenantService);
  const activeTenantId = tenantService.activeTenantId();

  // Si hay un tenant activo en el sistema, clonamos la petición e inyectamos la cabecera
  if (activeTenantId) {
    const clonedRequest = req.clone({
      setHeaders: {
        'X-Tenant-ID': String(activeTenantId)
      }
    });
    return next(clonedRequest);
  }

  return next(req);
};