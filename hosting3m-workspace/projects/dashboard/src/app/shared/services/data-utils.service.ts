import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class DateUtilsService {
  get todayStr(): string {
    return new Date().toISOString().split('T')[0];
  }

  formatToInputDate(date: Date | string): string {
    return new Date(date).toISOString().split('T')[0];
  }
}