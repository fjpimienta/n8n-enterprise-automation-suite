import { Injectable, signal, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { tap } from 'rxjs';
import { environment } from '@env/environment';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);
  
  // Signal para saber si estoy logueado
  isAuthenticated = signal<boolean>(!!localStorage.getItem('ph_token'));

  login(credentials: { email: string; password: string }) {
    // Apunta a tu Workflow de Auth (Módulo 01)
    return this.http.post<{ token: string }>(`${environment.apiUrl}/auth/login`, credentials).pipe(
      tap(response => {
        if (response.token) {
          localStorage.setItem('ph_token', response.token);
          this.isAuthenticated.set(true);
          this.router.navigate(['/']); // Ir al Dashboard
        }
      })
    );
  }

  logout() {
    localStorage.removeItem('ph_token');
    this.isAuthenticated.set(false);
    this.router.navigate(['/login']);
  }

  getToken() {
    return localStorage.getItem('ph_token');
  }
}