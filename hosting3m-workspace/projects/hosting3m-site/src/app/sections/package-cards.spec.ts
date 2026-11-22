import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { PlansService, parsePlans } from '../core/plans';
import { PlansSection } from './plans-section';

const base = {
  summary: 'Resumen de prueba', features: ['Uno', 'Dos'], badge: null, billing_period: 'yearly', price_amount: 1000, managed_amount: null, promo_amount: null, promo_months: null,
  renewal_amount: null, setup_fee: null, term_months: null, currency: 'MXN', tax_included: false, valid_until: null, is_featured: false, price_checked_at: '2026-11-01',
};
const plan = (over: Record<string, unknown>) => ({ ...base, service_label: 'Servicio', sort_order: 1, ...over });
const quote = (over: Record<string, unknown> = {}) => plan({ billing_period: 'quote', price_amount: null, price_checked_at: null, ...over });

function render(plans: unknown[]) {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
  const fixture = TestBed.createComponent(PlansSection);
  fixture.detectChanges();
  return fixture.nativeElement as HTMLElement;
}
const before = (a: Element, b: Element) => Boolean(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);

describe('package cards polish', () => {
  it('quote-only cards list the features BEFORE the CTA, in the same order as priced cards', () => {
    const el = render([quote({ plan_key: 'q', family: 'email', name: 'Correo profesional' }), plan({ plan_key: 'p', family: 'vps', name: 'VPS', sort_order: 0 })]);
    const [priced, quoted] = Array.from(el.querySelectorAll('[data-testid="plan-card"]'));
    for (const card of [priced, quoted]) {
      const list = card.querySelector('ul')!;
      const cta = card.querySelector('[data-testid="quote-cta"], [data-testid="quote-plan"]')!;
      expect(list.textContent).toContain('Uno');
      expect(before(list, cta)).toBe(true);
    }
    expect(quoted.querySelector('[data-testid="quote-note"]')).toBeNull();
  });

  it('every summary uses the body font (no monospace) with the same classes on quote and priced cards', () => {
    const el = render([quote({ plan_key: 'q', family: 'email', name: 'Correo' }), plan({ plan_key: 'p', family: 'vps', name: 'VPS', sort_order: 0 })]);
    const summaries = Array.from(el.querySelectorAll('[data-testid="summary"]'));
    expect(summaries).toHaveLength(2);
    expect(summaries.every((s) => !s.className.includes('font-mono'))).toBe(true);
    expect(summaries[0].className).toBe(summaries[1].className);
  });

  it('shows the price date once per group (the most recent one) and never inside a card', () => {
    const el = render([
      plan({ plan_key: 'a', family: 'vps', name: 'A', price_checked_at: '2026-11-01', sort_order: 1 }),
      plan({ plan_key: 'b', family: 'vps', name: 'B', price_checked_at: '2026-11-20', sort_order: 2 }),
      plan({ plan_key: 'c', family: 'hosting', name: 'C', price_checked_at: '2026-10-05', sort_order: 3 }),
    ]);
    const notes = Array.from(el.querySelectorAll('[data-testid="group-date"]')).map((n) => n.textContent?.trim());
    expect(notes).toEqual(['Precios vigentes al 20 de noviembre de 2026', 'Precios vigentes al 5 de octubre de 2026']);
    expect(el.querySelectorAll('[data-testid="plan-card"] [data-testid="group-date"]')).toHaveLength(0);
    expect(Array.from(el.querySelectorAll('[data-testid="plan-card"]')).some((c) => c.textContent?.includes('Precios vigentes'))).toBe(false);
  });

  it('groups of quote-only plans show no date note', () => {
    const el = render([quote({ plan_key: 'q', family: 'email', name: 'Correo' })]);
    expect(el.querySelector('[data-testid="group-date"]')).toBeNull();
  });

  it('a group of four plans uses 2 columns up to xl and 4 from xl (no orphan); groups of one to three keep 3 columns at lg', () => {
    const four = ['a', 'b', 'c', 'd'].map((k, i) => plan({ plan_key: k, family: 'vps', name: k, sort_order: i }));
    const three = ['e', 'f', 'g'].map((k, i) => plan({ plan_key: k, family: 'hosting', name: k, sort_order: 10 + i }));
    const one = [plan({ plan_key: 'h', family: 'web', name: 'h', sort_order: 20 })];
    const grids = Array.from(render([...four, ...three, ...one]).querySelectorAll('[data-testid="plan-grid"]'));
    expect(grids).toHaveLength(3);
    expect(grids[0].className).toContain('sm:grid-cols-2');
    expect(grids[0].className).toContain('xl:grid-cols-4');
    expect(grids[0].className).not.toContain('lg:grid-cols-3');
    for (const g of [grids[1], grids[2]]) {
      expect(g.className).toContain('lg:grid-cols-3');
      expect(g.className).not.toContain('xl:grid-cols-4');
    }
    expect(grids.every((g) => !g.className.split(' ').some((c) => /^grid-cols-[2-9]$/.test(c)))).toBe(true); // 1 column on phones
  });

  it('the managed toggle stacks in narrow cards (container query) so four-column groups do not clip it', () => {
    const el = render([plan({ plan_key: 'a', family: 'vps', name: 'A', managed_amount: 2000 })]);
    const toggle = el.querySelector('[role="group"]')!;
    expect(toggle.className).toContain('flex-col');
    expect(toggle.className).toContain('@xs:flex-row');
    expect(el.querySelector('[data-testid="plan-card"]')?.className).toContain('@container');
  });
});
