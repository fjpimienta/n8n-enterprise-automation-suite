import { signal, computed, linkedSignal, Signal, WritableSignal } from '@angular/core';
import { normalizeForSearch } from './text-normalize.util';

/**
 * Pagination standard for agro-erp tables — cattle-event-log remains the reference for
 * sort/grouping/CSV; those stay component-owned computeds feeding a plain array into this
 * class, same separation of concerns the existing `Paginator` already had. Search is the one
 * exception: it's owned here (see `SearchConfig`) so every table gets the same normalized,
 * accent-insensitive matching for free instead of each one hand-rolling its own.
 *
 * Reset-on-change is a `linkedSignal`, not an `effect()`: `currentPage` behaves like a
 * `computed` that recalculates to 1 whenever a reactive signal read inside its computation
 * changes (the consumer's `resetKeyFn()` — filters, activeTenantId, whatever they compose —
 * AND the internal search query, read in the same computation so a search edit resets the
 * page through the exact same mechanism, no separate wiring needed), but — unlike a plain
 * `computed` — it stays writable in between those resets: `changePage()`/`changePageSize()`
 * call `.set()` on it directly, and that value survives until the next change to either input.
 * No injection context required, so a `PagedTable` can be constructed anywhere a class field
 * initializer runs, same as today's `Paginator`.
 */
export interface SearchConfig<T> {
  /** Returns the row's searchable strings — only these fields are matched against. */
  fields: (row: T) => readonly (string | null | undefined)[];
}

/**
 * Non-generic slice of `PagedTable` — what `TableFooterComponent` needs. Deliberately not
 * `PagedTable<unknown>` as the input type for that component: `SearchConfig<T>.fields` takes a
 * `T` parameter (contravariant position), so `PagedTable<Livestock>` is NOT assignable to
 * `PagedTable<unknown>` even though every member actually used here is T-independent. These
 * interfaces describe only the T-independent members, so any `PagedTable<AnythingAtAll>`
 * satisfies them structurally, no cast or `any` needed.
 */
export interface PagerView {
  readonly pageSize: WritableSignal<number>;
  readonly pageSizeOptions: readonly number[];
  readonly showingStart: Signal<number>;
  readonly showingEnd: Signal<number>;
  readonly totalItems: Signal<number>;
  readonly showPager: Signal<boolean>;
  readonly effectivePage: Signal<number>;
  readonly totalPages: Signal<number>;
  changePage(delta: number): void;
  changePageSize(event: Event): void;
}

/** Non-generic slice of `PagedTable` — what `TableToolbarComponent`'s search box needs. */
export interface SearchableView {
  readonly searchEnabled: boolean;
  readonly searchQuery: WritableSignal<string>;
  setSearchQuery(value: string): void;
}

export interface PagedTableConfig<T> {
  /** Default 10. */
  defaultPageSize?: number;
  /** Default [10, 25, 50]. Purely informational — the page-size <select> reads this. */
  pageSizeOptions?: number[];
  /** Default 0 — the footer ("Mostrando X–Y de N" + page-size select) is always visible. Raise it to hide the pager below a row-count threshold. */
  minRowsToShowPager?: number;
  /** Omit to disable search entirely (searchQuery/matchedRows become a no-op passthrough). */
  search?: SearchConfig<T>;
}

export class PagedTable<T> implements PagerView, SearchableView {
  public readonly pageSizeOptions: readonly number[];
  public readonly minRowsToShowPager: number;
  private readonly searchConfig?: SearchConfig<T>;

  public readonly pageSize: WritableSignal<number>;
  public readonly searchQuery: WritableSignal<string> = signal('');
  /** `true` when a SearchConfig was provided — lets a generic toolbar know whether to render a search input. */
  public readonly searchEnabled: boolean;

  /** Writable, but see the class doc — resets to 1 whenever resetKeyFn() or searchQuery() changes. */
  public readonly currentPage: WritableSignal<number>;

  constructor(
    private readonly sourceFn: () => readonly T[],
    private readonly resetKeyFn: () => unknown,
    config?: PagedTableConfig<T>
  ) {
    this.pageSizeOptions = config?.pageSizeOptions ?? [10, 25, 50];
    this.minRowsToShowPager = config?.minRowsToShowPager ?? 0;
    this.searchConfig = config?.search;
    this.searchEnabled = !!config?.search;
    this.pageSize = signal(config?.defaultPageSize ?? 10);
    this.currentPage = linkedSignal(() => {
      this.resetKeyFn();
      this.searchQuery();
      return 1;
    });
  }

  public setSearchQuery(value: string): void {
    this.searchQuery.set(value);
  }

  /** Rows after search — the actual pagination base. Equal to the raw source when search is disabled or empty. */
  public readonly matchedRows: Signal<readonly T[]> = computed(() => {
    const query = normalizeForSearch(this.searchQuery().trim());
    const rows = this.sourceFn();
    if (!query || !this.searchConfig) return rows;
    return rows.filter(row =>
      this.searchConfig!.fields(row).some(field => field != null && normalizeForSearch(field).includes(query))
    );
  });

  public readonly totalItems: Signal<number> = computed(() => this.matchedRows().length);

  public readonly totalPages: Signal<number> = computed(
    () => Math.ceil(this.totalItems() / this.pageSize()) || 1
  );

  /**
   * Clamped to totalPages — use this, never the raw `currentPage`, for slicing. The key-based
   * reset above only fires when the key or the search query change; it doesn't catch a dataset
   * that shrinks for some other reason (e.g. a live refresh dropping rows) while sitting on a
   * now-out-of-range page. Pure computed, so it's always consistent with the current data, no
   * effect() needed here either.
   */
  public readonly effectivePage: Signal<number> = computed(() =>
    Math.min(this.currentPage(), this.totalPages())
  );

  public readonly showPager: Signal<boolean> = computed(() => this.totalItems() > this.minRowsToShowPager);

  public readonly showingStart: Signal<number> = computed(() => {
    if (this.totalItems() === 0) return 0;
    return (this.effectivePage() - 1) * this.pageSize() + 1;
  });

  public readonly showingEnd: Signal<number> = computed(() =>
    Math.min(this.effectivePage() * this.pageSize(), this.totalItems())
  );

  public readonly paginatedRows: Signal<readonly T[]> = computed(() => {
    const start = (this.effectivePage() - 1) * this.pageSize();
    return this.matchedRows().slice(start, start + this.pageSize());
  });

  public changePage(delta: number): void {
    const next = this.effectivePage() + delta;
    if (next >= 1 && next <= this.totalPages()) {
      this.currentPage.set(next);
    }
  }

  public changePageSize(event: Event): void {
    this.pageSize.set(Number((event.target as HTMLSelectElement).value));
    this.currentPage.set(1);
  }
}
