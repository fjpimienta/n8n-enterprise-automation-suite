import { Injectable } from '@angular/core';

@Injectable({
  providedIn: 'root',
})
export class ReportService {
  calculateDailyReport(bookings: any[], filter: 'day' | 'week' | 'month' | 'year') {
    const now = new Date();
    const todayStr = this.getLocalDateString(now);

    const filtered = bookings.filter((b: any) => {
      if (!b.created_at) return false;
      const createdDate = new Date(b.created_at);
      const createdStr = this.getLocalDateString(createdDate);

      switch (filter) {
        case 'day': return createdStr === todayStr;
        case 'week':
          const weekAgo = new Date();
          weekAgo.setDate(now.getDate() - 7);
          return createdDate >= weekAgo;
        case 'month':
          return createdDate.getMonth() === now.getMonth() && createdDate.getFullYear() === now.getFullYear();
        case 'year':
          return createdDate.getFullYear() === now.getFullYear();
        default: return createdStr === todayStr;
      }
    });

    const stats = { total: 0, paid: 0, pending: 0, transactions: filtered };

    filtered.forEach(b => {
      const amount = parseFloat(b.total_amount || 0);
      stats.total += amount;
      if (b.payment_status === 'paid') stats.paid += amount;
      else stats.pending += amount;
    });

    return stats;
  }

  private getLocalDateString(date: Date): string {
    const offset = date.getTimezoneOffset();
    const localDate = new Date(date.getTime() - (offset * 60 * 1000));
    return localDate.toISOString().split('T')[0];
  }
}
