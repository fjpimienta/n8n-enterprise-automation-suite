import { Component, Input, input, output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-daily-report-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './daily-report-modal.component.html',
  styleUrl: './daily-report-modal.component.css',
})
export class DailyReportModalComponent {
  @Input() isLoading: boolean = false;

  // Inputs requeridos actualizados
  isOpen = input.required<boolean>();
  currentFilter = input.required<'day' | 'week' | 'month' | 'year'>();
  roomsList = input.required<any[]>();

  // 🔥 AQUÍ ESTABA EL DETALLE: Actualizamos la estructura de datos
  reportData = input.required<{
    total_sales: number;     // Ventas totales
    paid_in: number;         // Cobrado real
    pending: number;         // Por cobrar
    total_expenses: number;  // Gastos (Nuevo)
    balance: number;         // Utilidad (Nuevo)
    transactions: any[];     // Lista Ventas
    expenseTransactions: any[]; // Lista Gastos (Nuevo)
    periodLabel: string;
  }>();

  activeTab = signal<'ingresos' | 'gastos'>('ingresos');

  // Outputs
  onClose = output<void>();
  onFilterChange = output<'day' | 'week' | 'month' | 'year'>();

  // Helpers
  getRoomNumber(id: number): string {
    const found = this.roomsList()?.find((r: any) => r.id === id);
    return found ? found.room_number : 'Unknown';
  }

  getNights(checkIn: string, checkOut: string): number {
    if (!checkIn || !checkOut) return 1;
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diffDays = Math.ceil(Math.abs(end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 1 : diffDays;
  }

  printReport() {
    window.print();
  }
}