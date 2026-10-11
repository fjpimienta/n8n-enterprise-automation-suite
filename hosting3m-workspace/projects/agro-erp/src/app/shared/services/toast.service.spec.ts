import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ToastService } from './toast.service';

describe('ToastService', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('queues toasts by type and auto-dismisses each one after 5 s', () => {
    const service = new ToastService();
    service.success('Solicitud cancelada');
    vi.advanceTimersByTime(2000);
    service.error('Fallo');

    expect(service.toasts().map(t => [t.type, t.text])).toEqual([['success', 'Solicitud cancelada'], ['error', 'Fallo']]);

    vi.advanceTimersByTime(3000); // first toast reaches 5 s
    expect(service.toasts().map(t => t.text)).toEqual(['Fallo']);

    vi.advanceTimersByTime(2000);
    expect(service.toasts()).toEqual([]);
  });

  it('dismisses a toast manually', () => {
    const service = new ToastService();
    const id = service.info('Hola');
    service.dismiss(id);
    expect(service.toasts()).toEqual([]);
  });
});
