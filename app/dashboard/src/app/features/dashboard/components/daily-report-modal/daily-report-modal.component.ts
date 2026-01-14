import { Component, input, output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-daily-report-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './daily-report-modal.component.html',
  styleUrl: './daily-report-modal.component.css',
})
export class DailyReportModalComponent {
  // --- Inputs con tipado fuerte ---
  isOpen = input.required<boolean>();
  reportData = input.required<{
    total: number;
    paid: number;
    pending: number;
    transactions: any[];
    periodLabel: string;
  }>();
  currentFilter = input.required<'day' | 'week' | 'month' | 'year'>();
  roomsList = input.required<any[]>();

  // --- Outputs ---
  onClose = output<void>();
  onFilterChange = output<'day' | 'week' | 'month' | 'year'>();

  // --- Helpers de visualización ---
  getRoomNumber(id: number): string {
    const found = this.roomsList().find((r: any) => r.id === id);
    return found ? found.room_number : '??';
  }

  getNights(checkIn: string, checkOut: string): number {
    if (!checkIn || !checkOut) return 1;
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diffTime = Math.abs(end.getTime() - start.getTime());
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 1 : diffDays;
  }
}