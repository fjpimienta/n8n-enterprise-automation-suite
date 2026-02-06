import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, tap, throwError } from 'rxjs';
import { jwtDecode } from 'jwt-decode';
import { environment } from '@env/environment';

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
  private apiUrl_token = environment.apiUrl_token;

  // CORRECCIÓN 1: Usar la misma llave 'authToken' para inicializar
  isAuthenticated = signal<boolean>(!!localStorage.getItem('authToken'));

  currentUser = signal<UserPayload | null>(this.getUserFromStorage());

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
    return this.http.post<any>(this.apiUrl_token, credentials).pipe(
      tap(response => {
        if (response.status === 'success' && response.data?.token) {
          const token = response.data.token;
          
          // Guardamos en LocalStorage
          localStorage.setItem('authToken', token);
          
          // Decodificamos usuario
          const decoded = jwtDecode<UserPayload>(token);
          this.currentUser.set(decoded);

          // CORRECCIÓN 2: ¡Avisar a la app que ya estamos logueados!
          this.isAuthenticated.set(true); 
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
    localStorage.removeItem('authToken');
    localStorage.removeItem('role'); // Si usas esto
    
    // CORRECCIÓN 3: Limpiar estado reactivo
    this.currentUser.set(null);
    this.isAuthenticated.set(false); 
  }

  isAdmin(): boolean {
    return this.currentUser()?.role === 'admin';
  }
}