import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { AUTH_ENV_CONFIG } from '../auth.config'; // <-- Importa tu token

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);
  const envConfig = inject(AUTH_ENV_CONFIG); // <-- Inyecta la configuración

  let clonedReq = req;
  const token = authService.getStoredToken();

  const protectedApis = [envConfig.apiUrl_crud, envConfig.apiUrl_ai].filter(Boolean);
  const isApiRequest = protectedApis.some(url => req.url.startsWith(url));

  if (token && isApiRequest) {
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