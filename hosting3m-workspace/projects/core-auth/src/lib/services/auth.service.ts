import { LoggerService } from './logger.service';
import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError, map, Observable, Subject } from 'rxjs';
import { jwtDecode } from 'jwt-decode';

// ✅ Importación consolidada de configuración y contexto
import { AUTH_ENV_CONFIG, CompanyContext } from '../auth.config';
import { TenantService } from './tenant.service';

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
  user?: string;
}

/** Side-effect-free session classification (see `AuthService.getSessionState()`). */
export type SessionState = 'valid' | 'grace' | 'expired';

/** Identity partition key for a future offline store. Never contains the token. */
export interface SessionScope {
  user: string;
  id_company: number;
}

/** Login/logout notification. Carries no token. */
export type SessionEvent =
  | { type: 'login'; scope: SessionScope | null }
  | { type: 'logout' };

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);

  // Inyectamos la configuración del entorno (Desacoplamiento Multi-App)
  private envConfig = inject(AUTH_ENV_CONFIG);
  private apiUrl_token = this.envConfig.apiUrl_token;

  // Inyección de dependencias de utilidades
  private logger = inject(LoggerService);
  private tenantService = inject(TenantService);

  private readonly _currentUser = signal<UserPayload | null>(this.loadUserFromStorage());
  private readonly _isAuthenticated = signal<boolean>(this.hasValidToken());

  readonly currentUser = this._currentUser.asReadonly();
  readonly isAuthenticated = this._isAuthenticated.asReadonly();

  private readonly _sessionEvents = new Subject<SessionEvent>();
  /** Read-only stream of login/logout events. Additive; carries no token. */
  readonly sessionEvents$: Observable<SessionEvent> = this._sessionEvents.asObservable();

  /**
   * Classifies the stored session without side effects: it never calls `logout()`, never
   * refreshes anything and never touches storage. Fail-closed: anything missing, malformed or
   * ambiguous is `'expired'`.
   *
   * - `'valid'`: token not expired (same rule as `getStoredToken()`), with a usable identity.
   * - `'grace'`: token expired, but within `offlineGraceMs` (from `AUTH_ENV_CONFIG`) after `exp`.
   * - `'expired'`: no token, malformed token, missing/invalid `exp`, grace not configured or elapsed,
   *   missing user, malformed JWT `id_company`, or an active tenant that is missing or not in `TenantService.availableTenants()`.
   */
  getSessionState(): SessionState {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token) return 'expired';
    const decoded = this.decodeSafely(token);
    if (!decoded || !this.resolveScope(decoded)) return 'expired';
    const exp = decoded.exp;
    if (typeof exp !== 'number' || !Number.isFinite(exp)) return 'expired';

    const nowMs = Date.now();
    if (exp >= Math.floor(nowMs / 1000)) return 'valid';

    const grace = this.envConfig.offlineGraceMs;
    if (typeof grace === 'number' && Number.isFinite(grace) && grace > 0
      && Math.floor(nowMs / 1000) * 1000 <= exp * 1000 + grace) {
      return 'grace';
    }
    return 'expired';
  }

  /**
   * (user, id_company) of the stored session for partitioning, or `null` when it is missing,
   * malformed or ambiguous. Independent of expiry; combine with `getSessionState()`.
   */
  getSessionScope(): SessionScope | null {
    const token = localStorage.getItem(TOKEN_KEY);
    const decoded = token ? this.decodeSafely(token) : null;
    return decoded ? this.resolveScope(decoded) : null;
  }

  private decodeSafely(token: string): JwtPayload | null {
    try {
      const decoded = jwtDecode<JwtPayload>(token);
      return decoded && typeof decoded === 'object' ? decoded : null;
    } catch {
      return null;
    }
  }

  /** Fail-closed wrapper: any exception while resolving the scope yields `null` (never throws). */
  private resolveScope(decoded: JwtPayload): SessionScope | null {
    try {
      return this.resolveScopeUnsafe(decoded);
    } catch (err) {
      // Log only the error name: never the token, claims or tenant data.
      this.logger.warn('Session scope resolution failed; failing closed', (err as Error)?.name);
      return null;
    }
  }

  private resolveScopeUnsafe(decoded: JwtPayload): SessionScope | null {
    const user = [decoded.user, decoded.email]
      .find((v): v is string => typeof v === 'string' && v.trim().length > 0);
    if (!user) return null;
    // The JWT company is the one chosen at login and is NOT re-issued on a tenant switch, so it
    // only has to be well-formed; it is not the partition key.
    const jwtCompany = decoded.id_company;
    if (typeof jwtCompany !== 'number' || !Number.isInteger(jwtCompany) || jwtCompany <= 0) return null;
    const active = this.tenantService.activeTenantId();
    if (typeof active !== 'number' || !Number.isInteger(active) || active <= 0) return null;
    const isMember = this.tenantService.availableTenants().some(t => t?.id_company === active);
    if (!isMember) return null;
    return { user, id_company: active };
  }

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

      const currentTime = Math.floor(Date.now() / 1000);
      return decoded.exp < currentTime;
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

  /**
   * 🚀 Lógica Multi-Tenant y Multi-App fusionada con Adaptador n8n
   * Permite recibir el id_company opcional durante el paso 2 de selección.
   */
  login(credentials: { user: string; pass: string; id_company?: number | string }) {
    const payload = {
      ...credentials,
      system_id: this.envConfig.system_id
    };

    return this.http.post<any>(this.apiUrl_token, payload).pipe(
      // 🛡️ PATRÓN ADAPTADOR: Normalización del Contrato Multi-Tenant
      map(response => {
        // Meta-CRUD / n8n report failures as HTTP 200 with `error: true` (see #1037): surface them as errors.
        if (response?.error === true) {
          const message = typeof response.message === 'string' && response.message
            ? response.message
            : (typeof response.error_message === 'string' && response.error_message
              ? response.error_message
              : 'El servidor rechazó la solicitud.');
          throw Object.assign(new Error(message), { error: true, body: response });
        }

        // Si n8n envolvió la respuesta estructurada del microservicio dentro de su propio 'data'
        if (response?.data && (response.data.status === 'select_company' || response.data.status === 'success')) {
          return response.data;
        }

        // Caso de uso Legacy: Si viene el formato plano antiguo (Pista de hielo / Contratos anteriores)
        if (response?.data && response.data.token) {
          return {
            status: 'success',
            data: response.data
          };
        }

        return response;
      }),
      tap(res => {
        if (res.status === 'success' && res.data?.token) {
          const token = res.data.token;
          localStorage.setItem(TOKEN_KEY, token);

          const decoded = jwtDecode<any>(token);
          this._currentUser.set(decoded);
          this._isAuthenticated.set(true);
          this._sessionEvents.next({ type: 'login', scope: this.getSessionScope() });
        }
      }),
      catchError(err => throwError(() => err))
    );
  }

  logout(): void {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem('role');
    this._currentUser.set(null);
    this._isAuthenticated.set(false);
    // Fail-closed: sin esto, el siguiente login en el mismo navegador podía heredar
    // el `user_tenants`/`active_tenant_context` de la sesión anterior si esa cuenta
    // tiene una sola empresa (ver incidente de Context Switcher, 2026-10-04).
    this.tenantService.clearContext();
    this._sessionEvents.next({ type: 'logout' });
  }

  hasRole(role: string): boolean {
    const userRole = this._currentUser()?.role;
    return userRole ? userRole.toUpperCase() === role.toUpperCase() : false;
  }
}