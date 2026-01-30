import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { PhInstructor } from '@core/models/instructor.types';
import { firstValueFrom } from 'rxjs';
import { PhClient } from '@core/models/client.types';

@Injectable({
  providedIn: 'root'
})
export class InstructorService {
  private http = inject(HttpClient);
  private apiUrl = `${(environment as any).apiUrl_crud}/ph_instructores` || `${environment.apiUrl_crud}/webhook/46c903ec-0397-43ea-b99e-2606f8e4f0de/crud/v3/ph_instructores`;

  // Estado Reactivo
  instructors = signal<PhInstructor[]>([]);
  isLoading = signal<boolean>(false);

  async loadInstructors() {
    this.isLoading.set(true);
    try {
      // Petición al Dynamic CRUD Engine de n8n
      const response = await firstValueFrom(
        this.http.post<{ data: PhInstructor[] }>(this.apiUrl, {
          operation: 'getall',
          model: 'ph_clients', // Nombre de la tabla en BD
          where: { status: 'ACT', client_category: 'ALUMNO' }
        })
      );
      // Actualizamos el Signal con datos reales
      this.instructors.set(response.data || []);

    } catch (error) {
      console.error('❌ Error sincronizando alumnos:', error);
      // Opcional: Mostrar un toast de error aquí
    } finally {
      this.isLoading.set(false);
    }
  }

  loadInstructors_delete() {
    this.isLoading.set(true);

    this.http.get<PhInstructor[]>(this.apiUrl).subscribe({
      next: (data) => {
        // Ordenamos alfabéticamente
        const sorted = data.sort((a, b) => a.full_name.localeCompare(b.full_name));
        this.instructors.set(sorted);
        this.isLoading.set(false);
      },
      error: (err) => {
        console.error('Error cargando instructores', err);
        this.isLoading.set(false);
      }
    });
  }

  // Helper para etiquetas de especialidad
  getSpecialtyLabel(type: string): { label: string, color: string } {
    switch (type) {
      case 'ARTISTICO': return { label: '⛸️ Artístico', color: 'bg-purple-lt' };
      case 'HOCKEY': return { label: '🏒 Hockey', color: 'bg-azure-lt' };
      case 'STAFF': return { label: '🛡️ Staff', color: 'bg-orange-lt' };
      default: return { label: '🎓 Básico', color: 'bg-blue-lt' };
    }
  }
}