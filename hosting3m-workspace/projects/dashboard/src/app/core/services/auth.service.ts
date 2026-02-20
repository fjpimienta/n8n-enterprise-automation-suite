import { Injectable, inject, signal } from '@angular/core';
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
