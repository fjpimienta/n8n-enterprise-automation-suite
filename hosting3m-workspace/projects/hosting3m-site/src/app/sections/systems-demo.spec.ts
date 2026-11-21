import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { ContactForm } from './contact-form';
import { SystemsDemo } from './systems-demo';

@Component({ imports: [SystemsDemo, ContactForm], template: '<app-systems-demo /><app-contact-form />' })
class Host {}

describe('SystemsDemo (Míralo en acción)', () => {
  function setup() {
    TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
    const fixture = TestBed.createComponent(Host);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    return {
      fixture, el,
      tabs: () => Array.from(el.querySelectorAll<HTMLButtonElement>('[role="tab"]')),
      panels: () => Array.from(el.querySelectorAll<HTMLElement>('[role="tabpanel"]')),
      mocks: () => Array.from(el.querySelectorAll<HTMLElement>('figure')),
    };
  }

  it('has 3 tabs with one selected, and shows only the matching mock and text', () => {
    const { fixture, tabs, panels, mocks } = setup();
    expect(tabs().map((t) => t.textContent?.trim())).toEqual(['ERP hotelero', 'Agro ERP · chat web', 'Agro ERP · WhatsApp']);
    expect(tabs().map((t) => t.getAttribute('aria-selected'))).toEqual(['true', 'false', 'false']);
    expect(mocks().map((m) => m.hidden)).toEqual([false, true, true]);
    tabs()[2].click();
    fixture.detectChanges();
    expect(tabs().map((t) => t.getAttribute('aria-selected'))).toEqual(['false', 'false', 'true']);
    expect(mocks().map((m) => m.hidden)).toEqual([true, true, false]);
    expect(panels().map((p) => p.hidden)).toEqual([true, true, false]);
    expect(panels()[2].textContent).toContain('tokens firmados y datos separados por empresa');
  });

  it('supports arrow keys, Home and End with roving tabindex', () => {
    const { fixture, tabs } = setup();
    tabs()[0].dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    fixture.detectChanges();
    expect(tabs()[1].getAttribute('aria-selected')).toBe('true');
    expect(tabs().map((t) => t.getAttribute('tabindex'))).toEqual(['-1', '0', '-1']);
    tabs()[1].dispatchEvent(new KeyboardEvent('keydown', { key: 'End', bubbles: true }));
    fixture.detectChanges();
    expect(tabs()[2].getAttribute('aria-selected')).toBe('true');
    tabs()[2].dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    fixture.detectChanges();
    expect(tabs()[0].getAttribute('aria-selected')).toBe('true');
  });

  it('labels the mocks as illustrative and uses only the demo names', () => {
    const { el } = setup();
    const text = el.textContent ?? '';
    expect(text).toContain('Ejemplo ilustrativo');
    expect(text).toContain('Hotel Demo');
    expect(text).toContain('Rancho Demo');
    expect(text).toContain('desde enero de 2026');
    expect(text).toContain('desde noviembre de 2026');
    expect(text).not.toMatch(/24\/7|uptime|RS256|encriptaci/i);
  });

  it('keeps the message-by-message animation in CSS only (reduced motion is handled in the stylesheet)', () => {
    const { el } = setup();
    expect(el.querySelectorAll('.chat-msg').length).toBe(8);
    expect(el.querySelector('[style]')).toBeNull(); // no inline styles (CSP)
  });

  it('the two demo CTAs preselect the service and prefill the message in the contact form', async () => {
    const { fixture, el } = setup();
    const select = el.querySelector<HTMLSelectElement>('#cf-service')!;
    const message = el.querySelector<HTMLTextAreaElement>('#cf-message')!;
    el.querySelector<HTMLAnchorElement>('[data-testid="demo-hotel"]')!.click();
    fixture.detectChanges();
    await fixture.whenStable();
    await new Promise((r) => setTimeout(r));
    fixture.detectChanges();
    expect(select.value).toBe('ERP hotelero (solicitud de demo)');
    expect(message.value).toBe('Quiero una demo del ERP hotelero.');
    el.querySelector<HTMLAnchorElement>('[data-testid="demo-agro"]')!.click();
    fixture.detectChanges();
    await fixture.whenStable();
    await new Promise((r) => setTimeout(r));
    fixture.detectChanges();
    expect(select.value).toBe('Agro ERP (solicitud de demo)');
    expect(message.value).toBe('Quiero una demo del Agro ERP.');
  });
});
