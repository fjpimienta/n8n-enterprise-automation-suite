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

async function setup(plans: object[] = [plan]) {
  TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
  TestBed.inject(PlansService).plans.set(parsePlans(plans));
  const fixture = TestBed.createComponent(Host);
  fixture.detectChanges();
  const el = fixture.nativeElement as HTMLElement;
  const select = () => el.querySelector<HTMLSelectElement>('#cf-service')!;
  const message = () => el.querySelector<HTMLTextAreaElement>('#cf-message')!;
  const quote = async (index = 0) => {
    el.querySelectorAll<HTMLAnchorElement>('[data-testid="quote-plan"]')[index].click();
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

  it('refreshes the prefill for a second plan while the text is still the auto-generated one', async () => {
    const plan2 = { ...plan, plan_key: 'k2', name: 'Hosting B', service_label: 'Otro servicio', sort_order: 2 };
    const { select, message, quote } = await setup([plan, plan2]);
    await quote(0);
    expect(message().value).toBe('Quiero cotizar: Hosting A (Autoadministrado)');
    await quote(1);
    expect(message().value).toBe('Quiero cotizar: Hosting B (Autoadministrado)');
    expect(select().value).toBe('Otro servicio');
  });

  it('keeps text the visitor edited, even for a later plan', async () => {
    const plan2 = { ...plan, plan_key: 'k2', name: 'Hosting B', service_label: 'Otro servicio', sort_order: 2 };
    const { fixture, message, quote } = await setup([plan, plan2]);
    await quote(0);
    message().value = message().value + ' y necesito factura';
    message().dispatchEvent(new Event('input'));
    fixture.detectChanges();
    await quote(1);
    expect(message().value).toBe('Quiero cotizar: Hosting A (Autoadministrado) y necesito factura');
  });

  it('reflects the toggle at the moment of each click', async () => {
    const plan2 = { ...plan, plan_key: 'k2', name: 'Hosting B', service_label: 'Otro servicio', sort_order: 2 };
    const { fixture, el, message, quote } = await setup([plan, plan2]);
    const groups = el.querySelectorAll('[role="group"]');
    await quote(0);
    expect(message().value).toContain('(Autoadministrado)');
    groups[0].querySelectorAll('button')[1].click(); // plan A -> managed
    fixture.detectChanges();
    await quote(0);
    expect(message().value).toBe('Quiero cotizar: Hosting A (Administrado por Hosting3M)');
    groups[1].querySelectorAll('button')[1].click(); // plan B -> managed
    fixture.detectChanges();
    await quote(1);
    expect(message().value).toBe('Quiero cotizar: Hosting B (Administrado por Hosting3M)');
  });
});
