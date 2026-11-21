import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BUSINESS } from '../core/business';
import { ConsentService } from '../core/consent';
import { Footer } from './footer';
import { Header } from './header';

describe('Header', () => {
  function render() {
    TestBed.configureTestingModule({ providers: [provideRouter([])] });
    const fixture = TestBed.createComponent(Header);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    return { fixture, el, button: el.querySelector<HTMLButtonElement>('button[aria-controls="main-nav"]')!, nav: el.querySelector<HTMLElement>('#main-nav')! };
  }

  it('has a real hamburger: closed by default, toggles aria-expanded and the menu', () => {
    const { fixture, button, nav } = render();
    expect(button.getAttribute('aria-expanded')).toBe('false');
    expect(button.getAttribute('aria-label')).toBe('Abrir menú');
    expect(nav.classList).toContain('hidden');
    button.click();
    fixture.detectChanges();
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(button.getAttribute('aria-label')).toBe('Cerrar menú');
    expect(nav.classList).not.toContain('hidden');
  });

  it('closes with Escape and returns focus to the button, and when a link is chosen', () => {
    const { fixture, el, button, nav } = render();
    document.body.appendChild(el);
    button.click();
    fixture.detectChanges();
    el.querySelector('header')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    fixture.detectChanges();
    expect(nav.classList).toContain('hidden');
    expect(document.activeElement).toBe(button);
    button.click();
    fixture.detectChanges();
    nav.querySelector<HTMLAnchorElement>('a')!.click();
    fixture.detectChanges();
    expect(nav.classList).toContain('hidden');
    el.remove();
  });

  it('shows the real logo with dimensions and descriptive Spanish alt text', () => {
    const { el } = render();
    const img = el.querySelector('a img')!;
    expect(img.getAttribute('src')).toBe('/images/logo-112.webp');
    expect([img.getAttribute('width'), img.getAttribute('height')]).toEqual(['56', '56']);
    expect(img.getAttribute('alt')).toContain('Logotipo de Hosting3M');
  });

  it('links to the page sections of the redesign', () => {
    const { nav } = render();
    expect(Array.from(nav.querySelectorAll('a')).map((a) => a.textContent?.trim())).toEqual(['Servicios', 'Paquetes', 'Sistemas', 'Noticias', 'Contacto']);
  });
});

describe('Footer', () => {
  it('shows the legal entity, address and hours from the business data, and reopens the cookie banner', () => {
    TestBed.configureTestingModule({ providers: [provideRouter([])] });
    const consent = TestBed.inject(ConsentService);
    const fixture = TestBed.createComponent(Footer);
    fixture.detectChanges();
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain(BUSINESS.legalName);
    expect(text).toContain(BUSINESS.address.street);
    expect(text).toContain(BUSINESS.hoursText);
    const logo = (fixture.nativeElement as HTMLElement).querySelector('img')!;
    expect(logo.getAttribute('alt')).toBe('Logotipo de Hosting3M');
    expect(logo.getAttribute('width')).toBe('56');
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button')).find((b) => b.textContent?.includes('Preferencias de cookies'))!;
    button.click();
    expect(consent.bannerOpen()).toBe(true);
  });
});
