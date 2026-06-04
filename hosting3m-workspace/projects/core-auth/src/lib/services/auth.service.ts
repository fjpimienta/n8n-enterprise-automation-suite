import { LoggerService } from './logger.service';
import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError, map } from 'rxjs';
import { jwtDecode } from 'jwt-decode';

// ✅ Importación consolidada de configuración y contexto
import { AUTH_ENV_CONFIG, CompanyContext } from '../auth.config';

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

  // Inyectamos la configuración del entorno (Desacoplamiento Multi-App)
  private envConfig = inject(AUTH_ENV_CONFIG);
  private apiUrl_token = this.envConfig.apiUrl_token;

  // Inyección de dependencias de utilidades
  private logger = inject(LoggerService);

  private readonly _currentUser = signal<UserPayload | null>(this.loadUserFromStorage());
  private readonly _isAuthenticated = signal<boolean>(this.hasValidToken());

  readonly currentUser = this._currentUser.asReadonly();
  readonly isAuthenticated = this._isAuthenticated.asReadonly();

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
  }

  hasRole(role: string): boolean {
    const userRole = this._currentUser()?.role;
    return userRole ? userRole.toUpperCase() === role.toUpperCase() : false;
  }
}