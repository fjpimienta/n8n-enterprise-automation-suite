import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { PalpationEventRow, ReportStatus } from '../../models/palpation.types';
import { GOLDEN_A, GOLDEN_B, GOLDEN_MATRIX_ONLY_B, goldenData } from '../../testing/palpation-golden.fixtures';
import { CsvWriter, PALPATION_CSV_WRITER } from '../../utils/palpation-campaign-export';
import { MatrixCell, parseDeepLink } from '../../utils/palpation-matrix-cells';
import { PalpationMatrixCellComponent } from './palpation-matrix-cell.component';

const TENANT = 9101;
const matrix = goldenData(GOLDEN_MATRIX_ONLY_B);
const NO_PRENADA: MatrixCell = { from: 'NO_PALPADA', to: 'PREÑADA' };

function render(over: { cell?: MatrixCell; count?: number; events?: PalpationEventRow[]; herd?: typeof matrix.herd; status?: ReportStatus; tenantId?: number | null; ready?: boolean } = {}) {
  const writer = vi.fn();
  TestBed.configureTestingModule({ providers: [{ provide: PALPATION_CSV_WRITER, useValue: writer as unknown as CsvWriter }] });
  const f: ComponentFixture<PalpationMatrixCellComponent> = TestBed.createComponent(PalpationMatrixCellComponent);
  f.componentRef.setInput('events', over.events ?? matrix.events);
  f.componentRef.setInput('herd', over.herd ?? matrix.herd);
  f.componentRef.setInput('a', GOLDEN_A);
  f.componentRef.setInput('b', GOLDEN_B);
  f.componentRef.setInput('cell', over.cell ?? NO_PRENADA);
  f.componentRef.setInput('matrixCount', over.count ?? 32);
  if (over.ready !== false) {
    f.componentRef.setInput('reportStatus', over.status ?? 'listo');
    f.componentRef.setInput('tenantId', over.tenantId === undefined ? TENANT : over.tenantId);
  }
  let closed = 0;
  f.componentInstance.closed.subscribe(() => (closed += 1));
  f.detectChanges();
  return { f, writer, closed: () => closed };
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const q = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`) as T;
const qa = (f: ComponentFixture<unknown>, id: string) => [...el(f).querySelectorAll(`[data-testid="${id}"]`)] as HTMLElement[];
const text = (n: Element | null | undefined) => (n?.textContent ?? '').replace(/\s+/g, ' ').trim();

describe('PalpationMatrixCellComponent', () => {
  it('shows the cell as a titled section with the animals of that cell, the same count the matrix has, and the shared table', () => {
    const { f } = render();
    expect(text(q(f, 'cell-title'))).toBe('Animales: Sin registro en Campaña A y Preñada en Campaña B');
    expect(el(f).querySelector('section')?.getAttribute('aria-labelledby')).toBe('palp-cell-title');
    expect(text(q(f, 'cell-count'))).toContain('32');
    expect(text(q(f, 'cell-count'))).toContain('los mismos que cuenta la matriz');
    expect(text(q(f, 'cell-count'))).toContain('32 (los mismos'); // a space between the number and the note
    expect(qa(f, 'cell-row').length).toBe(10); // first page
    expect(text(el(f))).toContain('Mostrando 1 a 10 de 32');
  });

  it('shows the 52 animals of "sin registro en A y Vacía en B"', () => {
    const { f } = render({ cell: { from: 'NO_PALPADA', to: 'VACÍA' }, count: 52 });
    expect(text(q(f, 'cell-count'))).toContain('52');
    expect(text(el(f))).toContain('Mostrando 1 a 10 de 52');
  });

  it('says what "sin registro" includes: rows that could not be matched or loaded, not only animals that were skipped', () => {
    const { f } = render();
    expect(text(q(f, 'cell-note-sin-registro'))).toContain(
      '«Sin registro» incluye a los animales cuyas filas no se pudieron emparejar o cargar, no solo a los que se saltaron en esa campaña',
    );
    expect(text(q(f, 'cell-note-sin-registro'))).toContain('no hay ninguna palpación que cuente dentro de las fechas de esa campaña (un NR no cuenta)');
    expect(text(q(f, 'cell-note-scope'))).toContain('no es el hato completo');
  });

  it('shows the coverage note also for a cell that has no "sin registro" in it', () => {
    const { f } = render({ cell: { from: 'VACÍA', to: 'VACÍA' }, count: 31 });
    expect(q(f, 'cell-coverage')).not.toBeNull();
    expect(text(q(f, 'cell-note-sin-registro'))).toContain('Sin registro');
  });

  it('counts the animals whose rows could not be matched to the herd, keeps them in the list and says so', () => {
    const missing = new Set(['golden-001', 'golden-002']);
    const { f } = render({ cell: { from: 'VACÍA', to: 'VACÍA' }, count: 31, herd: matrix.herd.filter(h => !missing.has(h.livestock_id)) });
    expect(text(q(f, 'cell-count'))).toContain('31'); // still all of them
    expect(text(q(f, 'cell-note-unmatched'))).toContain('2 animales tienen palpaciones en estas campañas pero ninguna ficha en el hato');
    expect(text(q(f, 'cell-note-unmatched'))).toContain('no tienen SINIIGA, categoría ni estado');
  });

  it('does not show the unmatched note when every animal has its herd row', () => {
    const { f } = render();
    expect(el(f).querySelector('[data-testid="cell-note-unmatched"]')).toBeNull();
  });

  it('says the list is partial when the report is incomplete, and disables the export', () => {
    const { f, writer } = render({ status: 'truncado' });
    expect(text(q(f, 'cell-note-truncated'))).toContain('esta lista es parcial');
    expect(q<HTMLButtonElement>(f, 'cell-export').disabled).toBe(true);
    expect(text(q(f, 'cell-export-why'))).toContain('incompleto');
    q<HTMLButtonElement>(f, 'cell-export').click();
    expect(writer).not.toHaveBeenCalled();
  });

  it('does not show a list that does not match the matrix, and says the figures do not add up', () => {
    const { f } = render({ count: 31 });
    expect(q(f, 'cell-mismatch').getAttribute('role')).toBe('alert');
    expect(text(q(f, 'cell-mismatch'))).toContain('La matriz cuenta 31 y la lista tiene 32');
    expect(el(f).querySelector('[data-testid="cell-row"]')).toBeNull();
    expect(q<HTMLButtonElement>(f, 'cell-export').disabled).toBe(true);
  });

  it('says so when the cell has no animals', () => {
    const { f } = render({ cell: { from: 'SIN_INTERPRETAR', to: 'RANCHO' }, count: 0 });
    expect(text(q(f, 'cell-empty'))).toBe('Ningún animal en esta celda.');
    expect(el(f).querySelector('app-palpation-pair-table')).toBeNull();
  });

  it('shows the same columns as the follow-up groups, with the code, the condition and the unconfirmed flag', () => {
    const { f } = render({ cell: { from: 'VACÍA', to: 'VACÍA' }, count: 31 });
    expect([...q(f, 'cell-table').querySelectorAll('thead th')].map(text)).toEqual(['SINIIGA', 'Quemado', 'Marca', 'Categoría', 'Estado actual', 'Campaña A', 'Campaña B']);
    const une = qa(f, 'cell-row').find(r => text(r.querySelector('[data-col="a"]')).includes('Código: UNE'));
    expect(text(une?.querySelector('[data-col="a"]'))).toContain('Condición: Estática (UNE)');
    const input = el(f).querySelector('app-table-toolbar input') as HTMLInputElement;
    input.value = 'YF15';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    f.detectChanges();
    expect(qa(f, 'cell-row').length).toBeGreaterThan(0);
    expect(el(f).querySelector('app-palp-flag')).not.toBeNull();
  });

  it('renders phone cards with the same data, so no sideways scroll is needed', () => {
    const { f } = render();
    expect(q(f, 'cell-table').closest('.table-responsive')?.className).toContain('d-none d-md-block');
    expect(q(f, 'cell-cards').className).toContain('d-md-none');
    expect(qa(f, 'cell-card').length).toBe(10);
    expect(text(qa(f, 'cell-card')[0])).toContain('Sin registro en esa campaña');
  });

  it('has no technician anywhere', () => {
    const { f } = render({ events: matrix.events.map(e => ({ ...e, technician: 'Técnico demo 1' })) });
    expect(text(el(f))).not.toContain('Técnico');
  });

  describe('deep link', () => {
    const withClipboard = async (impl: (text: string) => Promise<void> | void) => {
      const writeText = vi.fn(impl);
      Object.defineProperty(window.navigator, 'clipboard', { value: { writeText }, configurable: true });
      return writeText;
    };

    it('copies a link with only the two date ranges and the cell id, and says so', async () => {
      const writeText = await withClipboard(() => undefined);
      const { f } = render();
      q<HTMLButtonElement>(f, 'cell-copy-link').click();
      await f.whenStable();
      f.detectChanges();
      expect(writeText).toHaveBeenCalledTimes(1);
      const link = new URL(writeText.mock.calls[0]?.[0] as string);
      expect([...link.searchParams.keys()]).toEqual(['a', 'b', 'cell']);
      expect(link.searchParams.get('a')).toBe('2026-08-03_2026-08-03');
      expect(link.searchParams.get('b')).toBe('2026-11-01_2026-11-30');
      expect(link.searchParams.get('cell')).toBe('sin-registro.prenada');
      expect(parseDeepLink({ getAll: n => link.searchParams.getAll(n) })?.cell).toEqual(NO_PRENADA);
      expect(text(q(f, 'cell-message'))).toContain('Enlace copiado');
      expect(text(q(f, 'cell-message'))).toContain('empresa activa');
    });

    it('holds no animal data, no company and no result in the link', async () => {
      const writeText = await withClipboard(() => undefined);
      const { f } = render({ tenantId: 4242 });
      q<HTMLButtonElement>(f, 'cell-copy-link').click();
      await f.whenStable();
      const link = writeText.mock.calls[0]?.[0] as string;
      expect(link).not.toMatch(/golden|9999|4242|tenant|company|empresa|livestock/i);
    });

    it('shows the link to copy by hand when the browser does not allow the clipboard', async () => {
      await withClipboard(() => Promise.reject(new Error('denied')));
      const { f } = render();
      q<HTMLButtonElement>(f, 'cell-copy-link').click();
      await f.whenStable();
      f.detectChanges();
      expect(text(q(f, 'cell-message'))).toContain('No se pudo copiar solo');
      const input = q<HTMLInputElement>(f, 'cell-link-input');
      expect(input.readOnly).toBe(true);
      expect(input.value).toContain('cell=sin-registro.prenada');
      expect(el(f).querySelector('label[for="palp-cell-link"]')).not.toBeNull();
    });

    it('also falls back when there is no clipboard at all', async () => {
      Object.defineProperty(window.navigator, 'clipboard', { value: undefined, configurable: true });
      const { f } = render();
      q<HTMLButtonElement>(f, 'cell-copy-link').click();
      await f.whenStable();
      f.detectChanges();
      expect(q<HTMLInputElement>(f, 'cell-link-input').value).toContain('?a=2026-08-03_2026-08-03&b=2026-11-01_2026-11-30&cell=sin-registro.prenada');
    });
  });

  describe('export', () => {
    it('writes the file of the cell through the guarded exporter: its animals, 16 columns and the file name with the cell and both date ranges', () => {
      const { f, writer } = render();
      expect(q<HTMLButtonElement>(f, 'cell-export').disabled).toBe(false);
      q<HTMLButtonElement>(f, 'cell-export').click();
      f.detectChanges();
      expect(writer).toHaveBeenCalledTimes(1);
      const [rows, columns, filename] = writer.mock.calls[0] as [unknown[], unknown[], string];
      expect(rows.length).toBe(32);
      expect(columns.length).toBe(16);
      expect(filename).toBe('palpaciones_celda_sin-registro.prenada_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
      expect(text(q(f, 'cell-message'))).toContain('Archivo generado: palpaciones_celda_sin-registro.prenada_A_');
    });

    it('is disabled by default, and for a missing company, with the reason written next to it', () => {
      const closedByDefault = render({ ready: false });
      expect(q<HTMLButtonElement>(closedByDefault.f, 'cell-export').disabled).toBe(true);
      TestBed.resetTestingModule();
      const noTenant = render({ tenantId: null });
      expect(q<HTMLButtonElement>(noTenant.f, 'cell-export').disabled).toBe(true);
      expect(text(q(noTenant.f, 'cell-export-why'))).toContain('empresa');
    });

    it('refuses, writes nothing and says why when a row belongs to another company', () => {
      const foreign = matrix.events.map((e, i) => (i === 11 ? { ...e, id_company: 9102 } : e));
      const { f, writer } = render({ events: foreign });
      q<HTMLButtonElement>(f, 'cell-export').click();
      f.detectChanges();
      expect(writer).not.toHaveBeenCalled();
      expect(text(q(f, 'cell-message'))).toContain('otra empresa');
      expect(q(f, 'cell-message').getAttribute('role')).toBe('alert');
    });
  });

  describe('buttons and focus', () => {
    it('has three native buttons with their words, and Cerrar emits closed', () => {
      const { f, closed } = render();
      expect(['cell-copy-link', 'cell-export', 'cell-close'].map(id => q(f, id).tagName)).toEqual(['BUTTON', 'BUTTON', 'BUTTON']);
      expect(text(q(f, 'cell-close'))).toBe('Cerrar');
      q<HTMLButtonElement>(f, 'cell-close').click();
      expect(closed()).toBe(1);
    });

    it('moves the focus to the title when it opens and when another cell is chosen', async () => {
      const { f } = render();
      await f.whenStable();
      expect(document.activeElement).toBe(q(f, 'cell-title'));
      expect(q(f, 'cell-title').getAttribute('tabindex')).toBe('-1');
      (document.activeElement as HTMLElement).blur();
      f.componentRef.setInput('cell', { from: 'NO_PALPADA', to: 'VACÍA' });
      f.componentRef.setInput('matrixCount', 52);
      f.detectChanges();
      await f.whenStable();
      expect(document.activeElement).toBe(q(f, 'cell-title'));
    });
  });
});
