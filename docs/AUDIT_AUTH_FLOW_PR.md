# 🔐 Audit: Auth Flow Security & Architecture (auth.service | auth.guard | auth.interceptor)

## Executive Summary

| Severity | Finding | Impact |
|----------|---------|--------|
| **CRITICAL** | JWT leak to external origins | Token enviado en TODAS las peticiones HTTP sin validar destino |
| **HIGH** | Desincronización AuthService ↔ Interceptor | Estado inconsistente tras 401; logout en interceptor no notifica al Service |
| **HIGH** | Inconsistencia en validación de roles | `isAdmin()` usa `'admin'` vs `'ADMIN'` en otros componentes |
| **MEDIUM** | Sin validación de expiración de token | Usuario "autenticado" con token expirado |
| **LOW** | `authGuard` no verifica roles | Rutas protegidas sin control RBAC; riesgo de acceso lateral |

**Recomendación:** Aplicar refactor propuesto antes de producción. Los cambios son backward-compatible y no rompen el flujo actual.

---

## Changes Checklist

- [ ] **Interceptor:** Filtrar requests por origen (solo API propia) antes de adjuntar Bearer
- [ ] **Interceptor:** Sincronizar logout con AuthService en respuesta 401
- [ ] **Service:** Centralizar token en un único punto; invalidar estado ante token expirado
- [ ] **Service:** Normalizar roles (case-insensitive o constante única)
- [ ] **Guard:** Añadir roleGuard opcional con lookup O(1) vía `Set`
- [ ] **Guard:** Verificar token no expirado antes de permitir navegación

---

## Deep Technical Details

### 1. Interceptor: Fuga de JWT en peticiones externas

**Problema actual:** El token se adjunta a **cualquier** petición HTTP:

```typescript
if (authToken) {
  clonedReq = req.clone({
    setHeaders: { Authorization: `Bearer ${authToken}` }
  });
}
```

Si se añaden recursos externos (analytics, CDNs, mapas, webhooks de terceros), el JWT se enviará a esos orígenes. **OWASP:** Exposure of sensitive data in logs / third-party scripts.

**Solución:** Comprobar que la URL pertenezca al dominio de la API:

```typescript
const apiOrigin = new URL(environment.apiUrl).origin;
const requestOrigin = new URL(req.url, window.location.origin).origin;
const isOwnApi = requestOrigin === apiOrigin || req.url.startsWith(environment.apiUrl);
```

---

### 2. Service: Vulnerabilidades de estado

| Issue | Descripción |
|-------|-------------|
| **Múltiples fuentes de verdad** | `localStorage` + signals: el interceptor lee `localStorage` directamente y hace `removeItem` en 401 sin avisar al Service |
| **Token expirado** | `isAuthenticated` y `getUserFromStorage` no validan `exp` del JWT |
| **Race condition** | Interceptor limpia `localStorage` → AuthService sigue con `isAuthenticated = true` hasta recarga |

**Solución:** Inyectar AuthService en el interceptor para llamar a `logout()` en 401. El Service debe ser la única fuente de verdad para autenticación.

---

### 3. Guard: Complejidad en verificación de roles

**Estado actual:** El `authGuard` solo verifica `isAuthenticated()`. No existe `roleGuard`.

Si se implementa verificación de roles con `allowedRoles.includes(userRole)`:
- **Big O:** O(n) donde n = número de roles permitidos (típicamente 2–5)
- **Recomendación:** Usar `Set<string>` para lookup O(1):

```typescript
const ALLOWED = new Set(['ADMIN', 'EDITOR']);
return ALLOWED.has(userRole);
```

---

## Testing Protocol

| # | Test | Expected |
|---|------|----------|
| 1 | Request a `https://external-cdn.com/api` → NO debe incluir header `Authorization` | Pass |
| 2 | Request a `environment.apiUrl + 'webhook/...'` → SÍ debe incluir Bearer | Pass |
| 3 | 401 en cualquier request → AuthService.isAuthenticated = false, redirect a /login | Pass |
| 4 | Token expirado en localStorage → isAuthenticated = false, currentUser = null | Pass |
| 5 | roleGuard(['ADMIN']) con user role EDITOR → redirect 403 o /unauthorized | Pass |
| 6 | Login exitoso → signals actualizados, token en localStorage | Pass |
| 7 | Logout → localStorage limpio, signals en estado inicial | Pass |

---

## Senior Checklist

- [ ] Revisar política de CORS en backend para orígenes permitidos
- [ ] Considerar HttpOnly cookies para token (mitiga XSS vs localStorage)
- [ ] Añadir refresh token si la sesión supera 1h
- [ ] Unificar convención de roles (UPPER vs lower) en backend y frontend
- [ ] Documentar en ADR la decisión localStorage vs cookies

---

## Código Refactorizado

### auth.interceptor.ts

```typescript
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
    const normalizedUrl = url.startsWith('http') ? url : `${window.location.origin}${url.startsWith('/') ? '' : '/'}${url}`;
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
```

---

### auth.service.ts

```typescript
import { Injectable, inject, signal, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError } from 'rxjs';
import { jwtDecode } from 'jwt-decode';
import { environment } from '@env/environment';

const TOKEN_KEY = 'authToken';

export interface UserPayload {
  id: number;
  email: string;
  role: string;
  id_company: number;
  name: string;
}

interface JwtPayload extends UserPayload {
  exp?: number;
}

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);
  private apiUrl_token = environment.apiUrl_token;

  private readonly _currentUser = signal<UserPayload | null>(this.loadUserFromStorage());
  private readonly _isAuthenticated = signal<boolean>(this.hasValidToken());

  readonly currentUser = this._currentUser.asReadonly();
  readonly isAuthenticated = this._isAuthenticated.asReadonly();

  /**
   * Única fuente de lectura del token. Usado por el interceptor.
   */
  getStoredToken(): string | null {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token) return null;
    if (this.isTokenExpired(token)) {
      this.logout();
      return null;
    }
    return token;
  }

  private hasValidToken(): boolean {
    const token = localStorage.getItem(TOKEN_KEY);
    return !!token && !this.isTokenExpired(token);
  }

  private isTokenExpired(token: string): boolean {
    try {
      const decoded = jwtDecode<JwtPayload>(token);
      if (!decoded.exp) return false;
      const now = Math.floor(Date.now() / 1000);
      return decoded.exp < now;
    } catch {
      return true;
    }
  }

  private loadUserFromStorage(): UserPayload | null {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token || this.isTokenExpired(token)) return null;
    try {
      const { exp, ...user } = jwtDecode<JwtPayload>(token);
      return user;
    } catch {
      return null;
    }
  }

  login(credentials: { user: string; pass: string }) {
    return this.http.post<any>(this.apiUrl_token, credentials).pipe(
      tap(response => {
        if (response.status === 'success' && response.data?.token) {
          const token = response.data.token;
          localStorage.setItem(TOKEN_KEY, token);
          const decoded = jwtDecode<JwtPayload>(token);
          const { exp, ...user } = decoded;
          this._currentUser.set(user);
          this._isAuthenticated.set(true);
        }
      }),
      catchError(err => {
        if (err.status === 401) {
          return throwError(() => new Error('Credenciales inválidas'));
        }
        return throwError(() => err);
      })
    );
  }

  logout(): void {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem('role');
    this._currentUser.set(null);
    this._isAuthenticated.set(false);
  }

  /** Comparación case-insensitive para evitar inconsistencia admin vs ADMIN */
  hasRole(role: string): boolean {
    const userRole = this._currentUser()?.role;
    return userRole ? userRole.toUpperCase() === role.toUpperCase() : false;
  }

  isAdmin(): boolean {
    return this.hasRole('admin');
  }
}
```

---

### auth.guard.ts

```typescript
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.isAuthenticated()) {
    return true;
  }

  router.navigate(['/login']);
  return false;
};

/**
 * Role guard con lookup O(1) vía Set.
 * Uso: canActivate: [authGuard, roleGuard(['ADMIN', 'EDITOR'])]
 */
export function roleGuard(allowedRoles: readonly string[]): CanActivateFn {
  const allowed = new Set(allowedRoles.map(r => r.toUpperCase()));

  return (route, state) => {
    const authService = inject(AuthService);
    const router = inject(Router);

    if (!authService.isAuthenticated()) {
      router.navigate(['/login']);
      return false;
    }

    const userRole = authService.currentUser()?.role?.toUpperCase();
    if (userRole && allowed.has(userRole)) {
      return true;
    }

    router.navigate(['/unauthorized']);
    return false;
  };
}
```

---

## Migración

1. Añadir ruta `/unauthorized` si se usa `roleGuard`.
2. Actualizar rutas que requieran roles:

```typescript
{
  path: 'personal',
  component: UserListComponent,
  canActivate: [authGuard, roleGuard(['ADMIN'])],
},
```

3. Reemplazar `currentUser()?.role === 'ADMIN'` por `authService.hasRole('ADMIN')` en componentes.
