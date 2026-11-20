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

  it('shows the VPS setup line and a compact table for domains', () => {
    const { el } = render([api({ plan_key: 'v', family: 'vps', managed_amount: null }), api({ plan_key: 'd', family: 'domain', name: '.com', managed_amount: null, renewal_amount: 300 })]);
    expect(el.querySelector('[data-testid="setup"]')?.textContent).toContain('Instalación inicial: cotiza');
    expect(el.querySelector('table')).not.toBeNull();
    expect(el.querySelector('table')?.textContent).toContain('$300');
  });

  it('hides the renewal column when no domain has a renewal price', () => {
    const { el } = render([api({ plan_key: 'd1', family: 'domain', name: '.com', managed_amount: null }), api({ plan_key: 'd2', family: 'domain', name: '.mx', managed_amount: null })]);
    expect(el.querySelector('table')).not.toBeNull();
    expect(el.querySelector('table')?.textContent).not.toContain('Renovación');
    expect(el.querySelectorAll('thead th')).toHaveLength(3);
    expect(el.querySelectorAll('tbody tr:first-child > *')).toHaveLength(3);
  });

  it('shows the renewal column with a dash only for rows without a value', () => {
    const { el } = render([
      api({ plan_key: 'd1', family: 'domain', name: '.com', managed_amount: null, renewal_amount: 24.29 }),
      api({ plan_key: 'd2', family: 'domain', name: '.mx', managed_amount: null }),
    ]);
    const rows = el.querySelectorAll('tbody tr');
    expect(el.querySelector('thead')?.textContent).toContain('Renovación');
    expect(rows[0].textContent).toContain('$24.29');
    expect(rows[1].textContent).toContain('—');
  });

  it('shows a neutral quote section without prices when the catalog is empty', () => {
    const { el } = render([]);
    expect(el.textContent).toContain('Cotiza por WhatsApp');
    expect(el.querySelector('[data-testid="price"]')).toBeNull();
    expect(el.textContent).not.toMatch(/\$\s?\d/);
  });
});
