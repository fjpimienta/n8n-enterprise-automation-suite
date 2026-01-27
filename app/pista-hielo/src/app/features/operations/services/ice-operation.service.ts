import { Injectable, signal, inject, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { PhTransaction } from '@core/models/pista.types';
import { firstValueFrom, tap } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class IceOperationsService {
  private http = inject(HttpClient);

  // Usamos la URL específica del Webhook CRUD definida en tu script de Plesk
  // Si en environment no existe 'apiUrl_crud', usa 'apiUrl' como fallback
  private apiUrl = `${(environment as any).apiUrl_crud}/transactions` || `${environment.apiUrl_crud}/webhook/46c903ec-0397-43ea-b99e-2606f8e4f0de/crud/v3/transactions`;

  // Estado reactivo central
  private skatersSignal = signal<PhTransaction[]>([]);
  public isLoading = signal<boolean>(false);

  // Selector: Filtra solo los que están en estatus ACT (Activos en pista)
  public activeSkaters = computed(() =>
    this.skatersSignal().filter(s => s.status === 'ACT')
  );

  /**
   * Obtiene la lista real de patinadores desde PostgreSQL
   */
  async fetchActiveSkaters() {
    this.isLoading.set(true);
    try {
      // Petición al Dynamic CRUD Engine de n8n
      const response = await firstValueFrom(
        this.http.post<{ data: PhTransaction[] }>(this.apiUrl, {
          operation: 'getall',
          model: 'transactions', // Nombre de la tabla en BD
          where: { status: 'ACT' }
        })
      );

      // Actualizamos el Signal con datos reales
      this.skatersSignal.set(response.data || []);

    } catch (error) {
      console.error('❌ Error sincronizando pista:', error);
      // Opcional: Mostrar un toast de error aquí
    } finally {
      this.isLoading.set(false);
    }
  }

  /**
   * Registra una nueva entrada (Check-in)
   */
  startSession(payload: { skate_number: string; client_type: 'GENERAL' | 'ALUMNO'; notes?: string }) {
    // Calculamos la hora actual HH:MM:SS
    const now = new Date();
    const timeString = now.toTimeString().split(' ')[0];
    const dateString = now.toISOString().split('T')[0];

    return this.http.post<{ status: string, data: any }>(
      this.apiUrl,
      {
        operation: 'insert',
        model: 'transactions',
        fields: {
          transaction_type: 'RENTAL',
          status: 'ACT',
          transaction_date: dateString,
          start_time: timeString,

          metadata: {
            skate_number: payload.skate_number,
            client_type: payload.client_type,
            notes: payload.notes || ''
          }
        }
      }
    ).pipe(
      // Optimistic Update: Al insertar, recargamos la lista inmediatamente
      tap(() => this.fetchActiveSkaters())
    );
  }

  /**
   * Cierra la sesión (Cobro y Salida)
   */
  closeSession(payload: { transactionId: number; endTime: string; finalAmount: number; paymentMethod: string }) {
    return this.http.post<{ status: string; data: any }>(
      this.apiUrl,
      {
        operation: 'update',
        model: 'transactions',
        id: payload.transactionId,
        fields: {
          status: 'FIN', 
          end_time: payload.endTime,
          amount: payload.finalAmount,
          payment_method: payload.paymentMethod
        }
      }
    ).pipe(
      // Al cobrar, recargamos la lista para que el patín desaparezca del monitor
      tap(() => this.fetchActiveSkaters())
    );
  }
}