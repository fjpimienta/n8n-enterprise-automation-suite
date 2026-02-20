import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class DateUtilsService {
  private _todayStrCache: { date: string; value: string } | null = null;

  /** O(1) con memoización por día natural para evitar crear Date en cada acceso */
  get todayStr(): string {
    const today = new Date().toISOString().split('T')[0];
    if (this._todayStrCache?.date === today) {
      return this._todayStrCache.value;
    }
    this._todayStrCache = { date: today, value: today };
    return this._todayStrCache.value;
  }

  formatToInputDate(date: Date | string): string {
    return new Date(date).toISOString().split('T')[0];
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
