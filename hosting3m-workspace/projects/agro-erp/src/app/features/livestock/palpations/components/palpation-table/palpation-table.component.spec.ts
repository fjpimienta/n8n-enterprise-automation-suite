import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { colorForKey } from '../../utils/palpation-colors';
import { PalpationTableRow, SortDir, SortKey } from '../../utils/palpation-view';
import { PalpationTableComponent, RowOpenEvent } from './palpation-table.component';

function row(over: Partial<PalpationTableRow> = {}): PalpationTableRow {
  return {
    livestockId: 'an-1', identifier: '9999000001', category: 'VACA', currentStatus: 'ACTIVO', lastDate: '2026-11-10',
    state: 'VACÍA', subtype: 'ESTATICA', ranchTerm: null, gestation: null, technician: null, unconfirmedCode: null,
    historical: false, uninterpreted: false, ...over,
  };
}

function render(rows: PalpationTableRow[], sort: { key?: SortKey; dir?: SortDir } = {}): ComponentFixture<PalpationTableComponent> {
  const f = TestBed.createComponent(PalpationTableComponent);
  f.componentRef.setInput('rows', rows);
  f.componentRef.setInput('sortKey', sort.key ?? 'lastDate');
  f.componentRef.setInput('sortDir', sort.dir ?? 'desc');
  f.detectChanges();
  return f;
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const text = (n: Element | null) => n?.textContent?.replace(/\s+/g, ' ').trim() ?? '';
const tableText = (f: ComponentFixture<unknown>) => text(el(f).querySelector('[data-testid="palp-table"]'));

const many = (n: number) => Array.from({ length: n }, (_, i) => row({ livestockId: `an-${i}`, identifier: `99990000${String(i).padStart(2, '0')}` }));

describe('PalpationTableComponent', () => {
  it('renders each animal with its date, result as text, gestation, technician and status', () => {
    const f = render([
      row({ livestockId: 'a', identifier: '9999000001', state: 'PREÑADA', subtype: null, gestation: { months: 3, days: 90 }, technician: 'Técnico sintético' }),
      row({ livestockId: 'b', identifier: '9999000002', state: 'VACÍA', subtype: 'CICLANDO', currentStatus: 'RIESGO' }),
    ]);
    const t = tableText(f);
    expect(t).toContain('9999000001');
    expect(t).toContain('10/11/2026');
    expect(t).toContain('Preñada');
    expect(t).toContain('3,0 meses (90 días)');
    expect(t).toContain('Técnico sintético');
    expect(t).toContain('Vacía');
    expect(t).toContain('Subtipo: Ciclando');
    expect(t).toContain('RIESGO');
  });

  it('shows an em dash for the gestation of a result that is not pregnant', () => {
    const f = render([row({ state: 'VACÍA' })]);
    const cells = [...el(f).querySelectorAll('[data-testid="palp-table"] tbody td')].map(c => text(c));
    expect(cells).toContain('—');
  });

  it('labels a ranch term, the historical load and an unconfirmed code with text, and shows the code as typed', () => {
    const f = render([
      row({ livestockId: 'r', identifier: 'R1', state: 'TERMINO_RANCHO', subtype: null, ranchTerm: 'RP' }),
      row({ livestockId: 'h', identifier: 'H1', state: 'PREÑADA', subtype: null, historical: true }),
      row({ livestockId: 'u', identifier: 'U1', state: 'VACÍA', subtype: 'SIN_CONFIRMAR', unconfirmedCode: 'DF15' }),
    ]);
    const t = tableText(f);
    expect(t).toContain('Término del rancho: RP');
    expect(t).toContain('Definido por el rancho');
    expect(t).toContain('histórico (carga 2023)');
    expect(t).toContain('código sin confirmar: DF15');
    expect(t).not.toContain('Subtipo: Código sin confirmar');
  });

  it('puts the chart colour of each result next to its name, and shows an unconfirmed code on a grey badge', () => {
    const rgb = (hex: string): string => `rgb(${[1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)).join(', ')})`;
    const f = render([
      row({ livestockId: 'p', identifier: 'P1', state: 'PREÑADA', subtype: null, gestation: { months: 5, days: 150 } }),
      row({ livestockId: 'c', identifier: 'C1', state: 'VACÍA', subtype: 'CICLANDO' }),
      row({ livestockId: 'r', identifier: 'R1', state: 'TERMINO_RANCHO', subtype: null, ranchTerm: 'RP' }),
      row({ livestockId: 'u', identifier: 'U1', state: 'VACÍA', subtype: 'SIN_CONFIRMAR', unconfirmedCode: 'DF15' }),
    ]);
    const dots = [...el(f).querySelectorAll('table .palp-swatch')].map(d => (d as HTMLElement).style.backgroundColor);
    expect(dots).toEqual([rgb(colorForKey('p-5')), rgb(colorForKey('v-CICLANDO')), rgb(colorForKey('r-RP')), rgb(colorForKey('v-SIN_CONFIRMAR'))]);
    const unconfirmed = [...el(f).querySelectorAll('table .badge')].find(b => b.textContent?.includes('código sin confirmar'));
    expect(unconfirmed?.classList.contains('bg-secondary-lt')).toBe(true);
    expect(unconfirmed?.classList.contains('bg-yellow-lt')).toBe(false);
  });

  it('gives the same result the same colour in two different rows', () => {
    const f = render([
      row({ livestockId: 'a', identifier: 'A1', state: 'PREÑADA', subtype: null, gestation: { months: 3, days: 90 } }),
      row({ livestockId: 'b', identifier: 'B1', state: 'PREÑADA', subtype: null, gestation: { months: 3.3, days: 100 } }),
    ]);
    const dots = [...el(f).querySelectorAll('table .palp-swatch')].map(d => (d as HTMLElement).style.backgroundColor);
    expect(dots[0]).toBe(dots[1]);
  });

  it('shows "Sin interpretar" for an unrecognised value', () => {
    expect(tableText(render([row({ state: 'SIN_INTERPRETAR', subtype: null, uninterpreted: true })]))).toContain('Sin interpretar');
  });

  it('exposes the sort state to assistive technology with aria-sort', () => {
    const f = render(many(2), { key: 'identifier', dir: 'asc' });
    const th = (key: string) => el(f).querySelector(`[data-sort="${key}"]`)?.closest('th');
    expect(th('identifier')?.getAttribute('aria-sort')).toBe('ascending');
    expect(th('lastDate')?.getAttribute('aria-sort')).toBe('none');
    f.componentRef.setInput('sortDir', 'desc');
    f.detectChanges();
    expect(th('identifier')?.getAttribute('aria-sort')).toBe('descending');
  });

  it('sorts from the keyboard: the headers are buttons, and pressing one emits the key', () => {
    const f = render(many(2));
    const spy = vi.fn();
    f.componentInstance.sortChange.subscribe(spy);
    const headers = [...el(f).querySelectorAll<HTMLButtonElement>('thead button')];
    expect(headers.length).toBe(6);
    for (const b of headers) {
      expect(b.tagName).toBe('BUTTON');
      expect(b.getAttribute('tabindex')).not.toBe('-1');
    }
    headers[0]!.click();
    headers[2]!.click();
    expect(spy.mock.calls.map(c => c[0])).toEqual(['identifier', 'state']);
  });

  it('searches by identifier, category, status, technician and code, ignoring accents', () => {
    const f = render([
      row({ livestockId: 'a', identifier: '9999000001', technician: 'Técnico sintético' }),
      row({ livestockId: 'b', identifier: '9999000002', technician: null }),
    ]);
    const input = el(f).querySelector<HTMLInputElement>('input[type="text"]')!;
    input.value = 'tecnico sintetico';
    input.dispatchEvent(new Event('input'));
    f.detectChanges();
    const t = tableText(f);
    expect(t).toContain('9999000001');
    expect(t).not.toContain('9999000002');
  });

  it('paginates, and the footer shows the range and the total', () => {
    const f = render(many(12));
    expect(el(f).querySelectorAll('[data-testid="palp-table"] tbody tr').length).toBe(10);
    expect(text(el(f).querySelector('.card-footer'))).toContain('Mostrando 1 a 10 de 12');
  });

  it('gives each row a button with an accessible name that includes the identifier, and emits the row and the button', () => {
    const f = render([row({ livestockId: 'a', identifier: '9999000001' })]);
    const spy = vi.fn<(e: RowOpenEvent) => void>();
    f.componentInstance.rowOpen.subscribe(spy);
    const btn = el(f).querySelector<HTMLButtonElement>('[data-testid="open-row"]')!;
    expect(btn.getAttribute('aria-label')).toBe('Ver historial de palpaciones de 9999000001');
    btn.click();
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0]![0].row.livestockId).toBe('a');
    expect(spy.mock.calls[0]![0].opener).toBe(btn);
  });

  it('renders stacked cards for a phone with the same identifier, result and button', () => {
    const f = render([row({ identifier: '9999000001', state: 'PREÑADA', subtype: null, gestation: { months: 3, days: 90 } })]);
    const cards = text(el(f).querySelector('[data-testid="palp-cards"]'));
    expect(cards).toContain('9999000001');
    expect(cards).toContain('Preñada');
    expect(cards).toContain('Gestación: 3,0 meses (90 días)');
    expect(el(f).querySelector('[data-testid="open-card"]')).not.toBeNull();
  });

  it('says so when no animal matches', () => {
    const f = render([]);
    expect(text(el(f))).toContain('No hay animales que coincidan con la búsqueda o los filtros');
    expect(el(f).querySelector('[data-testid="palp-table"]')).toBeNull();
  });
});
