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

  /** Map O(1) para lookup room_id → room_number; evita O(n²) en tabla de ingresos */
  roomNumberMap = computed(() => {
    const map = new Map<number, string>();
    this.bookingService.rooms().forEach(r => map.set(r.id, r.room_number));
    return map;
  });

  ngOnInit() {
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

  reportData = computed(() => {
    return this.reportService.calculateDailyReport(
      this.rawBookings(),
      this.rawExpenses(),
      this.currentFilter()
    );
  });

  // Helpers UI
  setFilter(f: 'day' | 'week' | 'month' | 'year') {
    this.currentFilter.set(f);
  }

  getRoomNumber(id: number): string {
    return this.roomNumberMap().get(id) ?? 'N/A';
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
