import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { PlansService, groupByFamily, parsePlans } from '../core/plans';
import { ContactForm } from './contact-form';
import { PlansSection } from './plans-section';

const quotePlan = (over: Record<string, unknown>) => ({
  summary: null, features: [], badge: null, billing_period: 'quote', price_amount: null, managed_amount: null, promo_amount: null, promo_months: null,
  renewal_amount: null, setup_fee: null, term_months: null, currency: 'MXN', tax_included: false, price_checked_at: null, valid_until: null, is_featured: false, ...over,
});
const WEB = quotePlan({ plan_key: 'paquete-lanzamiento', family: 'web', name: 'Paquete de lanzamiento', service_label: 'Creación de Páginas Web', sort_order: 320 });
const EMAIL = quotePlan({ plan_key: 'correo-profesional', family: 'email', name: 'Correo profesional', service_label: 'Correo electrónico', sort_order: 330 });

@Component({ imports: [PlansSection, ContactForm], template: '<app-plans-section /><app-contact-form />' })
class Host {}

function setup(plans: unknown[]) {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
  const fixture = TestBed.createComponent(Host);
  fixture.detectChanges();
  const el = fixture.nativeElement as HTMLElement;
  return { fixture, el };
}

describe('quote-only plans: web (Paquete de lanzamiento) and email (Correo profesional)', () => {
  it('render as cards with the name, the own-service note, the quote note and no price, summary or features', () => {
    const { el } = setup([WEB, EMAIL]);
    const cards = Array.from(el.querySelectorAll('[data-testid="plan-card"]'));
    expect(cards).toHaveLength(2);
    expect(el.querySelector('[data-testid="price"]')).toBeNull();
    expect(el.querySelector('[data-testid="suffix"]')).toBeNull();
    for (const card of cards) {
      expect(card.querySelector('ul')).toBeNull(); // empty features: no empty list
      expect(card.querySelector('p.font-mono')).toBeNull(); // null summary: no blank line
      expect(card.querySelector('[data-testid="quote-note"]')?.textContent).toContain('se acuerda por escrito antes de contratar');
      expect(card.querySelector('a')?.textContent).toContain('Cotiza por WhatsApp');
    }
    const notes = Array.from(el.querySelectorAll('[data-testid="family-note"]')).map((n) => n.textContent);
    expect(notes).toEqual(['Creación de páginas web: servicio propio de Hosting3M.', 'Correo profesional: servicio propio de Hosting3M.']);
    expect(el.textContent).not.toMatch(/\$\s?\d|TODO_|24\/7|uptime|GB|entrega en/i);
  });

  it('the WhatsApp link carries the plan name', () => {
    const { el } = setup([WEB]);
    const link = el.querySelector<HTMLAnchorElement>('[data-testid="plan-card"] a')!;
    expect(decodeURIComponent(link.href)).toContain('Paquete de lanzamiento');
  });

  it('the CTA preselects the service and prefills the contact form with the plan name, without overwriting the visitor\'s text', async () => {
    const { fixture, el } = setup([WEB, EMAIL]);
    const select = el.querySelector<HTMLSelectElement>('#cf-service')!;
    const message = el.querySelector<HTMLTextAreaElement>('#cf-message')!;
    const click = async (i: number) => {
      el.querySelectorAll<HTMLAnchorElement>('[data-testid="plan-card"] a')[i].click();
      fixture.detectChanges();
      await fixture.whenStable();
      await new Promise((r) => setTimeout(r));
      fixture.detectChanges();
    };
    await click(0);
    expect(select.value).toBe('Creación de Páginas Web');
    expect(message.value).toBe('Quiero cotizar: Paquete de lanzamiento');
    await click(1); // replaces its own text
    expect(select.value).toBe('Correo electrónico');
    expect(message.value).toBe('Quiero cotizar: Correo profesional');
    message.value += ' para 5 cuentas';
    message.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    await click(0); // keeps the visitor's edit
    expect(message.value).toBe('Quiero cotizar: Correo profesional para 5 cuentas');
  });

  it('the groups follow the catalog sort_order (vps, hosting, domain, automation, web, email)', () => {
    const mk = (family: string, sort: number) => quotePlan({ plan_key: `${family}-${sort}`, family, name: family, service_label: family, sort_order: sort });
    const plans = [mk('email', 330), mk('domain', 210), mk('web', 320), mk('vps', 10), mk('automation', 310), mk('hosting', 110)];
    const order = groupByFamily(parsePlans(plans)).map((g) => g.family);
    expect(order).toEqual(['vps', 'hosting', 'domain', 'automation', 'web', 'email']);
  });
});
