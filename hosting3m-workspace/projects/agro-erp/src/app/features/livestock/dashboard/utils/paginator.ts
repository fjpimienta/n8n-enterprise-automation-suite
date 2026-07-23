import { signal, computed } from '@angular/core';

/**
 * Paginación en memoria basada en signals. Cada instancia mantiene su propio
 * estado (currentPage/pageSize), parametrizada por una función que reporta
 * la longitud del dataset actualmente activo.
 */
export class Paginator {
  public readonly currentPage = signal(1);
  public readonly pageSize = signal(10);

  constructor(private readonly totalItemsFn: () => number) {}

  public readonly totalPages = computed(() => Math.ceil(this.totalItemsFn() / this.pageSize()) || 1);

  public readonly showingStart = computed(() => {
    if (this.totalItemsFn() === 0) return 0;
    return ((this.currentPage() - 1) * this.pageSize()) + 1;
  });

  public readonly showingEnd = computed(() => Math.min(this.currentPage() * this.pageSize(), this.totalItemsFn()));

  public changePageSize(event: Event) {
    this.pageSize.set(Number((event.target as HTMLSelectElement).value));
    this.currentPage.set(1);
  }

  public changePage(delta: number) {
    const newPage = this.currentPage() + delta;
    if (newPage >= 1 && newPage <= this.totalPages()) {
      this.currentPage.set(newPage);
    }
  }

  public reset() {
    this.currentPage.set(1);
  }
}
