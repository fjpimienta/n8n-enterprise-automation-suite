import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { ContactForm } from '../sections/contact-form';
import { Portfolio } from './portfolio';
import { Profile } from './profile';

const providers = () => ({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });

describe('Profile page (/fjpimienta)', () => {
  function render() {
    TestBed.configureTestingModule(providers());
    const fixture = TestBed.createComponent(Profile);
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  it('shows the approved content: name, title, location, summary, areas and education', () => {
    const el = render();
    const text = el.textContent ?? '';
    expect(el.querySelector('h1')?.textContent).toContain('Francisco Jesús Pérez Pimienta');
    expect(text).toContain('Ingeniero en Sistemas Computacionales, Maestro en Administración de Proyectos');
    expect(text).toContain('Mérida, Yucatán');
    expect(text).toContain('Fundó Hosting3M en enero de 2020');
    expect(text).toContain('Universidad para la Cooperación Internacional');
    expect(text).toContain('Instituto Tecnológico de Villahermosa');
    expect(el.querySelectorAll('section[aria-labelledby="areas-title"] li')).toHaveLength(6);
    expect(text).not.toContain('TODO_');
  });

  it('has the optimized photo with dimensions and alt, LinkedIn only, and business contact data', () => {
    const el = render();
    const img = el.querySelector('img')!;
    expect(img.getAttribute('src')).toBe('/images/profile-400.webp');
    expect([img.getAttribute('width'), img.getAttribute('height')]).toEqual(['400', '400']);
    expect(img.getAttribute('alt')).toBe('Fotografía de Francisco Jesús Pérez Pimienta');
    const hrefs = Array.from(el.querySelectorAll('a')).map((a) => a.getAttribute('href') ?? '');
    expect(hrefs).toContain('https://www.linkedin.com/in/fjpimienta');
    expect(hrefs.some((h) => h.includes('github'))).toBe(false);
    expect(hrefs).toContain('mailto:contacto@hosting3m.com');
    expect(hrefs).toContain('tel:+529993902625');
  });

  it('never mentions certifications, employers, language level, courses, GitHub or a personal email', () => {
    const text = render().textContent ?? '';
    expect(text).not.toMatch(/PMP|certific|nivel de ingl|inglés|curso|github|gmail|fjpimienta@/i);
  });
});

@Component({ imports: [Portfolio, ContactForm], template: '<app-portfolio /><app-contact-form />' })
class PortfolioHost {}

describe('Portfolio page', () => {
  function setup() {
    TestBed.configureTestingModule(providers());
    const fixture = TestBed.createComponent(PortfolioHost);
    fixture.detectChanges();
    return { fixture, el: fixture.nativeElement as HTMLElement };
  }

  it('presents the two own ERPs with their dates, using the shared mocks, and nothing invented', () => {
    const { el } = setup();
    const text = el.textContent ?? '';
    expect(text).toContain('ERP hotelero');
    expect(text).toContain('En operación desde enero de 2026');
    expect(text).toContain('Agro ERP con asistente de IA');
    expect(text).toContain('En operación desde noviembre de 2026');
    expect(el.querySelectorAll('app-demo-mock')).toHaveLength(3); // hotel, agro chat, agro WhatsApp
    expect(text).toContain('Ejemplo ilustrativo');
    expect(text).not.toMatch(/Pista de Hielo|TODO_|testimonio|clientes? (satisfechos|activos)|\d+\s*(clientes|usuarios)/i);
    expect(el.querySelector('[style]')).toBeNull();
  });

  it('"Pedir demo" preselects the service and prefills the message, replacing its own text but not the visitor\'s', async () => {
    const { fixture, el } = setup();
    const select = el.querySelector<HTMLSelectElement>('#cf-service')!;
    const message = el.querySelector<HTMLTextAreaElement>('#cf-message')!;
    const click = async (id: string) => {
      el.querySelector<HTMLAnchorElement>(`[data-testid="${id}"]`)!.click();
      fixture.detectChanges();
      await fixture.whenStable();
      await new Promise((r) => setTimeout(r));
      fixture.detectChanges();
    };
    await click('demo-hotel');
    expect(select.value).toBe('ERP hotelero (solicitud de demo)');
    expect(message.value).toBe('Quiero una demo del ERP hotelero.');
    await click('demo-agro');
    expect(select.value).toBe('Agro ERP (solicitud de demo)');
    expect(message.value).toBe('Quiero una demo del Agro ERP.');
    message.value += ' Somos tres personas.';
    message.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    await click('demo-hotel');
    expect(message.value).toBe('Quiero una demo del Agro ERP. Somos tres personas.');
  });
});
