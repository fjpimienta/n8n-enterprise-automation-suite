import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';
import { environment } from '@env/environment';
import { AuthService } from '../services/auth.service';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  let clonedReq = req;
  const token = authService.getStoredToken();

  // 🛠️ FIX: Validamos usando la variable correcta de tu entorno (apiUrl_crud)
  const isApiRequest = req.url.startsWith(environment.apiUrl_crud);

  // Si tenemos token y la URL va hacia nuestro n8n, inyectamos los headers
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
          // El token realmente caducó
          authService.logout();
          router.navigate(['/login']);
        } else {
          // El servidor rechazó, pero el token vive
          console.warn('⚠️ Tolerancia a fallos: Petición rechazada (401), pero el token local sigue vigente.');
        }
      }
      return throwError(() => error);
    })
  );
};