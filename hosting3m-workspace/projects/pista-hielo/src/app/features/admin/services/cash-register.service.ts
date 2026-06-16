import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment';
import { map } from 'rxjs';
import { PhTransaction } from '@core/models/transaction.types';

@Injectable({ providedIn: 'root' })
export class CashRegisterService {
  private http = inject(HttpClient);
  // Ajusta esto según tu environment real
  private apiUrl = `${environment.apiUrl_crud}/transactions`;

  // Signals para el reporte
  public todayTransactions = signal<PhTransaction[]>([]);
  public summary = signal({ cash: 0, card: 0, total: 0, count: 0 });

  loadDailyReport() {
    // Genera fecha formato YYYY-MM-DD
    const localDate = new Date().toLocaleDateString('sv-SE');

    // console.log('📅 Consultando fecha:', localDate); // DEBUG: Ver qué fecha enviamos

    return this.http.post<{ data: PhTransaction[] }>(this.apiUrl, {
      operation: 'getall',
      model: 'transactions',
      filters: {
        // Envolvemos en _eq para activar la lógica de fecha en n8n
        transaction_date: { _eq: localDate },
        status: 'FIN'
      }
    }).pipe(
      map(res => res.data || [])
    ).subscribe({
      next: (data) => {
        // console.log('✅ Datos recibidos:', data.length, 'registros'); // DEBUG

        // ¡ESTO FALTABA! Actualizar los signals para que la pantalla cambie
        this.todayTransactions.set(data);
        this.calculateTotals(data);
      },
      error: (err) => console.error('❌ Error cargando corte:', err)
    });
  }

  private calculateTotals(data: PhTransaction[]) {
    const cash = data
      .filter(t => t.payment_method === 'CASH')
      .reduce((acc, curr) => acc + Number(curr.amount), 0);

    const card = data
      .filter(t => t.payment_method === 'CARD')
      .reduce((acc, curr) => acc + Number(curr.amount), 0);

    this.summary.set({
      cash,
      card,
      total: cash + card,
      count: data.length
    });
  }
}