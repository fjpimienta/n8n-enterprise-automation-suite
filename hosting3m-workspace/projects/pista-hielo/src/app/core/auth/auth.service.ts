import { jwtDecode } from 'jwt-decode';
import { Injectable, signal, inject, PLATFORM_ID } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '@env/environment'; // Asegúrate que el path sea correcto
import { isPlatformBrowser } from '@angular/common';
import { catchError, tap, throwError } from 'rxjs';

// Interfaz para el Payload del Token
interface UserPayload {
  id: number;
  email: string;
  role: string;
  id_company: number;
  name: string;
}

// Interfaz para la respuesta de la API
interface AuthResponse {
  status: string;
  message: string;
  data: {
    token: string;
    role: string;
    id_company: number;
  }
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);
  private platformId = inject(PLATFORM_ID);
  private apiUrl_token = environment.apiUrl_token;

  // Signals de Estado
  currentUser = signal<UserPayload | null>(this.getUserFromStorage());
  isAuthenticated = signal<boolean>(this.checkTokenExistence());

  login(credentials: { user: string; pass: string }) {
    return this.http.post<AuthResponse>(this.apiUrl_token, credentials).pipe(
      tap(response => {
        if (response.status === 'success' && response.data?.token) {

          const token = response.data.token;

          // 1. Guardar en LocalStorage (USANDO SIEMPRE 'ph_token')
          if (isPlatformBrowser(this.platformId)) {
            localStorage.setItem('ph_token', token);
          }

          // 2. Decodificar y actualizar estado del usuario
          try {
            const decoded = jwtDecode<UserPayload>(token);
            this.currentUser.set(decoded);
          } catch (e) {
            console.warn('Error decodificando token, usando datos crudos');
          }

          // 3. SEÑALIZAR QUE YA ESTÁ LOGUEADO (¡Muy Importante!)
          this.isAuthenticated.set(true);

          // 4. REDIRECCIONAR (La pieza faltante)
          this.router.navigate(['/operations/monitor']);
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

  logout() {
    if (isPlatformBrowser(this.platformId)) {
      localStorage.removeItem('ph_token');
      localStorage.removeItem('ph_user');
    }
    this.isAuthenticated.set(false);
    this.currentUser.set(null);
    this.router.navigate(['/login']);
  }

  getToken(): string | null {
    if (isPlatformBrowser(this.platformId)) {
      // Debe coincidir con lo que guardaste en el login
      return localStorage.getItem('ph_token');
    }
    return null;
  }

  private getUserFromStorage() {
    if (isPlatformBrowser(this.platformId)) {
      const token = localStorage.getItem('ph_token');
      if (token) {
        try {
          return jwtDecode<UserPayload>(token);
        } catch { return null; }
      }
    }
    return null;
  }

  // MEJORA: Esta función ahora valida que el token exista Y que no haya caducado
  private checkTokenExistence(): boolean {
    if (isPlatformBrowser(this.platformId)) {
      const token = localStorage.getItem('ph_token');

      if (!token) return false; // No hay token, fuera.

      try {
        const decoded: any = jwtDecode(token);
        const currentTime = Date.now() / 1000; // Tiempo actual en segundos

        // Si el token tiene campo 'exp' y ya pasó la fecha...
        if (decoded.exp && decoded.exp < currentTime) {
          console.warn('Token expirado, limpiando sesión...');
          this.logout(); // Limpiamos storage
          return false;  // Decimos que NO está autenticado
        }

        return true; // Token existe y es válido en tiempo
      } catch (error) {
        // Si el token es basura y no se puede decodificar
        this.logout();
        return false;
      }
    }
    return false;
  }
}