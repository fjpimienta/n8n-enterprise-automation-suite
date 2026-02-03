import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@env/environment'; // Asegúrate que tu alias @environments funcione, si no usa '../environments/environment'
import { map } from 'rxjs';
import { PhTransaction } from '@core/models/transaction.types';

@Injectable({ providedIn: 'root' })
export class CashRegisterService {
  private http = inject(HttpClient);
  // Usamos la misma API de transacciones o la específica de CRUD
  private apiUrl = `${(environment as any).apiUrl_crud}/transactions` || `${environment.apiUrl_crud}/webhook/46c903ec-0397-43ea-b99e-2606f8e4f0de/crud/v3/transactions`;

  // Signals para el reporte
  public todayTransactions = signal<PhTransaction[]>([]);
  public summary = signal({ cash: 0, card: 0, total: 0, count: 0 });

  /**
   * Obtiene todas las ventas FINALIZADAS de HOY
   */
  loadDailyReport() {
    // Usamos 'sv-SE' (formato sueco) que es el estándar ISO local para evitar problemas de zona horaria (UTC vs Mexico)
    const localDate = new Date().toLocaleDateString('sv-SE');

    return this.http.post<{ data: PhTransaction[] }>(this.apiUrl, {
      operation: 'getall',
      model: 'transactions',
      filters: {
        // 3. Usamos sintaxis de Objeto {_eq} para entrar al bloque "Inteligente" de n8n
        // Esto generará en SQL: WHERE transaction_date::date = '2026-01-26'::date
        transaction_date: localDate,
        status: 'FIN'
      }
    }).pipe(
      map(res => res.data || [])
    ).subscribe({
      next: (data) => {
        this.todayTransactions.set(data);
        this.calculateTotals(data);
      },
      error: (err) => console.error('Error cargando corte:', err)
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