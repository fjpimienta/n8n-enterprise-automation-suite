import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { environment } from '@env/environment';
import { map } from 'rxjs';

// Definimos interfaces locales para no romper si no existen en core
export interface Company {
  id_company: number;
  company_name: string;
  is_default?: boolean;
}

@Injectable({ providedIn: 'root' })
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl_crud}`; // Ajuste a tu ruta de n8n

  // Signals
  public companies = signal<Company[]>([]);
  public loadingCompanies = signal<boolean>(false);

  /**
   * Carga el catálogo de empresas.
   * NOTA: Este endpoint en n8n debe permitir acceso público (Rol: Public) 
   * o manejar un token de invitado si el usuario no ha iniciado sesión.
   */
  public loadCompanies() {
    this.loadingCompanies.set(true);
    
    // Payload estándar para tu Dynamic CRUD Engine
    const payload = {
      operation: 'getall',
      model: 'companys', // Asegúrate que coincida con tu tabla en Postgres
      // Si n8n requiere filtros, añádelos aquí
    };

    this.http.post<{ data: Company[] }>(`${this.apiUrl}/companys`, payload).subscribe({
      next: (res) => {
        const data = res.data || [];
        // Ordenar alfabéticamente para facilitar la búsqueda visual
        const sorted = data.sort((a, b) => a.company_name.localeCompare(b.company_name));
        this.companies.set(sorted);
        this.loadingCompanies.set(false);
      },
      error: (err) => {
        console.error('Error cargando empresas:', err);
        // Fallback para desarrollo si falla la API (opcional)
        // this.companies.set([{ id_company: 1, company_name: 'Pista Hielo Principal', is_default: true }]); 
        this.loadingCompanies.set(false);
      }
    });
  }
}