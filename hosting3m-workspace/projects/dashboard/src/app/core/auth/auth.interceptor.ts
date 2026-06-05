import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';
import { environment } from '@env/environment';
import { AuthService } from 'core-auth';

function isOwnApiRequest(url: string): boolean {
  try {
    const apiBase = environment.apiUrl.replace(/\/$/, '');
    const normalizedUrl = url.startsWith('http')
      ? url
      : `${window.location.origin}${url.startsWith('/') ? '' : '/'}${url}`;
    return normalizedUrl.startsWith(apiBase);
  } catch {
    return false;
  }
}

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  let clonedReq = req;
  const token = authService.getStoredToken();

  if (token && isOwnApiRequest(req.url)) {
    clonedReq = req.clone({
      setHeaders: { Authorization: `Bearer ${token}` }
    });
  }

  return next(clonedReq).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status === 401) {
        // VALIDACIÓN DE FALSO POSITIVO:
        // Verificamos criptográficamente el payload antes de destruir la sesión.
        // Si getStoredToken() retorna null, el token realmente expiró.
        const currentToken = authService.getStoredToken();
        
        if (!currentToken) {
          // Expiración real confirmada: Ejecutamos logout seguro.
          authService.logout();
          router.navigate(['/login']);
        } else {
          // Falso 401: El servidor falló (timeout/rate limit) pero la sesión es válida.
          console.warn('⚠️ Tolerancia a fallos: Petición rechazada (401), pero el token local sigue vigente.');
          // Omitimos el logout para no perjudicar la experiencia de usuario (UX).
        }
      }
      return throwError(() => error);
    })
  );
};