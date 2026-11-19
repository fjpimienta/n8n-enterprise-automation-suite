import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../../testing/palpation.fixtures';
import { Campaign } from '../../utils/palpation-campaigns';
import { PalpationCampaignCompareComponent } from './palpation-campaign-compare.component';

const camp = (id: string, label: string, from: string, to: string): Campaign => ({ id, label, from, to });
const C1 = camp('c1', 'Enero', '2026-01-01', '2026-01-10');
const C2 = camp('c2', 'Abril', '2026-04-01', '2026-04-10');
const C3 = camp('c3', 'Agosto', '2026-08-01', '2026-08-10');

const ev = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  eventRow({ health_log_id: id, livestock_id: animal, event_date: day, result: 'VACÍA', ...over });
const preg = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  ev(id, animal, day, { result: 'PREÑADA', gestation_days: 90, ...over });

const herd = Array.from({ length: 30 }, (_, i) => herdRow({ livestock_id: `A${i}`, rfid_siniiga: `99990001${String(i).padStart(2, '0')}`, category: 'VACA', current_status: 'ACTIVO' }));

function render(events: ReturnType<typeof eventRow>[], campaigns: readonly Campaign[]) {
  const f: ComponentFixture<PalpationCampaignCompareComponent> = TestBed.createComponent(PalpationCampaignCompareComponent);
  f.componentRef.setInput('events', events);
  f.componentRef.setInput('herd', herd);
  f.componentRef.setInput('campaigns', campaigns);
  f.detectChanges();
  return f;
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const q = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`) as T;
const qa = (f: ComponentFixture<unknown>, id: string) => [...el(f).querySelectorAll(`[data-testid="${id}"]`)] as HTMLElement[];
const text = (n: Element | null | undefined) => (n?.textContent ?? '').replace(/\s+/g, ' ').trim();
const choose = (f: ComponentFixture<unknown>, id: string, value: string) => {
  const s = q<HTMLSelectElement>(f, id);
  s.value = value;
  s.dispatchEvent(new Event('change', { bubbles: true }));
  f.detectChanges();
};

describe('PalpationCampaignCompareComponent', () => {
  // A0 vacía->vacía->vacía (3), A1 vacía only in c1, A2 pregnant in c2, A3 RP in c1, A4 unconfirmed Vacía in c1 + c2
  const events = [
    ev('a0c1', 'A0', '2026-01-05'), ev('a0c2', 'A0', '2026-04-05'), ev('a0c3', 'A0', '2026-08-05'),
    ev('a1', 'A1', '2026-01-05'),
    ev('a2c1', 'A2', '2026-01-05'), preg('a2c2', 'A2', '2026-04-05'),
    ev('a3', 'A3', '2026-01-05', { ranch_term: 'RP', is_clinical_result: false }),
    ev('a4c1', 'A4', '2026-01-05', { mapping_status: 'UNMAPPED', raw_code: 'DF15' }), ev('a4c2', 'A4', '2026-04-05'),
  ];

  it('shows the neutral note and never names a cause', () => {
    const f = render(events, [C1, C2, C3]);
    expect(text(q(f, 'compare-note'))).toBe('Compara resultados de palpación; no explica causas.');
    expect(text(el(f)).toLowerCase()).not.toMatch(/infertil|diagn[oó]stic|estéril/);
  });

  it('compares the two most recent campaigns by default and lets the user choose A and B, each select with a visible label', () => {
    const f = render(events, [C1, C2, C3]);
    expect(q<HTMLSelectElement>(f, 'compare-a').selectedOptions[0]?.textContent).toContain('Abril');
    expect(q<HTMLSelectElement>(f, 'compare-b').selectedOptions[0]?.textContent).toContain('Agosto');
    expect(el(f).querySelector('label[for="palp-compare-a"]')?.textContent).toContain('Campaña A');
    expect(el(f).querySelector('label[for="palp-compare-b"]')?.textContent).toContain('Campaña B');
    choose(f, 'compare-a', 'c1');
    choose(f, 'compare-b', 'c2');
    expect(text(q(f, 'compare-universe'))).toContain('Enero o en Abril');
  });

  it('shows each count with its denominator ("n de N") and the totals of the rows and columns', () => {
    const f = render(events, [C1, C2, C3]);
    choose(f, 'compare-a', 'c1');
    choose(f, 'compare-b', 'c2');
    // c1: A0 vacía, A1 vacía, A2 vacía, A3 rancho, A4 vacía = 4 vacías, 1 rancho; c2: A0 vacía, A2 preñada, A4 vacía
    expect(text(q(f, 'transition-table').querySelector('[data-cell="VACÍA>VACÍA"]'))).toBe('2 de 4');
    expect(text(q(f, 'transition-table').querySelector('[data-cell="VACÍA>PREÑADA"]'))).toBe('1 de 4');
    expect(text(q(f, 'transition-table').querySelector('[data-cell="VACÍA>NO_PALPADA"]'))).toBe('1 de 4'); // A1
    expect(text(q(f, 'transition-table').querySelector('[data-cell="RANCHO>NO_PALPADA"]'))).toBe('1 de 1'); // A3
    expect(text(q(f, 'transition-table').querySelector('[data-total-row="VACÍA"]'))).toBe('4');
    expect(text(q(f, 'transition-table').querySelector('[data-total-col="VACÍA"]'))).toBe('2');
    // a row with nobody in it shows a dash instead of "0 de 0"
    expect(text(q(f, 'transition-table').querySelector('[data-cell="PREÑADA>VACÍA"]'))).toBe('—');
  });

  it('gives the table an accessible name and column and row headers, and writes the category names in the headers', () => {
    const f = render(events, [C1, C2]);
    const table = q<HTMLTableElement>(f, 'transition-table');
    expect(text(table.querySelector('caption'))).toContain('Animales por resultado en Enero (filas) y en Abril (columnas)');
    expect(table.querySelectorAll('thead th[scope="col"]').length).toBe(7);
    expect(table.querySelectorAll('tbody th[scope="row"]').length).toBe(5);
    expect(text(table.querySelector('thead'))).toContain('No palpada en esa campaña');
    expect(text(table.querySelector('thead'))).toContain('Definido por el rancho');
  });

  it('flags the animals with an unconfirmed code without leaving the result they carry', () => {
    const f = render(events, [C1, C2]);
    expect(text(q(f, 'compare-unconfirmed'))).toContain('código sin confirmar: 1 en Enero y 0 en Abril');
    expect(text(q(f, 'compare-unconfirmed'))).toContain('no se interpreta');
  });

  it('asks for two different campaigns when A and B are the same, and shows no table', () => {
    const f = render(events, [C1, C2, C3]);
    choose(f, 'compare-a', 'c3');
    expect(q(f, 'compare-same')).not.toBeNull();
    expect(el(f).querySelector('[data-testid="transition-table"]')).toBeNull();
  });

  it('says so when no palpation falls in the two campaigns', () => {
    const f = render([ev('x', 'A0', '2026-06-01')], [C1, C2]);
    expect(text(q(f, 'compare-empty'))).toContain('Ninguna palpación');
  });

  it('lists the animals without pregnancy in any campaign: "Vacía en la única campaña" and "Vacía en N campañas"', () => {
    const f = render(events, [C1, C2, C3]);
    expect(text(q(f, 'never-count'))).toContain('3');
    const rows = qa(f, 'never-row');
    const byId = (id: string) => rows.find(r => text(r).includes(id));
    expect(text(byId('9999000100')?.querySelector('[data-testid="never-label"]'))).toBe('Vacía en 3 campañas'); // A0
    expect(text(byId('9999000101')?.querySelector('[data-testid="never-label"]'))).toBe('Vacía en la única campaña'); // A1
    expect(text(byId('9999000104')?.querySelector('[data-testid="never-label"]'))).toBe('Vacía en 2 campañas'); // A4
    expect(byId('9999000102')).toBeUndefined(); // A2 was pregnant in c2
  });

  it('shows a column "Con código sin confirmar" with the code as typed, and "No" for the others', () => {
    const f = render(events, [C1, C2, C3]);
    expect(text(el(f).querySelector('[data-testid="never-table"] thead'))).toContain('Con código sin confirmar');
    const flags = qa(f, 'never-flag').map(text);
    expect(flags.filter(x => x.startsWith('Sí'))).toEqual(['Sí: DF15']);
    expect(flags.filter(x => x === 'No').length).toBe(2);
  });

  it('shows what each animal was in the campaigns where it was palpated, and names the others in one line, in words', () => {
    const f = render(events, [C1, C2, C3]);
    const a1 = qa(f, 'never-row').find(r => text(r).includes('9999000101'));
    expect(text(a1)).toContain('Enero: Vacía');
    expect(text(a1)).not.toContain('Abril: ');
    expect(text(a1?.querySelector('[data-testid="never-missing"]'))).toBe('No palpada en: Abril, Agosto');
    const a0 = qa(f, 'never-row').find(r => text(r).includes('9999000100'));
    expect(text(a0)).toContain('Enero: Vacía');
    expect(text(a0)).toContain('Abril: Vacía');
    expect(text(a0)).toContain('Agosto: Vacía');
    expect(a0?.querySelector('[data-testid="never-missing"]')).toBeNull();
  });

  it('keeps ranch terms apart, in their own group, and does not count them as vacías', () => {
    const f = render(events, [C1, C2, C3]);
    const group = q(f, 'uninterpreted-group');
    expect(text(group.querySelector('[data-testid="uninterpreted-count"]'))).toContain('1');
    expect(text(group.querySelector('[data-testid="uninterpreted-row"]'))).toContain('9999000103');
    expect(text(group.querySelector('[data-testid="uninterpreted-row"]'))).toContain('Sin interpretar en la única campaña');
    expect(qa(f, 'never-row').some(r => text(r).includes('9999000103'))).toBe(false);
  });

  it('says so when no animal meets the condition, and when the second group is empty', () => {
    const f = render([preg('p1', 'A0', '2026-01-05'), preg('p2', 'A0', '2026-04-05')], [C1, C2]);
    expect(q(f, 'never-empty')).not.toBeNull();
    expect(el(f).querySelector('[data-testid="never-table"]')).toBeNull();
    expect(q(f, 'uninterpreted-empty')).not.toBeNull();
  });

  it('lists each animal once and pages a long list', () => {
    const many = Array.from({ length: 25 }, (_, i) => ev(`m${i}`, `A${i}`, '2026-01-05'));
    const f = render(many, [C1, C2]);
    expect(qa(f, 'never-row').length).toBe(10);
    expect(text(q(f, 'never-count'))).toContain('25');
    expect(text(el(f))).toContain('Mostrando 1 a 10 de 25');
  });

  it('searches the list by identifier', () => {
    const many = Array.from({ length: 12 }, (_, i) => ev(`m${i}`, `A${i}`, '2026-01-05'));
    const f = render(many, [C1, C2]);
    const input = el(f).querySelector('app-table-toolbar input') as HTMLInputElement;
    input.value = '9999000103';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    f.detectChanges();
    expect(qa(f, 'never-row').length).toBe(1);
  });

  it('does not show a technician anywhere', () => {
    const f = render(events.map(e => ({ ...e, technician: 'Técnico demo' })), [C1, C2, C3]);
    expect(text(el(f))).not.toContain('Técnico');
  });
});
