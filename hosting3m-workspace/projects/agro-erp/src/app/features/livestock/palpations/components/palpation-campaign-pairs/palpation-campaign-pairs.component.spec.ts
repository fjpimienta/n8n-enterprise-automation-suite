import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { PalpationEventRow, ReportStatus } from '../../models/palpation.types';
import { GOLDEN, GOLDEN_A, GOLDEN_B, goldenData } from '../../testing/palpation-golden.fixtures';
import { eventRow } from '../../testing/palpation.fixtures';
import { CsvWriter, PALPATION_CSV_WRITER } from '../../utils/palpation-campaign-export';
import { PalpationCampaignPairsComponent } from './palpation-campaign-pairs.component';

const TENANT = 9101;
const { events, herd } = goldenData();

function render(over: { events?: PalpationEventRow[]; status?: ReportStatus; tenantId?: number | null; withReadyInputs?: boolean } = {}) {
  const writer = vi.fn();
  TestBed.configureTestingModule({ providers: [{ provide: PALPATION_CSV_WRITER, useValue: writer as unknown as CsvWriter }] });
  const f: ComponentFixture<PalpationCampaignPairsComponent> = TestBed.createComponent(PalpationCampaignPairsComponent);
  f.componentRef.setInput('events', over.events ?? events);
  f.componentRef.setInput('herd', herd);
  f.componentRef.setInput('a', GOLDEN_A);
  f.componentRef.setInput('b', GOLDEN_B);
  if (over.withReadyInputs !== false) {
    f.componentRef.setInput('reportStatus', over.status ?? 'listo');
    f.componentRef.setInput('tenantId', over.tenantId === undefined ? TENANT : over.tenantId);
  }
  f.detectChanges();
  return { f, writer };
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const q = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`) as T;
const qa = (f: ComponentFixture<unknown>, id: string) => [...el(f).querySelectorAll(`[data-testid="${id}"]`)] as HTMLElement[];
const text = (n: Element | null | undefined) => (n?.textContent ?? '').replace(/\s+/g, ' ').trim();
/** Types in the search box of one group (0 = persistent, 1 = pending): each group has its own table and its own search. */
const search = (f: ComponentFixture<unknown>, group: 0 | 1, value: string) => {
  const input = el(f).querySelectorAll('app-table-toolbar input')[group] as HTMLInputElement;
  input.value = value;
  input.dispatchEvent(new Event('input', { bubbles: true }));
  f.detectChanges();
};

describe('PalpationCampaignPairsComponent', () => {
  it('shows the two groups in the same view with their counts: 31 persistent and 19 pending', () => {
    const { f } = render();
    expect(text(q(f, 'persistent-title'))).toBe('Vacía en A y en B (persistente)');
    expect(text(q(f, 'pending-title'))).toBe('Vacía en A y no palpada en B (seguimiento)');
    expect(text(q(f, 'persistent-count'))).toContain(String(GOLDEN.vaciaVacia));
    expect(text(q(f, 'pending-count'))).toContain(String(GOLDEN.vaciaNoPalpada));
    expect(qa(f, 'persistent-row').length).toBe(10); // first page
    expect(qa(f, 'pending-row').length).toBe(10);
  });

  it('has the columns SINIIGA, quemado, marca, categoría, estado actual and one per campaign, in a table with a caption', () => {
    const { f } = render();
    const table = q(f, 'persistent-table');
    expect([...table.querySelectorAll('thead th')].map(text)).toEqual(['SINIIGA', 'Quemado', 'Marca', 'Categoría', 'Estado actual', 'Campaña A', 'Campaña B']);
    expect(text(table.querySelector('caption'))).toContain('un animal por fila');
  });

  it('shows the identifiers, the category and the status of each animal from the herd', () => {
    const { f } = render();
    const row = qa(f, 'persistent-row')[0] as HTMLElement;
    const cell = (col: string) => text(row.querySelector(`[data-col="${col}"]`));
    expect(cell('siniiga') === '—' || /^9999\d{6}$/.test(cell('siniiga'))).toBe(true);
    expect(cell('category')).toMatch(/^(VACA|NOVILLONA)$/);
    expect(cell('status')).toMatch(/^(ACTIVO|VENDIDO)$/);
    search(f, 0, 'ZZ1'); // the animals without SINIIGA are identified by brand and fuego
    const noSiniiga = qa(f, 'persistent-row').find(r => text(r.querySelector('[data-col="siniiga"]')) === '—');
    expect(text(noSiniiga?.querySelector('[data-col="brand"]'))).toBe('ZZ1');
    expect(text(noSiniiga?.querySelector('[data-col="fuego"]'))).toMatch(/^[FQ]\d{3}$/);
  });

  it('shows UNE in August and ESTATICA in November, each with its code as typed and the condition Estática (UNE)', () => {
    const { f } = render();
    const row = qa(f, 'persistent-row').find(r => text(r.querySelector('[data-col="a"]')).includes('Código: UNE'));
    expect(row).toBeDefined();
    expect(text(row?.querySelector('[data-col="a"]'))).toContain('03/08/2026');
    expect(text(row?.querySelector('[data-col="a"]'))).toContain('Vacía');
    expect(text(row?.querySelector('[data-col="a"]'))).toContain('Código: UNE · Condición: Estática (UNE)');
    expect(text(row?.querySelector('[data-col="b"]'))).toContain('Código: ESTATICA · Condición: Estática (UNE)');
    expect(text(row?.querySelector('[data-col="b"]'))).toMatch(/1[12]\/11\/2026/);
  });

  it('flags an unconfirmed code with the badge, shows the code as typed, and does not call it a condition', () => {
    const { f } = render();
    search(f, 0, 'YF15');
    search(f, 1, 'YF15');
    const rows = qa(f, 'persistent-row').concat(qa(f, 'pending-row'));
    expect(qa(f, 'persistent-row').length).toBeGreaterThan(0);
    expect(qa(f, 'pending-row').length).toBeGreaterThan(0);
    for (const r of rows) {
      const flagged = [...r.querySelectorAll('[data-col="a"], [data-col="b"]')].find(c => text(c).includes('YF15'));
      expect(text(flagged)).toContain('Código: YF15');
      expect(text(flagged)).not.toContain('Condición');
      expect(text(flagged)).toContain('código sin confirmar');
      expect(flagged?.querySelector('app-palp-flag')).not.toBeNull();
      expect(text(flagged)).toContain('Vacía'); // Vacía with a flag: the code is never reinterpreted (Y is not D)
    }
  });

  it('shows a pending animal with campaign B as "Sin registro en esa campaña", without date or code', () => {
    const { f } = render();
    const row = qa(f, 'pending-row')[0] as HTMLElement;
    expect(text(row.querySelector('[data-col="b"]'))).toBe('Sin registro en esa campaña');
    expect(text(row.querySelector('[data-col="a"]'))).toContain('03/08/2026');
  });

  it('gives the coverage note: palpated in A and B, in both, only in A, only in B, rancho and NR, and says the lists are not complete', () => {
    const { f } = render();
    const t = (id: string) => text(q(f, id));
    expect(t('cov-palpated-a')).toContain('Palpadas en Campaña A: 120');
    expect(t('cov-palpated-a')).toContain('45 preñadas, 75 vacías, 0 definido por el rancho, 0 sin interpretar');
    expect(t('cov-palpated-b')).toContain('Palpadas en Campaña B: 81');
    expect(t('cov-palpated-b')).toContain('34 preñadas, 45 vacías, 2 definido por el rancho, 0 sin interpretar');
    expect(t('cov-both')).toContain('74');
    expect(t('cov-only-a')).toContain('46');
    expect(t('cov-only-b')).toContain('7');
    expect(t('cov-rancho')).toContain('RP, NO APTO, MATRIZ OCUPADA');
    expect(t('cov-rancho')).toContain('2');
    expect(t('cov-nr')).toContain('1 en Campaña A');
    expect(t('cov-nr')).toContain('2 en Campaña B');
    expect(t('cov-other')).toContain('25');
    expect(t('pairs-coverage')).toContain('no son el hato completo');
  });

  it('says in the note that rancho animals are neither vacías nor preñadas and are in no list', () => {
    const { f } = render();
    expect(text(q(f, 'cov-rancho'))).toContain('no son vacías ni preñadas y no están en ninguna lista');
  });

  it('searches by SINIIGA, quemado, marca, category, status and code, and never by technician', () => {
    const withTech = events.map(e => ({ ...e, technician: 'Técnico demo 1' }));
    const { f } = render({ events: withTech });
    search(f, 0, 'Técnico demo 1');
    search(f, 1, 'Técnico demo 1');
    expect(qa(f, 'persistent-row').length).toBe(0);
    expect(qa(f, 'pending-row').length).toBe(0);
    search(f, 0, 'ESTATICA');
    expect(qa(f, 'persistent-row').length).toBeGreaterThan(0);
    expect(text(el(f))).not.toContain('Técnico');
  });

  it('renders stacked cards on phones with the identifiers, the two campaigns and the unconfirmed flag, so no sideways scroll is needed', () => {
    const { f } = render();
    expect(q(f, 'persistent-table').closest('.table-responsive')?.className).toContain('d-none d-md-block');
    expect(q(f, 'persistent-cards').className).toContain('d-md-none');
    expect(qa(f, 'persistent-card').length).toBe(qa(f, 'persistent-row').length);
    const card = qa(f, 'persistent-card')[0] as HTMLElement;
    expect(text(card)).toContain('SINIIGA:');
    expect(text(card)).toContain('Quemado:');
    expect(text(card)).toContain('Marca:');
    expect(text(card)).toContain('Campaña A');
    expect(text(card)).toContain('Campaña B');
    search(f, 0, 'DF15');
    search(f, 1, 'DF15');
    const flagged = qa(f, 'persistent-card').concat(qa(f, 'pending-card')).find(c => text(c).includes('código sin confirmar'));
    expect(text(flagged)).toContain('Código: DF15');
  });

  it('says so when a group has no animals', () => {
    const onlyPending = events.filter(e => !(e.event_date >= '2026-11-01' && e.event_date <= '2026-11-30'));
    const { f } = render({ events: onlyPending });
    expect(text(q(f, 'persistent-empty'))).toBe('Ningún animal en este grupo.');
    expect(text(q(f, 'pending-count'))).toContain(String(GOLDEN.vaciaVacia + GOLDEN.vaciaNoPalpada + GOLDEN.vaciaPrenada));
  });

  describe('export button', () => {
    it('is a native button, enabled when the report is ready and the company is valid, and writes the file through the writer with the 50 animals', () => {
      const { f, writer } = render();
      const button = q<HTMLButtonElement>(f, 'pairs-export');
      expect(button.tagName).toBe('BUTTON');
      expect(button.disabled).toBe(false);
      expect(el(f).querySelector('[data-testid="pairs-export-why"]')).toBeNull();
      button.click();
      f.detectChanges();
      expect(writer).toHaveBeenCalledTimes(1);
      const [rows, columns, filename] = writer.mock.calls[0] as [unknown[], unknown[], string];
      expect(rows.length).toBe(50);
      expect(columns.length).toBe(16);
      expect(filename).toBe('palpaciones_vacias_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
      expect(text(q(f, 'pairs-export-message'))).toContain('Archivo generado: palpaciones_vacias_A_');
      expect(text(q(f, 'pairs-export-message'))).toContain('50 animales');
    });

    it('is disabled by default: a parent that does not say the report is ready cannot export', () => {
      const { f, writer } = render({ withReadyInputs: false });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(true);
      q<HTMLButtonElement>(f, 'pairs-export').click();
      expect(writer).not.toHaveBeenCalled();
    });

    it('is disabled for a truncated report and says why in words', () => {
      const { f, writer } = render({ status: 'truncado' });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(true);
      expect(text(q(f, 'pairs-export-why'))).toContain('incompleto');
      q<HTMLButtonElement>(f, 'pairs-export').click();
      expect(writer).not.toHaveBeenCalled();
    });

    it.each(['cargando', 'error', 'vacio', 'sin-tenant', 'sin-permiso'] as ReportStatus[])('is disabled while the report is "%s"', status => {
      const { f } = render({ status });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(true);
      expect(q(f, 'pairs-export-why')).not.toBeNull();
    });

    it.each([null, 0, -3])('is disabled without a valid company (%s)', tenantId => {
      const { f } = render({ tenantId });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(true);
      expect(text(q(f, 'pairs-export-why'))).toContain('empresa');
    });

    it('refuses, writes nothing and says why when a row belongs to another company', () => {
      const foreign = events.map((e, i) => (i === 7 ? { ...e, id_company: 9102 } : e));
      const { f, writer } = render({ events: foreign });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(false); // the cheap check passes; the full plan catches the row
      q<HTMLButtonElement>(f, 'pairs-export').click();
      f.detectChanges();
      expect(writer).not.toHaveBeenCalled();
      expect(text(q(f, 'pairs-export-message'))).toContain('otra empresa');
      expect(q(f, 'pairs-export-message').getAttribute('role')).toBe('alert');
    });

    it('does not export the technician or the company name', () => {
      const { f, writer } = render({ events: events.map(e => ({ ...e, technician: 'Técnico demo 1' })) });
      q<HTMLButtonElement>(f, 'pairs-export').click();
      const [rows, columns, filename] = writer.mock.calls[0] as [PalpationEventRow[], { header: string; value: (r: unknown) => string }[], string];
      expect(columns.some(c => /t[eé]cnico/i.test(c.header))).toBe(false);
      expect(JSON.stringify(rows.map(r => columns.map(c => c.value(r))))).not.toContain('Técnico');
      expect(filename).not.toMatch(/[a-z]{4,}\s/i);
    });
  });
});

describe('golden proportions in the view', () => {
  it('reproduces 31 / 19 and the 25 that are in neither list', () => {
    const { f } = render();
    expect(text(q(f, 'persistent-count'))).toContain('31');
    expect(text(q(f, 'pending-count'))).toContain('19');
    expect(text(q(f, 'cov-other'))).toContain('25');
  });

  it('a Preñada animal never appears in the lists', () => {
    const e = [eventRow({ health_log_id: 'p', livestock_id: 'P', event_date: '2026-08-03', result: 'PREÑADA', gestation_days: 60 })];
    const { f } = render({ events: e });
    expect(el(f).querySelector('[data-testid="persistent-row"]')).toBeNull();
    expect(el(f).querySelector('[data-testid="pending-row"]')).toBeNull();
  });
});
