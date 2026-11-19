import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { Campaign, CampaignError } from '../../utils/palpation-campaigns';
import { PalpationCampaignsEditorComponent } from './palpation-campaigns-editor.component';

const camp = (id: string, label: string, from: string, to: string): Campaign => ({ id, label, from, to });
const TWO = [camp('camp-1', 'Campaña 1', '2026-09-01', '2026-09-10'), camp('camp-2', 'Campaña 2', '2026-11-01', '2026-11-10')];

function render(campaigns: readonly Campaign[], extra: { errors?: CampaignError[]; suggested?: boolean } = {}) {
  const f: ComponentFixture<PalpationCampaignsEditorComponent> = TestBed.createComponent(PalpationCampaignsEditorComponent);
  f.componentRef.setInput('campaigns', campaigns);
  f.componentRef.setInput('errors', extra.errors ?? []);
  f.componentRef.setInput('suggested', extra.suggested ?? false);
  const emitted: Campaign[][] = [];
  f.componentInstance.campaignsChange.subscribe(v => emitted.push(v));
  let resuggested = 0;
  f.componentInstance.resuggest.subscribe(() => (resuggested += 1));
  f.detectChanges();
  return { f, emitted, resuggested: () => resuggested };
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const q = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`) as T;
const qa = <T extends HTMLElement>(f: ComponentFixture<unknown>, id: string) => [...el(f).querySelectorAll(`[data-testid="${id}"]`)] as T[];
const type = (input: HTMLInputElement, value: string) => {
  input.value = value;
  input.dispatchEvent(new Event('change', { bubbles: true }));
};

describe('PalpationCampaignsEditorComponent', () => {
  it('shows one row per campaign with its name and its two dates, each control with a visible label', () => {
    const { f } = render(TWO);
    expect(qa(f, 'campaign-row').length).toBe(2);
    expect((qa<HTMLInputElement>(f, 'campaign-label')[1]).value).toBe('Campaña 2');
    expect((qa<HTMLInputElement>(f, 'campaign-from')[0]).value).toBe('2026-09-01');
    expect((qa<HTMLInputElement>(f, 'campaign-to')[0]).value).toBe('2026-09-10');
    for (const input of el(f).querySelectorAll('input')) {
      const label = el(f).querySelector(`label[for="${input.id}"]`);
      expect(label?.textContent?.trim().length).toBeGreaterThan(0);
    }
  });

  it('emits the whole new list when a name or a date is edited, and does not touch the others', () => {
    const { f, emitted } = render(TWO);
    type(qa<HTMLInputElement>(f, 'campaign-label')[0], 'Monta de septiembre');
    type(qa<HTMLInputElement>(f, 'campaign-to')[1], '2026-11-20');
    expect(emitted[0]?.map(c => c.label)).toEqual(['Monta de septiembre', 'Campaña 2']);
    expect(emitted[1]?.[1]).toMatchObject({ from: '2026-11-01', to: '2026-11-20' });
    expect(emitted[1]?.[0]?.label).toBe('Campaña 1');
  });

  it('adds a campaign with a new id and name up to the maximum of 6, then disables the button and says why', () => {
    let list: Campaign[] = [...TWO];
    for (let i = 0; i < 4; i++) {
      const { f, emitted } = render(list);
      expect(q<HTMLButtonElement>(f, 'campaign-add').disabled).toBe(false);
      q<HTMLButtonElement>(f, 'campaign-add').click();
      list = emitted[0] as Campaign[];
    }
    expect(list.length).toBe(6);
    expect(new Set(list.map(c => c.id)).size).toBe(6);
    expect(new Set(list.map(c => c.label)).size).toBe(6);
    const { f, emitted } = render(list);
    expect(q<HTMLButtonElement>(f, 'campaign-add').disabled).toBe(true);
    q<HTMLButtonElement>(f, 'campaign-add').click();
    expect(emitted.length).toBe(0);
    expect(q(f, 'campaign-max').textContent).toContain('6');
  });

  it('adds an empty range for the user to fill in, not a guessed one', () => {
    const { f, emitted } = render(TWO);
    q<HTMLButtonElement>(f, 'campaign-add').click();
    expect(emitted[0]?.[2]).toMatchObject({ from: '', to: '' });
  });

  it('gives a new campaign a name that is not already taken', () => {
    const { f, emitted } = render([camp('camp-1', 'Campaña 3', '2026-09-01', '2026-09-10'), camp('camp-2', 'Otra', '2026-11-01', '2026-11-10')]);
    q<HTMLButtonElement>(f, 'campaign-add').click();
    expect(emitted[0]?.[2]?.label).toBe('Campaña 4');
  });

  it('removes a campaign, but not below the minimum of 2 (the buttons are disabled and a note says why)', () => {
    const three = [...TWO, camp('camp-3', 'Campaña 3', '2026-12-01', '2026-12-10')];
    const a = render(three);
    qa<HTMLButtonElement>(a.f, 'campaign-remove')[1]?.click();
    expect(a.emitted[0]?.map(c => c.id)).toEqual(['camp-1', 'camp-3']);

    const b = render(TWO);
    expect(qa<HTMLButtonElement>(b.f, 'campaign-remove').every(x => x.disabled)).toBe(true);
    qa<HTMLButtonElement>(b.f, 'campaign-remove')[0]?.click();
    expect(b.emitted.length).toBe(0);
    expect(q(b.f, 'campaign-min').textContent).toContain('2');
  });

  it('names the campaign in the accessible name of each remove button', () => {
    const { f } = render([...TWO, camp('camp-3', 'Monta de diciembre', '2026-12-01', '2026-12-10')]);
    expect(qa<HTMLButtonElement>(f, 'campaign-remove')[2]?.getAttribute('aria-label')).toBe('Quitar la campaña Monta de diciembre');
  });

  it('shows the errors of a campaign next to it and marks the fields invalid, and shows the errors of the whole list', () => {
    const errors: CampaignError[] = [
      { id: 'camp-2', code: 'overlap', other: 'Campaña 1' },
      { id: 'camp-1', code: 'label-empty', other: null },
      { id: null, code: 'too-few', other: null },
    ];
    const { f } = render(TWO, { errors });
    const rows = qa(f, 'campaign-row');
    expect(rows[1]?.textContent).toContain('Campaña 1');
    expect(rows[1]?.textContent).toContain('traslapa');
    expect(rows[0]?.textContent).toContain('Escribe un nombre');
    expect(qa<HTMLInputElement>(f, 'campaign-from')[1]?.getAttribute('aria-invalid')).toBe('true');
    expect(qa<HTMLInputElement>(f, 'campaign-label')[0]?.getAttribute('aria-invalid')).toBe('true');
    expect(qa<HTMLInputElement>(f, 'campaign-label')[1]?.getAttribute('aria-invalid')).toBe('false');
    expect(q(f, 'campaign-list-errors').textContent).toContain('al menos 2 campañas');
  });

  it('says the ranges are an automatic proposal, and lets the user ask for another one', () => {
    const { f, resuggested } = render(TWO, { suggested: true });
    expect(q(f, 'campaign-suggested').textContent).toContain('Propuesta automática');
    expect(q(f, 'campaign-suggested').textContent).toContain('7 días');
    q<HTMLButtonElement>(f, 'campaign-suggest').click();
    expect(resuggested()).toBe(1);
  });

  it('does not say "propuesta automática" once the user edited the list', () => {
    const { f } = render(TWO, { suggested: false });
    expect(el(f).querySelector('[data-testid="campaign-suggested"]')).toBeNull();
  });

  it('explains an empty proposal and still lets the user add ranges', () => {
    const { f, emitted } = render([], { suggested: true });
    expect(q(f, 'campaign-none').textContent).toContain('No se pudo proponer');
    expect(el(f).querySelector('[data-testid="campaign-suggested"]')).toBeNull();
    q<HTMLButtonElement>(f, 'campaign-add').click();
    expect(emitted[0]?.length).toBe(1);
  });

  it('can be used with the keyboard: every control is a native button or input and none removes itself from the tab order', () => {
    const { f } = render(TWO);
    const controls = [...el(f).querySelectorAll('button, input')] as HTMLElement[];
    expect(controls.length).toBeGreaterThan(8);
    expect(controls.every(c => c.getAttribute('tabindex') !== '-1')).toBe(true);
    expect(el(f).querySelectorAll('[role="button"]').length).toBe(0);
  });
});
