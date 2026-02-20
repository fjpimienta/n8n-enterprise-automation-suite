import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';
import { environment } from '@env/environment';
import { AuthService } from '../services/auth.service';

/**
 * Adjunta JWT solo a peticiones hacia la API propia.
 * Previene fugas de token a orígenes externos (CDNs, analytics, etc.).
 */
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
        authService.logout();
        router.navigate(['/login']);
      }
      return throwError(() => error);
    })
  );
};
