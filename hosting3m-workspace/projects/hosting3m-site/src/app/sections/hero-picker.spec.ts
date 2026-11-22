import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { PlansService, parsePlans } from '../core/plans';
import { ContactForm } from './contact-form';
import { Hero } from './hero';
import { ServicePicker } from './service-picker';

const api = (over: Record<string, unknown> = {}) => ({
  plan_key: 'vps-1', family: 'vps', name: 'VPS de prueba', features: [], billing_period: 'yearly', price_amount: 1000, managed_amount: 1800,
  currency: 'MXN', tax_included: false, service_label: 'Renta de Servidores VPS', sort_order: 1, ...over,
});
const setup = (plans: unknown[] = []) => {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
};

describe('Hero', () => {
  it('renders the h1, the LCP image with dimensions and high fetch priority, and the facts', () => {
    setup();
    const fixture = TestBed.createComponent(Hero);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent).toContain('Soluciones en la nube para tu negocio');
    const img = el.querySelector('img')!;
    expect(img.getAttribute('src')).toBe('/images/hero-880.webp');
    expect(img.getAttribute('srcset')).toContain('/images/hero-440.webp 440w');
    expect(img.getAttribute('sizes')).toContain('100vw');
    expect(img.getAttribute('width')).toBe('880');
    expect(img.getAttribute('height')).toBe('920');
    expect(img.getAttribute('fetchpriority')).toBe('high');
    expect(img.getAttribute('alt')?.length).toBeGreaterThan(10);
    expect(el.textContent).toContain('Respuesta en 1 día hábil');
    expect(el.querySelector('a[href^="https://wa.me/5219993902625"]')).not.toBeNull();
  });
});

describe('ServicePicker (01 Elige)', () => {
  const render = () => {
    const fixture = TestBed.createComponent(ServicePicker);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const buttons = () => Array.from(el.querySelectorAll<HTMLButtonElement>('[role="group"] button'));
    return { fixture, el, buttons, title: () => el.querySelector('[data-testid="rec-title"]')?.textContent?.trim(), price: () => el.querySelector('[data-testid="rec-price"]')?.textContent?.trim() };
  };

  it('has 4 options with exactly one aria-pressed, and the panel follows the selection', () => {
    setup();
    const { fixture, buttons, title } = render();
    expect(buttons()).toHaveLength(4);
    expect(buttons().filter((b) => b.getAttribute('aria-pressed') === 'true')).toHaveLength(1);
    expect(buttons()[0].getAttribute('aria-pressed')).toBe('true');
    buttons()[1].click();
    fixture.detectChanges();
    expect(buttons().map((b) => b.getAttribute('aria-pressed'))).toEqual(['false', 'true', 'false', 'false']);
    expect(title()).toBe('Dominio');
  });

  it('takes the recommended plan and price from the catalog, never from hardcoded values', () => {
    setup([api()]);
    const { price, title } = render();
    expect(title()).toBe('VPS de prueba');
    expect(price()).toBe('Desde $1,000 MXN / año + IVA');
  });

  it('offers a WhatsApp quote when the catalog is empty (no price at all)', () => {
    setup([]);
    const { price, el } = render();
    expect(price()).toBe('Cotiza por WhatsApp');
    expect(el.textContent).not.toMatch(/\$\s?\d/);
  });
});

@Component({ imports: [ServicePicker, ContactForm], template: '<app-service-picker /><app-contact-form />' })
class Host {}

describe('ServicePicker prefill of the contact form', () => {
  async function flow() {
    setup([api()]);
    const fixture = TestBed.createComponent(Host);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const message = () => el.querySelector<HTMLTextAreaElement>('#cf-message')!;
    const select = () => el.querySelector<HTMLSelectElement>('#cf-service')!;
    const click = async (index: number) => {
      el.querySelectorAll<HTMLButtonElement>('[role="group"] button')[index].click();
      fixture.detectChanges();
      el.querySelector<HTMLAnchorElement>('[data-testid="rec-cta"]')!.click();
      fixture.detectChanges();
      await fixture.whenStable();
      await new Promise((r) => setTimeout(r));
      fixture.detectChanges();
    };
    return { fixture, message, select, click };
  }

  it('selects the service and writes the message, then replaces its own text for the next option', async () => {
    const { select, message, click } = await flow();
    await click(0);
    expect(select().value).toBe('Renta de Servidores VPS');
    expect(message().value).toBe('Quiero cotizar: VPS de prueba');
    await click(1);
    expect(select().value).toBe('Registro de Dominios');
    expect(message().value).toBe('Quiero cotizar: Dominio');
  });

  it('keeps a message the visitor edited', async () => {
    const { fixture, message, click } = await flow();
    await click(0);
    message().value = message().value + ' con IP fija';
    message().dispatchEvent(new Event('input'));
    fixture.detectChanges();
    await click(1);
    expect(message().value).toBe('Quiero cotizar: VPS de prueba con IP fija');
  });
});
