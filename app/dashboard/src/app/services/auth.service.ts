import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError } from 'rxjs';
import { jwtDecode } from 'jwt-decode';
import { environment } from '../../environments/environment';

interface UserPayload {
  id: number;
  email: string;
  role: string;
  id_company: number;
  name: string;
}

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl; // URL de n8n: v2/genera-token

  // Usamos un Signal para el estado del usuario (Angular 21 style)
  currentUser = signal<UserPayload | null>(this.getUserFromStorage());

  isLoggedIn(): boolean {
    return !!localStorage.getItem('authToken');
  }

  private getUserFromStorage(): UserPayload | null {
    const token = localStorage.getItem('authToken');
    if (!token) return null;
    try {
      return jwtDecode<UserPayload>(token);
    } catch {
      return null;
    }
  }

  login(credentials: { user: string; pass: string }) {
    return this.http.post<any>(this.apiUrl, credentials).pipe(
      tap(response => {
        // Usamos la estructura que definimos en n8n: { status, data, message }
        if (response.status === 'success' && response.data?.token) {
          localStorage.setItem('authToken', response.data.token);
          const decoded = jwtDecode<UserPayload>(response.data.token);
          this.currentUser.set(decoded);
        }
      }),
      catchError(err => {
        // Si n8n responde 401, lanzamos un error con mensaje personalizado
        if (err.status === 401) {
          return throwError(() => new Error('Credenciales inválidas'));
        }
        // Si es otro error (500, 404), pasamos el error original
        return throwError(() => err);
      })
    );
  }

  logout() {
    localStorage.removeItem('token');
    localStorage.removeItem('role');
    this.currentUser.set(null);
  }

  isAdmin(): boolean {
    return this.currentUser()?.role === 'admin';
  }
}