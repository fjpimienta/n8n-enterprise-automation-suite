import { Injectable, inject, signal } from '@angular/core'; // <--- CORREGIDO: Injectable
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { PhClient } from '@core/models/client.types';
import { firstValueFrom } from 'rxjs';

@Injectable({ // <--- CORREGIDO: Era @Component, debe ser @Injectable
  providedIn: 'root'
})
export class ClientService {
  private http = inject(HttpClient);
  private apiUrl = `${(environment as any).apiUrl_crud}/ph_clients` || `${environment.apiUrl_crud}/webhook/46c903ec-0397-43ea-b99e-2606f8e4f0de/crud/v3/ph_clients`;

  // --- STATE (Signals) ---
  clients = signal<PhClient[]>([]);
  isLoading = signal<boolean>(false);

  // --- ACTIONS ---
  async loadStudents() {
    this.isLoading.set(true);
    try {
      // Petición al Dynamic CRUD Engine de n8n
      const response = await firstValueFrom(
        this.http.post<{ data: PhClient[] }>(this.apiUrl, {
          operation: 'getall',
          model: 'ph_clients', // Nombre de la tabla en BD
          where: { status: 'ACT', client_category: 'ALUMNO' }
        })
      );
      // Actualizamos el Signal con datos reales
      this.clients.set(response.data || []);

    } catch (error) {
      console.error('❌ Error sincronizando alumnos:', error);
      // Opcional: Mostrar un toast de error aquí
    } finally {
      this.isLoading.set(false);
    }
  }

  isMembershipExpired(expiryDate?: string): boolean {
    if (!expiryDate) return true;
    const today = new Date();
    const expiry = new Date(expiryDate);
    return expiry < today;
  }
}