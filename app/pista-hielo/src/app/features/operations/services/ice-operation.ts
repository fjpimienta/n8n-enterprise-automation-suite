import { Injectable, signal, inject, computed } from '@angular/core'; // Corrección de import
import { HttpClient } from '@angular/common/http';
import { PhTransaction } from '@core/models/pista.types';
//import { environment } from '@env/environment';
// import { firstValueFrom } from 'rxjs'; // Lo usaremos luego

@Injectable({ providedIn: 'root' })
export class IceOperationsService {
  private http = inject(HttpClient);
  
  // Estado reactivo
  private skatersSignal = signal<PhTransaction[]>([]);
  isLoading = signal<boolean>(false);

  // Computado: Filtra solo los activos
  activeSkaters = computed(() => 
    this.skatersSignal().filter(s => s.status === 'ACT')
  );

  async fetchActiveSkaters() {
    this.isLoading.set(true);
    
    // --- MODO MOCK (Para validar diseño) ---
    // Simulamos un delay de red de 500ms
    setTimeout(() => {
      this.skatersSignal.set(this.getMockData());
      this.isLoading.set(false);
    }, 800);

    // --- MODO REAL (Descomentar cuando tengamos Login) ---
    /*
    try {
      const response = await firstValueFrom(
        this.http.post<{data: PhTransaction[]}>(`${environment.apiUrl}/crud/v2/transactions`, {
          operation: 'getall',
          model: 'transactions',
          where: { status: 'ACT' }
        })
      );
      this.skatersSignal.set(response.data || []);
    } catch (e) {
      console.error('Error fetching data', e);
    } finally {
      this.isLoading.set(false);
    }
    */
  }

  // Datos falsos que imitan tu DB PostgreSQL
  private getMockData(): PhTransaction[] {
    return [
      {
        id: 101,
        client_id: 0,
        amount: 80,
        transaction_type: 'RENTAL',
        status: 'ACT',
        start_time: '6:30', // Hace rato
        metadata: { skate_number: '24', client_name: 'Juan Perez (General)' }
      },
      {
        id: 102,
        client_id: 50,
        amount: 0,
        transaction_type: 'CLASS',
        status: 'ACT',
        start_time: '7:15', // Reciente
        metadata: { skate_number: '30', client_name: 'Maria (Alumna)', instructor: 'Pedro' }
      },
      {
        id: 103,
        client_id: 0,
        amount: 80,
        transaction_type: 'RENTAL',
        status: 'ACT',
        start_time: '5:00', // Tiempo excedido
        metadata: { skate_number: '28', client_name: 'Visitante' }
      }
    ];
  }
}