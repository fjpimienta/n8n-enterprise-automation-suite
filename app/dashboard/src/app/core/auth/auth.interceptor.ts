// auth.interceptor.ts (Mejorado)
import { inject } from '@angular/core';
import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authToken = localStorage.getItem('authToken');
  const router = inject(Router);

  let clonedReq = req;
  if (authToken) {
    clonedReq = req.clone({
      setHeaders: { Authorization: `Bearer ${authToken}` }
    });
  }

  return next(clonedReq).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status === 401) {
        // authToken inválido o expirado
        localStorage.removeItem('authToken');
        router.navigate(['/login']);
      }
      return throwError(() => error);
    })
  );
};