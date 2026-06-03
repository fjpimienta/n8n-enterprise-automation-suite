import { LoggerService } from './logger.service';
import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError, Observable, map } from 'rxjs';
import { jwtDecode } from 'jwt-decode';

// ✅ ÚNICA declaración de CompanyContext (viene de auth.config)
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

  // Inyectamos la configuración del entorno para el desacoplamiento Multi-App
  private envConfig = inject(AUTH_ENV_CONFIG);
  private apiUrl_token = this.envConfig.apiUrl_token;

  // ✅ FIX: Inyección correcta de la instancia del Logger
  private logger = inject(LoggerService);

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
   * Realiza la petición de autenticación integrando el system_id del entorno actual.
   * Puede retornar el token directamente si viene resuelto, o el listado de empresas
   * si el backend requiere que el usuario elija en cuál conectarse.
   */
  login(credentials: { user: string; pass: string }) {
    return this.http.post<any>(this.apiUrl_token, credentials).pipe(
      // 🛡️ PATRÓN ADAPTADOR: Normalizamos la respuesta de n8n
      map(response => {
        // Si detectamos el "doble envoltorio" de n8n (Matryoshka)
        if (response?.data && response.data.status) {
          // ✅ FIX: Llamada correcta a la instancia (this.logger)
          this.logger.log('🔧 Adaptador: Desenvolviendo respuesta de n8n');
          return response.data; // Entregamos solo el núcleo útil
        }
        return response; // Si la respuesta ya es plana, la dejamos pasar
      }),
      // ⬇️ A partir de aquí, 'res' ya es perfectamente plano para el componente y el tap
      tap(res => {
        if (res.status === 'success' && res.data?.token) {
          const token = res.data.token;
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
}