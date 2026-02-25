import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { BookingService } from '@features/booking/services/booking.service';
import { ReportService } from '@features/finance/services/report.service';

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

  // 👇 FORZAMOS Number(id) PARA EVITAR EL "N/A"
  getRoomStatus(id: any) {
    return this.roomStatusMap().get(Number(id)) ?? { text: 'N/A', badge: 'bg-secondary-lt' };
  }

  getRoomNumber(id: any): string {
    return this.roomNumberMap().get(Number(id)) ?? 'N/A';
  }

  // 👇 FILTRAMOS LAS CANCELADAS ANTES DE QUE ENTREN A LAS MATEMÁTICAS
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

  // Helpers UI
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

  printReport() {
    window.print();
  }
}
