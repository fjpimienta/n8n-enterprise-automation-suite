import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { PlansService, parsePlans } from '../core/plans';
import { PlansSection } from './plans-section';

const api = (over: Record<string, unknown> = {}) => ({
  plan_key: 'k', family: 'hosting', name: 'Hosting A', summary: '', features: ['Uno', 'Dos'], badge: 'Popular', billing_period: 'yearly',
  price_amount: 1000, managed_amount: 2500, currency: 'MXN', tax_included: false, service_label: 'Creación de Páginas Web',
  price_checked_at: '2026-11-01', sort_order: 1, ...over,
});

function render(plans: unknown[]) {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
  const fixture = TestBed.createComponent(PlansSection);
  fixture.detectChanges();
  return { fixture, el: fixture.nativeElement as HTMLElement };
}

describe('PlansSection', () => {
  it('renders price, suffix, badge, features and the checked date', () => {
    const { el } = render([api()]);
    expect(el.querySelector('[data-testid="price"]')?.textContent).toContain('$1,000');
    expect(el.querySelector('[data-testid="suffix"]')?.textContent?.trim()).toBe('MXN / año + IVA');
    expect(el.textContent).toContain('Popular');
    expect(el.querySelectorAll('li li, ul ul li').length).toBeGreaterThanOrEqual(2);
    expect(el.textContent).toContain('Precios vigentes al 1 de noviembre de 2026');
    expect(el.querySelector('[data-testid="setup"]')).toBeNull(); // hosting with null setup_fee
  });

  it('is a segmented control: exactly one button pressed, the active one marked, with a helper line', () => {
    const { fixture, el } = render([api()]);
    const buttons = el.querySelectorAll<HTMLButtonElement>('[role="group"] button');
    const pressed = () => Array.from(buttons).filter((b) => b.getAttribute('aria-pressed') === 'true');
    expect(pressed()).toEqual([buttons[0]]);
    expect(buttons[0].textContent).toContain('✓');
    expect(buttons[1].textContent).not.toContain('✓');
    expect(buttons[0].className).toContain('bg-orange');
    expect(el.querySelector('[data-testid="mode-note"]')?.textContent).toBe('Precio autoadministrado');
    buttons[1].click();
    fixture.detectChanges();
    expect(pressed()).toEqual([buttons[1]]);
    expect(buttons[1].textContent).toContain('✓');
    expect(el.querySelector('[data-testid="mode-note"]')?.textContent).toBe('Incluye administración y soporte de Hosting3M');
  });

  it('toggles between self-managed and managed prices', () => {
    const { fixture, el } = render([api()]);
    const buttons = el.querySelectorAll<HTMLButtonElement>('[role="group"] button');
    expect(buttons[0].textContent).toContain('Autoadministrado');
    expect(buttons[1].textContent).toContain('Administrado por Hosting3M');
    buttons[1].click();
    fixture.detectChanges();
    expect(el.querySelector('[data-testid="price"]')?.textContent).toContain('$2,500');
    expect(buttons[1].getAttribute('aria-pressed')).toBe('true');
  });

  it('renders "Cotiza por WhatsApp" with a prefilled wa.me link for quote plans, with no price', () => {
    const { el } = render([api({ billing_period: 'quote', price_amount: null })]);
    const link = el.querySelector<HTMLAnchorElement>('a[href^="https://wa.me/5219993902625"]');
    expect(link?.textContent).toContain('Cotiza por WhatsApp');
    expect(decodeURIComponent(link!.href)).toContain('Hosting A');
    expect(el.querySelector('[data-testid="price"]')).toBeNull();
  });

  it('shows the VPS setup line and compact tiles for domains', () => {
    const { el } = render([api({ plan_key: 'v', family: 'vps', managed_amount: null }), api({ plan_key: 'd', family: 'domain', name: '.com', managed_amount: null, renewal_amount: 300 })]);
    expect(el.querySelector('[data-testid="setup"]')?.textContent).toContain('Instalación inicial: cotiza');
    expect(el.querySelector('table')).toBeNull();
    expect(el.querySelector('[data-testid="domain-tile"]')?.textContent).toContain('Renovación: $300');
  });

  it('shows a neutral quote section without prices when the catalog is empty', () => {
    const { el } = render([]);
    expect(el.textContent).toContain('Cotiza por WhatsApp');
    expect(el.querySelector('[data-testid="price"]')).toBeNull();
    expect(el.textContent).not.toMatch(/\$\s?\d/);
  });

  it('empty catalog: the four fallback cards carry the approved one-line summaries and no TODO_ text', () => {
    const { el } = render([]);
    const cards = Array.from(el.querySelectorAll('li')).map((li) => li.textContent ?? '');
    expect(cards).toHaveLength(4);
    expect(cards[0]).toContain('Servidores virtuales con acceso root, autoadministrados o administrados por Hosting3M.');
    expect(cards[1]).toContain('Hosting para tu sitio web, autoadministrado o administrado por Hosting3M.');
    expect(cards[2]).toContain('Registro y administración de dominios .com, .mx, .com.mx, .org, .net y .ai.');
    expect(cards[3]).toContain('n8n instalado y operado por Hosting3M, listo para tus flujos de automatización.');
    expect(el.textContent).not.toContain('TODO_');
  });
});
