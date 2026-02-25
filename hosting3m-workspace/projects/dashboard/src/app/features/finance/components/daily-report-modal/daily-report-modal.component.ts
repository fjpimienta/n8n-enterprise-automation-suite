import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { BookingService } from '@features/booking/services/booking.service';
import { ReportService } from '@features/finance/services/report.service';
// 👇 NUEVAS IMPORTACIONES
import { PdfExportConfig, PdfExportService } from 'ui-pdf-export';

@Component({
  selector: 'app-daily-report-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './daily-report-modal.component.html',
  styleUrl: './daily-report-modal.component.css',
})
export class DailyReportModalComponent implements OnInit {
  private reportService = inject(ReportService);
  private bookingService = inject(BookingService);
  private pdfService = inject(PdfExportService); // 👈 INYECTAMOS LA LIBRERÍA

  // Estados
  isLoading = signal(true);

  private rawBookings = signal<any[]>([]);
  private rawExpenses = signal<any[]>([]);

  currentFilter = signal<'day' | 'week' | 'month' | 'year'>('day');
  activeTab = signal<'ingresos' | 'gastos'>('ingresos');

  /** Map O(1) para lookup room_id → room_number */
  roomNumberMap = computed(() => {
    const map = new Map<number, string>();
    this.bookingService.rooms().forEach(r => map.set(Number(r.id), r.room_number));
    return map;
  });

  roomStatusMap = computed(() => {
    const map = new Map<number, { text: string, badge: string }>();
    this.bookingService.rooms().forEach(r => {
      if (r.status === 'maintenance') {
        map.set(Number(r.id), { text: 'MANTENIMIENTO', badge: 'bg-blue-lt' });
      } else if (r.status === 'occupied') {
        map.set(Number(r.id), { text: 'OCUPADA', badge: 'bg-red-lt' });
      } else if (r.cleaning_status === 'dirty') {
        map.set(Number(r.id), { text: 'SUCIA', badge: 'bg-orange-lt' });
      } else {
        map.set(Number(r.id), { text: 'DISPONIBLE', badge: 'bg-green-lt' });
      }
    });
    return map;
  });

  getRoomStatus(id: any) {
    return this.roomStatusMap().get(Number(id)) ?? { text: 'N/A', badge: 'bg-secondary-lt' };
  }

  getRoomNumber(id: any): string {
    return this.roomNumberMap().get(Number(id)) ?? 'N/A';
  }

  reportData = computed(() => {
    const validBookings = this.rawBookings().filter(b => b.status !== 'cancelled');
    return this.reportService.calculateDailyReport(
      validBookings,
      this.rawExpenses(),
      this.currentFilter()
    );
  });

  ngOnInit() {
    if (this.bookingService.rooms().length === 0) {
      this.bookingService.loadRooms();
    }
    this.loadData();
  }

  async loadData() {
    this.isLoading.set(true);
    try {
      const [bookings, expenses] = await Promise.all([
        this.reportService.getRawBookingsForReport(),
        this.reportService.getRawExpensesForReport()
      ]);
      this.rawBookings.set(bookings);
      this.rawExpenses.set(expenses);
    } catch (error) {
      console.error('Error cargando datos financieros:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  setFilter(f: 'day' | 'week' | 'month' | 'year') {
    this.currentFilter.set(f);
  }

  getNights(checkIn: string, checkOut: string): number {
    if (!checkIn || !checkOut) return 1;
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diffDays = Math.ceil(Math.abs(end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 1 : diffDays;
  }

  // 👇 NUEVO HELPER PARA ETIQUETAS DEL PDF
  private getPeriodLabel(): string {
    const labels: Record<string, string> = { 'day': 'Día Actual', 'week': 'Semana Actual', 'month': 'Mes Actual', 'year': 'Año Actual' };
    return labels[this.currentFilter()] || 'Periodo';
  }

  // 👇 FUNCIÓN REESCRITA PARA USAR LA LIBRERÍA PDF
  printReport() {
    const stats = this.reportData();
    const currentTab = this.activeTab();
    const period = this.getPeriodLabel();

    let reportItems: any[] = [];
    let reportTitle = '';

    // MAPEO CONDICIONAL: Dependiendo de la pestaña activa, mapeamos ingresos o gastos
    if (currentTab === 'ingresos') {
      reportTitle = `REPORTE DE INGRESOS - ${period.toUpperCase()}`;

      if (stats.transactions.length === 0) {
        alert('No hay ingresos en este periodo para imprimir.');
        return;
      }

      stats.transactions.forEach((t: any) => {
        reportItems.push({
          concept: `Habitación ${this.getRoomNumber(t.room_id)}`,
          description: `Ingreso: ${new Date(t.check_in).toLocaleDateString()} | Noches: ${this.getNights(t.check_in, t.check_out)} | Estado: ${t.payment_status === 'paid' ? 'PAGADO' : 'PENDIENTE'}`,
          quantity: 1,
          unitPrice: Number(t.total_amount) || 0,
          total: Number(t.total_amount) || 0
        });
      });
    } else {
      reportTitle = `REPORTE DE GASTOS - ${period.toUpperCase()}`;

      if (stats.expenseTransactions.length === 0) {
        alert('No hay gastos en este periodo para imprimir.');
        return;
      }

      stats.expenseTransactions.forEach((ex: any) => {
        reportItems.push({
          concept: ex.category || 'Gasto Operativo',
          description: `${ex.description} | Registró: ${ex.registered_by_name}`,
          quantity: 1,
          unitPrice: Number(ex.amount) || 0,
          total: Number(ex.amount) || 0
        });
      });
    }

    // CONFIGURACIÓN DEL PDF
    const pdfConfig: PdfExportConfig = {
      fileName: `Corte_${currentTab}_${period.replace(' ', '_')}`,
      title: reportTitle,
      companyName: 'Hotel San José',
      companyAddress: 'Av. Juarez s/n, Centro, Catazajá, Chiapas',
      clientName: 'Reporte Financiero Interno',
      clientSubtitle: 'Departamento de Contabilidad',
      items: reportItems,

      showTaxes: false,
      showTotals: false,
      showValidity: false,

      footerTitle: 'Resumen Global del Periodo',
      footerText: [
        `Ingresos Cobrados: $${stats.paid_in.toFixed(2)}`,
        `Pendiente de Cobro: $${stats.pending.toFixed(2)}`,
        `Gastos Totales: $${stats.total_expenses.toFixed(2)}`,
        `UTILIDAD NETA: $${stats.balance.toFixed(2)}`
      ]
    };

    // GENERACIÓN
    this.pdfService.generate(pdfConfig);
  }
}