import { Injectable } from '@angular/core';

/**
 * Formats a date as YYYY-MM-DD using LOCAL calendar fields (Timezone Armor).
 * `toISOString()` returns the UTC day, which is tomorrow after 18:00 in UTC-6.
 */
export function toLocalDateString(date: Date | string | number = new Date()): string {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

@Injectable({ providedIn: 'root' })
export class DateUtilsService {
  private _todayStrCache: { date: string; value: string } | null = null;

  /** O(1) con memoización por día natural para evitar crear Date en cada acceso */
  get todayStr(): string {
    const today = toLocalDateString();
    if (this._todayStrCache?.date === today) {
      return this._todayStrCache.value;
    }
    this._todayStrCache = { date: today, value: today };
    return this._todayStrCache.value;
  }

  formatToInputDate(date: Date | string): string {
    return toLocalDateString(date);
  }

  /**
   * Construye un Map para lookup O(1) por id. Evita O(n²) cuando se hace
   * find() dentro de bucles (ej. getRoomNumber en tablas).
   */
  buildIdLookupMap<T extends { id: number }, K extends keyof T>(
    items: T[],
    valueKey: K
  ): Map<number, T[K]> {
    const map = new Map<number, T[K]>();
    items.forEach(item => map.set(item.id, item[valueKey]));
    return map;
  }
}
