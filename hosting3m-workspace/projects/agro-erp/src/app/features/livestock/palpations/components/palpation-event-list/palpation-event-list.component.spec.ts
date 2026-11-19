import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { eventRow, herdRow } from '../../testing/palpation.fixtures';
import { campaignEventRows } from '../../utils/palpation-campaign-compare';
import { Campaign } from '../../utils/palpation-campaigns';
import { colorForKey } from '../../utils/palpation-colors';
import { EVENT_SEARCH_HINT, EVENT_SEARCH_PLACEHOLDER, PalpationEventListComponent } from './palpation-event-list.component';

const camp = (id: string, label: string, from: string, to: string): Campaign => ({ id, label, from, to });
const C1 = camp('c1', 'Septiembre', '2026-09-01', '2026-09-15');
const C2 = camp('c2', 'Noviembre', '2026-11-01', '2026-11-15');
const CAMPAIGNS = [C1, C2];

const ev = (id: string, animal: string, day: string, over: Parameters<typeof eventRow>[0] = {}) =>
  eventRow({ health_log_id: id, livestock_id: animal, event_date: day, result: 'VACÍA', technician: 'Técnico demo 1', ...over });
const herd = Array.from({ length: 40 }, (_, i) => herdRow({ livestock_id: `A${i}`, rfid_siniiga: `99990002${String(i).padStart(2, '0')}`, category: 'VACA', current_status: 'ACTIVO' }));

function render(events: ReturnType<typeof eventRow>[], campaigns: readonly Campaign[] = CAMPAIGNS) {
  const f: ComponentFixture<PalpationEventListComponent> = TestBed.createComponent(PalpationEventListComponent);
  f.componentRef.setInput('rows', campaignEventRows(events, herd, campaigns));
  f.componentRef.setInput('campaigns', campaigns);
  f.detectChanges();
  return f;
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const q = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`) as T;
const qa = (f: ComponentFixture<unknown>, id: string) => [...el(f).querySelectorAll(`[data-testid="${id}"]`)] as HTMLElement[];
const text = (n: Element | null | undefined) => (n?.textContent ?? '').replace(/\s+/g, ' ').trim();
const ids = (f: ComponentFixture<unknown>) => qa(f, 'event-row').map(r => (r.querySelector('th')?.childNodes[0]?.textContent ?? '').trim());

describe('PalpationEventListComponent', () => {
  const events = [
    ev('e1', 'A1', '2026-09-03'),
    ev('e2', 'A2', '2026-09-10', { result: 'PREÑADA', gestation_days: 120 }),
    ev('e3', 'A3', '2026-11-04'),
    ev('e4', 'A1', '2026-11-09', { result: 'PREÑADA', gestation_days: 60 }),
    ev('nr', 'A4', '2026-11-05', { ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false }),
    ev('u', 'A5', '2026-09-12', { mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
    ev('h', 'A6', '2026-09-01', { is_historical_load: true }),
    ev('out', 'A7', '2026-10-10'),
  ];

  it('has one row per event inside a campaign, each once, and none from outside the campaigns', () => {
    const f = render(events);
    expect(qa(f, 'event-row').length).toBe(7);
    expect(text(q(f, 'events-count'))).toContain('7');
    expect(text(q(f, 'events-table'))).not.toContain('9999000207'); // A7 is outside every campaign
  });

  it('starts ordered by campaign, and by date (newest first) inside each campaign', () => {
    const f = render(events);
    const rows = qa(f, 'event-row').map(r => [text(r.querySelectorAll('td')[0]), text(r.querySelectorAll('td')[1])]);
    expect(rows).toEqual([
      ['Septiembre', '12/09/2026'], ['Septiembre', '10/09/2026'], ['Septiembre', '03/09/2026'], ['Septiembre', '01/09/2026'],
      ['Noviembre', '09/11/2026'], ['Noviembre', '05/11/2026'], ['Noviembre', '04/11/2026'],
    ]);
  });

  it('has a Campaña column and no technician column or text', () => {
    const f = render(events);
    const heads = [...el(f).querySelectorAll('[data-testid="events-table"] thead th')].map(h => text(h).replace(/[▲▼]/g, '').trim());
    expect(heads).toEqual(['Campaña', 'Fecha', 'Identificador', 'Resultado', 'Gestación', 'Estado', 'Detalle']);
    expect(heads.join(' ')).not.toMatch(/Técnico/);
    expect(text(el(f))).not.toContain('Técnico demo');
  });

  it('lists an NR and says it does not count as a palpation', () => {
    const f = render(events);
    const nr = qa(f, 'event-row').find(r => text(r).includes('Término del rancho: NR'));
    expect(nr).toBeDefined();
    expect(text(nr?.querySelector('[data-testid="not-counted"]'))).toBe('No cuenta como palpada.');
    expect(q(f, 'events-table').querySelectorAll('[data-testid="not-counted"]').length).toBe(1);
  });

  it('shows an unconfirmed code as typed on a grey badge, the historical badge, and gestation only for pregnant animals', () => {
    const f = render(events);
    const rows = qa(f, 'event-row');
    const u = rows.find(r => text(r).includes('código sin confirmar'));
    expect(text(u)).toContain('código sin confirmar: DF15');
    expect(text(u)).toContain('Vacía');
    const badge = [...(u as HTMLElement).querySelectorAll('.badge')].find(b => text(b).includes('código sin confirmar'));
    expect(badge?.classList.contains('bg-secondary-lt')).toBe(true);
    expect(text(rows.find(r => text(r).includes('histórico (carga 2023)')))).toContain('Vacía');
    const pregnant = rows.find(r => text(r).includes('04/11') === false && text(r).includes('10/09/2026'));
    expect(text(pregnant)).toContain('4,0 meses (120 días)');
    const empty = rows.find(r => text(r).includes('03/09/2026'));
    expect(text(empty?.querySelectorAll('td')[3])).toBe('—'); // gestation column
  });

  it('puts the chart colour of each result next to its name, and never relies on colour alone', () => {
    const f = render([ev('p', 'A1', '2026-09-03', { result: 'PREÑADA', gestation_days: 150 })]);
    const dot = el(f).querySelector('[data-testid="events-table"] .palp-swatch') as HTMLElement;
    const hex = colorForKey('p-5');
    expect(dot.style.backgroundColor).toBe(`rgb(${[1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)).join(', ')})`);
    expect(dot.getAttribute('aria-hidden')).toBe('true');
    expect(text(q(f, 'event-row'))).toContain('Preñada');
  });

  it('filters by campaign, keeps the count in step, and goes back to all', () => {
    const f = render(events);
    const select = q<HTMLSelectElement>(f, 'events-campaign');
    select.value = 'c2';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    f.detectChanges();
    expect(qa(f, 'event-row').length).toBe(3);
    expect(qa(f, 'event-row').every(r => text(r).includes('Noviembre'))).toBe(true);
    expect(text(q(f, 'events-count'))).toContain('3');
    select.value = 'TODAS';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    f.detectChanges();
    expect(qa(f, 'event-row').length).toBe(7);
  });

  it('labels the campaign filter and the table, and exposes the sort state with aria-sort', () => {
    const f = render(events);
    expect(el(f).querySelector('label[for="palp-events-campaign"]')?.textContent).toContain('Campaña');
    expect(text(q(f, 'events-table').querySelector('caption'))).toContain('una fila por evento');
    const th = (key: string) => q(f, 'events-table').querySelector(`th:has([data-sort="${key}"])`) as HTMLElement;
    expect(th('campaign').getAttribute('aria-sort')).toBe('ascending');
    expect(th('date').getAttribute('aria-sort')).toBe('none');
  });

  it('sorts from the keyboard-reachable header buttons, toggling the direction', () => {
    const f = render(events);
    const press = (key: string) => {
      (q(f, 'events-table').querySelector(`[data-sort="${key}"]`) as HTMLButtonElement).click();
      f.detectChanges();
    };
    press('date');
    expect(qa(f, 'event-row').map(r => text(r.querySelectorAll('td')[1]))[0]).toBe('09/11/2026'); // newest first on the first press
    press('date');
    expect(qa(f, 'event-row').map(r => text(r.querySelectorAll('td')[1]))[0]).toBe('01/09/2026');
    press('identifier');
    expect(ids(f)[0]).toBe('9999000201');
    press('identifier');
    expect(ids(f)[0]).toBe('9999000206');
    expect(q(f, 'events-table').querySelector('th:has([data-sort="identifier"])')?.getAttribute('aria-sort')).toBe('descending');
    for (const b of q(f, 'events-table').querySelectorAll('thead button')) expect((b as HTMLButtonElement).tabIndex).not.toBe(-1);
  });

  it('searches by identifier, campaign and unconfirmed code, and does not search the technician', () => {
    const f = render(events);
    const search = (value: string) => {
      const input = el(f).querySelector('app-table-toolbar input') as HTMLInputElement;
      input.value = value;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      f.detectChanges();
    };
    search('9999000203');
    expect(qa(f, 'event-row').length).toBe(1);
    search('noviembre');
    expect(qa(f, 'event-row').length).toBe(3);
    search('df15');
    expect(qa(f, 'event-row').length).toBe(1);
    search('Técnico demo 1');
    expect(qa(f, 'event-row').length).toBe(0);
    expect(q(f, 'events-no-match')).not.toBeNull();
    expect(EVENT_SEARCH_HINT).not.toMatch(/técnico/i);
    expect(EVENT_SEARCH_PLACEHOLDER.length).toBeLessThanOrEqual(34);
  });

  it('pages a long list (10 per page, as the selector shows) and shows the range and the total', () => {
    const many = Array.from({ length: 30 }, (_, i) => ev(`m${i}`, `A${i}`, '2026-09-05'));
    const f = render(many);
    expect(qa(f, 'event-row').length).toBe(10);
    expect(text(el(f))).toContain('Mostrando 1 a 10 de 30');
    expect((el(f).querySelector('app-table-footer select') as HTMLSelectElement).value).toBe('10');
  });

  it('renders stacked cards for a phone with the campaign, the date and the same result', () => {
    const f = render(events);
    expect(qa(f, 'event-card').length).toBe(7);
    const card = qa(f, 'event-card')[0];
    expect(text(card)).toContain('Septiembre');
    expect(text(card)).toContain('12/09/2026');
    expect(text(card)).not.toContain('Técnico demo');
  });

  it('says so when no event falls in the campaigns, and shows the visible note', () => {
    const f = render([ev('x', 'A1', '2026-06-01')]);
    expect(text(q(f, 'events-empty'))).toContain('Ninguna palpación');
    expect(text(q(f, 'events-note'))).toBe('Compara resultados de palpación; no explica causas.');
    expect(el(f).querySelector('[data-testid="events-table"]')).toBeNull();
  });

  it('goes back to all the campaigns when the chosen campaign is removed', () => {
    const f = render(events);
    const select = q<HTMLSelectElement>(f, 'events-campaign');
    select.value = 'c2';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    f.detectChanges();
    f.componentRef.setInput('campaigns', [C1]);
    f.componentRef.setInput('rows', campaignEventRows(events, herd, [C1]));
    f.detectChanges();
    expect(qa(f, 'event-row').length).toBe(4);
    expect(q<HTMLSelectElement>(f, 'events-campaign').value).toBe('TODAS');
  });
});
