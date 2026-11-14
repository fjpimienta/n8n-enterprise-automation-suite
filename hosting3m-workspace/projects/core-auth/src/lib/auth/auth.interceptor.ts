import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config'; // <-- Importa tu token
import { isAllowedOrigin, isExemptRoute } from '../allowed-origin';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);
  const envConfig = inject(AUTH_ENV_CONFIG);

  const token = authService.getStoredToken();
  const isApiRequest = isAllowedOrigin(req.url, envConfig);
  const isExempt = isExemptRoute(req.url, envConfig);

  if (!token && isApiRequest && !isExempt) {
    return throwError(() => new HttpErrorResponse({
      status: 401,
      statusText: 'No auth token',
      url: req.url
    }));
  }

  let clonedReq = req;
  if (token && isApiRequest && !isExempt) {
    clonedReq = req.clone({
      setHeaders: { Authorization: `Bearer ${token}` }
    });
  }

  return next(clonedReq).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status === 401) {
        const currentToken = authService.getStoredToken();

        if (!currentToken) {
          authService.logout();
          router.navigate(['/login']);
        } else {
          console.warn('⚠️ Tolerancia a fallos: Petición rechazada (401), pero el token local sigue vigente.');
        }
      }
      return throwError(() => error);
    })
  );
};