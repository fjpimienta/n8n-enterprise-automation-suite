import { Injectable, signal } from '@angular/core';

export type ToastType = 'success' | 'error' | 'info';

export interface Toast {
  id: number;
  type: ToastType;
  text: string;
}

/**
 * App-wide, non-blocking notifications (replaces native `alert()`). Rendered once by
 * `ToastContainerComponent` in the main layout; each toast dismisses itself after 5 s.
 */
@Injectable({ providedIn: 'root' })
export class ToastService {
  static readonly DURATION_MS = 5000;

  private readonly _toasts = signal<Toast[]>([]);
  readonly toasts = this._toasts.asReadonly();
  private nextId = 1;

  success(text: string): number {
    return this.show('success', text);
  }

  error(text: string): number {
    return this.show('error', text);
  }

  info(text: string): number {
    return this.show('info', text);
  }

  show(type: ToastType, text: string, durationMs = ToastService.DURATION_MS): number {
    const id = this.nextId++;
    this._toasts.update(list => [...list, { id, type, text }]);
    setTimeout(() => this.dismiss(id), durationMs);
    return id;
  }

  dismiss(id: number): void {
    this._toasts.update(list => list.filter(t => t.id !== id));
  }
}
