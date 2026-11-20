import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { PlansService, parsePlans } from '../core/plans';
import { ContactForm } from './contact-form';
import { PlansSection } from './plans-section';

@Component({ imports: [PlansSection, ContactForm], template: '<app-plans-section /><app-contact-form />' })
class Host {}

const plan = {
  plan_key: 'k', family: 'hosting', name: 'Hosting A', summary: '', features: [], badge: null, billing_period: 'yearly',
  price_amount: 1000, managed_amount: 2500, currency: 'MXN', tax_included: false, service_label: 'Hosting administrado', sort_order: 1,
};

async function setup() {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans([plan]));
  const fixture = TestBed.createComponent(Host);
  fixture.detectChanges();
  const el = fixture.nativeElement as HTMLElement;
  const select = () => el.querySelector<HTMLSelectElement>('#cf-service')!;
  const message = () => el.querySelector<HTMLTextAreaElement>('#cf-message')!;
  const quote = async () => {
    el.querySelector<HTMLAnchorElement>('[data-testid="quote-plan"]')!.click();
    fixture.detectChanges();
    await fixture.whenStable();
    await new Promise((r) => setTimeout(r)); // focus is applied after a tick
    fixture.detectChanges();
  };
  return { fixture, el, select, message, quote };
}

describe('"Cotizar <plan>" flow', () => {
  it('adds the plan service to the select, selects it, prefills the message with the mode and focuses it', async () => {
    const { el, select, message, quote } = await setup();
    document.body.appendChild(el); // focus needs an attached element
    await quote();
    expect(Array.from(select().options).map((o) => o.value)).toContain('Hosting administrado');
    expect(select().selectedOptions[0].value).toBe('Hosting administrado');
    expect(message().value).toBe('Quiero cotizar: Hosting A (Autoadministrado)');
    expect(document.activeElement).toBe(message());
    el.remove();
  });

  it('uses the active mode in the message', async () => {
    const { fixture, el, message, quote } = await setup();
    el.querySelectorAll<HTMLButtonElement>('[role="group"] button')[1].click();
    fixture.detectChanges();
    await quote();
    expect(message().value).toBe('Quiero cotizar: Hosting A (Administrado por Hosting3M)');
  });

  it('never overwrites a message the visitor already wrote', async () => {
    const { fixture, message, quote } = await setup();
    message().value = 'Mi propio mensaje';
    message().dispatchEvent(new Event('input'));
    fixture.detectChanges();
    await quote();
    expect(message().value).toBe('Mi propio mensaje');
  });
});
