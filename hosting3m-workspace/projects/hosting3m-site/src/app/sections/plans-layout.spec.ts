import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { PlansService, parsePlans, splitQuotePlans } from '../core/plans';
import { PlansSection } from './plans-section';

const priced = (over: Record<string, unknown>) => ({
  summary: null, features: [], badge: null, billing_period: 'yearly', price_amount: 340, managed_amount: null, promo_amount: null, promo_months: null, renewal_amount: null,
  setup_fee: null, term_months: null, currency: 'MXN', tax_included: false, valid_until: null, is_featured: false, price_checked_at: '2026-11-20', service_label: 'Servicio', sort_order: 1, ...over,
});
const quote = (over: Record<string, unknown>) => priced({ billing_period: 'quote', price_amount: null, price_checked_at: null, ...over });

function render(plans: unknown[]) {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
  const fixture = TestBed.createComponent(PlansSection);
  fixture.detectChanges();
  return fixture.nativeElement as HTMLElement;
}

const DOMAINS = [['.com', 340], ['.mx', 700], ['.com.mx', 500], ['.org', 400], ['.net', 400], ['.ai', 2750]].map(([name, price], i) =>
  priced({ plan_key: `domain${name}`, family: 'domain', name, price_amount: price, sort_order: 210 + i * 10 }),
);
const AUTOMATION = quote({ plan_key: 'n8n', family: 'automation', name: 'n8n administrado', service_label: 'Automatización de Procesos con Agentes IA', sort_order: 310 });
const WEB = quote({ plan_key: 'web', family: 'web', name: 'Paquete de lanzamiento', service_label: 'Creación de Páginas Web', sort_order: 320 });
const EMAIL = quote({ plan_key: 'mail', family: 'email', name: 'Correo profesional', service_label: 'Correo electrónico', sort_order: 330 });

describe('quote-only families: one "Servicios a la medida" section', () => {
  it('merges automation, web and email into a single section with its title and line (no per-family headings)', () => {
    const el = render([priced({ plan_key: 'v', family: 'vps', name: 'VPS' }), AUTOMATION, WEB, EMAIL]);
    expect(el.querySelectorAll('[data-testid="quote-section-title"]')).toHaveLength(1);
    expect(el.querySelector('[data-testid="quote-section-title"]')?.textContent).toBe('Servicios a la medida');
    expect(el.querySelector('[data-testid="quote-section-line"]')?.textContent).toBe('Precio por cotización: se acuerda por escrito antes de contratar.');
    expect(el.querySelectorAll('[data-testid="quote-grid"]')).toHaveLength(1);
    expect(el.querySelectorAll('[data-testid="quote-grid"] [data-testid="plan-card"]')).toHaveLength(3);
    const headings = Array.from(el.querySelectorAll('h3')).map((h) => h.textContent?.trim());
    expect(headings).toEqual(['Servidores VPS', 'Servicios a la medida']);
  });

  it('orders the cards by the catalog sort_order, whatever the input order', () => {
    const el = render([EMAIL, AUTOMATION, WEB]);
    const names = Array.from(el.querySelectorAll('[data-testid="quote-grid"] h4')).map((h) => h.textContent?.trim());
    expect(names).toEqual(['n8n administrado', 'Paquete de lanzamiento', 'Correo profesional']);
  });

  it('keeps name, small family label and CTA in each card, without repeating the note per card', () => {
    const el = render([AUTOMATION, WEB, EMAIL]);
    const cards = Array.from(el.querySelectorAll('[data-testid="quote-grid"] [data-testid="plan-card"]'));
    expect(cards.map((c) => c.querySelector('[data-testid="family-label"]')?.textContent)).toEqual([
      'Automatización de procesos con agentes de IA: servicio propio de Hosting3M.',
      'Creación de páginas web: servicio propio de Hosting3M.',
      'Correo profesional: servicio propio de Hosting3M.',
    ]);
    expect(cards.every((c) => c.querySelector('[data-testid="quote-note"]') === null)).toBe(true);
    expect(cards.every((c) => c.querySelector('a')?.textContent?.includes('Cotiza por WhatsApp'))).toBe(true);
    expect(el.textContent?.match(/se acuerda por escrito antes de contratar/g)).toHaveLength(1);
  });

  it('a NEW quote-only family joins the section automatically (grouped by billing_period, not by family name)', () => {
    const NEW = quote({ plan_key: 'cloud-x', family: 'cloud', name: 'Nube a la medida', sort_order: 340 });
    const el = render([AUTOMATION, WEB, EMAIL, NEW]);
    const names = Array.from(el.querySelectorAll('[data-testid="quote-grid"] h4')).map((h) => h.textContent?.trim());
    expect(names).toEqual(['n8n administrado', 'Paquete de lanzamiento', 'Correo profesional', 'Nube a la medida']);
    expect(el.querySelectorAll('h3')).toHaveLength(1); // no separate "Nube" group
    // a family that is usually priced also joins when its plan is sold by quote
    const mixed = splitQuotePlans(parsePlans([priced({ plan_key: 'd', family: 'domain', name: '.xyz' }), quote({ plan_key: 'dq', family: 'domain', name: '.premium' })]));
    expect(mixed.priced.map((p) => p.key)).toEqual(['d']);
    expect(mixed.quote.map((p) => p.key)).toEqual(['dq']);
  });

  it('with no quote-only plans the section is not rendered', () => {
    const el = render([priced({ plan_key: 'v', family: 'vps', name: 'VPS' })]);
    expect(el.querySelector('[data-testid="quote-section-title"]')).toBeNull();
  });

  it('the quote-only grid is 1 column on phones and 3 at lg', () => {
    const el = render([AUTOMATION, WEB, EMAIL]);
    const grid = el.querySelector('[data-testid="quote-grid"]')!;
    expect(grid.className).toContain('lg:grid-cols-3');
    expect(grid.className.split(' ').some((c) => /^grid-cols-[2-9]$/.test(c))).toBe(false);
  });
});

describe('domain tiles', () => {
  it('renders one tile per domain (no table) with the extension, the price from the catalog and the group\'s single date note', () => {
    const el = render(DOMAINS);
    expect(el.querySelector('table')).toBeNull();
    const tiles = Array.from(el.querySelectorAll('[data-testid="domain-tile"]'));
    expect(tiles.map((t) => t.querySelector('h4')?.textContent?.trim())).toEqual(['.com', '.mx', '.com.mx', '.org', '.net', '.ai']);
    expect(tiles[0].querySelector('[data-testid="domain-price"]')?.textContent?.replace(/\s+/g, ' ').trim()).toBe('$340 MXN / año + IVA');
    expect(tiles[5].querySelector('[data-testid="domain-price"]')?.textContent?.replace(/\s+/g, ' ').trim()).toBe('$2,750 MXN / año + IVA');
    expect(el.querySelectorAll('[data-testid="group-date"]')).toHaveLength(1);
    expect(tiles.some((t) => t.textContent?.includes('Precios vigentes'))).toBe(false);
  });

  it('uses 2 columns on phones, 3 from md and 6 from xl, and is a real list', () => {
    const grid = render(DOMAINS).querySelector('[data-testid="domain-grid"]')!;
    expect(grid.tagName).toBe('UL');
    for (const c of ['grid-cols-2', 'md:grid-cols-3', 'xl:grid-cols-6']) expect(grid.className).toContain(c);
  });

  it('a domain sold by quote keeps the WhatsApp CTA with the prefill, as the old table row did', () => {
    const el = render([...DOMAINS.slice(0, 2), quote({ plan_key: 'dq', family: 'domain', name: '.premium', service_label: 'Registro de Dominios', sort_order: 270 })]);
    // a quote domain goes to the "Servicios a la medida" section (billing_period = quote), still with the CTA
    const card = el.querySelector('[data-testid="quote-grid"] [data-testid="plan-card"]')!;
    expect(card.querySelector('a')?.textContent).toContain('Cotiza por WhatsApp');
    expect(card.querySelector('a')?.getAttribute('href')).toContain('wa.me');
  });
});
