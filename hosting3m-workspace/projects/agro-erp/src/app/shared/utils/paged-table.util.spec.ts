import { signal } from '@angular/core';
import { PagedTable } from './paged-table.util';

describe('PagedTable', () => {
  function range(n: number): number[] {
    return Array.from({ length: n }, (_, i) => i + 1);
  }

  interface Animal { rfid: string; fuego: string; lot: string | null }

  function animals(): Animal[] {
    return [
      { rfid: '0710070001', fuego: 'A1', lot: 'El Peñón' },
      { rfid: '0710070002', fuego: 'A2', lot: 'La Bendición' },
      { rfid: '0710070003', fuego: 'A3', lot: null }
    ];
  }

  it('slices the source into pages of pageSize', () => {
    const source = signal(range(25));
    const table = new PagedTable(() => source(), () => null);

    expect(table.totalItems()).toBe(25);
    expect(table.totalPages()).toBe(3); // 10 + 10 + 5
    expect(table.paginatedRows()).toEqual(range(10));

    table.changePage(1);
    expect(table.effectivePage()).toBe(2);
    expect(table.paginatedRows()).toEqual(range(20).slice(10));
  });

  it('resets to page 1 when the reset key changes, via linkedSignal (no effect())', () => {
    const source = signal(range(50));
    const filterQuery = signal('');
    const table = new PagedTable(() => source(), () => filterQuery());

    table.changePage(1); // page 2
    table.changePage(1); // page 3
    expect(table.effectivePage()).toBe(3);

    filterQuery.set('something'); // simulates a filter/search change
    expect(table.currentPage()).toBe(1);
    expect(table.effectivePage()).toBe(1);
  });

  it('keeps the manually-set page until the key actually changes', () => {
    const source = signal(range(50));
    const filterQuery = signal('same');
    const table = new PagedTable(() => source(), () => filterQuery());

    table.changePage(1);
    expect(table.effectivePage()).toBe(2);

    filterQuery.set('same'); // same value — linkedSignal's source recomputed but didn't change
    expect(table.effectivePage()).toBe(2);
  });

  it('resets on tenant change when the key composes tenant + filters', () => {
    const source = signal(range(30));
    const tenantId = signal(1);
    const query = signal('');
    const table = new PagedTable(() => source(), () => ({ tenantId: tenantId(), query: query() }));

    table.changePage(1);
    expect(table.effectivePage()).toBe(2);

    tenantId.set(2); // Context Switcher switches ranch
    expect(table.effectivePage()).toBe(1);
  });

  it('clamps effectivePage when the dataset shrinks without a key change', () => {
    const source = signal(range(30));
    const table = new PagedTable(() => source(), () => null);

    table.changePage(2); // page 3 of 3 (10/page)
    expect(table.effectivePage()).toBe(3);

    source.set(range(5)); // same "key" (none), but data shrank to 1 page
    expect(table.totalPages()).toBe(1);
    expect(table.effectivePage()).toBe(1);
    expect(table.paginatedRows()).toEqual(range(5));
  });

  it('showPager defaults to true for any non-empty dataset (minRowsToShowPager defaults to 0)', () => {
    const source = signal(range(1));
    const table = new PagedTable(() => source(), () => null);
    expect(table.showPager()).toBe(true);

    source.set([]);
    expect(table.showPager()).toBe(false);
  });

  it('showPager respects an explicit minRowsToShowPager threshold', () => {
    const source = signal(range(10));
    const table = new PagedTable(() => source(), () => null, { minRowsToShowPager: 10 });
    expect(table.showPager()).toBe(false);

    source.set(range(11));
    expect(table.showPager()).toBe(true);
  });

  it('changePage ignores deltas that would go out of range', () => {
    const source = signal(range(15)); // 2 pages of 10
    const table = new PagedTable(() => source(), () => null);

    table.changePage(-1);
    expect(table.effectivePage()).toBe(1); // can't go below 1

    table.changePage(1);
    expect(table.effectivePage()).toBe(2);
    table.changePage(1);
    expect(table.effectivePage()).toBe(2); // can't go past totalPages
  });

  it('changePageSize updates pageSize and resets to page 1', () => {
    const source = signal(range(30));
    const table = new PagedTable(() => source(), () => null);

    table.changePage(2); // page 3 of 3
    table.changePageSize({ target: { value: '25' } } as unknown as Event);

    expect(table.pageSize()).toBe(25);
    expect(table.effectivePage()).toBe(1);
    expect(table.totalPages()).toBe(2);
  });

  it('showingStart/showingEnd are 0 when there are no rows (shown as "0 a 0 de 0"), correct otherwise', () => {
    const source = signal<number[]>([]);
    const table = new PagedTable(() => source(), () => null);
    expect(table.showingStart()).toBe(0);
    expect(table.showingEnd()).toBe(0);
    expect(table.totalItems()).toBe(0);

    source.set(range(25));
    expect(table.showingStart()).toBe(1);
    expect(table.showingEnd()).toBe(10);

    table.changePage(2); // last page, partial
    expect(table.showingStart()).toBe(21);
    expect(table.showingEnd()).toBe(25);
  });

  it('search matches only the configured fields, normalized (no accents, case-insensitive)', () => {
    const source = signal(animals());
    const table = new PagedTable(() => source(), () => null, {
      search: { fields: row => [row.rfid, row.fuego, row.lot] }
    });

    table.setSearchQuery('PENON'); // no accent, uppercase — should still match "El Peñón"
    expect(table.matchedRows()).toEqual([animals()[0]]);

    table.setSearchQuery('0710070002');
    expect(table.matchedRows()).toEqual([animals()[1]]);

    table.setSearchQuery('');
    expect(table.matchedRows()).toEqual(animals());
  });

  it('a search edit resets the page through the same reset mechanism as the key', () => {
    const source = signal(range(30).map(n => ({ rfid: String(n), fuego: '', lot: null as string | null })));
    const table = new PagedTable(() => source(), () => null, {
      search: { fields: row => [row.rfid] }
    });

    table.changePage(2); // page 3 of 3
    expect(table.effectivePage()).toBe(3);

    table.setSearchQuery('1'); // matches 1,10-19,21 — enough to change totalPages
    expect(table.currentPage()).toBe(1);
  });

  it('search is a no-op passthrough when no SearchConfig is provided', () => {
    const source = signal(animals());
    const table = new PagedTable(() => source(), () => null);

    table.setSearchQuery('anything');
    expect(table.matchedRows()).toEqual(animals());
  });
});
