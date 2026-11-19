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

function render(events: ReturnType<typeof eventRow>[], campaigns: readonly Campaign[], ready?: { status: 'listo' | 'truncado'; tenantId: number }) {
  const f: ComponentFixture<PalpationCampaignCompareComponent> = TestBed.createComponent(PalpationCampaignCompareComponent);
  f.componentRef.setInput('events', events);
  f.componentRef.setInput('herd', herd);
  f.componentRef.setInput('campaigns', campaigns);
  if (ready) {
    f.componentRef.setInput('reportStatus', ready.status);
    f.componentRef.setInput('tenantId', ready.tenantId);
  }
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
    const input = el(f).querySelector('[aria-labelledby="palp-never-title"] app-table-toolbar input') as HTMLInputElement;
    input.value = '9999000103';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    f.detectChanges();
    expect(qa(f, 'never-row').length).toBe(1);
  });

  it('does not show a technician anywhere', () => {
    const f = render(events.map(e => ({ ...e, technician: 'Técnico demo' })), [C1, C2, C3]);
    expect(text(el(f))).not.toContain('Técnico');
  });

  describe('follow-up lists of the selected pair', () => {
    it('shows the persistent and pending lists for the selected pair A and B, between the transitions and the existing list', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      const html = el(f).innerHTML;
      expect(html.indexOf('data-testid="transition-table"')).toBeLessThan(html.indexOf('data-testid="pairs-section"'));
      expect(html.indexOf('data-testid="pairs-section"')).toBeLessThan(html.indexOf('palp-never-title'));
      expect(text(q(f, 'pairs-section').querySelector('h3'))).toBe('Seguimiento de vacías: Enero y Abril');
      expect(qa(f, 'persistent-row').length).toBeGreaterThan(0);
    });

    it('uses ONLY the selected pair: changing B changes the groups, while the "Sin indicios" list keeps using all the campaigns', () => {
      const f = render(events, [C1, C2, C3]);
      const neverBefore = text(q(f, 'never-count'));
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      const persistentAB = text(q(f, 'persistent-count'));
      choose(f, 'compare-b', 'c3');
      expect(text(q(f, 'persistent-count'))).not.toBe(persistentAB);
      expect(text(q(f, 'never-count'))).toBe(neverBefore);
      expect(el(f).querySelectorAll('[data-testid="never-row"]').length).toBe(qa(f, 'never-row').length);
    });

    it('leaves the existing "Sin indicios de preñez" list unchanged', () => {
      const f = render(events, [C1, C2, C3]);
      expect(text(q(f, 'never-count'))).toContain('3');
      expect(qa(f, 'never-row').length).toBe(3);
      expect(el(f).querySelector('#palp-never-title')?.textContent).toBe('Sin indicios de preñez en ninguna campaña');
    });

    it('does not show the follow-up lists when A and B are the same campaign', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c3');
      expect(el(f).querySelector('[data-testid="pairs-section"]')).toBeNull();
    });

    it('starts with the export disabled (the parent has to say the report is ready) and enables it with a ready report and a company', () => {
      const closed = render(events, [C1, C2, C3]);
      expect(q<HTMLButtonElement>(closed, 'pairs-export').disabled).toBe(true);
      TestBed.resetTestingModule();
      const open = render(events, [C1, C2, C3], { status: 'listo', tenantId: 9101 });
      expect(q<HTMLButtonElement>(open, 'pairs-export').disabled).toBe(false);
    });

    it('keeps the export disabled for a truncated report', () => {
      const f = render(events, [C1, C2, C3], { status: 'truncado', tenantId: 9101 });
      expect(q<HTMLButtonElement>(f, 'pairs-export').disabled).toBe(true);
      expect(text(q(f, 'pairs-export-why'))).toContain('incompleto');
    });
  });

  describe('phone layout (stacked cards instead of tables that need a sideways scroll)', () => {
    const cardText = (n: Element | null | undefined) => text(n);

    it('shows the "sin indicios" list as cards on phones and as a table from the md breakpoint, never both at once', () => {
      const f = render(events, [C1, C2, C3]);
      expect(q(f, 'never-table').closest('.table-responsive')?.className).toContain('d-none d-md-block');
      expect(q(f, 'never-cards').className).toContain('d-md-none');
      expect(qa(f, 'never-card').length).toBe(qa(f, 'never-row').length);
    });

    it('puts the "con código sin confirmar" flag inside each card, with the code as typed, so no sideways scroll is needed to see it', () => {
      const f = render(events, [C1, C2, C3]);
      const cards = qa(f, 'never-card');
      const flags = cards.map(c => cardText(c.querySelector('[data-testid="never-card-flag"]')));
      expect(flags.every(x => x.startsWith('Con código sin confirmar:'))).toBe(true);
      expect(flags.filter(x => x.includes('Sí: DF15')).length).toBe(1);
      expect(flags.filter(x => x.endsWith('No')).length).toBe(2);
      const flagged = cards.find(c => cardText(c).includes('9999000104'));
      expect(cardText(flagged)).toContain('Vacía en 2 campañas');
      expect(cardText(flagged)).toContain('Sí: DF15');
    });

    it('a card has the identifier, the wording of the result, one line per palpated campaign and the campaigns without palpation', () => {
      const f = render(events, [C1, C2, C3]);
      const a1 = qa(f, 'never-card').find(c => cardText(c).includes('9999000101'));
      expect(cardText(a1?.querySelector('[data-testid="never-card-label"]'))).toBe('Vacía en la única campaña');
      expect(cardText(a1)).toContain('Enero: Vacía');
      expect(cardText(a1)).toContain('No palpada en: Abril, Agosto');
      expect(cardText(a1)).toContain('VACA · ACTIVO');
    });

    it('pages the cards together with the table (10 per page)', () => {
      const many = Array.from({ length: 25 }, (_, i) => ev(`m${i}`, `A${i}`, '2026-01-05'));
      const f = render(many, [C1, C2]);
      expect(qa(f, 'never-card').length).toBe(10);
    });

    it('shows the transition table as cards on phones, one per category of campaign A, plus a card with the totals of campaign B', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      expect(q(f, 'transition-table').closest('.table-responsive')?.className).toContain('d-none d-md-block');
      expect(q(f, 'transition-cards').className).toContain('d-md-none');
      const cards = [...el(f).querySelectorAll('[data-testid="transition-cards"] [data-card-row]')];
      expect(cards.map(c => c.getAttribute('data-card-row'))).toEqual(['PREÑADA', 'VACÍA', 'RANCHO', 'SIN_INTERPRETAR', 'NO_PALPADA']);
      expect(q(f, 'transition-cards-total')).not.toBeNull();
    });

    it('lists every category of campaign B in each non-empty card, including "Sin interpretar" and "No palpada en esa campaña", each as "n de N"', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      const vacia = el(f).querySelector('[data-testid="transition-cards"] [data-card-row="VACÍA"]') as HTMLElement;
      const lines = [...vacia.querySelectorAll('[data-card-cell]')].map(li => [li.getAttribute('data-card-cell'), text(li)]);
      expect(lines.map(l => l[0])).toEqual(['VACÍA>PREÑADA', 'VACÍA>VACÍA', 'VACÍA>RANCHO', 'VACÍA>SIN_INTERPRETAR', 'VACÍA>NO_PALPADA']);
      expect(text(vacia.querySelector('[data-card-cell="VACÍA>VACÍA"]'))).toBe('Vacía 2 de 4');
      expect(text(vacia.querySelector('[data-card-cell="VACÍA>PREÑADA"]'))).toBe('Preñada 1 de 4');
      expect(text(vacia.querySelector('[data-card-cell="VACÍA>SIN_INTERPRETAR"]'))).toBe('Sin interpretar 0 de 4');
      expect(text(vacia.querySelector('[data-card-cell="VACÍA>NO_PALPADA"]'))).toBe('No palpada en esa campaña 1 de 4');
      expect(text(vacia.querySelector('[data-card-total]'))).toBe('4');
    });

    it('says so in a card whose category has no animals, instead of listing zeros', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      const sinInterpretar = el(f).querySelector('[data-testid="transition-cards"] [data-card-row="SIN_INTERPRETAR"]') as HTMLElement;
      expect(text(sinInterpretar)).toContain('Ningún animal en esta categoría.');
      expect(sinInterpretar.querySelectorAll('[data-card-cell]').length).toBe(0);
    });

    it('exposes every total of the table in the cards: the total of each row, of each column and the universe', () => {
      const f = render(events, [C1, C2, C3]);
      choose(f, 'compare-a', 'c1');
      choose(f, 'compare-b', 'c2');
      for (const cat of ['PREÑADA', 'VACÍA', 'RANCHO', 'SIN_INTERPRETAR', 'NO_PALPADA']) {
        const tableRowTotal = text(q(f, 'transition-table').querySelector(`[data-total-row="${cat}"]`));
        const cardRowTotal = text(el(f).querySelector(`[data-card-row="${cat}"] [data-card-total]`));
        expect(cardRowTotal).toBe(tableRowTotal);
        const tableColTotal = text(q(f, 'transition-table').querySelector(`[data-total-col="${cat}"]`));
        const cardColTotal = text(el(f).querySelector(`[data-card-col-total="${cat}"] strong`));
        expect(cardColTotal).toBe(tableColTotal);
      }
      expect(text(q(f, 'transition-cards-total'))).toContain('Animales comparados: 5');
      expect(text(q(f, 'transition-cards-total'))).toContain('Total en Abril');
    });

    it('keeps card titles short (a category and a campaign name, never a header that wraps over several lines)', () => {
      const f = render(events, [C1, C2, C3]);
      for (const h of el(f).querySelectorAll('[data-testid="transition-cards"] h4')) expect(text(h).length).toBeLessThanOrEqual(32);
    });

    it('writes the neutral note and the unconfirmed-code flag with pieces that set their own readable colours', () => {
    const f = render(events, [C1, C2, C3]);
    const note = q(f, 'compare-note');
    expect(note.tagName.toLowerCase()).toBe('app-palp-note');
    expect(note.getAttribute('role')).toBe('note');
    expect(text(note)).toBe('Compara resultados de palpación; no explica causas.');
    expect(el(f).querySelector('.alert-secondary')).toBeNull();
    const flags = [...el(f).querySelectorAll('app-palp-flag')].map(text);
    expect(flags.length).toBe(2); // the table row and the phone card of the one flagged animal
    expect(flags.every(x => x === 'Sí: DF15')).toBe(true);
    expect(el(f).querySelector('.badge.bg-secondary-lt')).toBeNull();
  });

  it('keeps the corner heading of the desktop table on one line', () => {
      const f = render(events, [C1, C2]);
      expect(q(f, 'transition-table').querySelector('th.palp-corner')).not.toBeNull();
    });
  });
});
